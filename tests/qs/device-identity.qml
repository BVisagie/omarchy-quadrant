import QtQuick
import Quickshell
import Quickshell.Io
import "components" as Components
import "lib/index.mjs" as Model

// Deterministic Store test: helpers read staged inventories, then a real
// refresh re-enumerates devices without touching the host's settings.
ShellRoot {
  id: harness
  property int phase: -2
  property int ticks: 0
  property int waitUntil: 0
  property double now: Date.now() / 1000
  property int sequence: 0
  property int cpuCount: 0
  property int diskCount: 0
  property int gpuCount: 0
  property string inventoryBefore: ""
  property var writes: []
  property bool deferWrites: false
  property var deferredEntry: null
  property var cliWrites: []

  QtObject {
    id: fakeShell
    function updateEntryInline(id, settings) {
      harness.writes.push(settings)
      if (harness.deferWrites) harness.deferredEntry = settings
      else store.applySettings(settings)
      return true
    }
  }
  Components.Store {
    id: store
    shell: fakeShell
    settingsRaw: ({ gpuDevice: "card0", gpuDeviceId: "0000:03:00.0", integratedGpuDevice: "none" })
    saveIntervalMs: 60000
  }
  FileView { id: stageFile; path: Quickshell.env("QUADRANT_TEST_STAGE"); printErrors: false }
  FileView { id: diskGate; path: Quickshell.env("QUADRANT_TEST_DISK_GATE"); printErrors: false }
  FileView { id: gpuGate; path: Quickshell.env("QUADRANT_TEST_GPU_GATE"); printErrors: false }
  FileView { id: listGate; path: Quickshell.env("QUADRANT_TEST_LIST_GATE"); printErrors: false }

  function check(value, message) {
    if (value) return
    console.error("QIDENTITY fail phase=" + phase + " " + message)
    Qt.quit()
    throw new Error(message)
  }
  function sample(base) {
    sequence++
    store.handleSample(JSON.stringify({
      v: 1, ts: now + sequence, up: 1000,
      cpu: [100 + sequence * 10, 0, 20 + sequence, 500 + sequence * 10, 0, 0, 0, 0],
      mem: { tot: 1000, fre: 200, avl: 400, buf: 50, cac: 100, srec: 10, slab: 20, swtot: 0, swfre: 0 },
      net: [], disk: [
        { n: "sda", rd: base + sequence, rs: base + sequence, wr: sequence, ws: sequence, io: sequence },
        { n: "sdb", rd: base + sequence, rs: base + sequence, wr: sequence, ws: sequence, io: sequence }
      ]
    }))
  }
  function freshGpuStream() {
    // This fixture stubs the stream. Supply the active observation that now
    // permits helper polling; sleeping/waiting stores must not launch it.
    var at = Date.now() / 1000, mono = store.currentGpuTimeMs()
    store.acceptAmdStream({ state: "fresh", pm: "active", generation: store.gpuControlGeneration,
      path: store.gpu.path, busy: 55, acquiredAt: at, acquiredMs: mono,
      sequence: "identity:" + ticks }, at, mono)
  }
  function stage(name, next) {
    stageFile.setText(name + "\n")
    waitUntil = ticks + 2
    phase = next
  }
  function readyForRefresh(next) {
    if (ticks < waitUntil) return
    store.refreshHardware()
    phase = next
  }
  function assertPins() {
    check(store.gpu && store.gpu.card === "card1", "GPU pin followed another card")
    check(store.integratedGpu && store.integratedGpu.card === "card0", "iGPU pin followed another card")
    check(store.effectiveDisk === "sdb", "disk pin followed another drive")
    check(store.cfg.gpuDevice === "card1" && store.cfg.diskDevice === "sdb" && store.cfg.integratedGpuDevice === "card0", "compatibility names did not migrate")
  }
  function assertUnpinned() {
    check(store.cfg.gpuDevice === "auto" && store.cfg.gpuDeviceId === "", "GPU policy reset re-created its ID")
    check(store.cfg.diskDevice === "auto" && store.cfg.diskDeviceId === "", "disk policy reset re-created its ID")
    check(store.cfg.integratedGpuDevice === "none" && store.cfg.integratedGpuDeviceId === "", "integrated policy reset re-created its ID")
  }
  function rememberInventory() {
    inventoryBefore = JSON.stringify(store.rawGpus)
    store.discreteGpuLive = { busy: 34 }
    store.discreteDrmPrev = { ts: 123 }
    store.integratedGpuLive = { busy: 21 }
    store.igpuDrmPrev = { ts: 456 }
  }
  function assertInventoryRetained() {
    assertPins()
    check(!store.gpuListFailed && store.gpuTopologyReady && store.discreteGpuAvailable, "refresh failure invalidated known topology")
    check(JSON.stringify(store.rawGpus) === inventoryBefore, "refresh failure dropped raw inventory")
    check(store.discreteGpuLive.busy === 34 && store.discreteDrmPrev.ts === 123, "refresh failure erased dedicated readings")
    check(store.integratedGpuLive.busy === 21 && store.igpuDrmPrev.ts === 456, "refresh failure erased integrated readings")
    check(store.gpuLong[0].b === 88 && store.diskLong[0].r === 71, "refresh failure reset history")
    check(store.gpuDetectionError !== "", "refresh failure hid its diagnostic")
  }

  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      harness.ticks++
      harness.check(harness.ticks < 180, "deadline exceeded")
      if (harness.phase === -2) {
        if (!store.gpuListReady || !store.gpuTopologyReady) return
        harness.check(store.gpuListFailed && store.gpus.length === 0 && !store.gpu && !store.integratedGpu, "startup failure fabricated topology")
        harness.check(store.gpuDetectionError !== "", "startup failure hid its diagnostic")
        listGate.setText("ready\n")
        harness.waitUntil = harness.ticks + 2
        harness.phase = -1
      } else if (harness.phase === -1) {
        harness.readyForRefresh(0)
      } else if (harness.phase === 0) {
        if (!store.gpuTopologyReady || !store.bootTimeReady) return
        if (store.gpuListFailed) return
        harness.check(store.gpuDetectionError === "", "success did not clear startup failure")
        harness.check(!store.diskInfoReady, "disk fixture must arrive after stream rates")
        store.applyHistoryFile(JSON.stringify({ v: 2, saved: harness.now - 10,
          tags: { disk: "by-id:wwn-A" }, disk: [{ t: harness.now - 100, r: 71, w: 4, b: 1 }] }))
        harness.sample(0)
        harness.sample(10)
        harness.check(store.effectiveDisk === "" && store.diskLong.length === 0, "provisional rate list selected a disk")
        harness.check(store.loadedHistory.series.disk.length === 1, "inventory race consumed saved disk history")
        diskGate.setText("ready\n")
        harness.phase = 1
      } else if (harness.phase === 1) {
        if (!store.diskInfoReady) return
        harness.sample(20)
        harness.sample(30)
        harness.check(store.diskLong.length > 0 && store.diskLong[0].r === 71, "stable disk history was not adopted")
        store.selectDisk("sda")
        store.selectIntegratedGpu("card1")
        harness.check(store.cfg.diskDeviceId === "wwn-A", "disk picker did not persist its ID")
        harness.check(store.cfg.integratedGpuDeviceId === "0000:08:00.0", "iGPU picker did not persist its ID")
        store.gpuLong = [{ t: harness.now - 100, b: 88 }]
        harness.cpuCount = store.cpuLong.length
        harness.diskCount = store.diskLong.length
        harness.gpuCount = store.gpuLong.length
        harness.stage("swapped", 2)
      } else if (harness.phase === 2) {
        harness.readyForRefresh(3)
      } else if (harness.phase === 3) {
        if (!store.gpu || store.gpu.card !== "card1" || store.effectiveDisk !== "sdb" || store.cfg.diskDevice !== "sdb") return
        harness.assertPins()
        harness.check(store.gpuLong.length === harness.gpuCount && store.gpuLong[0].b === 88, "GPU history reset on renumbering")
        harness.check(store.diskLong.length === harness.diskCount && store.diskLong[0].r === 71, "disk history reset on renumbering")
        harness.check(store.cpuLong.length === harness.cpuCount, "refresh reset CPU history")
        harness.sample(1000000)
        harness.check(store.diskRates === null, "new disk name inherited another device's counters")
        harness.sample(1000010)
        harness.check(store.diskRates && store.diskRates.readBps < 10000, "disk rate baseline did not recover")
        harness.rememberInventory()
        store.applyGpuList('{"ok":false,"error":"refresh failed"}')
        harness.assertInventoryRetained()
        store.applyGpuList("bad json")
        harness.assertInventoryRetained()
        store.applyGpuList('{"ok":true}')
        harness.assertInventoryRetained()
        harness.stage("failed-envelope", 30)
      } else if (harness.phase === 30) {
        harness.readyForRefresh(31)
      } else if (harness.phase === 31) {
        if (store.gpuDetectionError.indexOf("refresh fixture failure") < 0) return
        harness.assertInventoryRetained()
        harness.stage("failed-exit", 32)
      } else if (harness.phase === 32) {
        harness.readyForRefresh(33)
      } else if (harness.phase === 33) {
        if (store.gpuDetectionError.indexOf("code 7") < 0) return
        harness.assertInventoryRetained()
        harness.stage("missing", 4)
      } else if (harness.phase === 4) {
        harness.readyForRefresh(5)
      } else if (harness.phase === 5) {
        if (store.gpu || store.effectiveDisk !== "") return
        harness.check(store.gpuDetectionError === "", "successful refresh did not clear the failure diagnostic")
        harness.check(store.gpuDeviceWarning.indexOf("0000:03:00.0") >= 0, "missing GPU warning lost the pin")
        harness.check(store.diskDeviceError.indexOf("wwn-A") >= 0, "missing disk warning lost the pin")
        harness.check(store.cfg.gpuDeviceId === "0000:03:00.0" && store.cfg.diskDeviceId === "wwn-A", "absent pins were rewritten")
        harness.stage("swapped", 6)
      } else if (harness.phase === 6) {
        harness.readyForRefresh(7)
      } else if (harness.phase === 7) {
        if (!store.gpu || store.effectiveDisk !== "sdb") return
        harness.assertPins()
        harness.check(store.gpuDeviceWarning === "" && store.diskDeviceError === "", "reappearance did not clear warnings")
        harness.check(store.gpuLong[0].b === 88 && store.diskLong[0].r === 71, "missing device erased its stable history")
        store.gpuLong = []
        store.diskLong = []
        store.applyHistoryFile(JSON.stringify({ v: 1, saved: store.bootTime - 1,
          tags: { gpu: "card1", disk: "sdb" }, gpu: [{ t: harness.now - 100, b: 99 }], disk: [{ t: harness.now - 100, r: 99 }] }))
        harness.check(store.adoptLoaded("gpu", store.gpuSeriesIdentity, "card1").length === 0, "previous-boot GPU history adopted")
        harness.check(store.adoptLoaded("disk", store.diskIdentity, "sdb").length === 0, "previous-boot disk history adopted")
        store.applyHistoryFile(JSON.stringify({ v: 1, saved: harness.now,
          tags: { gpu: "card1", disk: "sdb" }, gpu: [{ t: harness.now - 100, b: 77 }], disk: [{ t: harness.now - 100, r: 66 }] }))
        harness.check(store.adoptLoaded("gpu", store.gpuSeriesIdentity, "card1")[0].b === 77, "same-boot GPU history rejected")
        harness.check(store.adoptLoaded("disk", store.diskIdentity, "sdb")[0].r === 66, "same-boot disk history rejected")
        store.setViewer("test", { gpuTab: true, open: true })
        harness.freshGpuStream()
        // The old poll takes 0.5 s. Replace hardware in its slot before it
        // finishes; its result must never become the new card's baseline.
        harness.waitUntil = harness.ticks + 1
        harness.phase = 8
      } else if (harness.phase === 8) {
        if (harness.ticks < harness.waitUntil) return
        var raw = store.rawGpus.map(function (g) { var copy = Object.assign({}, g); if (g.card === "card1") copy.pciId = "1002:7550"; return copy })
        store.applyGpuList(JSON.stringify({ ok: true, gpus: raw }))
        harness.check(store.gpu && store.gpu.pciId === "1002:7550", "replacement did not resolve")
        harness.check(store.discreteDrmPrev === null, "replacement inherited a rate baseline")
        gpuGate.setText("ready\n")
        harness.waitUntil = harness.ticks + 6
        harness.phase = 9
      } else if (harness.phase === 9) {
        if (harness.ticks < harness.waitUntil) return
        harness.check(store.discreteGpuLive === null && store.gpuSampleAtMs === 0, "in-flight result crossed device identities")
        harness.freshGpuStream()
        store.pollDiscreteGpu()
        harness.waitUntil = harness.ticks + 6
        harness.phase = 10
      } else if (harness.phase === 10) {
        if (harness.ticks < harness.waitUntil) return
        harness.check(store.discreteGpuLive && store.discreteGpuLive.busy === 55, "new device's poll did not recover")
        // A final NVIDIA fixture verifies that its helper target is the
        // resolved PCI address, independent of DRM/NVIDIA list ordering.
        store.applyGpuList(JSON.stringify({ ok: true, gpus: [{ card: "card7", slot: "0000:03:00.0", vendor: "nvidia",
          pciId: "10de:2684", path: "/sys/class/drm/card7/device" }] }))
        harness.check(store.gpu.card === "card7" && store.nvidiaTarget === "0000:03:00.0", "NVIDIA target uses enumeration order")
        harness.waitUntil = harness.ticks + 6
        harness.phase = 11
      } else if (harness.phase === 11) {
        if (harness.ticks < harness.waitUntil) return
        harness.check(store.nvidiaGpu && store.nvidiaGpu.utilPct === 42, "NVIDIA poll did not read resolved card")
        store.selectGpu("auto")
        store.selectIntegratedGpu("none")
        store.selectDisk("auto")
        harness.check(store.cfg.gpuDeviceId === "" && store.cfg.gpuDevice === "auto", "auto did not clear GPU pin")
        harness.check(store.cfg.integratedGpuDeviceId === "" && store.cfg.integratedGpuDevice === "none", "none did not clear integrated pin")
        harness.check(store.cfg.diskDeviceId === "" && store.cfg.diskDevice === "auto", "auto did not clear disk pin")
        store.clearViewer("test")
        store.applyGpuList(JSON.stringify({ ok: true, gpus: JSON.parse(harness.inventoryBefore) }))
        store.selectGpu("card1")
        store.selectIntegratedGpu("card0")
        store.selectDisk("sdb")
        harness.assertPins()
        // The shell CLI changes policy keys but leaves IDs in its entry.
        // Delay the writer's acknowledgement and refresh in between: the
        // optimistic reset must already hide every old ID from migration.
        harness.writes = []
        harness.deferWrites = true
        store.applySettings(Object.assign({}, store.settingsRaw, {
          gpuDevice: '"auto"', diskDevice: '"auto"', integratedGpuDevice: '"none"', userNote: "keep"
        }))
        harness.assertUnpinned()
        harness.check(harness.writes.length === 1, "policy resets were not persisted together")
        harness.check(harness.deferredEntry.userNote === "keep", "policy repair dropped unknown settings")
        harness.check(!harness.deferredEntry.gpuDeviceId && !harness.deferredEntry.diskDeviceId && !harness.deferredEntry.integratedGpuDeviceId, "writer retained a reset ID")
        store.refreshHardware()
        harness.waitUntil = harness.ticks + 2
        harness.phase = 12
      } else if (harness.phase === 12) {
        if (harness.ticks < harness.waitUntil) return
        harness.assertUnpinned()
        harness.check(harness.writes.length === 1, "inventory refresh re-pinned an unacknowledged reset")
        harness.deferWrites = false
        store.applySettings(harness.deferredEntry)
        // The plugin's IPC/write path must make the same paired change.
        store.selectGpu("card1")
        store.persistSettings({ gpuDevice: "auto" })
        store.selectIntegratedGpu("card0")
        store.persistSettings({ integratedGpuDevice: "auto" })
        harness.check(store.cfg.integratedGpuDeviceId === "" && store.cfg.integratedGpuDevice === "auto", "integrated auto reset failed")
        store.selectIntegratedGpu("card0")
        store.persistSettings({ integratedGpuDevice: "none" })
        store.selectDisk("sdb")
        store.persistSettings({ diskDevice: "auto" })
        harness.assertUnpinned()
        store.refreshHardware()
        harness.waitUntil = harness.ticks + 2
        harness.phase = 13
      } else if (harness.phase === 13) {
        if (harness.ticks < harness.waitUntil) return
        harness.assertUnpinned()
        // The shell CLI may also set only an ID next to an auto/none
        // policy. That is a new pin, not a reset of an existing one.
        store.applySettings(Object.assign({}, store.settingsRaw, {
          gpuDeviceId: "0000:03:00.0", integratedGpuDeviceId: "0000:08:00.0", diskDeviceId: "wwn-A"
        }))
        harness.waitUntil = harness.ticks + 2
        harness.phase = 14
      } else if (harness.phase === 14) {
        if (harness.ticks < harness.waitUntil) return
        harness.assertPins()
        // Old shells use command writes. Generated reset keys must reach
        // that fallback too, rather than existing only optimistically.
        store.shell = null
        store.runCommand = function (command) { harness.cliWrites.push(command) }
        store.persistSettings({ diskDevice: "auto" })
        harness.check(harness.cliWrites.length === 2, "CLI fallback omitted a paired reset write")
        harness.check(harness.cliWrites.some(function (command) { return command.indexOf(" diskDeviceId '") >= 0 && command.indexOf("'\"\"' --json") >= 0 }), "CLI fallback did not clear the ID")
        var persisted = Model.settingsPatch(store.settingsRaw, store.pendingSettings)
        store.shell = fakeShell
        store.runCommand = null
        store.applySettings(persisted)
        store.migrateDevicePins()
        harness.check(store.cfg.diskDevice === "auto" && store.cfg.diskDeviceId === "", "fallback reset did not survive acknowledgement")
        store.applyGpuList('{"ok":true,"gpus":[]}')
        harness.check(!store.gpu && !store.integratedGpu && store.gpus.length === 0 && !store.gpuListFailed, "successful empty list retained removed hardware")
        store.failGpuList("GPU detection timed out")
        harness.check(!store.gpuListFailed && store.gpus.length === 0, "failed refresh invalidated a successful empty inventory")
        console.log("QIDENTITY ok (delayed inventory, failed refreshes, swaps, missing pins, history, in-flight polls, NVIDIA PCI target)")
        Qt.quit()
      }
    }
  }
}
