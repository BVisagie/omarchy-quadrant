import QtQuick
import "components" as Components
import Quickshell
import "lib/index.mjs" as Model
import "graph-data.mjs" as Graphs

// Public screenshots use illustrative readings and identities. No collectors,
// desktop inventory scans, clipboard requests, or launch actions are used.
HardwareFixture {
  id: fixture
  property var settingsRaw: ({})
  cfg: Model.readSettings(settingsRaw)
  includeCores: true
  property bool expandedProcesses: false
  property var processApps: Components.ProcessApps {
    active: false
    desktopValues: [
      { id: "t3code", name: "T3 Code Nightly", startupClass: "t3code", command: ["t3code-nightly", "%U"],
        icon: String(Qt.resolvedUrl("icons/t3code-nightly.png")) },
      { id: "brave-origin", name: "Brave Origin", command: ["brave-origin", "%U"],
        icon: String(Qt.resolvedUrl("icons/brave-origin.png")) }
    ]
    nativeAppLibrary: QtObject {
      function iconSource(icon) {
        return icon && icon !== "application-x-executable" ? icon : String(Qt.resolvedUrl("icons/application-x-executable.svg"))
      }
    }
  }
  property int processCount: cfg.processCount
  property string rateUnit: cfg.rateUnit
  property string procError: ""
  property string netError: ""
  property string nvidiaError: ""
  property string integratedGpuError: ""
  property string diskDeviceError: ""
  property string diskInfoError: ""
  property string networkInterfaceError: ""
  property bool pinnedInterface: false
  property string networkInterface: "auto"
  property string effectiveInterface: "eth0"
  property string effectiveDisk: "nvme0n1"
  property bool cpuPackagePowerAvailable: true
  property real cpuFreqMhz: 2400
  property var cpuPct: ({ nonIdle: 18, user: 12, system: 4, iowait: 2, steal: 0 })
  property var coreUsage: ({})
  property var swapRate: ({ inKBs: 0, outKBs: 0 })
  property var memComp: Model.memComposition(sample.mem)
  sample: ({
    cores: 22, tempC: 52, uptimeS: 19260, load: [1.42, 1.08, 0.84],
    psi: { cs10: 0.1, cf10: 0, ms10: 0, mf10: 0 },
    mem: { tot: 32 * 1048576, avl: 22 * 1048576, fre: 17 * 1048576,
      buf: 0, cac: 6 * 1048576, srec: 0, slab: 0.5 * 1048576, swtot: 32 * 1048576, swfre: 32 * 1048576 },
    net: [{ n: "eth0", rx: 2.6 * 1073741824, tx: 384 * 1048576 }, { n: "wlan0", rx: 0, tx: 0 }]
  })
  property var sysInfo: ({
    cpu: { modelName: "Intel Core Ultra 9 185H", physCores: 16, threads: 22, cacheKb: 24576,
      mhzNow: 2400, maxMhz: 5100, governor: "powersave",
      classes: { performance: 6, efficiency: 8, lowpower: 2 },
      topo: Array.from({ length: 22 }, function (_, i) {
        return { id: i, pkg: 0, core: i < 12 ? Math.floor(i / 2) : i - 6,
          cls: i < 12 ? "performance" : i < 20 ? "efficiency" : "lowpower" }
      }) },
    host: { sysVendor: "Example", productName: "Workstation", kernel: "Linux" },
    mem: { ram: { label: "32 GiB · LPDDR5 7467 MT/s" },
      swaps: [{ file: "/dev/zram0", kind: "zram", sizeKb: 32 * 1048576 }],
      zram: [{ dev: "zram0", alg: "zstd" }] },
    net: { byName: {
      eth0: { mac: "02:00:00:00:00:04", addrs: ["192.0.2.4/24", "2001:db8::4/64"], speedMbps: 1000, operstate: "up" },
      wlan0: { mac: "02:00:00:00:00:05", addrs: [], wireless: true, speedMbps: null, operstate: "down" }
    } }
  })
  gpus: [
    { card: "card0", vendor: "intel", driver: "i915", deviceId: "0000:00:02.0", name: "Intel Arc Graphics", role: "integrated" },
    { card: "card1", vendor: "amd", driver: "amdgpu", deviceId: "0000:03:00.0", name: "AMD Radeon RX 7800 XT", role: "discrete" }
  ]
  property var integratedGpuLive: ({ busy: 12, busySource: "drm", freqCurMhz: 1200, freqMaxMhz: 2350, vramUsed: 1.7 * 1073741824, vramTotal: null, memKind: "shared" })
  property string amdCollectionState: Quickshell.env("QUADRANT_RENDER_AMD_STATE") === "sleeping" ? "sleeping" : "fresh"
  property string amdPowerState: amdCollectionState === "sleeping" ? "suspended" : "active"
  // Match graph-data's relative timeline and the invented boot uptime.
  readonly property real gpuFixtureNow: Graphs.history(false, "normal").slice(-1)[0].t
  readonly property real gpuPolicyNowMs: sample.uptimeS * 1000
  readonly property real gpuReadingAgeMs: amdCollectionState === "sleeping" ? 20000 : 0
  property var gpuLive: ({ busy: 38, vramUsed: 16 * 1073741824 * 0.66, vramTotal: 16 * 1073741824,
    tempC: 58, powerW: 87, clockMhz: 2140, memoryClockMhz: 1000, memoryClockSource: "pp_dpm_mclk",
    acquiredAt: gpuFixtureNow - gpuReadingAgeMs / 1000, acquiredMs: gpuPolicyNowMs - gpuReadingAgeMs })
  property var gpuDisplay: ({ pct: 38, estimated: false })
  readonly property string gpuCollectionText: Model.gpuReadingLabel(amdCollectionState, amdPowerState,
    gpuLive.acquiredMs, gpuPolicyNowMs, Math.max(6000, panelIntervalMs * 3))
  readonly property var gpuDetailLive: amdCollectionState === "fresh" ? gpuLive : null
  readonly property string gpuDetailAge: gpuDetailLive
    ? "last read " + Math.floor(Math.max(0, gpuPolicyNowMs - gpuDetailLive.acquiredMs) / 1000) + "s ago" : ""
  property var gpuRows: amdCollectionState === "sleeping" ? [] : [
    { pid: 2600, comm: "blender", value: 30, vram: 4 * 1073741824, sortKey: 30 },
    { pid: 2800, comm: "Hyprland", value: 5, vram: 384 * 1048576, sortKey: 5 }
  ]
  diskInfo: ({
    disks: [{ name: "nvme0n1", model: "Example NVMe SSD", sizeBytes: 1024 * 1073741824, rotational: false, tempC: 41 }],
    mounts: [{ source: "/dev/nvme0n1p2", target: "/", size: 200 * 1073741824, used: 84 * 1073741824, pct: 42 },
      { source: "/dev/nvme0n1p3", target: "/home", size: 800 * 1073741824, used: 288 * 1073741824, pct: 36 }],
    backing: { nvme0n1p2: "nvme0n1", nvme0n1p3: "nvme0n1" }
  })
  property var diskRates: ({ utilPct: 20, readBps: 25 * 1048576, writeBps: 8 * 1048576, readIops: 640, writeIops: 256 })
  property var ifaceRates: ({ rxBps: 2.4 * 1048576, txBps: 180 * 1024 })
  property var netRows: [
    { pid: 2200, comm: "brave", rx: 2 * 1048576, tx: 100 * 1024, sortKey: 2.1 * 1048576, history: [1, 2, 3, 2, 4, 3] },
    { pid: 3100, comm: "git", rx: 0.3 * 1048576, tx: 60 * 1024, sortKey: 0.4 * 1048576, history: [1, 2, 2, 3, 2, 4] },
    { pid: 0, comm: "Other traffic", rx: 0.1 * 1048576, tx: 20 * 1024, sortKey: 0.2 * 1048576 }
  ]
  property var procStats: ({ mode: expandedProcesses ? "expanded" : "compact", dt: 2, rateState: "ready",
    candidateLimit: 20, procs: expandedProcesses ? 13 : 248, running: 2, threads: 1048, unreadable: 3,
    cpuReady: expandedProcesses ? 10 : 245, ioVisible: expandedProcesses ? 10 : 102,
    ioReady: expandedProcesses ? 10 : 102, ioHidden: expandedProcesses ? 3 : 146 })
  property var cpuRows: processRows("cpu", false)
  property var memRows: processRows("mem", false)
  property var ioRows: processRows("io", false)
  property var allCpuRows: processRows("cpu", true)
  property var allMemRows: processRows("mem", true)
  property var allIoRows: processRows("io", true)
  function processRows(metric, expanded) {
    var names = ["brave", "brave", "t3code", "t3code", "blender", "quickshell", "Hyprland", "terminal", "git", "music"]
    var rows = names.map(function (name, i) {
      var value = metric === "mem" ? (expanded ? 420 : 320) * 1024 / (i + 1) : metric === "cpu" ? 4 / (i + 1) : 1048576 / (i + 1)
      return { pid: 2200 + i * 100, start: 100 + i, comm: name, value: value,
        core: metric === "cpu" ? value * 22 : null, read: metric === "io" ? value : null,
        write: metric === "io" ? value / 3 : null, kind: metric === "mem" ? (expanded ? "rss" : "pss") : "" }
    })
    return Model.nameAndCollapse(rows, expanded ? names.length : 5).map(function (row) {
      return Object.assign({}, row, { pct: metric === "mem" ? row.value / fixture.sample.mem.tot * 100 : 0,
        sortKey: row.value, history: [row.value * 0.6, row.value * 0.8, row.value * 0.7, row.value] })
    })
  }
  function history(longer, kind) {
    return Graphs.history(longer, "normal").map(function (p) {
      if (kind === "cpu") return { t: p.t, u: p.b * 12 / 38, s: p.b * 4 / 38, io: p.b * 2 / 38, st: 0 }
      if (kind === "mem") return { t: p.t, u: 31.25 + (p.b - 38) / 28 }
      if (kind === "disk") return { t: p.t, r: p.b / 38 * fixture.diskRates.readBps, w: p.v / 66 * fixture.diskRates.writeBps }
      if (kind === "net") return { t: p.t, rx: p.b / 38 * fixture.ifaceRates.rxBps, tx: p.v / 66 * fixture.ifaceRates.txBps }
      if (kind === "gpu") {
        if (p.t > fixture.gpuLive.acquiredAt) return { t: p.t, b: null, v: null, gap: 1 }
        if (p.t === fixture.gpuLive.acquiredAt) return { t: p.t, b: fixture.gpuLive.busy, v: Model.gpuVramPct(fixture.gpuLive) }
      }
      return { t: p.t, b: p.b, v: p.v }
    })
  }
  property var cpuHistory: history(false, "cpu")
  property var cpuLong: history(true, "cpu")
  property var memHistory: history(false, "mem")
  property var memLong: history(true, "mem")
  property var gpuHistory: history(false, "gpu")
  property var gpuLong: history(true, "gpu")
  property var diskHistory: history(false, "disk")
  property var diskLong: history(true, "disk")
  property var netHistory: history(false, "net")
  property var netLong: history(true, "net")
  function segmentEnabled(name) { return cfg.segments.indexOf(name) >= 0 }
  function setViewer(id, state) { }
  function pollProcesses() { }
  function pollDiskUsage() { }
  function pollNet() { }
  function refreshSysInfo() { }
  function pollNvidia() { }
  function pollDiscreteGpu() { }
}
