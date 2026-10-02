import QtQuick
import Quickshell
import "components" as Components

// Headless smoke test for the Store: tests/qs-smoke.sh copies the plugin
// tree to a temp dir, drops this file in as its shell.qml and runs it under
// a throwaway quickshell instance — no Omarchy shell needed. Exercises the
// stream, settings application and persistence through a fake
// PluginShellApi, viewer gating, and the history file round trip.
// Prints one JSON line per phase; the runner asserts on them.
ShellRoot {
  id: harness

  property var writes: []
  property int phase: 0

  QtObject {
    id: fakeShell
    function updateEntryInline(id, settings) {
      harness.writes.push({ id: id, settings: settings })
      // Echo what the real shell does: deliver the written entry back.
      var entry = { id: id }
      for (var k in settings) entry[k] = settings[k]
      store.applySettings(entry)
      return true
    }
  }

  Components.Store {
    id: store
    embedded: true
    shell: fakeShell
    saveIntervalMs: 1500
  }

  function report(name, data) {
    console.log("QSMOKE " + JSON.stringify({ phase: name, data: data }))
  }

  Timer {
    interval: 3500
    running: true
    repeat: false
    onTriggered: {
      harness.report("stream", {
        live: store.streamLive,
        error: store.streamError,
        hasCpu: store.cpuPct !== null,
        cores: Object.keys(store.coreUsage).length,
        memUsed: store.memComp ? Math.round(store.memComp.usedPct) : null,
        iface: store.effectiveInterface,
        disk: store.effectiveDisk,
        cells: store.visibleBarCells,
        gpuReady: store.gpuTopologyReady,
        gpu: store.gpu ? store.gpu.card : null,
        cpuHistory: store.cpuHistory.length,
        cpuLong: store.cpuLong.length,
        memLong: store.memLong.length
      })
      // settings: typed apply + optimistic pending + persist
      store.applySettings({ id: "dev.bvisagie.quadrant", processCount: "8", diskDevice: "\"nvme0n1\"" })
      harness.report("settings-legacy", { processCount: store.processCount, diskDevice: store.diskDevice })
      store.setBarSegment("network", false)
      harness.report("settings-persist", {
        segments: store.segmentsSetting,
        pending: store.pendingSettings,
        writes: harness.writes
      })
      // viewers gate the pollers
      store.setViewer("w1", { gpuSegment: true, gpuTab: false, cpuTab: true, memTab: true, diskTab: false, netTab: true, open: true })
      store.setViewer("w2", { gpuSegment: true, gpuTab: true, cpuTab: false, diskTab: false, open: true })
      harness.report("viewers", {
        gpuSeg: store.gpuSegmentViewers, gpuTab: store.gpuTabViewers,
        cpuTab: store.cpuTabViewers, open: store.openPanels,
        discretePoll: store.discretePollWanted,
        procWanted: store.procSampleWanted, netWanted: store.netSampleWanted
      })
      store.clearViewer("w2")
      harness.report("viewers-after", { gpuSeg: store.gpuSegmentViewers, gpuTab: store.gpuTabViewers, open: store.openPanels })
      saveWait.start()
      procWait.start()
    }
  }

  // Two process-sample runs are needed for rates: the first seeds the
  // interval state, the second (one panelInterval later) yields rows.
  Timer {
    id: procWait
    interval: 4600
    repeat: false
    onTriggered: {
      harness.report("procs", {
        error: store.procError,
        stats: store.procStats,
        cpuRows: store.cpuRows.length,
        memRows: store.memRows.length,
        memKind: store.memRows.length ? store.memRows[0].kind : null,
        netError: store.netError,
        netRows: store.netRows.length
      })
    }
  }

  Timer {
    id: saveWait
    interval: 5200
    repeat: false
    onTriggered: {
      harness.report("saved", { dirty: store.historyDirty, path: store.historyPath })
      Qt.quit()
    }
  }
}
