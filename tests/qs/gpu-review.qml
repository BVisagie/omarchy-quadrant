import QtQuick
import Quickshell
import Quickshell.Io
import "components" as Components

ShellRoot {
  id: harness
  property string mode: Quickshell.env("QUADRANT_REVIEW_CASE")
  property int phase: 0
  property int ticks: 0
  property int waitUntil: 0
  property int streamPid: 0
  property string sleepingRequests: ""
  property string root: Quickshell.env("QUADRANT_SYS_PATH")

  Components.Store {
    id: store
    settingsRaw: ({ barIntervalMs: 250, panelIntervalMs: 500, integratedGpuDevice: "none" })
    saveIntervalMs: 60000
  }
  FileView { id: requests; path: Quickshell.env("QUADRANT_TEST_REQUESTS"); printErrors: false }
  FileView { id: intelReady; path: Quickshell.env("QUADRANT_INTEL_READY"); printErrors: false }
  FileView { id: status; path: harness.root + "/class/drm/card0/device/power/runtime_status"; printErrors: false }

  function check(value, message) {
    if (value) return
    console.error("QGPUREVIEW fail " + mode + " phase=" + phase + " " + message)
    Qt.quit()
    throw new Error(message)
  }
  function target(vendor) {
    return { card: "card0", vendor: vendor, deviceId: "0000:03:00.0", slot: "0000:03:00.0",
      path: root + "/class/drm/card0/device" }
  }
  function later(next, delay) { waitUntil = ticks + delay; phase = next }
  function done() { console.log("QGPUREVIEW ok " + mode); Qt.quit() }

  function checkHistoryOrdering() {
    var now = Date.now() / 1000, mono = store.currentGpuTimeMs()
    store.gpuHistory = []; store.gpuLong = []; store.gpuSourceSequences = ({})
    store.lastGpuHistoryMs = 0; store.gpuGapMs = 0; store.gpuGapAt = 0
    store.recordAmdHistory({ busy: 10, acquiredAt: now - 20, acquiredMs: mono - 20000 }, "seed")
    store.markGpuGap(now, mono)
    var state = store.amdCollectionState
    store.applyDiscreteGpu(JSON.stringify({ ok: true, vendor: "amd", state: "fresh", pm: "active",
      generation: store.gpuControlGeneration, monoMs: mono - 1000, ts: now - 1, payload: "gpu_busy_percent=20" }))
    check(store.amdCollectionState === state && store.discreteGpuLive === null, "late helper changed collection state")
    store.recordAmdHistory({ busy: 20, acquiredAt: now - 1, acquiredMs: mono - 1000 }, "helper:delayed")
    check(store.gpuHistory[0].b === 10 && store.gpuLong[0].b === 10, "late helper erased history after gap")
    store.recordAmdHistory({ busy: 30, acquiredAt: now + 0.1, acquiredMs: mono + 100 }, "resumed")
    check(store.gpuHistory[0].b === 10 && store.gpuLong[0].b === 10, "resume discarded old history")
    // A real wall-clock rollback still starts a new chronological window.
    store.recordAmdHistory({ busy: 40, acquiredAt: now - 100, acquiredMs: mono + 200 }, "clock-reset")
    check(store.gpuHistory.length === 1 && store.gpuHistory[0].b === 40, "real clock rollback was mistaken for delay")
  }

  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      harness.ticks++
      harness.check(harness.ticks < 150, "deadline exceeded")
      requests.reload()
      if (harness.phase === 0) {
        if (!store.gpuTopologyReady) return
        if (harness.mode === "intel-cancel") {
          store.setIntegratedGpu(harness.target("intel"))
          store.setViewer("cpu", { cpuTab: true, open: true })
          harness.phase = 10
        } else {
          // Break the initial Process.running binding while control setup is pending.
          store.applySettings({ barIntervalMs: 500, panelIntervalMs: 500, integratedGpuDevice: "none" })
          store.applySettings({ barIntervalMs: 250, panelIntervalMs: 500, integratedGpuDevice: "none" })
          store.setGpu(harness.target(harness.mode === "nvidia" ? "nvidia" : "amd"))
          if (harness.mode !== "nvidia") store.setViewer("bar", { gpuSegment: true })
          harness.later(1, 7)
        }
      } else if (harness.phase === 1 && harness.ticks >= harness.waitUntil) {
        harness.check(store.streamLive && store.cpuHistory.length >= 1, "control setup blocked system sampling")
        harness.streamPid = store.streamProcessId
        if (harness.mode === "delayed") harness.check(!store.gpuControlReady, "fixture did not delay setup")
        harness.later(2, 25)
      } else if (harness.phase === 2 && harness.ticks >= harness.waitUntil) {
        harness.check(store.streamLive && store.cpuHistory.length > 5, "system samples stopped")
        harness.check(store.streamProcessId === harness.streamPid, "control readiness restarted the stream")
        if (harness.mode === "failed") {
          harness.check(!store.gpuControlReady && store.gpuControlError !== "", "control failure was not reported")
          harness.done()
        } else if (harness.mode === "nvidia") {
          harness.check(!store.gpuControlReady && store.gpuPolicyNowMs === 0, "NVIDIA-only store started a control heartbeat")
          harness.done()
        } else {
          harness.check(store.gpuControlReady && store.gpuDisplay && store.gpuDisplay.pct === 37,
            "delayed/retried GPU setup did not recover: " + JSON.stringify({ ready: store.gpuControlReady,
              error: store.gpuControlError, state: store.amdCollectionState, gpu: store.gpu, display: store.gpuDisplay }))
          if (harness.mode !== "review") { harness.done(); return }
          var generation = store.gpuControlGeneration
          var state = store.amdCollectionState, baseline = store.discreteDrmPrev
          store.discreteDrmPrev = { sentinel: true }
          store.setViewer("cpu", { cpuTab: true, open: true })
          store.clearViewer("cpu")
          harness.check(store.gpuControlGeneration === generation && store.amdCollectionState === state
            && store.discreteDrmPrev.sentinel === true, "unrelated CPU tab invalidated GPU collection")
          store.discreteDrmPrev = baseline
          store.discreteGpuLive = { busy: 2, acquiredMs: store.amdStreamReading.acquiredMs - 1000, memoryClockMhz: 19 }
          store.setViewer("detail", { gpuTab: true, open: true })
          harness.check(store.gpuLive.busy === 37, "old helper overrode newer stream")
          store.amdCollectionState = "failed"
          harness.check(store.discreteGpuLive === null && store.gpuLive.busy === 37, "failed helper remained current")
          store.discreteGpuLive = { busy: 2, acquiredMs: store.amdStreamReading.acquiredMs - 1000 }
          store.clearViewer("detail")
          store.clearViewer("bar")
          harness.check(store.gpuControlGeneration > generation && store.discreteGpuLive === null,
            "generation change retained current helper data")
          store.setViewer("bar", { gpuSegment: true })
          harness.checkHistoryOrdering()
          status.setText("suspended\n")
          harness.later(3, 10)
        }
      } else if (harness.phase === 3 && harness.ticks >= harness.waitUntil) {
        harness.check(store.amdCollectionState === "sleeping" && !store.drmSampleable && !store.discretePollWanted,
          "sleep started fallback helper polling")
        harness.sleepingRequests = requests.text()
        store.pollDiscreteGpu()
        harness.later(4, 12)
      } else if (harness.phase === 4 && harness.ticks >= harness.waitUntil) {
        harness.check(requests.text() === harness.sleepingRequests, "sleep/refresh spawned another helper")
        harness.done()
      } else if (harness.phase === 10) {
        if (requests.text().indexOf("intel") < 0) return
        store.clearViewer("cpu")
        intelReady.setText("ready\n")
        harness.later(11, 8)
      } else if (harness.phase === 11 && harness.ticks >= harness.waitUntil) {
        harness.check(store.integratedGpuError === "", "intentional Intel cancellation became an error")
        store.setViewer("cpu", { cpuTab: true, open: true })
        harness.later(12, 8)
      } else if (harness.phase === 12 && harness.ticks >= harness.waitUntil) {
        harness.check(store.integratedGpuError === "" && store.integratedGpuLive && store.integratedGpuLive.freqCurMhz === 400,
          "Intel helper did not recover after cancellation")
        harness.done()
      }
    }
  }
}
