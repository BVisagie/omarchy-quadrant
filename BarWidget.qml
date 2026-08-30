import QtQuick
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model
import "Theme.js" as Theme
import "components" as Components

// Quadrant bar slot: one compact widget covering CPU, GPU, memory, and
// network. Owns the long-lived sampler (quadrant-stream), the 60s history
// buffers, and GPU detection; the nested Panel reads everything through
// hostWidget.
BarWidget {
  id: root
  moduleName: "dev.bvisagie.quadrant"

  // ---- settings (manifest barWidget.defaults mirrored as fallbacks) ----
  readonly property var segmentsSetting: {
    var v = setting("segments", null)
    return Array.isArray(v) ? v : ["cpu", "gpu", "memory", "network"]
  }
  readonly property int barIntervalMs: Model.clamp(setting("barIntervalMs", 1000), 250, 60000)
  readonly property int panelIntervalMs: Model.clamp(setting("panelIntervalMs", 2000), 500, 60000)
  readonly property int historyLimit: Math.ceil(60000 / barIntervalMs) + 1
  readonly property int processCount: Model.clamp(setting("processCount", 5), 1, 10)
  readonly property string networkInterface: String(setting("networkInterface", "auto"))
  readonly property string gpuDevice: String(setting("gpuDevice", "auto"))
  readonly property string barPaletteMode: {
    var v = String(setting("barPalette", "theme")).toLowerCase()
    return v === "vivid" ? "vivid" : "theme"
  }
  readonly property string barLabelsMode: {
    var v = String(setting("barLabels", "glyph")).toLowerCase()
    return (v === "letter" || v === "none") ? v : "glyph"
  }

  readonly property int visibleSegmentCount: {
    var n = 0
    if (segmentEnabled("cpu")) n++
    if (segmentEnabled("memory")) n++
    if (segmentEnabled("gpu") && gpuAvailable) n++
    if (segmentEnabled("network")) n++
    return Math.max(1, n)
  }

  function segmentEnabled(name) {
    return segmentsSetting.indexOf(name) !== -1
  }

  function localPath(rel) {
    return decodeURIComponent(String(Qt.resolvedUrl(rel)).replace(/^file:\/\//, ""))
  }

  readonly property string streamScript: localPath("scripts/quadrant-stream")
  readonly property string gpuStatsScript: localPath("scripts/gpu-stats")

  // ---- sampler state ----
  property var sample: null
  property var prevSample: null
  property bool streamLive: false
  property double lastSampleAtMs: 0
  property double streamStartedAtMs: 0
  property string streamError: ""
  property var cpuPct: null
  property var memComp: null
  property var swapRate: ({ inKBs: 0, outKBs: 0 })
  property var ifaceRates: null
  property var cpuHistory: []
  property var netHistory: []

  // ---- GPU state ----
  property var gpus: []
  property var gpu: null
  property var nvidiaGpu: null
  property string nvidiaError: ""
  property string gpuDetectionError: ""

  // ---- hardware identity (one-shot, re-run on R) ----
  property var sysInfo: null
  readonly property var cpuFreqMhz: sample && sample.cpuFreqMhz !== undefined ? sample.cpuFreqMhz : null

  readonly property var themePal: Theme.barPaletteFor(
    String(root.bar ? (root.bar.barForeground || root.bar.foreground) : Color.foreground),
    String(Color.accent),
    String(root.bar ? root.bar.urgent : Color.urgent)
  )
  readonly property bool cpuHot: cpuPct !== null && cpuPct.busy >= 90
  readonly property bool memHot: memComp !== null && memComp.usedPct >= 90
  readonly property bool gpuHot: gpuDisplay !== null && gpuDisplay.pct >= 90
  readonly property var cpuMeterUser: {
    if (barPaletteMode === "vivid") return cpuHot ? Theme.series.cpuSteal : Theme.series.cpuUser
    return cpuHot ? themePal.urgent : themePal.fill
  }
  readonly property var cpuMeterSystem: {
    if (barPaletteMode === "vivid") return cpuHot ? Theme.series.cpuSteal : Theme.series.cpuSystem
    return cpuHot ? themePal.urgent : themePal.fillStack
  }
  readonly property var memMeterFill: {
    if (barPaletteMode === "vivid") return memHot ? Theme.series.cpuSteal : Theme.series.memApps
    return memHot ? themePal.urgent : themePal.fill
  }
  readonly property var gpuMeterFill: {
    if (barPaletteMode === "vivid") return gpuHot ? Theme.series.cpuSteal : Theme.series.gpu
    return gpuHot ? themePal.urgent : themePal.fill
  }
  readonly property var meterTrack: {
    if (barPaletteMode === "vivid")
      return Theme.trackFor(String(root.bar ? (root.bar.barForeground || root.bar.foreground) : Color.foreground))
    return themePal.track
  }
  readonly property string cpuValueText: cpuPct ? Model.formatPct(cpuPct.busy) : "--"
  readonly property string memValueText: memComp ? Model.formatPct(memComp.usedPct) : "--"
  readonly property string gpuValueText: {
    if (!gpuDisplay) return "--"
    return (gpuDisplay.estimated ? "~" : "") + Model.formatPct(gpuDisplay.pct)
  }
  readonly property color hotTextColor: {
    if (barPaletteMode === "vivid") return Theme.series.cpuSteal
    return themePal.urgent
  }
  // Two caption lines, matching the network stack so every cell shares
  // both baselines. Network's own height is preferred when it is shown.
  readonly property int lineBoxHeight: pctSizer.implicitHeight
  readonly property int segmentHeight: {
    var two = lineBoxHeight * 2
    if (!root.segmentEnabled("network")) return two
    var h = netCol.implicitHeight
    return h > two ? h : two
  }
  readonly property int metricLabelWidth: {
    if (root.vertical || root.barLabelsMode === "none") return 0
    return Math.max(cpuGlyphSizer.implicitWidth, gpuGlyphSizer.implicitWidth, memGlyphSizer.implicitWidth)
  }
  readonly property int metricCellWidth: {
    var w = pctSizer.implicitWidth
    if (root.metricLabelWidth > 0)
      w += Style.space(Theme.metrics.barLabelGap) + root.metricLabelWidth
    if (root.vertical && root.bar)
      return Math.min(w, root.bar.barSize)
    return w
  }
  readonly property int verticalSlot: root.bar ? root.bar.barSize : Style.bar.sizeVertical
  readonly property bool gpuAvailable: gpu !== null
  readonly property bool nvidiaSelected: gpu !== null && gpu.vendor === "nvidia"
  // Position of the selected card among the NVIDIA cards — nvidia-smi -i
  // indexes NVIDIA devices, not /sys cards.
  readonly property int nvidiaIndex: {
    if (!nvidiaSelected) return 0
    var idx = 0
    for (var i = 0; i < gpus.length; i++) {
      if (gpus[i].vendor !== "nvidia") continue
      if (gpus[i].card === gpu.card) return idx
      idx++
    }
    return 0
  }
  readonly property bool panelGpuOpen: panelLoader.item
    ? (panelLoader.item.opened === true && panelLoader.item.currentTab === "gpu")
    : false

  readonly property string effectiveInterface: {
    if (networkInterface !== "auto" && networkInterface !== "") return networkInterface
    return sample ? Model.pickInterface(sample.r4, sample.r6, sample.net) : ""
  }
  readonly property bool pinnedInterface: networkInterface !== "auto" && networkInterface !== ""
  readonly property bool effectiveInterfaceAvailable: {
    if (!sample || effectiveInterface === "") return false
    for (var i = 0; i < sample.net.length; i++)
      if (sample.net[i].n === effectiveInterface) return true
    return false
  }
  readonly property string networkInterfaceError: {
    if (!pinnedInterface || !sample || effectiveInterfaceAvailable) return ""
    return "Pinned interface " + networkInterface + " is not available"
  }

  // GPU segment value: { pct, estimated } or null when unknown.
  readonly property var gpuDisplay: {
    if (!gpu) return null
    if (gpu.vendor === "nvidia") {
      if (nvidiaGpu && nvidiaGpu.utilPct !== null) return ({ pct: nvidiaGpu.utilPct, estimated: false })
      return null
    }
    var g = sample ? sample.gpu : null
    if (!g) return null
    if (g.kind === "intel") {
      if (g.freqCurMhz !== null && g.freqMaxMhz !== null && g.freqMaxMhz > 0)
        return ({ pct: Model.clamp(100 * g.freqCurMhz / g.freqMaxMhz, 0, 100), estimated: true })
      return null
    }
    if (g.busy !== null) return ({ pct: g.busy, estimated: false })
    return null
  }

  readonly property string tooltipLine: {
    if (!streamLive) return "Quadrant: sampler offline"
    var parts = []
    if (segmentEnabled("cpu") && cpuPct)
      parts.push("CPU " + Model.formatPct(cpuPct.busy))
    if (segmentEnabled("gpu") && gpuAvailable && gpuDisplay)
      parts.push("GPU " + Model.formatPct(gpuDisplay.pct) + (gpuDisplay.estimated ? " (freq)" : ""))
    if (segmentEnabled("memory") && memComp)
      parts.push("MEM " + Model.formatPct(memComp.usedPct))
    if (segmentEnabled("network") && ifaceRates)
      parts.push("↑ " + Model.formatRate(ifaceRates.txBps) + " ↓ " + Model.formatRate(ifaceRates.rxBps))
    return parts.length > 0 ? parts.join("  ·  ") : "Quadrant"
  }

  // ---- panel contract (Quattro bar-widget shape) ----
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  // Click on a segment: open the panel on that tab; clicking the slot
  // elsewhere toggles the panel on the last-used tab. Segment MouseAreas
  // sit above WidgetButton's own MouseArea; ignoreNextToggle drops the
  // button press when both still fire.
  property bool ignoreNextToggle: false

  function noteSegmentPress() {
    ignoreNextToggle = true
  }

  function segmentClicked(tab) {
    ignoreNextToggle = true
    var p = panelLoader.item
    if (!p) {
      Qt.callLater(function () { root.ignoreNextToggle = false })
      return
    }
    if (p.opened) {
      if (p.currentTab === tab) p.close()
      else p.currentTab = tab
    } else {
      p.showTab(tab)
    }
    Qt.callLater(function () { root.ignoreNextToggle = false })
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  // ---- sampler wiring ----
  function handleSample(line) {
    var s = Model.parseStreamLine(line)
    if (!s) return
    var dt = prevSample ? s.ts - prevSample.ts : 0
    cpuPct = Model.cpuDelta(prevSample ? prevSample.cpu : null, s.cpu)
    memComp = Model.memComposition(s.mem)
    swapRate = Model.swapRates(prevSample ? prevSample.vm : null, s.vm, dt)
    var rates = Model.netRates(prevSample ? prevSample.net : null, s.net, dt)
    ifaceRates = null
    for (var i = 0; i < rates.length; i++) {
      if (rates[i].name === effectiveInterface) { ifaceRates = rates[i]; break }
    }
    if (cpuPct)
      cpuHistory = Model.pushTimedWindow(
        cpuHistory, { u: cpuPct.user, s: cpuPct.system, io: cpuPct.iowait },
        s.ts, 60, historyLimit)
    if (ifaceRates)
      netHistory = Model.pushTimedWindow(
        netHistory, { rx: ifaceRates.rxBps, tx: ifaceRates.txBps },
        s.ts, 60, historyLimit)
    prevSample = s
    sample = s
    streamLive = true
    lastSampleAtMs = Date.now()
    streamError = ""
  }

  function restartStream() {
    streamProc.intentionalStop = true
    streamProc.running = false
    streamLive = false
    streamRelaunchTimer.restart()
  }

  onBarIntervalMsChanged: restartStream()
  onGpuChanged: restartStream()

  Process {
    id: streamProc
    property bool intentionalStop: false
    command: {
      var args = [root.streamScript, String(root.barIntervalMs)]
      if (root.gpu && (root.gpu.vendor === "amd" || root.gpu.vendor === "intel"))
        args.push(root.gpu.path, root.gpu.vendor)
      return args
    }
    running: true
    stdout: SplitParser {
      onRead: function(line) { root.handleSample(line) }
    }
    onRunningChanged: if (running) root.streamStartedAtMs = Date.now()
    onExited: function(exitCode, exitStatus) {
      root.streamLive = false
      if (streamProc.intentionalStop) {
        streamProc.intentionalStop = false
      } else {
        // Crashed or killed: relaunch. Never present a dead sampler as
        // "all zeros" — streamLive=false drives the offline tooltip.
        if (root.streamError === "")
          root.streamError = "System sampler exited with code " + exitCode
        streamCrashTimer.restart()
      }
    }
  }

  // An alive Process can still wedge on a kernel/sysfs read. Detect missing
  // ticks, keep the last-good data visible, and let onExited relaunch it.
  Timer {
    id: streamWatchdog
    interval: Math.max(2000, root.barIntervalMs * 3)
    repeat: true
    running: true
    onTriggered: {
      if (!streamProc.running) return
      var reference = root.lastSampleAtMs > root.streamStartedAtMs
        ? root.lastSampleAtMs : root.streamStartedAtMs
      if (reference > 0 && Date.now() - reference <= interval) return
      root.streamLive = false
      root.streamError = "System sampler stopped producing data; restarting"
      streamProc.signal(9)
    }
  }

  Timer {
    id: streamRelaunchTimer
    interval: 250
    repeat: false
    onTriggered: streamProc.running = true
  }

  Timer {
    id: streamCrashTimer
    interval: 2000
    repeat: false
    onTriggered: streamProc.running = true
  }

  // ---- GPU detection + on-demand NVIDIA sampling ----
  function applyGpuList(text) {
    var data = Model.safeJson(text)
    if (!data || data.ok !== true) {
      gpuDetectionError = (data && data.error)
        ? "GPU detection failed: " + String(data.error)
        : "GPU detection returned invalid output"
      return
    }
    gpus = Model.normalizeGpuList(data)
    gpu = Model.pickGpu(gpus, gpuDevice)
    gpuDetectionError = ""
  }

  function persistGpuDevice(card) {
    if (!root.bar || typeof root.bar.run !== "function") return
    if (typeof card !== "string" || !/^card[0-9]+$/.test(card)) return
    var value = '"' + card + '"'
    var quotedId = (typeof Util !== "undefined" && Util.shellQuote)
      ? Util.shellQuote("dev.bvisagie.quadrant") : "'dev.bvisagie.quadrant'"
    var quotedValue = (typeof Util !== "undefined" && Util.shellQuote)
      ? Util.shellQuote(value) : ("'" + value + "'")
    root.bar.run("omarchy bar set " + quotedId + " gpuDevice " + quotedValue)
  }

  function selectGpu(card) {
    var chosen = Model.pickGpu(gpus, card)
    if (chosen) {
      gpu = chosen
      persistGpuDevice(chosen.card)
    }
  }

  onGpuDeviceChanged: {
    var chosen = Model.pickGpu(gpus, gpuDevice)
    if (chosen) gpu = chosen
  }

  Process {
    id: gpuListProc
    command: [root.gpuStatsScript, "list"]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyGpuList(text)
    }
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0 && root.gpuDetectionError === "")
        root.gpuDetectionError = "GPU detection exited with code " + exitCode
    }
  }

  function applySysInfo(text) {
    var data = Model.safeJson(text)
    if (!data || data.ok !== true) return
    sysInfo = Model.parseSystemInfo(data)
  }

  function refreshSysInfo() {
    if (sysInfoProc.running) return
    sysInfoProc.running = true
  }

  Process {
    id: sysInfoProc
    command: [root.localPath("scripts/system-info")]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applySysInfo(text)
    }
  }

  function applyNvidia(text) {
    var data = Model.safeJson(text)
    if (!data || data.ok !== true) {
      root.nvidiaGpu = null
      root.nvidiaError = (data && data.error) ? String(data.error) : "gpu-stats returned bad output"
      return
    }
    var rows = Model.parseNvidiaCsv(data.payload)
    root.nvidiaGpu = rows.length > 0 ? rows[0] : null
    root.nvidiaError = ""
  }

  function pollNvidia() {
    if (nvidiaProc.running) return
    nvidiaWatchdog.restart()
    nvidiaProc.running = true
  }

  Timer {
    id: nvidiaTimer
    interval: root.panelIntervalMs
    repeat: true
    running: root.nvidiaSelected && (root.segmentEnabled("gpu") || root.panelGpuOpen)
    onRunningChanged: if (running) root.pollNvidia()
    onTriggered: root.pollNvidia()
  }

  Process {
    id: nvidiaProc
    command: [root.gpuStatsScript, "sample", "nvidia", String(root.nvidiaIndex)]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyNvidia(text)
    }
    onExited: function(exitCode, exitStatus) {
      nvidiaWatchdog.stop()
      if (exitCode !== 0) {
        root.nvidiaGpu = null
        if (root.nvidiaError === "")
          root.nvidiaError = "gpu-stats exited with code " + exitCode
      }
    }
  }

  Timer {
    id: nvidiaWatchdog
    interval: 6000
    repeat: false
    onTriggered: {
      if (nvidiaProc.running) {
        nvidiaProc.signal(9)
        root.nvidiaGpu = null
        root.nvidiaError = "gpu-stats timed out"
      }
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // ---- bar slot ----
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    keepSpace: true
    tooltipText: root.tooltipLine
    // tooltipLine is rates/percentages, never process comm. The shell's
    // WidgetButton tooltip Text is already PlainText.
    fixedWidth: root.vertical ? -1 : segGrid.implicitWidth + Style.spaceReal(8.5) * 2
    fixedHeight: root.vertical ? segGrid.implicitHeight + Style.spaceReal(6) * 2 : -1

    onPressed: function(buttonCode) {
      if (buttonCode !== Qt.LeftButton) return
      if (root.ignoreNextToggle) {
        root.ignoreNextToggle = false
        return
      }
      root.toggle()
    }

    // Shared sizers: cell width is locked to glyph + "~100%" so digits
    // never resize the slot. Hidden, not Grid children.
    Text {
      id: pctSizer
      visible: false
      textFormat: Text.PlainText
      text: "~100%"
      font.family: button.fontFamily
      font.pixelSize: Style.font.caption
    }
    Text {
      id: cpuGlyphSizer
      visible: false
      textFormat: Text.PlainText
      text: Theme.barLabelFor(root.barLabelsMode, "cpu")
      font.family: button.fontFamily
      font.pixelSize: Style.font.caption
    }
    Text {
      id: gpuGlyphSizer
      visible: false
      textFormat: Text.PlainText
      text: Theme.barLabelFor(root.barLabelsMode, "gpu")
      font.family: button.fontFamily
      font.pixelSize: Style.font.caption
    }
    Text {
      id: memGlyphSizer
      visible: false
      textFormat: Text.PlainText
      text: Theme.barLabelFor(root.barLabelsMode, "mem")
      font.family: button.fontFamily
      font.pixelSize: Style.font.caption
    }

    Grid {
      id: segGrid
      z: 1
      anchors.centerIn: parent
      columns: root.vertical ? 1 : root.visibleSegmentCount
      columnSpacing: Style.space(Theme.metrics.barSegmentGap)
      rowSpacing: Style.space(4)
      verticalItemAlignment: Grid.AlignVCenter
      horizontalItemAlignment: Grid.AlignHCenter

      MetricCell {
        visible: root.segmentEnabled("cpu")
        tab: "cpu"
        metric: "cpu"
        valueText: root.cpuValueText
        hot: root.cpuHot
        meterSegments: [
          { fraction: root.cpuPct ? root.cpuPct.user / 100 : 0, color: root.cpuMeterUser },
          { fraction: root.cpuPct ? root.cpuPct.system / 100 : 0, color: root.cpuMeterSystem }
        ]
      }

      MetricCell {
        visible: root.segmentEnabled("gpu") && root.gpuAvailable
        tab: "gpu"
        metric: "gpu"
        valueText: root.gpuValueText
        hot: root.gpuHot
        meterSegments: [
          { fraction: root.gpuDisplay ? root.gpuDisplay.pct / 100 : 0, color: root.gpuMeterFill }
        ]
      }

      MetricCell {
        visible: root.segmentEnabled("memory")
        tab: "mem"
        metric: "mem"
        valueText: root.memValueText
        hot: root.memHot
        meterSegments: [
          { fraction: root.memComp ? root.memComp.usedPct / 100 : 0, color: root.memMeterFill }
        ]
      }

      // ---- Network segment (two-line rates) ----
      Item {
        visible: root.segmentEnabled("network")
        implicitWidth: {
          var w = netSizer.implicitWidth
          if (root.vertical) return Math.min(w, root.verticalSlot)
          return w
        }
        implicitHeight: netCol.implicitHeight

        Text {
          id: netSizer
          visible: false
          textFormat: Text.PlainText
          text: root.vertical ? "↓999T" : "↓ 999T"
          font.family: button.fontFamily
          font.pixelSize: Style.font.caption
        }

        Column {
          id: netCol
          width: parent.width
          spacing: 0
          Text {
            textFormat: Text.PlainText
            width: parent.width
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignRight
            text: (root.vertical ? "↑" : "↑ ") + (root.ifaceRates ? Model.formatRateCompact(root.ifaceRates.txBps) : "--")
            color: button.foreground
            font.family: button.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignRight
            text: (root.vertical ? "↓" : "↓ ") + (root.ifaceRates ? Model.formatRateCompact(root.ifaceRates.rxBps) : "--")
            color: button.foreground
            font.family: button.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: false
          acceptedButtons: Qt.LeftButton
          onPressed: root.noteSegmentPress()
          onClicked: root.segmentClicked("net")
        }
      }
    }
  }

  // Two-line metric cell: glyph/letter + right-aligned percentage over a
  // hairline meter. Width is locked by the shared sizers on `button`.
  component MetricCell: Item {
    id: cell

    property string tab: ""
    property string metric: ""
    property string valueText: "--"
    property var meterSegments: []
    property bool hot: false

    readonly property string label: root.vertical ? "" : Theme.barLabelFor(root.barLabelsMode, metric)
    readonly property color valueColor: cell.hot ? root.hotTextColor : button.foreground

    implicitWidth: root.metricCellWidth
    implicitHeight: root.segmentHeight

    Column {
      width: parent.width
      spacing: 0
      anchors.verticalCenter: parent.verticalCenter

      Item {
        width: parent.width
        height: root.lineBoxHeight

        Text {
          id: labelText
          visible: cell.label !== ""
          textFormat: Text.PlainText
          text: cell.label
          color: button.foreground
          font.family: button.fontFamily
          font.pixelSize: Style.font.caption
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          textFormat: Text.PlainText
          text: cell.valueText
          color: cell.valueColor
          font.family: button.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignRight
          elide: Text.ElideRight
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: labelText.visible
                        ? labelText.right
                        : parent.left
          anchors.leftMargin: labelText.visible ? Style.space(Theme.metrics.barLabelGap) : 0
        }
      }

      Item {
        width: parent.width
        height: root.lineBoxHeight

        Components.MeterBar {
          width: parent.width
          height: Style.space(Theme.metrics.barMeterThickness)
          anchors.verticalCenter: parent.verticalCenter
          trackColor: root.meterTrack
          segments: cell.meterSegments
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: false
      acceptedButtons: Qt.LeftButton
      onPressed: root.noteSegmentPress()
      onClicked: root.segmentClicked(cell.tab)
    }
  }
}
