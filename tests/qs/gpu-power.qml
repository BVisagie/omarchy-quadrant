import QtQuick
import Quickshell
import Quickshell.Io
import "components" as Components

ShellRoot {
  id: harness
  property int phase: 0
  property int ticks: 0
  property int waitUntil: 0
  property int streamPid: 0
  property double heldAt: 0
  property int historyCount: 0
  property int generation: 0
  property string root: Quickshell.env("QUADRANT_SYS_PATH")

  Components.Store {
    id: store
    settingsRaw: ({ barIntervalMs: 250, panelIntervalMs: 500, integratedGpuDevice: "none" })
    saveIntervalMs: 60000
  }
  FileView { id: status; path: harness.root + "/class/drm/card0/device/power/runtime_status"; printErrors: false }
  FileView { id: busy; path: harness.root + "/class/drm/card0/device/gpu_busy_percent"; printErrors: false }

  function check(value, message) {
    if (value) return
    console.error("QGPUPOWER fail phase=" + phase + " " + message)
    Qt.quit()
    throw new Error(message)
  }
  function target(card) {
    return { card: card, vendor: "amd", deviceId: card === "card0" ? "0000:03:00.0" : "0000:04:00.0",
      slot: card === "card0" ? "0000:03:00.0" : "0000:04:00.0", path: root + "/class/drm/" + card + "/device" }
  }
  function later(next) { waitUntil = ticks + 8; phase = next }
  function measuredCount() {
    return store.gpuHistory.filter(function(p) { return p.gap !== 1 }).length
  }

  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      harness.ticks++
      harness.check(harness.ticks < 150, "deadline exceeded")
      if (harness.phase === 0) {
        if (!store.gpuTopologyReady || !store.streamLive || !store.gpuControlPath) return
        store.setGpu(harness.target("card0"))
        store.setViewer("first", { gpuSegment: true })
        harness.later(1)
      } else if (harness.phase === 1 && harness.ticks >= harness.waitUntil) {
        harness.check(store.gpuDisplay && store.gpuDisplay.pct === 37, "visible stream did not collect")
        harness.check(store.gpuLive.acquiredMs > 0 && store.gpuCollectionText.indexOf("Live") === 0, "fresh reading metadata missing")
        harness.streamPid = store.streamProcessId
        store.setViewer("second", { gpuSegment: true })
        store.clearViewer("first")
        harness.later(2)
      } else if (harness.phase === 2 && harness.ticks >= harness.waitUntil) {
        harness.check(store.gpuSegmentViewers === 1 && store.amdCollectionState === "fresh", "closing one viewer stopped another")
        harness.heldAt = store.gpuLive.acquiredMs
        store.clearViewer("second")
        harness.later(3)
      } else if (harness.phase === 3 && harness.ticks >= harness.waitUntil) {
        harness.check(store.amdCollectionState === "held", "last close did not suppress collection")
        harness.check(store.gpuLive.acquiredMs === harness.heldAt, "held value acquired a new timestamp")
        harness.check(store.gpuHistory[store.gpuHistory.length - 1].gap === 1, "suppression did not create a gap")
        harness.historyCount = harness.measuredCount()
        status.setText("suspended\n")
        store.setViewer("second", { gpuSegment: true, gpuTab: true, open: true })
        harness.later(4)
      } else if (harness.phase === 4 && harness.ticks >= harness.waitUntil) {
        harness.check(store.amdCollectionState === "sleeping", "opening detail queried a sleeping card")
        harness.check(harness.measuredCount() === harness.historyCount, "sleep added cached measurements")
        harness.check(store.gpuLive.acquiredMs === harness.heldAt, "sleep refreshed age")
        harness.check(store.gpuCollectionText.indexOf("Sleeping") === 0, "sleep is not described")
        store.pollDiscreteGpu() // the explicit tab/refresh path must also stay gated
        harness.generation = store.gpuControlGeneration
        store.setViewer("second", { gpuSegment: true, gpuTab: true, open: true, settings: true })
        harness.check(store.gpuControlGeneration === harness.generation, "settings created independent demand")
        harness.later(5)
      } else if (harness.phase === 5 && harness.ticks >= harness.waitUntil) {
        harness.check(harness.measuredCount() === harness.historyCount, "explicit refresh bypassed sleep")
        busy.setText("0\n")
        status.setText("active\n")
        harness.later(6)
      } else if (harness.phase === 6 && harness.ticks >= harness.waitUntil) {
        harness.check(store.gpuDisplay && store.gpuDisplay.pct === 0, "resume lost measured zero")
        harness.check(store.gpuLive.acquiredMs > harness.heldAt, "resume kept old acquisition")
        store.setGpu(harness.target("card1"))
        harness.later(7)
      } else if (harness.phase === 7 && harness.ticks >= harness.waitUntil) {
        harness.check(store.gpuDisplay && store.gpuDisplay.pct === 65, "selection accepted another device's reading")
        harness.check(store.streamProcessId === harness.streamPid, "visibility/device selection restarted the stream")
        harness.check(store.cpuHistory.length > 10 && store.streamLive, "unrelated sampling was interrupted")
        store.setIntegratedGpu(harness.target("card1"))
        store.setViewer("cpu", { open: true, cpuTab: true })
        store.clearViewer("second")
        harness.later(8)
      } else if (harness.phase === 8 && harness.ticks >= harness.waitUntil) {
        harness.check(store.sameAmdDevice && store.integratedGpuLive && store.integratedGpuLive.busy === 65, "same-device CPU demand was not combined")
        store.clearViewer("cpu")
        harness.later(9)
      } else if (harness.phase === 9 && harness.ticks >= harness.waitUntil) {
        harness.check(store.amdCollectionState === "held" && store.streamProcessId === harness.streamPid, "last CPU close did not suppress shared device")
        console.log("QGPUPOWER ok (two viewers, hidden/sleeping/detail/settings/refresh, age, gaps, zero, selection, CPU demand)")
        Qt.quit()
      }
    }
  }
}
