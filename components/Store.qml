import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/index.mjs" as Model
import "." as Components

// Quadrant's single data store. The shell creates one as the plugin's
// service (Service.qml) and every bar widget copy — one per monitor —
// binds to it, so the sampler, the GPU pollers, the 60 s and 1 h history
// and the persisted history file exist exactly once. A widget that cannot
// reach the service (pre-4.0.3 shell) embeds its own copy instead.
//
// The store never touches the bar: widgets push their settings and tell
// it which tabs and segments are being looked at (setViewer), and it
// scales the on-demand samplers to that. All derivations are pure
// functions under lib/; this file is wiring and state.
Item {
  id: store

  // Injected by the shell for the service (PluginShellApi, manifest);
  // set by the widget for an embedded copy.
  property var shell: null
  property var runCommand: null
  property bool embedded: false

  readonly property string moduleName: "dev.bvisagie.quadrant"

  function localPath(rel) {
    return decodeURIComponent(String(Qt.resolvedUrl("../" + rel)).replace(/^file:\/\//, ""))
  }

  readonly property string streamScript: localPath("scripts/quadrant-stream")
  readonly property string gpuStatsScript: localPath("scripts/gpu-stats")
  readonly property string diskInfoScript: localPath("scripts/disk-info")
  readonly property string sysInfoScript: localPath("scripts/system-info")

  // ---- settings --------------------------------------------------------
  // `settingsRaw` is the inline shell.json entry as the shell injects it
  // into the widgets; a change made from the panel is applied through
  // `pendingSettings` until the shell delivers the written entry back.
  property var settingsRaw: ({})
  property var pendingSettings: null
  readonly property var cfg: {
    var merged = {}
    var k
    var raw = store.settingsRaw
    if (raw && typeof raw === "object") for (k in raw) merged[k] = raw[k]
    var pending = store.pendingSettings
    if (pending && typeof pending === "object") for (k in pending) merged[k] = pending[k]
    return Model.readSettings(merged)
  }
  readonly property var segmentsSetting: cfg.segments
  readonly property int barIntervalMs: cfg.barIntervalMs
  readonly property int panelIntervalMs: cfg.panelIntervalMs
  readonly property int historyLimit: Math.ceil(60000 / barIntervalMs) + 1
  readonly property int processCount: cfg.processCount
  readonly property string networkInterface: cfg.networkInterface
  readonly property string gpuDevice: cfg.gpuDevice
  readonly property string integratedGpuDevice: cfg.integratedGpuDevice
  readonly property bool diskFallbackWithoutGpu: cfg.diskFallbackWithoutGpu
  readonly property string diskDevice: cfg.diskDevice
  readonly property string barPaletteMode: cfg.barPalette
  readonly property string barLabelsMode: cfg.barLabels
  readonly property string rateUnit: cfg.rateUnit

  function applySettings(raw) {
    settingsRaw = raw && typeof raw === "object" ? raw : {}
    pendingSettings = null
    pendingSettingsTimer.stop()
  }

  // Persist a partial settings object through the shell's in-process
  // writer (full typed entry; unknown keys kept, defaults dropped). A
  // shell without the writer falls back to `omarchy bar set --json`.
  function persistSettings(patch) {
    if (!patch || typeof patch !== "object") return
    var merged = {}
    var k
    if (pendingSettings) for (k in pendingSettings) merged[k] = pendingSettings[k]
    for (k in patch) merged[k] = patch[k]
    pendingSettings = merged
    pendingSettingsTimer.restart()
    var next = Model.settingsPatch(settingsRaw, merged)
    if (shell && typeof shell.updateEntryInline === "function") {
      try {
        var changed = shell.updateEntryInline(moduleName, next)
        if (changed === false) {
          // Nothing to write: the file already holds these values.
          pendingSettings = null
          pendingSettingsTimer.stop()
        }
        return
      } catch (e) {
        // fall through to the CLI path
      }
    }
    if (typeof runCommand !== "function") return
    for (k in patch) {
      if (!Object.prototype.hasOwnProperty.call(patch, k)) continue
      if (!/^[A-Za-z][A-Za-z0-9]*$/.test(k)) continue
      var value = Object.prototype.hasOwnProperty.call(next, k) ? next[k] : Model.SETTING_DEFAULTS[k]
      runCommand("omarchy bar set " + shellQuote(moduleName) + " " + k + " "
                 + shellQuote(JSON.stringify(value)) + " --json")
    }
  }

  function shellQuote(v) {
    return "'" + String(v).replace(/'/g, "'\\''") + "'"
  }

  // An optimistic value that the shell never confirmed (write refused,
  // file unchanged) must not outlive the file.
  Timer {
    id: pendingSettingsTimer
    interval: 4000
    repeat: false
    onTriggered: store.pendingSettings = null
  }

  function segmentEnabled(name) {
    return effectiveBarSegments.indexOf(name) !== -1
  }

  function setBarSegment(name, enabled) {
    if (name === "disk" && gpuTopologyReady && !discreteGpuAvailable && !gpuListFailed) {
      var patch = { diskFallbackWithoutGpu: enabled === true }
      if (enabled !== true && segmentsSetting.indexOf("disk") !== -1)
        patch.segments = Model.toggleSegment(segmentsSetting, "disk", false)
      persistSettings(patch)
      return
    }
    persistSettings({ segments: Model.toggleSegment(segmentsSetting, name, enabled) })
  }

  // ---- viewers ---------------------------------------------------------
  // Each widget copy reports what is on screen; the store only runs the
  // on-demand samplers somebody is looking at.
  property var viewers: ({})
  property int gpuSegmentViewers: 0
  property int gpuTabViewers: 0
  property int cpuTabViewers: 0
  property int memTabViewers: 0
  property int diskTabViewers: 0
  property int netTabViewers: 0
  property int openPanels: 0

  function setViewer(id, state) {
    var next = {}
    for (var k in viewers) if (k !== id) next[k] = viewers[k]
    if (state && typeof state === "object") next[id] = state
    viewers = next
    recomputeViewers()
  }

  function clearViewer(id) {
    setViewer(id, null)
  }

  function recomputeViewers() {
    var seg = 0, gpuTab = 0, cpuTab = 0, memTab = 0, diskTab = 0, netTab = 0, open = 0
    for (var k in viewers) {
      var v = viewers[k]
      if (!v) continue
      if (v.gpuSegment) seg++
      if (v.gpuTab) gpuTab++
      if (v.cpuTab) cpuTab++
      if (v.memTab) memTab++
      if (v.diskTab) diskTab++
      if (v.netTab) netTab++
      if (v.open) open++
    }
    gpuSegmentViewers = seg
    gpuTabViewers = gpuTab
    cpuTabViewers = cpuTab
    memTabViewers = memTab
    diskTabViewers = diskTab
    netTabViewers = netTab
    openPanels = open
  }

  // ---- derived bar lists -----------------------------------------------
  readonly property var effectiveBarSegments: Model.effectiveSegments(
    segmentsSetting, gpuTopologyReady, discreteGpuAvailable, diskFallbackWithoutGpu, gpuListFailed !== true)
  readonly property var visibleBarCells: Model.visibleBarCells(effectiveBarSegments, discreteGpuAvailable, diskAvailable)

  // ---- stream state ----------------------------------------------------
  property var sample: null
  property var prevSample: null
  property bool streamLive: false
  property double lastSampleAtMs: 0
  property double streamStartedAtMs: 0
  property string streamError: ""
  property var cpuPct: null
  property var coreUsage: ({})
  property var memComp: null
  property var swapRate: ({ inKBs: 0, outKBs: 0 })
  property var ifaceRates: null
  property var cpuHistory: []
  property var memHistory: []
  property var gpuHistory: []
  property var netHistory: []
  property var diskHistory: []
  property var diskRateList: null
  property var diskRates: null
  readonly property var cpuFreqMhz: sample && sample.cpuFreqMhz !== undefined ? sample.cpuFreqMhz : null
  readonly property bool diskAvailable: sample !== null && sample.disk && sample.disk.length > 0

  // ---- identity --------------------------------------------------------
  property var sysInfo: null
  property bool sysInfoReady: false
  property var diskInfo: null
  property string diskInfoError: ""

  // ---- GPU state -------------------------------------------------------
  property var rawGpus: []
  property var gpus: []
  property var discreteGpus: []
  property var integratedGpus: []
  property var gpu: null
  property var integratedGpu: null
  property bool gpuListReady: false
  property bool gpuListFailed: false
  property bool gpuTopologyReady: false
  property var nvidiaGpu: null
  property string nvidiaError: ""
  property var discreteGpuLive: null
  property var discreteDrmPrev: null
  property var discreteDrmSnap: null
  property var gpuProcessRows: []
  property var nvidiaApps: []
  // Per-process GPU rows for the GPU tab: DRM busy share + resident
  // memory (AMD/Intel) or compute-app memory (NVIDIA, memory only).
  readonly property var gpuRows: {
    var raw = []
    var i
    if (nvidiaSelected) {
      for (i = 0; i < nvidiaApps.length; i++)
        raw.push({ pid: nvidiaApps[i].pid, comm: nvidiaApps[i].comm, value: 0,
                   vram: Model.nvidiaMiBToBytes(nvidiaApps[i].memUsedM) || 0 })
    } else {
      for (i = 0; i < gpuProcessRows.length; i++)
        raw.push({ pid: gpuProcessRows[i].pid, comm: gpuProcessRows[i].comm, value: gpuProcessRows[i].busy,
                   vram: gpuProcessRows[i].dedicated + gpuProcessRows[i].shared })
    }
    var collapsed = Model.nameAndCollapse(raw.map(function (r) {
      return { pid: r.pid, comm: r.comm, exe: "", cmd: "", script: "", value: r.value, read: r.vram }
    }), processCount)
    var out = []
    for (i = 0; i < collapsed.length; i++)
      out.push({ pid: collapsed[i].pid, comm: collapsed[i].comm, value: collapsed[i].value,
                 vram: collapsed[i].read, sortKey: collapsed[i].value * 1e12 + collapsed[i].read })
    return out
  }
  property var igpuDrmPrev: null
  property string gpuDetectionError: ""
  property string gpuDeviceWarning: ""
  property var integratedGpuLive: null
  property string integratedGpuError: ""

  readonly property string streamGpuPath: Model.gpuStreamPath(gpu)
  readonly property string streamGpuVendor: Model.gpuStreamVendor(gpu)
  readonly property string streamGpuSignature: Model.gpuStreamSignature(gpu)
  readonly property bool discreteGpuAvailable: gpuTopologyReady && gpu !== null && gpuListFailed !== true
  readonly property bool nvidiaSelected: gpu !== null && gpu.vendor === "nvidia"
  // nvidia-smi -i indexes NVIDIA devices, not /sys cards.
  readonly property int nvidiaIndex: {
    if (!nvidiaSelected) return 0
    var idx = 0
    for (var i = 0; i < discreteGpus.length; i++) {
      if (discreteGpus[i].vendor !== "nvidia") continue
      if (discreteGpus[i].card === gpu.card) return idx
      idx++
    }
    return 0
  }
  readonly property bool igpuSampleable: {
    if (!integratedGpu) return false
    var v = integratedGpu.vendor
    return v === "amd" || v === "intel"
  }
  // The stream carries AMD busy from sysfs; DRM sampling is needed for
  // Intel cards, for AMD cards whose sysfs lacks gpu_busy_percent, and —
  // while the GPU tab is open — for per-process rows on either.
  readonly property bool drmSampleable: {
    if (!gpu || !gpu.path) return false
    if (gpu.vendor === "intel") return true
    if (gpu.vendor === "amd") {
      var g = sample && sample.gpu
      return !g || g.busy === null || g.busy === undefined
    }
    return false
  }
  readonly property bool discretePollWanted: {
    if (!gpu || !gpu.path) return false
    if (gpu.vendor !== "amd" && gpu.vendor !== "intel") return false
    if (gpuTabViewers > 0) return true
    return drmSampleable && gpuSegmentViewers > 0
  }

  // GPU segment value: { pct, estimated } or null. The stream's sysfs
  // busy wins; the DRM overlay only stands in when the stream has none.
  readonly property var gpuDisplay: {
    if (!gpu) return null
    if (gpu.vendor === "nvidia") {
      if (nvidiaGpu && nvidiaGpu.utilPct !== null) return ({ pct: nvidiaGpu.utilPct, estimated: false })
      return null
    }
    var g = sample ? sample.gpu : null
    if (g && g.busy !== null && g.busy !== undefined) return ({ pct: g.busy, estimated: false })
    var extra = discreteGpuLive
    if (extra && extra.busy !== null && extra.busy !== undefined)
      return ({ pct: extra.busy, estimated: extra.busySource !== "drm" && extra.busySource !== "sysfs" })
    if (g && g.kind === "intel" && g.freqCurMhz !== null && g.freqMaxMhz !== null && g.freqMaxMhz > 0)
      return ({ pct: Model.clamp(100 * g.freqCurMhz / g.freqMaxMhz, 0, 100), estimated: true })
    if (extra && extra.freqEstimate !== null && extra.freqEstimate !== undefined)
      return ({ pct: extra.freqEstimate, estimated: true })
    return null
  }
  // Live GPU object for VRAM: nvidia rows, else the DRM overlay, else the stream.
  readonly property var gpuLive: {
    if (!gpu) return null
    if (gpu.vendor === "nvidia") return nvidiaGpu
    if (discreteGpuLive) return discreteGpuLive
    return sample ? sample.gpu : null
  }

  // ---- disk / interface selection --------------------------------------
  readonly property string effectiveDisk: {
    var disks = diskInfo && diskInfo.disks ? diskInfo.disks : []
    var mounts = diskInfo && diskInfo.mounts ? diskInfo.mounts : []
    var backing = diskInfo && diskInfo.backing ? diskInfo.backing : {}
    return Model.pickDisk(disks, mounts, diskRateList, diskDevice, backing) || ""
  }
  readonly property bool pinnedDisk: diskDevice !== "auto" && diskDevice !== ""
  readonly property string diskDeviceError: {
    if (!pinnedDisk || !sample) return ""
    var backing = diskInfo && diskInfo.backing ? diskInfo.backing : {}
    var disks = diskInfo && diskInfo.disks ? diskInfo.disks : []
    var name = Model.resolveBackingDisk(diskDevice, backing)
    if (Model.diskNamePresent(name, disks, diskRateList)) return ""
    if (Model.diskNamePresent(diskDevice, disks, diskRateList)) return ""
    return "Pinned disk " + diskDevice + " is not available"
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

  // History follows one interface and one disk; a switch starts fresh.
  onEffectiveInterfaceChanged: {
    netHistory = []
    netLong = []
    ifaceRates = null
    resetNetRows()
    if (netSampleWanted) pollNet()
  }
  onEffectiveDiskChanged: { diskHistory = []; diskLong = []; diskRates = null }

  // ---- stream wiring ---------------------------------------------------
  function handleSample(line) {
    var s = Model.parseStreamLine(line)
    if (!s) return
    var dt = prevSample ? s.ts - prevSample.ts : 0
    var pct = Model.cpuDelta(prevSample ? prevSample.cpu : null, s.cpu)
    cpuPct = pct
    var usage = {}
    if (prevSample && prevSample.cpuCores && s.cpuCores) {
      var coreDeltas = Model.cpuCoreDeltas(prevSample.cpuCores, s.cpuCores, prevSample.cpuCoreIds, s.cpuCoreIds)
      for (var c = 0; c < coreDeltas.length; c++) usage[coreDeltas[c].id] = coreDeltas[c].busy
    }
    coreUsage = usage
    var comp = Model.memComposition(s.mem)
    memComp = comp
    swapRate = Model.swapRates(prevSample ? prevSample.vm : null, s.vm, dt)
    var rates = Model.netRates(prevSample ? prevSample.net : null, s.net, dt)
    var ir = null
    for (var i = 0; i < rates.length; i++) {
      if (rates[i].name === effectiveInterface) { ir = rates[i]; break }
    }
    ifaceRates = ir
    if (pct) {
      var cpuPoint = { u: pct.user, s: pct.system, io: pct.iowait, st: pct.steal }
      cpuHistory = Model.pushTimedWindow(cpuHistory, cpuPoint, s.ts, 60, historyLimit)
      cpuLong = Model.pushBucket(adoptLoaded("cpu", ""), cpuPoint, s.ts, longBucketS, longWindowS)
    }
    if (comp) {
      var memPoint = { u: comp.usedPct, p: s.psi ? s.psi.ms10 : null }
      memHistory = Model.pushTimedWindow(memHistory, memPoint, s.ts, 60, historyLimit)
      memLong = Model.pushBucket(adoptLoaded("mem", ""), memPoint, s.ts, longBucketS, longWindowS)
    }
    if (ir) {
      var netPoint = { rx: ir.rxBps, tx: ir.txBps }
      netHistory = Model.pushTimedWindow(netHistory, netPoint, s.ts, 60, historyLimit)
      netLong = Model.pushBucket(adoptLoaded("net", effectiveInterface), netPoint, s.ts, longBucketS, longWindowS)
    }
    var dRates = Model.diskRates(prevSample ? prevSample.disk : null, s.disk, dt)
    diskRateList = dRates
    var chosen = Model.pickDisk(
      diskInfo && diskInfo.disks ? diskInfo.disks : [],
      diskInfo && diskInfo.mounts ? diskInfo.mounts : [],
      dRates, diskDevice, diskInfo && diskInfo.backing ? diskInfo.backing : {})
    var dr = null
    for (var d = 0; d < dRates.length; d++) {
      if (dRates[d].name === chosen) { dr = dRates[d]; break }
    }
    diskRates = dr
    if (dr) {
      var diskPoint = { r: dr.readBps, w: dr.writeBps, b: dr.utilPct }
      diskHistory = Model.pushTimedWindow(diskHistory, diskPoint, s.ts, 60, historyLimit)
      diskLong = Model.pushBucket(adoptLoaded("disk", chosen), diskPoint, s.ts, longBucketS, longWindowS)
    }
    prevSample = s
    sample = s
    streamLive = true
    lastSampleAtMs = Date.now()
    streamError = ""
    recordGpuHistory(s.ts)
    historyDirty = true
  }

  function recordGpuHistory(ts) {
    var disp = gpuDisplay
    if (!disp || !gpu) return
    var point = { b: disp.pct, v: Model.gpuVramPct(gpuLive) }
    gpuHistory = Model.pushTimedWindow(gpuHistory, point, ts, 60, historyLimit)
    gpuLong = Model.pushBucket(adoptLoaded("gpu", gpu.card), point, ts, longBucketS, longWindowS)
  }

  function restartStream() {
    streamProc.intentionalStop = true
    streamProc.running = false
    streamLive = false
    streamRelaunchTimer.restart()
  }

  onBarIntervalMsChanged: restartStream()
  onStreamGpuSignatureChanged: restartStream()

  Process {
    id: streamProc
    property bool intentionalStop: false
    command: {
      var args = [store.streamScript, String(store.barIntervalMs)]
      if (store.streamGpuPath !== "" && store.streamGpuVendor !== "")
        args.push(store.streamGpuPath, store.streamGpuVendor)
      return args
    }
    running: true
    stdout: SplitParser {
      onRead: function (line) { store.handleSample(line) }
    }
    onRunningChanged: if (running) store.streamStartedAtMs = Date.now()
    onExited: function (exitCode) {
      store.streamLive = false
      if (streamProc.intentionalStop) {
        streamProc.intentionalStop = false
      } else {
        if (store.streamError === "")
          store.streamError = "System sampler exited with code " + exitCode
        streamCrashTimer.restart()
      }
    }
  }

  // A live Process can still wedge on a kernel read. Missing ticks keep
  // the last-good data on screen and relaunch the sampler: SIGTERM so its
  // EXIT trap removes the FIFO directory, SIGKILL only if it is stuck.
  Timer {
    id: streamWatchdog
    interval: Math.max(2000, store.barIntervalMs * 3)
    repeat: true
    running: true
    onTriggered: {
      if (!streamProc.running) return
      var reference = store.lastSampleAtMs > store.streamStartedAtMs ? store.lastSampleAtMs : store.streamStartedAtMs
      if (reference > 0 && Date.now() - reference <= interval) return
      store.streamLive = false
      store.streamError = "System sampler stopped producing data; restarting"
      streamProc.signal(15)
      streamKillTimer.restart()
    }
  }
  Timer {
    id: streamKillTimer
    interval: 1500
    repeat: false
    onTriggered: if (streamProc.running) streamProc.signal(9)
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

  // ---- GPU topology ----------------------------------------------------
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
      setGpu(null)
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
    setGpu(Model.pickGpu(topo.discreteGpus, gpuDevice))
    gpuTopologyReady = true
  }

  // Same physical card, new object: keep last-good live metrics. A real
  // identity change (or disappearance) clears everything sampled for the
  // old card so a stale busy value can never be shown for the new one.
  function setGpu(next) {
    if (Model.gpuIdentityEqual(gpu, next)) {
      gpu = next
      return
    }
    gpu = next
    discreteGpuLive = null
    discreteDrmPrev = null
    discreteDrmSnap = null
    gpuProcessRows = []
    nvidiaApps = []
    nvidiaGpu = null
    nvidiaError = ""
    gpuHistory = []
    gpuLong = []
  }

  function setIntegratedGpu(next) {
    if (Model.gpuIdentityEqual(integratedGpu, next)) return
    integratedGpu = next
    integratedGpuLive = null
    integratedGpuError = ""
    igpuDrmPrev = null
    if (igpuSampleable && cpuTabViewers > 0) pollIgpu()
  }

  function selectGpu(card) {
    var chosen = Model.pickGpu(discreteGpus, card)
    if (chosen) {
      setGpu(chosen)
      persistSettings({ gpuDevice: chosen.card })
    }
  }

  onGpuDeviceChanged: {
    if (!gpuTopologyReady || gpuListFailed) return
    gpuDeviceWarning = Model.gpuDevicePinMessage(gpus, gpuDevice)
    setGpu(Model.pickGpu(discreteGpus, gpuDevice))
  }

  onIntegratedGpuDeviceChanged: {
    if (gpuListReady && sysInfoReady) reconcileGpuTopology()
  }

  // Once the stream reports sysfs busy for an AMD card the DRM overlay is
  // no longer the source of truth; drop it so it cannot go stale.
  onDrmSampleableChanged: {
    if (!drmSampleable && gpuTabViewers === 0) discreteGpuLive = null
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

  Components.Sampler {
    id: gpuListProc
    command: [store.gpuStatsScript, "list"]
    timeoutMs: 10000
    onResult: function (text) { store.applyGpuList(text) }
    onFailed: function (message) {
      if (store.gpuListReady) return
      store.gpuDetectionError = "GPU detection " + message
      store.rawGpus = []
      store.gpuListFailed = true
      store.gpuListReady = true
      store.reconcileGpuTopology()
    }
  }

  // ---- hardware identity (one-shot, re-run on R) -----------------------
  function applySysInfo(text) {
    var data = Model.safeJson(text)
    if (data && data.ok === true) sysInfo = Model.parseSystemInfo(data)
    sysInfoReady = true
    reconcileGpuTopology()
  }

  function refreshSysInfo() {
    sysInfoProc.run()
  }

  Components.Sampler {
    id: sysInfoProc
    command: [store.sysInfoScript]
    timeoutMs: 10000
    onResult: function (text) { store.applySysInfo(text) }
    onFailed: function () {
      if (store.sysInfoReady) return
      store.sysInfoReady = true
      store.reconcileGpuTopology()
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
    diskInfoProc.run()
  }

  function selectDisk(name) {
    if (typeof name !== "string" || !/^[A-Za-z0-9._+-]+$/.test(name)) return
    persistSettings({ diskDevice: name })
  }

  Components.Sampler {
    id: diskInfoProc
    command: [store.diskInfoScript]
    onResult: function (text) { store.applyDiskInfo(text) }
    onFailed: function (message) {
      if (store.diskInfoError === "") store.diskInfoError = "Disk detection " + message
    }
  }

  // ---- NVIDIA (on demand) ----------------------------------------------
  function applyNvidia(text) {
    var data = Model.safeJson(text)
    if (!data || data.ok !== true) {
      nvidiaGpu = null
      nvidiaError = (data && data.error) ? String(data.error) : "gpu-stats returned bad output"
      return
    }
    var rows = Model.parseNvidiaCsv(data.payload)
    nvidiaGpu = rows.length > 0 ? rows[0] : null
    nvidiaApps = Model.parseNvidiaApps(data.apps)
    nvidiaError = ""
  }

  function pollNvidia() {
    nvidiaProc.run()
  }

  Timer {
    id: nvidiaTimer
    interval: store.panelIntervalMs
    repeat: true
    running: store.nvidiaSelected && (store.gpuSegmentViewers > 0 || store.gpuTabViewers > 0)
    onRunningChanged: if (running) store.pollNvidia()
    onTriggered: store.pollNvidia()
  }

  Components.Sampler {
    id: nvidiaProc
    command: [store.gpuStatsScript, "sample", "nvidia", String(store.nvidiaIndex)]
    onResult: function (text) { store.applyNvidia(text) }
    onFailed: function (message) {
      store.nvidiaGpu = null
      if (store.nvidiaError === "") store.nvidiaError = "gpu-stats " + message
    }
  }

  // ---- DRM / sysfs polls (on demand) -----------------------------------
  function applyDrmOverlay(data, which, live) {
    var prev = which === "igpu" ? igpuDrmPrev : discreteDrmPrev
    var snap = Model.parseDrmSnapshot(data && data.drm)
    var busy = Model.drmBusyPercent(prev, snap)
    if (snap) {
      if (which === "igpu") {
        igpuDrmPrev = snap
      } else {
        gpuProcessRows = Model.drmProcessRows(prev, snap)
        discreteDrmPrev = snap
        discreteDrmSnap = snap
      }
    }
    return Model.mergeGpuLive(live, busy, snap)
  }

  function applyIgpu(text) {
    var data = Model.safeJson(text)
    if (!data || data.ok !== true) {
      integratedGpuError = (data && data.error) ? String(data.error) : "gpu-stats returned bad output"
      return
    }
    var live = null
    if (data.vendor === "intel") live = Model.normalizeIntelGpu(Model.parseKeyValues(data.payload))
    else if (data.vendor === "amd") live = Model.normalizeAmdGpu(Model.parseKeyValues(data.payload))
    if (live) {
      integratedGpuLive = applyDrmOverlay(data, "igpu", live)
      integratedGpuError = ""
      return
    }
    integratedGpuError = "gpu-stats returned no readable iGPU metrics"
  }

  function pollIgpu() {
    if (!igpuSampleable || cpuTabViewers === 0) return
    igpuProc.run()
  }

  Timer {
    id: igpuTimer
    interval: store.panelIntervalMs
    repeat: true
    running: store.igpuSampleable && store.cpuTabViewers > 0
    onRunningChanged: if (running) store.pollIgpu()
    onTriggered: store.pollIgpu()
  }

  Components.Sampler {
    id: igpuProc
    command: {
      if (!store.igpuSampleable) return [store.gpuStatsScript, "sample", "intel", "/sys/class/drm"]
      return [store.gpuStatsScript, "sample", store.integratedGpu.vendor, store.integratedGpu.path]
    }
    onResult: function (text) { store.applyIgpu(text) }
    onFailed: function (message) {
      if (store.integratedGpuError === "") store.integratedGpuError = "gpu-stats " + message
    }
  }

  function applyDiscreteGpu(text) {
    var data = Model.safeJson(text)
    if (!data || data.ok !== true) {
      discreteGpuLive = null
      return
    }
    var live = null
    if (data.vendor === "intel") live = Model.normalizeIntelGpu(Model.parseKeyValues(data.payload))
    else if (data.vendor === "amd") live = Model.normalizeAmdGpu(Model.parseKeyValues(data.payload))
    if (!live) live = { kind: data.vendor || "" }
    discreteGpuLive = applyDrmOverlay(data, "discrete", live)
  }

  function pollDiscreteGpu() {
    if (!discretePollWanted) return
    discreteGpuProc.run()
  }

  Timer {
    id: discreteGpuTimer
    interval: store.panelIntervalMs
    repeat: true
    running: store.discretePollWanted
    onRunningChanged: if (running) store.pollDiscreteGpu()
    onTriggered: store.pollDiscreteGpu()
  }

  Components.Sampler {
    id: discreteGpuProc
    command: {
      if (!store.discretePollWanted) return [store.gpuStatsScript, "sample", "intel", "/sys/class/drm"]
      return [store.gpuStatsScript, "sample", store.gpu.vendor, store.gpu.path]
    }
    onResult: function (text) { store.applyDiscreteGpu(text) }
  }

  // ---- panel process samplers (on demand) ------------------------------
  // One /proc walk feeds the CPU, Memory and Drives tabs while any of them
  // is open on any monitor; process-net runs while a Network tab is open.
  // Rows keep raw numbers; tabs format them.
  property var procSample: null
  property var cpuRows: []        // { pid, comm, value: machine %, core: one-core %, sortKey, history }
  property var memRows: []        // { pid, comm, value: KiB, pct, kind, sortKey, history }
  property var ioRows: []         // { pid, comm, read, write, value: B/s, sortKey, history }
  // Short per-row trends for the sparklines: the last `sparkLength` values
  // of every row that is currently shown, keyed by pid per metric. Rows
  // that leave the list drop their trend.
  readonly property int sparkLength: 30
  property var sparkHist: ({ cpu: {}, mem: {}, io: {}, net: {}, gpu: {} })

  function withSpark(metric, rows) {
    var prev = sparkHist[metric] || {}
    var next = {}
    var out = []
    for (var i = 0; i < rows.length; i++) {
      var r = rows[i]
      var key = String(r.pid)
      var hist = Array.isArray(prev[key]) ? prev[key].slice() : []
      hist.push(Number(r.value) || 0)
      while (hist.length > sparkLength) hist.shift()
      next[key] = hist
      var copy = {}
      for (var k in r) copy[k] = r[k]
      copy.history = hist
      out.push(copy)
    }
    var all = {}
    for (var m in sparkHist) all[m] = sparkHist[m]
    all[metric] = next
    sparkHist = all
    return out
  }
  property var procStats: null    // { procs, running, threads, ncpu, ioVisible, ioHidden, dt }
  property string procError: ""
  readonly property bool procSampleWanted: openPanels > 0 && (cpuTabViewers > 0 || memTabViewers > 0 || diskTabViewers > 0)
  readonly property int procWindowS: Math.max(15, Math.ceil(panelIntervalMs * 3 / 1000))

  function applyProcessSample(text) {
    var env = Model.safeJson(text)
    if (!env || env.ok !== true) {
      procError = "process sampler failed: " + ((env && env.error) ? String(env.error) : "bad output")
      return
    }
    var parsed = Model.parseProcessSample(env.payload)
    if (!parsed) {
      procError = "process sampler returned bad output"
      return
    }
    procSample = parsed
    procStats = {
      procs: parsed.procs, running: parsed.running, threads: parsed.threads, ncpu: parsed.ncpu,
      ioVisible: parsed.ioVisible, ioHidden: parsed.ioHidden, dt: parsed.dt
    }
    var limit = processCount
    var totalK = sample ? sample.mem.tot : 0
    var i, c
    var cpuMapped = []
    c = Model.nameAndCollapse(parsed.cpu, limit)
    for (i = 0; i < c.length; i++)
      cpuMapped.push({ pid: c[i].pid, comm: c[i].comm, value: c[i].value, core: c[i].core, sortKey: c[i].value })
    // A sampler run without an interval (first run after a cold start)
    // has no CPU rows; keep the roster rather than flashing it empty.
    if (parsed.dt > 0 || cpuRows.length === 0) cpuRows = withSpark("cpu", Model.mergeRoster(cpuRows, cpuMapped, limit))
    var memMapped = []
    c = Model.nameAndCollapse(parsed.mem, limit)
    for (i = 0; i < c.length; i++)
      memMapped.push({ pid: c[i].pid, comm: c[i].comm, value: c[i].value, kind: c[i].kind || "rss",
                       pct: totalK > 0 ? 100 * c[i].value / totalK : null, sortKey: c[i].value })
    memRows = withSpark("mem", Model.mergeRoster(memRows, memMapped, limit))
    var ioMapped = []
    c = Model.nameAndCollapse(parsed.io, limit)
    for (i = 0; i < c.length; i++)
      ioMapped.push({ pid: c[i].pid, comm: c[i].comm, read: c[i].read, write: c[i].write, value: c[i].value, sortKey: c[i].value })
    if (parsed.dt > 0 || ioRows.length === 0) ioRows = withSpark("io", Model.mergeRoster(ioRows, ioMapped, limit))
    procError = ""
  }

  function pollProcesses() {
    if (!procSampleWanted) return
    procSampler.run()
  }

  Timer {
    id: procTimer
    interval: store.panelIntervalMs
    repeat: true
    running: store.procSampleWanted
    onRunningChanged: if (running) store.pollProcesses()
    onTriggered: store.pollProcesses()
  }

  Components.Sampler {
    id: procSampler
    command: [store.localPath("scripts/process-sample"), String(store.processCount), "--window", String(store.procWindowS)]
    timeoutMs: Math.max(6000, store.panelIntervalMs * 3)
    onResult: function (text) { store.applyProcessSample(text) }
    onFailed: function (message) {
      if (store.procError === "") store.procError = "process sampler " + message
    }
  }

  property var netRows: []        // { pid, comm, rx, tx, value, sortKey }; pid 0 = Other traffic
  property string netError: ""
  property var netPrevSockets: null
  property var netPrevIf: null
  property real netPrevTs: 0
  readonly property bool netSampleWanted: netTabViewers > 0 && effectiveInterface !== "" && networkInterfaceError === ""

  function resetNetRows() {
    netPrevSockets = null
    netPrevIf = null
    netPrevTs = 0
    netRows = []
    netError = ""
  }

  onNetworkInterfaceErrorChanged: if (networkInterfaceError !== "") resetNetRows()

  function applyNetSample(text) {
    var env = Model.safeJson(text)
    if (!env || env.ok !== true) {
      netError = "network sampler failed: " + ((env && env.error) ? String(env.error) : "bad output")
      return
    }
    var sockets = Model.parseSs(env.payload)
    var currIf = { rx: env.ifRx, tx: env.ifTx }
    var dt = netPrevTs > 0 ? env.ts - netPrevTs : 0
    var result = Model.computeNetAppRows(netPrevSockets, sockets, netPrevIf, currIf, dt, env.addrs)
    var limit = processCount
    var mapped = []
    for (var i = 0; i < result.rows.length; i++) {
      var r = result.rows[i]
      mapped.push({ pid: r.pid, comm: r.comm, rx: r.rxBps, tx: r.txBps, value: r.rxBps + r.txBps, sortKey: r.sortKey })
    }
    // The catch-all row is keyed strictly on pid 0; a process literally
    // named "Other traffic" keeps its own pid and cannot collide with it.
    mapped.push({ pid: 0, comm: "", rx: result.other.rxBps, tx: result.other.txBps,
                  value: result.other.rxBps + result.other.txBps, sortKey: result.other.rxBps + result.other.txBps })
    netRows = withSpark("net", Model.mergeRoster(netRows, mapped, limit + 1))
    netPrevSockets = sockets
    netPrevIf = currIf
    netPrevTs = env.ts
    netError = ""
  }

  function pollNet() {
    if (!netSampleWanted) return
    netSampler.run()
  }

  Timer {
    id: netTimer
    interval: store.panelIntervalMs
    repeat: true
    running: store.netSampleWanted
    onRunningChanged: if (running) store.pollNet()
    onTriggered: store.pollNet()
  }

  Components.Sampler {
    id: netSampler
    command: [store.localPath("scripts/process-net"), store.effectiveInterface]
    timeoutMs: Math.max(7000, store.panelIntervalMs * 3)
    onResult: function (text) { store.applyNetSample(text) }
    onFailed: function (message) {
      if (store.netError === "") store.netError = "network sampler " + message
    }
  }

  // ---- long history + persistence --------------------------------------
  // 10 s mean buckets over one hour, per series, written to one file under
  // $XDG_STATE_HOME so a shell restart does not wipe the graphs. gpu, net
  // and disk series are tagged with the device they were recorded for and
  // only adopted when it still matches.
  readonly property int longBucketS: 10
  readonly property int longWindowS: 3600
  property int saveIntervalMs: 30000
  property var cpuLong: []
  property var memLong: []
  property var gpuLong: []
  property var netLong: []
  property var diskLong: []
  property var loadedHistory: null
  property bool historyDirty: false
  readonly property string stateDir: {
    var xdg = Quickshell.env("XDG_STATE_HOME")
    var base = xdg && xdg !== "" ? xdg : Quickshell.env("HOME") + "/.local/state"
    return base + "/" + moduleName
  }
  readonly property string historyPath: stateDir + "/history.json"

  // Loaded buckets for `series` are glued in front of the live buckets the
  // first time that series is pushed with a matching tag; after that the
  // live array is returned unchanged.
  function adoptLoaded(series, tag) {
    var live = series === "cpu" ? cpuLong : series === "mem" ? memLong
             : series === "gpu" ? gpuLong : series === "net" ? netLong : diskLong
    var loaded = loadedHistory
    if (!loaded || !loaded.series || !loaded.series[series]) return live
    var wantTag = series === "gpu" ? loaded.tags.gpu : series === "net" ? loaded.tags.iface
                : series === "disk" ? loaded.tags.disk : ""
    var next = {}
    for (var k in loaded.series) if (k !== series) next[k] = loaded.series[k]
    loadedHistory = { series: next, tags: loaded.tags }
    if (wantTag !== String(tag || "")) return live
    return Model.mergeBuckets(loaded.series[series], live)
  }

  function applyHistoryFile(text) {
    var parsed = Model.loadHistoryFile(Model.safeJson(text), Date.now() / 1000, longWindowS, longBucketS)
    if (!parsed || !parsed.any) return
    loadedHistory = parsed
  }

  function saveHistory() {
    if (!historyDirty) return
    historyDirty = false
    var payload = Model.historyFilePayload(
      { cpu: cpuLong, mem: memLong, gpu: gpuLong, net: netLong, disk: diskLong },
      { gpu: gpu ? gpu.card : "", iface: effectiveInterface, disk: effectiveDisk },
      Date.now() / 1000)
    try {
      historyFile.setText(JSON.stringify(payload))
    } catch (e) {
      // State dir missing or unwritable: the graphs still work, they just
      // start empty after a restart.
    }
  }

  FileView {
    id: historyFile
    path: store.historyPath
    atomicWrites: true
    printErrors: false
    onLoaded: store.applyHistoryFile(text())
  }

  Process {
    id: stateDirProc
    command: ["mkdir", "-p", store.stateDir]
    running: true
  }

  Timer {
    id: historySaveTimer
    interval: store.saveIntervalMs
    repeat: true
    running: store.streamLive
    onTriggered: store.saveHistory()
  }

  // Identity runs once at startup (and again on R); the stream and the
  // on-demand pollers start themselves.
  Component.onCompleted: {
    gpuListProc.run()
    sysInfoProc.run()
    diskInfoProc.run()
  }

  Component.onDestruction: saveHistory()
}
