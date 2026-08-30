import QtQuick
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model
import "Theme.js" as Theme

// Quadrant bar slot: one compact widget covering CPU, GPU, memory, network,
// and an optional disk segment. Owns the long-lived sampler
// (quadrant-stream), the 60s history buffers, and GPU/disk detection; the
// nested Panel reads everything through hostWidget. An empty segments list
// collapses the slot to a system-monitor glyph; the panel stays complete.
BarWidget {
  id: root
  moduleName: "dev.bvisagie.quadrant"

  // ---- settings (manifest barWidget.defaults mirrored as fallbacks) ----
  property var localSegments: null
  readonly property var segmentsSetting: {
    if (Array.isArray(root.localSegments)) return root.localSegments
    return Model.segmentsFromSetting(setting("segments", null))
  }
  readonly property int barIntervalMs: Model.clamp(setting("barIntervalMs", 1000), 250, 60000)
  readonly property int panelIntervalMs: Model.clamp(setting("panelIntervalMs", 2000), 500, 60000)
  readonly property int historyLimit: Math.ceil(60000 / barIntervalMs) + 1
  readonly property int processCount: Model.clamp(setting("processCount", 5), 1, 10)
  readonly property string networkInterface: Model.normalizeDeviceSetting(setting("networkInterface", "auto"))
  readonly property string gpuDevice: Model.normalizeDeviceSetting(setting("gpuDevice", "auto"))
  readonly property string integratedGpuDevice: Model.normalizeIntegratedGpuDevice(setting("integratedGpuDevice", "auto"))
  property var localDiskFallback: null
  readonly property bool diskFallbackWithoutGpu: {
    if (root.localDiskFallback === true || root.localDiskFallback === false)
      return root.localDiskFallback
    return Model.parseBoolSetting(setting("diskFallbackWithoutGpu", true), true)
  }
  readonly property string diskDevice: Model.normalizeDeviceSetting(setting("diskDevice", "auto"))
  readonly property string barPaletteMode: {
    var v = String(setting("barPalette", "theme")).toLowerCase()
    return v === "vivid" ? "vivid" : "theme"
  }
  readonly property string barLabelsMode: {
    var v = String(setting("barLabels", "glyph")).toLowerCase()
    return (v === "letter" || v === "none") ? v : "glyph"
  }
  // Bar glyphs are icons, not captions: they size with the shell's body
  // text so they read at the same weight as neighbouring bar widgets,
  // while the percentage stays at caption.
  readonly property int glyphFontSize: Style.font.body

  readonly property var visibleBarCells: Model.visibleBarCells(
    effectiveBarSegments,
    discreteGpuAvailable,
    diskAvailable
  )
  readonly property int visibleSegmentCount: visibleBarCells.length
  readonly property bool showMonitorFallback: visibleSegmentCount === 0

  readonly property var effectiveBarSegments: Model.effectiveSegments(
    segmentsSetting,
    gpuTopologyReady,
    discreteGpuAvailable,
    diskFallbackWithoutGpu,
    gpuListFailed !== true
  )

  function segmentEnabled(name) {
    return effectiveBarSegments.indexOf(name) !== -1
  }

  function localPath(rel) {
    return decodeURIComponent(String(Qt.resolvedUrl(rel)).replace(/^file:\/\//, ""))
  }

  readonly property string streamScript: localPath("scripts/quadrant-stream")
  readonly property string gpuStatsScript: localPath("scripts/gpu-stats")
  readonly property string diskInfoScript: localPath("scripts/disk-info")

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
  property var diskHistory: []
  property var diskRateList: null
  property var diskRates: null
  property var diskInfo: null
  property string diskInfoError: ""
  property string selectedDiskName: ""

  // ---- GPU state ----
  property var rawGpus: []
  property var gpus: []
  property var discreteGpus: []
  property var integratedGpus: []
  property var gpu: null
  property var integratedGpu: null
  property bool gpuListReady: false
  property bool gpuListFailed: false
  property bool sysInfoReady: false
  property bool gpuTopologyReady: false
  property var nvidiaGpu: null
  property string nvidiaError: ""
  property string gpuDetectionError: ""
  property string gpuDeviceWarning: ""
  property var integratedGpuLive: null
  property string integratedGpuError: ""

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
  readonly property bool diskHot: diskRates !== null && diskRates.utilPct >= 90
  readonly property string cpuValueText: cpuPct ? Model.formatPct(cpuPct.busy) : "--"
  readonly property string memValueText: memComp ? Model.formatPct(memComp.usedPct) : "--"
  readonly property string gpuValueText: {
    if (!gpuDisplay) return "--"
    return (gpuDisplay.estimated ? "~" : "") + Model.formatPct(gpuDisplay.pct)
  }
  readonly property string diskValueText: diskRates ? Model.formatPct(diskRates.utilPct) : "--"
  readonly property color hotTextColor: {
    if (barPaletteMode === "vivid") return Theme.series.cpuSteal
    return themePal.urgent
  }
  readonly property color mutedLabelColor: {
    var c = Theme.mutedFor(String(root.bar ? (root.bar.barForeground || root.bar.foreground) : Color.foreground))
    return c || Color.foreground
  }
  // Single caption/glyph line. Vertical bars drop the glyph, so they
  // keep the caption height. Network's two-line vertical form can be taller.
  readonly property int lineBoxHeight: {
    if (root.vertical) return pctSizer.implicitHeight
    var g = Math.max(cpuGlyphSizer.implicitHeight, netGlyphSizer.implicitHeight)
    return g > pctSizer.implicitHeight ? g : pctSizer.implicitHeight
  }
  // Each cell is its own glyph (or letter) plus one reserved value slot.
  // Sharing the widest glyph padded narrower icons and made the gaps
  // between percentages look uneven.
  function metricLabelWidthFor(metric) {
    if (root.vertical || root.barLabelsMode === "none") return 0
    if (metric === "cpu") return cpuGlyphSizer.implicitWidth
    if (metric === "gpu") return gpuGlyphSizer.implicitWidth
    if (metric === "mem") return memGlyphSizer.implicitWidth
    if (metric === "disk") return diskGlyphSizer.implicitWidth
    if (metric === "net") return netGlyphSizer.implicitWidth
    return 0
  }
  function metricValueWidthFor(metric) {
    var w = pctSizer.implicitWidth
    if (metric === "gpu" && root.reserveEstimatePrefix)
      w += tildeSizer.implicitWidth
    return Math.ceil(w)
  }
  function metricCellWidthFor(metric) {
    var w = metricValueWidthFor(metric)
    var lw = metricLabelWidthFor(metric)
    if (lw > 0)
      w += Style.space(Theme.metrics.barLabelGap) + lw
    if (root.vertical && root.bar)
      return Math.min(w, root.bar.barSize)
    return w
  }
  // Truncating the sizer to int shrank the slot by a fraction of a pixel
  // and ElideRight ate the download rate. Ceil plus one pixel of guard.
  readonly property real networkRateWidth: Math.ceil(netSizer.implicitWidth) + 1
  readonly property real networkCellWidth: {
    var w = root.networkRateWidth
    var lw = metricLabelWidthFor("net")
    if (lw > 0)
      w += Style.space(Theme.metrics.barLabelGap) + lw
    if (root.vertical)
      return Math.min(w, root.verticalSlot)
    return w
  }
  // Only an Intel GPU reporting frequency-derived load ever prefixes "~".
  // Reserving it machine-wide would pad every cell on hardware that
  // can never show it.
  readonly property bool reserveEstimatePrefix: {
    if (!root.segmentEnabled("gpu") || !root.discreteGpuAvailable) return false
    return root.gpu && root.gpu.vendor === "intel"
  }
  readonly property int verticalSlot: root.bar ? root.bar.barSize : Style.bar.sizeVertical
  readonly property bool discreteGpuAvailable: gpuTopologyReady && gpu !== null && gpuListFailed !== true
  readonly property bool gpuAvailable: discreteGpuAvailable
  readonly property bool diskAvailable: sample !== null && sample.disk && sample.disk.length > 0
  readonly property string effectiveDisk: {
    var rates = diskRateList
    var disks = diskInfo && diskInfo.disks ? diskInfo.disks : []
    var mounts = diskInfo && diskInfo.mounts ? diskInfo.mounts : []
    var backing = diskInfo && diskInfo.backing ? diskInfo.backing : {}
    return Model.pickDisk(disks, mounts, rates, selectedDiskName || diskDevice, backing) || ""
  }
  readonly property bool pinnedDisk: diskDevice !== "auto" && diskDevice !== ""
  readonly property string diskDeviceError: {
    if (!pinnedDisk || !sample) return ""
    var backing = diskInfo && diskInfo.backing ? diskInfo.backing : {}
    var disks = diskInfo && diskInfo.disks ? diskInfo.disks : []
    var rates = diskRateList
    var name = Model.resolveBackingDisk(diskDevice, backing)
    if (Model.diskNamePresent(name, disks, rates)) return ""
    if (Model.diskNamePresent(diskDevice, disks, rates)) return ""
    return "Pinned disk " + diskDevice + " is not available"
  }
  readonly property bool nvidiaSelected: gpu !== null && gpu.vendor === "nvidia"
  // Position of the selected card among the NVIDIA cards — nvidia-smi -i
  // indexes NVIDIA devices, not /sys cards.
  readonly property int nvidiaIndex: {
    if (!nvidiaSelected) return 0
    var idx = 0
    var list = discreteGpus
    for (var i = 0; i < list.length; i++) {
      if (list[i].vendor !== "nvidia") continue
      if (list[i].card === gpu.card) return idx
      idx++
    }
    return 0
  }
  readonly property bool panelGpuOpen: panelLoader.item
    ? (panelLoader.item.opened === true && panelLoader.item.currentTab === "gpu")
    : false
  readonly property bool panelCpuOpen: panelLoader.item
    ? (panelLoader.item.opened === true && panelLoader.item.currentTab === "cpu")
    : false
  readonly property bool igpuSampleable: {
    if (!root.integratedGpu) return false
    var v = root.integratedGpu.vendor
    return v === "amd" || v === "intel"
  }

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
    if (segmentEnabled("gpu") && discreteGpuAvailable && gpuDisplay)
      parts.push("GPU " + Model.formatPct(gpuDisplay.pct) + (gpuDisplay.estimated ? " (freq)" : ""))
    if (segmentEnabled("memory") && memComp)
      parts.push("MEM " + Model.formatPct(memComp.usedPct))
    if (segmentEnabled("disk") && diskAvailable && diskRates)
      parts.push("DISK " + Model.formatPct(diskRates.utilPct)
        + "  R " + Model.formatRate(diskRates.readBps)
        + "  W " + Model.formatRate(diskRates.writeBps))
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
  // Quattro's default open-panel mark is 55% of the slot. Quadrant is a
  // wide multi-segment widget, so that became a long underline. A short
  // centered mark matches first-party icon widgets.
  readonly property real indicatorSlot: showMonitorFallback ? Style.bar.statusSlot : Style.bar.iconSlot
  readonly property real openPanelIndicatorWidth: Math.max(Style.space(10), Math.round(indicatorSlot * 0.55))
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(indicatorSlot * 0.55))

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
    var dRates = Model.diskRates(prevSample ? prevSample.disk : null, s.disk, dt)
    diskRateList = dRates
    var chosen = Model.pickDisk(
      diskInfo && diskInfo.disks ? diskInfo.disks : [],
      diskInfo && diskInfo.mounts ? diskInfo.mounts : [],
      dRates,
      selectedDiskName || diskDevice,
      diskInfo && diskInfo.backing ? diskInfo.backing : {}
    )
    diskRates = null
    for (var d = 0; d < dRates.length; d++) {
      if (dRates[d].name === chosen) { diskRates = dRates[d]; break }
    }
    if (diskRates)
      diskHistory = Model.pushTimedWindow(
        diskHistory, { r: diskRates.readBps, w: diskRates.writeBps },
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
  function reconcileGpuTopology() {
    if (!gpuListReady || !sysInfoReady) {
      gpuTopologyReady = false
      return
    }
    if (gpuListFailed) {
      gpus = []
      discreteGpus = []
      integratedGpus = []
      setIntegratedGpu(null)
      gpu = null
      gpuDeviceWarning = ""
      gpuTopologyReady = true
      return
    }
    var topo = Model.reconcileGpuTopology(rawGpus, sysInfo, integratedGpuDevice)
    gpus = topo.gpus
    discreteGpus = topo.discreteGpus
    integratedGpus = topo.integratedGpus
    setIntegratedGpu(topo.integratedGpu)
    gpuDeviceWarning = Model.gpuDevicePinMessage(topo.gpus, gpuDevice)
    gpu = Model.pickGpu(topo.discreteGpus, gpuDevice)
    gpuTopologyReady = true
  }

  function applyGpuList(text) {
    var data = Model.safeJson(text)
    if (!data || data.ok !== true) {
      gpuDetectionError = (data && data.error)
        ? "GPU detection failed: " + String(data.error)
        : "GPU detection returned invalid output"
      rawGpus = []
      gpuListFailed = true
      gpuListReady = true
      reconcileGpuTopology()
      return
    }
    rawGpus = Model.normalizeGpuList(data)
    gpuListFailed = false
    gpuListReady = true
    gpuDetectionError = ""
    reconcileGpuTopology()
  }

  function persistSegments(list) {
    if (!root.bar || typeof root.bar.run !== "function") return
    var value = JSON.stringify(list)
    if (typeof value !== "string" || value.charAt(0) !== "[") return
    var quotedId = (typeof Util !== "undefined" && Util.shellQuote)
      ? Util.shellQuote("dev.bvisagie.quadrant") : "'dev.bvisagie.quadrant'"
    var quotedValue = (typeof Util !== "undefined" && Util.shellQuote)
      ? Util.shellQuote(value) : ("'" + value.replace(/'/g, "'\\''") + "'")
    root.bar.run("omarchy bar set " + quotedId + " segments " + quotedValue)
  }

  function persistBoolSetting(key, enabled) {
    if (!root.bar || typeof root.bar.run !== "function") return
    if (typeof key !== "string" || !/^[A-Za-z][A-Za-z0-9]*$/.test(key)) return
    var quotedId = (typeof Util !== "undefined" && Util.shellQuote)
      ? Util.shellQuote("dev.bvisagie.quadrant") : "'dev.bvisagie.quadrant'"
    root.bar.run("omarchy bar set " + quotedId + " " + key + " " + (enabled ? "true" : "false"))
  }

  function setBarSegment(name, enabled) {
    if (name === "disk" && root.gpuTopologyReady && !root.discreteGpuAvailable && !root.gpuListFailed) {
      root.localDiskFallback = enabled === true
      persistBoolSetting("diskFallbackWithoutGpu", enabled === true)
      if (enabled !== true && root.segmentsSetting.indexOf("disk") !== -1) {
        var withoutDisk = Model.toggleSegment(root.segmentsSetting, "disk", false)
        root.localSegments = withoutDisk
        persistSegments(withoutDisk)
      }
      return
    }
    var next = Model.toggleSegment(root.segmentsSetting, name, enabled)
    root.localSegments = next
    persistSegments(next)
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
    var chosen = Model.pickGpu(discreteGpus, card)
    if (chosen) {
      gpu = chosen
      persistGpuDevice(chosen.card)
    }
  }

  onGpuDeviceChanged: {
    if (!gpuTopologyReady || gpuListFailed) return
    gpuDeviceWarning = Model.gpuDevicePinMessage(gpus, gpuDevice)
    var chosen = Model.pickGpu(discreteGpus, gpuDevice)
    gpu = chosen
  }

  onIntegratedGpuDeviceChanged: {
    if (gpuListReady && sysInfoReady) reconcileGpuTopology()
  }

  // Same physical card, new object: keep last-good live metrics. A real
  // identity change (or disappearance) clears the sample and re-polls.
  function setIntegratedGpu(next) {
    if (Model.gpuIdentityEqual(root.integratedGpu, next)) return
    root.integratedGpu = next
    root.integratedGpuLive = null
    root.integratedGpuError = ""
    if (root.igpuSampleable && root.panelCpuOpen) root.pollIgpu()
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
      if (exitCode !== 0) {
        root.rawGpus = []
        root.gpuListFailed = true
        root.gpuListReady = true
        root.reconcileGpuTopology()
      }
    }
  }

  function applySysInfo(text) {
    var data = Model.safeJson(text)
    if (!data || data.ok !== true) {
      sysInfoReady = true
      reconcileGpuTopology()
      return
    }
    sysInfo = Model.parseSystemInfo(data)
    sysInfoReady = true
    reconcileGpuTopology()
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
    onExited: function(exitCode, exitStatus) {
      if (root.sysInfoReady) return
      if (exitCode === 0) return
      root.sysInfoReady = true
      root.reconcileGpuTopology()
    }
  }

  function applyDiskInfo(text) {
    var data = Model.safeJson(text)
    if (!data || data.ok !== true) {
      diskInfoError = (data && data.error)
        ? "Disk detection failed: " + String(data.error)
        : "Disk detection returned invalid output"
      return
    }
    diskInfo = Model.parseDiskInfo(data)
    diskInfoError = ""
  }

  function refreshDiskInfo() {
    if (diskInfoProc.running) return
    diskInfoWatchdog.restart()
    diskInfoProc.running = true
  }

  function persistDiskDevice(name) {
    if (!root.bar || typeof root.bar.run !== "function") return
    if (typeof name !== "string" || !/^[A-Za-z0-9._+-]+$/.test(name)) return
    var value = '"' + name + '"'
    var quotedId = (typeof Util !== "undefined" && Util.shellQuote)
      ? Util.shellQuote("dev.bvisagie.quadrant") : "'dev.bvisagie.quadrant'"
    var quotedValue = (typeof Util !== "undefined" && Util.shellQuote)
      ? Util.shellQuote(value) : ("'" + value + "'")
    root.bar.run("omarchy bar set " + quotedId + " diskDevice " + quotedValue)
  }

  function selectDisk(name) {
    if (typeof name !== "string" || !/^[A-Za-z0-9._+-]+$/.test(name)) return
    selectedDiskName = name
    persistDiskDevice(name)
    diskHistory = []
  }

  Process {
    id: diskInfoProc
    command: [root.diskInfoScript]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyDiskInfo(text)
    }
    onRunningChanged: if (running) diskInfoWatchdog.restart()
    onExited: function(exitCode, exitStatus) {
      diskInfoWatchdog.stop()
      if (exitCode !== 0 && root.diskInfoError === "")
        root.diskInfoError = "Disk detection exited with code " + exitCode
    }
  }

  Timer {
    id: diskInfoWatchdog
    interval: 6000
    repeat: false
    onTriggered: {
      if (diskInfoProc.running) {
        diskInfoProc.signal(9)
        root.diskInfoError = "Disk detection timed out"
      }
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

  function applyIgpu(text) {
    var data = Model.safeJson(text)
    if (!data || data.ok !== true) {
      root.integratedGpuError = (data && data.error) ? String(data.error) : "gpu-stats returned bad output"
      return
    }
    var live = null
    if (data.vendor === "intel") live = Model.normalizeIntelGpu(Model.parseKeyValues(data.payload))
    else if (data.vendor === "amd") live = Model.normalizeAmdGpu(Model.parseKeyValues(data.payload))
    if (live) {
      root.integratedGpuLive = live
      root.integratedGpuError = ""
      return
    }
    root.integratedGpuError = "gpu-stats returned no readable iGPU metrics"
  }

  function pollIgpu() {
    if (!root.igpuSampleable || !root.panelCpuOpen) return
    if (igpuProc.running) return
    igpuWatchdog.restart()
    igpuProc.running = true
  }

  Timer {
    id: igpuTimer
    interval: root.panelIntervalMs
    repeat: true
    running: root.igpuSampleable && root.panelCpuOpen
    onRunningChanged: if (running) root.pollIgpu()
    onTriggered: root.pollIgpu()
  }

  Process {
    id: igpuProc
    command: {
      if (!root.igpuSampleable) return [root.gpuStatsScript, "sample", "intel", "/sys/class/drm"]
      return [root.gpuStatsScript, "sample", root.integratedGpu.vendor, root.integratedGpu.path]
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyIgpu(text)
    }
    onExited: function(exitCode, exitStatus) {
      igpuWatchdog.stop()
      if (exitCode !== 0 && root.integratedGpuError === "")
        root.integratedGpuError = "gpu-stats exited with code " + exitCode
    }
  }

  Timer {
    id: igpuWatchdog
    interval: 6000
    repeat: false
    onTriggered: {
      if (igpuProc.running) {
        igpuProc.signal(9)
        root.integratedGpuError = "gpu-stats timed out"
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
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.showMonitorFallback ? Theme.barGlyphs.monitor : ""
    hasVisualContent: true
    keepSpace: true
    tooltipText: root.tooltipLine
    // tooltipLine is rates/percentages, never process comm. The shell's
    // WidgetButton tooltip Text is already PlainText.
    // Empty-segment fallback is a compact status item. It keeps the shell's
    // standard icon canvas/font while avoiding icon-slot padding.
    slotSize: root.showMonitorFallback ? Style.bar.statusSlot : Style.bar.iconSlot
    fontSize: Style.bar.iconFont
    fixedWidth: root.vertical
                ? -1
                : (root.showMonitorFallback
                   ? Style.bar.statusSlot
                   : segGrid.implicitWidth + Style.spaceReal(Theme.metrics.barOuterPad) * 2)
    fixedHeight: root.vertical
                 ? (root.showMonitorFallback
                    ? Style.bar.statusSlot
                    : segGrid.implicitHeight + Style.spaceReal(Theme.metrics.barOuterPad) * 2)
                 : -1

    onPressed: function(buttonCode) {
      if (buttonCode !== Qt.LeftButton) return
      if (root.ignoreNextToggle) {
        root.ignoreNextToggle = false
        return
      }
      root.toggle()
    }

    // Shared sizers: cell width is locked to glyph + "100%" so digits
    // never resize the slot. The "~" estimate prefix is reserved only
    // when an Intel GPU can show it. Hidden, not Grid children.
    Text {
      id: pctSizer
      visible: false
      textFormat: Text.PlainText
      text: "100%"
      font.family: button.fontFamily
      font.pixelSize: Style.font.caption
    }
    Text {
      id: tildeSizer
      visible: false
      textFormat: Text.PlainText
      text: "~"
      font.family: button.fontFamily
      font.pixelSize: Style.font.caption
    }
    Text {
      id: cpuGlyphSizer
      visible: false
      textFormat: Text.PlainText
      text: Theme.barLabelFor(root.barLabelsMode, "cpu")
      font.family: button.fontFamily
      font.pixelSize: root.glyphFontSize
    }
    Text {
      id: gpuGlyphSizer
      visible: false
      textFormat: Text.PlainText
      text: Theme.barLabelFor(root.barLabelsMode, "gpu")
      font.family: button.fontFamily
      font.pixelSize: root.glyphFontSize
    }
    Text {
      id: memGlyphSizer
      visible: false
      textFormat: Text.PlainText
      text: Theme.barLabelFor(root.barLabelsMode, "mem")
      font.family: button.fontFamily
      font.pixelSize: root.glyphFontSize
    }
    Text {
      id: diskGlyphSizer
      visible: false
      textFormat: Text.PlainText
      text: Theme.barLabelFor(root.barLabelsMode, "disk")
      font.family: button.fontFamily
      font.pixelSize: root.glyphFontSize
    }
    Text {
      id: netGlyphSizer
      visible: false
      textFormat: Text.PlainText
      text: Theme.barLabelFor(root.barLabelsMode, "net")
      font.family: button.fontFamily
      font.pixelSize: root.glyphFontSize
    }
    Grid {
      id: segGrid
      z: 1
      visible: !root.showMonitorFallback
      anchors.centerIn: parent
      columns: root.vertical ? 1 : Math.max(1, root.visibleBarCells.length)
      columnSpacing: Style.space(Theme.metrics.barSegmentGap)
      rowSpacing: Style.space(Theme.metrics.barSegmentGap)
      verticalItemAlignment: Grid.AlignVCenter
      horizontalItemAlignment: Grid.AlignHCenter

      MetricCell {
        visible: root.segmentEnabled("cpu")
        tab: "cpu"
        metric: "cpu"
        valueText: root.cpuValueText
        hot: root.cpuHot
      }

      MetricCell {
        visible: root.segmentEnabled("gpu") && root.discreteGpuAvailable
        tab: "gpu"
        metric: "gpu"
        valueText: root.gpuValueText
        hot: root.gpuHot
      }

      MetricCell {
        visible: root.segmentEnabled("memory")
        tab: "mem"
        metric: "mem"
        valueText: root.memValueText
        hot: root.memHot
      }

      MetricCell {
        visible: root.segmentEnabled("disk") && root.diskAvailable
        tab: "disk"
        metric: "disk"
        valueText: root.diskValueText
        hot: root.diskHot
      }

      // ---- Network: glyph + inline rates; two-line only on vertical bars ----
      Item {
        visible: root.segmentEnabled("network")
        implicitWidth: root.networkCellWidth
        implicitHeight: root.vertical ? netCol.implicitHeight : root.lineBoxHeight

        Text {
          id: netSizer
          visible: false
          textFormat: Text.PlainText
          text: root.vertical ? "↓999T" : "↑ 999T  ↓ 999T"
          font.family: button.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          id: netLabel
          visible: !root.vertical && Theme.barLabelFor(root.barLabelsMode, "net") !== ""
          textFormat: Text.PlainText
          text: Theme.barLabelFor(root.barLabelsMode, "net")
          color: root.mutedLabelColor
          font.family: button.fontFamily
          font.pixelSize: root.glyphFontSize
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
        }

        Column {
          id: netCol
          anchors.left: netLabel.visible ? netLabel.right : parent.left
          anchors.leftMargin: netLabel.visible ? Style.space(Theme.metrics.barLabelGap) : 0
          anchors.verticalCenter: parent.verticalCenter
          width: netLabel.visible ? root.networkRateWidth : parent.width
          spacing: 0

          Text {
            visible: root.vertical
            textFormat: Text.PlainText
            width: parent.width
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignLeft
            text: "↑" + (root.ifaceRates ? Model.formatRateCompact(root.ifaceRates.txBps) : "--")
            color: button.foreground
            font.family: button.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            visible: !root.vertical
            textFormat: Text.PlainText
            width: parent.width
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignLeft
            text: "↑ " + (root.ifaceRates ? Model.formatRateCompact(root.ifaceRates.txBps) : "--")
                 + "  ↓ " + (root.ifaceRates ? Model.formatRateCompact(root.ifaceRates.rxBps) : "--")
            color: button.foreground
            font.family: button.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            visible: root.vertical
            textFormat: Text.PlainText
            width: parent.width
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignLeft
            text: "↓" + (root.ifaceRates ? Model.formatRateCompact(root.ifaceRates.rxBps) : "--")
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

  // Metric cell: this cell's glyph/letter + a reserved percentage slot.
  // The value hugs the icon; leftover slot width sits after the digits.
  component MetricCell: Item {
    id: cell

    property string tab: ""
    property string metric: ""
    property string valueText: "--"
    property bool hot: false

    readonly property string label: root.vertical ? "" : Theme.barLabelFor(root.barLabelsMode, metric)
    readonly property color valueColor: cell.hot ? root.hotTextColor : button.foreground

    implicitWidth: root.metricCellWidthFor(metric)
    implicitHeight: root.lineBoxHeight

    Text {
      id: labelText
      visible: cell.label !== ""
      textFormat: Text.PlainText
      text: cell.label
      color: root.mutedLabelColor
      font.family: button.fontFamily
      font.pixelSize: root.glyphFontSize
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      textFormat: Text.PlainText
      text: cell.valueText
      color: cell.valueColor
      font.family: button.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignLeft
      elide: Text.ElideRight
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: labelText.visible ? labelText.right : parent.left
      anchors.leftMargin: labelText.visible ? Style.space(Theme.metrics.barLabelGap) : 0
      anchors.right: parent.right
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
