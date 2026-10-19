import QtQuick
import Quickshell
import "components" as Components
import "lib/index.mjs" as Model

ShellRoot {
  id: harness
  property string mode: Quickshell.env("QUADRANT_TEST_MODE")
  property int stage: 0
  property real changed: Date.now()
  property int historyBeforeFailure: 0
  function report(phase) { console.log("QPROCESS " + JSON.stringify({ phase: phase })) }
  function check(condition, message) {
    if (!condition) { console.log("QPROCESS failure " + message); Qt.quit(); return false }
    return true
  }
  Components.Store { id: store; embedded: true }
  Component.onCompleted: {
    store.applySettings({ panelIntervalMs: 10000 })
    store.setViewer("monitor-a", { open: true, cpuTab: true })
    if (mode === "inflight") store.setViewer("monitor-a", { open: true, cpuTab: true, expandedProcesses: true })
    if (mode === "normal") store.setViewer("monitor-b", { open: true, memTab: true })
  }
  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      if (harness.stage === 0 && store.procStats) {
        if (!harness.check(store.procStats.dt === 0, "first run must measure")) return
        harness.report("cold")
        harness.changed = Date.now()
        if (harness.mode === "cancel") store.clearViewer("monitor-a")
        if (harness.mode === "early-valid") {
          var valid = Object.assign({}, store.procSample)
          valid.dt = 0.5
          store.applyProcessSample(JSON.stringify({ ok: true, payload: JSON.stringify(valid) }))
        }
        harness.stage = 1
      } else if (harness.stage === 1) {
        if (harness.mode === "cancel" || harness.mode === "early-valid") {
          if (Date.now() - harness.changed > 900) { harness.report("done"); Qt.quit() }
        } else if (harness.mode === "inflight" && store.procStats.mode === "expanded") {
          harness.report("expanded")
          store.clearViewer("monitor-a")
          harness.changed = Date.now()
          harness.stage = 5
        } else if (harness.mode !== "inflight" && store.procStats && store.procStats.dt > 0) {
          if (!harness.check(store.cpuRows.length <= 5 && store.memRows.length <= 5, "compact bound")) return
          harness.report("warm")
          if (harness.mode === "failed") {
            harness.historyBeforeFailure = store.cpuRows[0].history.length
            store.setViewer("monitor-a", { open: true, cpuTab: true, expandedProcesses: true })
            harness.stage = 20
            return
          }
          store.setViewer("monitor-a", { open: true, cpuTab: true, expandedProcesses: true })
          store.setViewer("monitor-b", { open: true, memTab: true, expandedProcesses: true })
          // Multiple requests still share a single cadence gate and helper.
          for (var i = 0; i < 10; i++) store.pollProcesses()
          harness.stage = 2
        }
      } else if (harness.stage === 2 && store.procStats.mode === "expanded") {
        if (!harness.check(store.expandedProcessViewers === 2 && store.allCpuRows.length === 80 && store.allMemRows.length === 80, "complete shared roster")) return
        if (!harness.check(store.procStats.ioHidden === 20, "I/O restriction metadata")) return
        var before = store.cpuRows[0].history.length
        store.applyProcessSample(JSON.stringify({ ok: true, truncated: true, payload: "" }))
        if (!harness.check(store.cpuRows[0].history.length === before && store.procError.indexOf("coverage") >= 0, "oversized preserves readings")) return
        store.setViewer("monitor-a", { open: true, cpuTab: true })
        if (!harness.check(store.procExpandedWanted && store.expandedProcessViewers === 1, "one remaining expanded viewer")) return
        var first = Model.nameAndCollapse([{pid: 900, start: 1, comm: "identity-test", value: 1}], 1)
        store.withSpark("cpu", first)
        if (!harness.check(store.withSpark("cpu", first)[0].history.length === 2, "surviving member keeps spark")) return
        var reused = Model.nameAndCollapse([{pid: 900, start: 2, comm: "identity-test", value: 1}], 1)
        if (!harness.check(store.withSpark("cpu", reused)[0].history.length === 1, "reused PID starts spark fresh")) return
        harness.report("expanded")
        harness.changed = Date.now()
        harness.stage = 3
      } else if (harness.stage === 3 && Date.now() - harness.changed > 450) {
        harness.report("one-viewer")
        store.clearViewer("monitor-b")
        if (!harness.check(!store.procExpandedWanted && store.procSampleWanted, "last expanded viewer releases")) return
        harness.stage = 4
      } else if (harness.stage === 4 && store.procStats.mode === "compact") {
        harness.report("compact")
        store.clearViewer("monitor-a")
        if (!harness.check(!store.procSampleWanted && !store.procExpandedWanted, "last viewer cancels sampling")) return
        harness.changed = Date.now()
        harness.stage = 5
      } else if (harness.stage === 20 && store.procError.indexOf("fixture process failure") >= 0) {
        if (!harness.check(store.cpuRows[0].history.length === harness.historyBeforeFailure, "failed helper preserves prior readings")) return
        harness.report("failed")
        harness.changed = Date.now()
        harness.stage = 21
      } else if (harness.stage === 21 && Date.now() - harness.changed > 1000) {
        store.clearViewer("monitor-a")
        harness.report("done")
        Qt.quit()
      } else if (harness.stage === 5 && Date.now() - harness.changed > 900) {
        harness.report("done")
        Qt.quit()
      }
    }
  }
}
