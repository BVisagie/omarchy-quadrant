import QtQuick
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model
import "Theme.js" as Theme
import "components" as Components

// Quadrant bar slot: one compact widget covering CPU, memory, GPU, and
// network. Owns the long-lived sampler (quadrant-stream), the 60s history
// buffers, and GPU detection; the nested Panel reads everything through
// hostWidget.
BarWidget {
  id: root
  moduleName: "dev.bvisagie.quadrant"

  // ---- settings (manifest barWidget.defaults mirrored as fallbacks) ----
  readonly property var segmentsSetting: {
    var v = setting("segments", null)
    return Array.isArray(v) ? v : ["cpu", "memory", "gpu", "network"]
  }
  readonly property int barIntervalMs: Model.clamp(setting("barIntervalMs", 1000), 250, 60000)
  readonly property int panelIntervalMs: Model.clamp(setting("panelIntervalMs", 2000), 500, 60000)
  readonly property int processCount: Model.clamp(setting("processCount", 5), 1, 10)
  readonly property string networkInterface: String(setting("networkInterface", "auto"))
  readonly property string gpuDevice: String(setting("gpuDevice", "auto"))
  readonly property string barPaletteMode: {
    var v = String(setting("barPalette", "theme")).toLowerCase()
    return v === "vivid" ? "vivid" : "theme"
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
    if (segmentEnabled("memory") && memComp)
      parts.push("MEM " + Model.formatPct(memComp.usedPct))
    if (segmentEnabled("gpu") && gpuAvailable && gpuDisplay)
      parts.push("GPU " + Model.formatPct(gpuDisplay.pct) + (gpuDisplay.estimated ? " (freq)" : ""))
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
      cpuHistory = Model.pushCapped(cpuHistory, { u: cpuPct.user, s: cpuPct.system, io: cpuPct.iowait }, 60)
    if (ifaceRates)
      netHistory = Model.pushCapped(netHistory, { rx: ifaceRates.rxBps, tx: ifaceRates.txBps }, 60)
    prevSample = s
    sample = s
    streamLive = true
  }

  function restartStream() {
    streamProc.intentionalStop = true
    streamProc.running = false
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
    onExited: function(exitCode, exitStatus) {
      root.streamLive = false
      if (streamProc.intentionalStop) {
        streamProc.intentionalStop = false
      } else {
        // Crashed or killed: relaunch. Never present a dead sampler as
        // "all zeros" — streamLive=false drives the offline tooltip.
        streamCrashTimer.restart()
      }
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
    if (!data || data.ok !== true) return
    gpus = Model.normalizeGpuList(data)
    gpu = Model.pickGpu(gpus, gpuDevice)
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

    Grid {
      id: segGrid
      z: 1
      anchors.centerIn: parent
      columns: root.vertical ? 1 : root.visibleSegmentCount
      columnSpacing: Style.space(Theme.metrics.barSegmentGap)
      rowSpacing: Style.space(4)

      // ---- CPU segment ----
      Item {
        visible: root.segmentEnabled("cpu")
        implicitWidth: cpuRow.implicitWidth
        implicitHeight: cpuRow.implicitHeight

        Row {
          id: cpuRow
          spacing: Style.space(4)
          Text {
            textFormat: Text.PlainText
            text: "C"
            color: button.foreground
            font.family: button.fontFamily
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }
          Components.MeterBar {
            trackColor: root.meterTrack
            segments: [
              { fraction: root.cpuPct ? root.cpuPct.user / 100 : 0, color: root.cpuMeterUser },
              { fraction: root.cpuPct ? root.cpuPct.system / 100 : 0, color: root.cpuMeterSystem }
            ]
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: false
          acceptedButtons: Qt.LeftButton
          onPressed: root.noteSegmentPress()
          onClicked: root.segmentClicked("cpu")
        }
      }

      // ---- Memory segment ----
      Item {
        visible: root.segmentEnabled("memory")
        implicitWidth: memRow.implicitWidth
        implicitHeight: memRow.implicitHeight

        Row {
          id: memRow
          spacing: Style.space(4)
          Text {
            textFormat: Text.PlainText
            text: "M"
            color: button.foreground
            font.family: button.fontFamily
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }
          Components.MeterBar {
            trackColor: root.meterTrack
            segments: [
              { fraction: root.memComp ? root.memComp.usedPct / 100 : 0, color: root.memMeterFill }
            ]
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: false
          acceptedButtons: Qt.LeftButton
          onPressed: root.noteSegmentPress()
          onClicked: root.segmentClicked("mem")
        }
      }

      // ---- GPU segment (auto-hides with no supported GPU) ----
      Item {
        visible: root.segmentEnabled("gpu") && root.gpuAvailable
        implicitWidth: gpuRow.implicitWidth
        implicitHeight: gpuRow.implicitHeight

        Row {
          id: gpuRow
          spacing: Style.space(4)
          Text {
            textFormat: Text.PlainText
            text: "G"
            color: button.foreground
            font.family: button.fontFamily
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }
          Components.MeterBar {
            trackColor: root.meterTrack
            segments: [
              { fraction: root.gpuDisplay ? root.gpuDisplay.pct / 100 : 0, color: root.gpuMeterFill }
            ]
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: false
          acceptedButtons: Qt.LeftButton
          onPressed: root.noteSegmentPress()
          onClicked: root.segmentClicked("gpu")
        }
      }

      // ---- Network segment (two-line rates) ----
      Item {
        visible: root.segmentEnabled("network")
        implicitWidth: Style.space(Theme.metrics.barNetWidth)
        implicitHeight: netCol.implicitHeight

        Column {
          id: netCol
          width: parent.width
          spacing: 0
          Text {
            textFormat: Text.PlainText
            width: parent.width
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignRight
            text: "↑ " + (root.ifaceRates ? Model.formatRateCompact(root.ifaceRates.txBps) : "--")
            color: button.foreground
            font.family: button.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignRight
            text: "↓ " + (root.ifaceRates ? Model.formatRateCompact(root.ifaceRates.rxBps) : "--")
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
}
