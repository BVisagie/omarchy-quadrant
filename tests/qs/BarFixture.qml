import QtQuick
import "lib/index.mjs" as Model

// Shared synthetic service for bar presentation/interaction tests. There are
// no collectors or poll methods here: widgets can only use shared snapshots.
QtObject {
  id: root
  property var settingsRaw: ({})
  readonly property var cfg: Model.readSettings(settingsRaw)
  readonly property var segmentsSetting: cfg.segments
  readonly property string barStyle: cfg.barStyle
  readonly property int barGraphWidth: cfg.barGraphWidth
  readonly property var barOrder: cfg.barOrder
  readonly property string barLabelsMode: cfg.barLabels
  readonly property string barPaletteMode: cfg.barPalette
  readonly property string rateUnit: cfg.rateUnit
  readonly property int barIntervalMs: cfg.barIntervalMs
  readonly property int processCount: cfg.processCount
  readonly property int panelIntervalMs: cfg.panelIntervalMs
  readonly property bool diskFallbackWithoutGpu: cfg.diskFallbackWithoutGpu
  property bool gpuTopologyReady: true
  property bool gpuListFailed: false
  property bool discreteGpuAvailable: true
  property bool diskAvailable: true
  readonly property var effectiveBarSegments: Model.effectiveSegments(segmentsSetting, gpuTopologyReady, discreteGpuAvailable, diskFallbackWithoutGpu, !gpuListFailed, barOrder)
  readonly property var visibleBarCells: Model.visibleBarCells(effectiveBarSegments, discreteGpuAvailable, diskAvailable)
  property bool streamLive: true
  property var cpuPct: ({ nonIdle: 42, user: 30, system: 8, iowait: 3, steal: 1 })
  property var memComp: ({ usedPct: 62, usedK: 20000000 })
  property var gpuDisplay: ({ pct: 38, estimated: false })
  property var gpu: ({ vendor: "intel" })
  property var diskRates: ({ utilPct: 18, readBps: 10000, writeBps: 2000 })
  property var ifaceRates: ({ rxBps: 2000000, txBps: 100000 })
  property var cpuHistory: []
  property var memHistory: []
  property var gpuHistory: []
  property var diskHistory: []
  property var netHistory: []
  property var viewers: ({})
  property var writes: []
  property var discreteGpus: []
  property var gpus: []
  property var sample: null
  property var diskInfo: null

  function applySettings(raw) { if (JSON.stringify(raw) !== JSON.stringify(settingsRaw)) settingsRaw = raw }
  function persistSettings(patch) { writes = writes.concat([patch]); settingsRaw = Model.settingsPatch(settingsRaw, patch) }
  function setBarSegment(name, enabled) { persistSettings(Model.barSegmentPatch(cfg, name, enabled, gpuTopologyReady && !discreteGpuAvailable && !gpuListFailed)) }
  function segmentEnabled(name) { return effectiveBarSegments.indexOf(name) >= 0 }
  function setViewer(id, state) { var next = Object.assign({}, viewers); next[id] = state; viewers = next }
  function clearViewer(id) { var next = Object.assign({}, viewers); delete next[id]; viewers = next }
  function seed(end) {
    var cpu = [], mem = [], gpuPoints = [], disk = [], net = []
    for (var age = 60; age >= 0; age--) {
      var phase = (60 - age) / 60, t = end - age
      // A collection gap and a missing individual GPU reading remain gaps.
      if (age > 22 && age < 32) continue
      var a = 40 + 28 * Math.sin(phase * Math.PI * 4)
      cpu.push({ t: t, u: a * 0.7, s: a * 0.2, io: a * 0.08, st: a * 0.02 })
      mem.push({ t: t, u: 62 + 3 * Math.sin(phase * Math.PI * 2) })
      gpuPoints.push({ t: t, b: age === 10 ? null : a, v: 35 })
      disk.push({ t: t, b: a / 2, r: a * 1024, w: a * 512 })
      net.push({ t: t, rx: a * 32768, tx: (50 - a / 2) * 16384 })
    }
    cpuHistory = cpu; memHistory = mem; gpuHistory = gpuPoints; diskHistory = disk; netHistory = net
  }
  function pulse(ts) {
    var n = 40 + 25 * Math.sin(ts / 3)
    cpuPct = { nonIdle: n }; memComp = { usedPct: 62 }; gpuDisplay = { pct: n, estimated: false }
    diskRates = { utilPct: n / 2 }; ifaceRates = { rxBps: n * 32768, txBps: n * 8192 }
    cpuHistory = Model.pushTimedWindow(cpuHistory, { u: n * 0.7, s: n * 0.2, io: n * 0.08, st: n * 0.02 }, ts, 60, 242)
    memHistory = Model.pushTimedWindow(memHistory, { u: 62 }, ts, 60, 242)
    gpuHistory = Model.pushTimedWindow(gpuHistory, { b: n }, ts, 60, 242)
    diskHistory = Model.pushTimedWindow(diskHistory, { b: n / 2 }, ts, 60, 242)
    netHistory = Model.pushTimedWindow(netHistory, { rx: n * 32768, tx: n * 8192 }, ts, 60, 242)
  }
}
