//@ pragma OmarchyLoadPatch
import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import QtTest
import qs.Commons as Commons
import "components" as Components
import "tabs" as Tabs
import "lib/index.mjs" as Model

ShellRoot {
 Window {
  id: win
  visible: true
  width: 440
  height: 2400
  HardwareFixture { id: fixture }
  FileView { id: stage; path: Quickshell.env("QUADRANT_TEST_HARDWARE_STATE"); blockWrites: true; printErrors: false }
  FileView { id: requests; path: Quickshell.env("QUADRANT_TEST_HARDWARE_REQUESTS"); watchChanges: true; printErrors: false; onFileChanged: reload() }
  QtObject {
    id: fakePanel
    property bool opened: true
    property bool settingsOpen: false
    property bool longWindow: false
    property string currentTab: "hardware"
    property var currentProcessList: null
    readonly property bool searchFocused: false
    readonly property var currentActions: currentTab === "hardware" ? view.actionList : null
    property var store: fixture
    property int switches: 0
    property int closes: 0
    readonly property var tabs: Model.panelTabs(fixture.discreteGpuAvailable, fixture.hardwareAvailable)
    readonly property var labels: ({ cpu: "CPU", gpu: "GPU", mem: "Memory", disk: "Drives", net: "Network", hardware: "Hardware" })
    onCurrentTabChanged: { if (view) view.actionList.leaveFocus(); keys.forceActiveFocus() }
    function showTab(tab) { currentTab = tab }
    function selectTabIndex(i) { currentTab = tabs[i] }
    function stepTab(d) { currentTab = tabs[(tabs.indexOf(currentTab) + d + tabs.length) % tabs.length] }
    function switchPanel(d) { switches += d }
    function close() { closes++ }
    function focusProcessKeys() { keys.forceActiveFocus() }
    function scrollActionItem(item) { }
    function refreshActiveTab() { view.refresh() }
    function moveCursor(d) { body.contentY = Model.clamp(body.contentY + d * Commons.Style.space(48), 0, Math.max(0, body.contentHeight - body.height)) }
  }
  Components.PanelKeys {
    id: keys
    anchors.fill: parent
    panel: fakePanel
    Components.PanelHeader {
      id: header
      x: 16; y: 16
      width: parent.width - 32
      options: fakePanel.tabs.map(function (t) { return { value: t, label: fakePanel.labels[t] } })
      currentTab: fakePanel.currentTab
      settingsOpen: fakePanel.settingsOpen
      barToggleVisible: false
      onTabSelected: function (value) { fakePanel.currentTab = value }
      onToggleSettings: fakePanel.settingsOpen = !fakePanel.settingsOpen
    }
    Flickable {
      id: body
      x: 16; y: header.y + header.implicitHeight + 16
      width: parent.width - 32; height: Math.max(1, parent.height - y - 16)
      contentWidth: width; contentHeight: view.implicitHeight
      clip: true
      visible: !fakePanel.settingsOpen && fakePanel.currentTab === "hardware"
      Tabs.HardwareTab { id: view; width: body.width; panel: fakePanel; model: fixture }
    }
    Components.SettingsView {
      id: settings
      x: 16; y: header.y + header.implicitHeight + 16
      width: parent.width - 32
      visible: fakePanel.settingsOpen
      store: fixture
    }
  }
  Component { id: storeComponent; Components.Store { } }
  Component { id: cpuComponent; Tabs.CpuTab { width: 408 } }
  Component { id: gpuComponent; Tabs.GpuTab { width: 408 } }
  Component { id: hardwareComponent; Tabs.HardwareTab { width: 408 } }
  TestCase {
    id: tests
    name: "HardwareDetails"
    when: win.visible
    windowShown: true
    property var initialStyle: ({})
    property var initialRaw: null
    property var initialGpus: null
    function initTestCase() { wait(20); initialStyle = Object.assign({}, Commons.Color.shellValues); initialRaw = fixture.raw; initialGpus = fixture.gpus }
    function cleanupTestCase() { console.log("QHARDWAREUI " + JSON.stringify({ passed: qtest_results.passCount, failed: qtest_results.failCount })) }
    function cleanup() { if (qtest_results.failed) console.error("QHARDWAREUI failure: " + qtest_results.functionName + " " + qtest_results.dataTag) }
    function check(value, message) {
      if (!value) console.error("QHARDWAREUI check: " + message + " " + new Error().stack)
      verify(value, message)
    }
    function equal(actual, expected, message) {
      if (actual !== expected) console.error("QHARDWAREUI compare: " + actual + " / " + expected + " " + message + " " + new Error().stack)
      compare(actual, expected, message)
    }
    function texts(item) {
      var result = []
      if ("text" in item && typeof item.text === "string") result.push(item.text)
      for (var child of item.children) result = result.concat(texts(child))
      return result
    }
    function records() {
      requests.reload()
      return String(requests.text()).split("\n").filter(function (line) { return line !== "" }).map(function (line) { return JSON.parse(line) })
    }
    function state(value) { stage.setText(JSON.stringify(value)); wait(30) }
    function realStore() {
      var store = createTemporaryObject(storeComponent, win.contentItem, { settingsRaw: { panelIntervalMs: 500 }, saveIntervalMs: 60000 })
      check(store, "real store created")
      tryCompare(store, "hardwareReady", true)
      equal(store.hardwareError, "")
      return store
    }
    function init() {
      Commons.Style.applyShellValues(initialStyle)
      win.width = 440; win.height = 2400
      fixture.cfg = Model.readSettings({}); fixture.raw = initialRaw; fixture.gpus = initialGpus
      fixture.hardwareError = ""; fixture.selectedGpu = ""; fixture.selectedIntegratedGpu = ""
      fixture.selectionWrites = 0; fixture.lastPatch = ({})
      fakePanel.opened = true; fakePanel.settingsOpen = false; fakePanel.currentTab = "hardware"
      fakePanel.switches = 0; fakePanel.closes = 0
      view.actionList.leaveFocus(); body.contentY = 0
      state({})
      keys.forceActiveFocus()
    }
    function test_pin_and_units_follow_the_selected_identity() {
      var id = fixture.hardwareInventory.sensors[0].id
      fixture.persistSettings({ sensorId: id, temperatureUnit: "fahrenheit" })
      wait(20)
      equal(view.pinnedSensor.id, id)
      check(texts(view).indexOf("126°F") >= 0)
      equal(fixture.hardwareReadings.sensors[0].value, 52)
      equal(fixture.hardwareReadings.sensors[0].criticalC, 100)
      check(texts(view).indexOf("0 RPM · stopped") >= 0)
      var originalRow = findChild(view, "hardwareSensorValue_" + id)
      var hot = Object.assign({}, initialRaw.sensors[0], { value: 101 })
      fixture.raw = Object.assign({}, initialRaw, { sensors: [hot].concat(initialRaw.sensors.slice(1)) })
      wait(20)
      var valueRow = findChild(view, "hardwareSensorValue_" + id)
      equal(valueRow, originalRow, "readings preserve the same sensor delegate")
      equal(valueRow.value, "214°F")
      equal(String(valueRow.valueColor), String(Commons.Color.urgent), "critical comparison remains Celsius")
    }
    function test_missing_pin_survives_removal_and_recovers() {
      var id = fixture.hardwareInventory.sensors[0].id
      fixture.persistSettings({ sensorId: id })
      wait(20); equal(view.pinnedSensor.id, id)
      fixture.raw = Object.assign({}, initialRaw, { sensors: initialRaw.sensors.slice(1) })
      wait(20)
      equal(view.pinnedSensor, null)
      check(findChild(view, "missingSensorPin").visible)
      equal(fixture.cfg.sensorId, id)
      fixture.raw = initialRaw; wait(20)
      equal(view.pinnedSensor.id, id)
    }
    function test_grouped_core_grid_keeps_live_identity_and_error_states() {
      win.width = Commons.Style.space(720) + 32
      var cores = []
      for (var i = 0; i < 8; i++) cores.push(Object.assign({}, initialRaw.sensors[0], {
        id: "hwmon:" + "0".repeat(62) + (32 + i).toString(16), label: "Core " + (i * 4), value: 40 + i
      }))
      fixture.raw = Object.assign({}, initialRaw, { sensors: [initialRaw.sensors[0]].concat(cores, initialRaw.sensors.slice(1)) })
      wait(30)
      var columns = findChild(view, "resourceColumns")
      check(columns.wide)
      var first = findChild(view, "hardwareSensorValue_" + cores[0].id)
      var next = findChild(view, "hardwareSensorValue_" + cores[1].id)
      check(first && next); check(next.x > first.x); equal(next.y, first.y)
      var group = first.parent.parent
      var details = findChild(group, "sensorDeviceDetails")
      details.expanded = true
      var changed = Object.assign({}, cores[0], { value: null, status: "Permission denied" })
      fixture.raw = Object.assign({}, fixture.raw, { sensors: [initialRaw.sensors[0], changed].concat(cores.slice(1), initialRaw.sensors.slice(1)) })
      wait(30)
      equal(findChild(view, "hardwareSensorValue_" + cores[0].id), first)
      equal(first.value, "--")
      check(details.expanded)
      check(texts(first).indexOf("Permission denied") >= 0)
      check(texts(view).indexOf("Core 28") >= 0, "reported core IDs are not renumbered")
      win.width = 320; wait(30)
      check(!columns.wide)
      equal(findChild(view, "hardwareSensorValue_" + cores[0].id), first)
      check(details.expanded)
    }
    function test_gpu_details_preserve_auto_with_keyboard_and_pointer() {
      equal(findChild(view.actionList, "actionButton_0").text, "Details")
      equal(findChild(view.actionList, "actionButton_1").text, "Details")
      keyClick(Qt.Key_A); check(view.actionList.keyboardActive)
      keyClick(Qt.Key_Down); keyClick(Qt.Key_Return)
      equal(fixture.selectedGpu, ""); equal(fakePanel.currentTab, "gpu")
      equal(view.actionList.runner.message, ""); check(!view.actionList.runner.busy)
      fakePanel.currentTab = "hardware"; wait(20)
      mouseClick(findChild(view.actionList, "actionButton_0"))
      equal(fixture.selectedIntegratedGpu, ""); equal(fakePanel.currentTab, "cpu")
      equal(view.actionList.runner.message, "")
      equal(fixture.selectionWrites, 0)
      equal(fixture.cfg.gpuDevice, "auto"); equal(fixture.cfg.gpuDeviceId, "")
      equal(fixture.cfg.integratedGpuDevice, "auto"); equal(fixture.cfg.integratedGpuDeviceId, "")
    }
    function test_select_other_gpu_is_explicit_and_persists_the_shared_selection() {
      var other = Object.assign({}, initialGpus[1], { card: "card2", deviceId: "0000:04:00.0", slot: "0000:04:00.0", name: "Other graphics" })
      fixture.gpus = initialGpus.concat([other]); wait(20)
      equal(findChild(view.actionList, "actionButton_2").text, "Select")
      mouseClick(findChild(view.actionList, "actionButton_2")); wait(20)
      equal(fixture.selectionWrites, 1); equal(fixture.selectedGpu, other.deviceId)
      equal(fixture.cfg.gpuDeviceId, other.deviceId); equal(fixture.gpu.deviceId, other.deviceId)
      equal(fakePanel.currentTab, "gpu")
      fakePanel.currentTab = "hardware"; wait(20)
      equal(findChild(view.actionList, "actionButton_2").text, "Details")
      mouseClick(findChild(view.actionList, "actionButton_2"))
      equal(fixture.selectionWrites, 1, "opening an already selected card does not rewrite settings")
    }
    function test_unavailable_gpu_stays_identified_without_selection() {
      fixture.gpus = [Object.assign({}, initialGpus[1], { telemetryAvailable: false })]
      wait(20)
      var button = findChild(view.actionList, "actionButton_0")
      check(button); check(!button.enabled)
      keyClick(Qt.Key_A); keyClick(Qt.Key_Return)
      check(view.actionList.runner.message.indexOf("Telemetry is unavailable") >= 0)
      equal(fixture.selectedGpu, "")
      check(texts(view).some(function (text) { return text.indexOf("Dedicated graphics") >= 0 }))
    }
    function test_empty_hardware_and_battery_sections_are_conditional() {
      fixture.gpus = []
      fixture.raw = Object.assign({}, initialRaw, { sensors: [], packages: [], batteries: [] })
      wait(20)
      check(!fixture.hardwareAvailable)
      equal(Model.panelTabs(false, false).indexOf("hardware"), -1)
      fixture.raw = Object.assign({}, initialRaw, { batteries: [] })
      wait(20)
      check(fixture.hardwareAvailable)
      // A parent column hides the entire battery section, preserving its title.
      check(!texts(view).some(function (text) { return text.indexOf("Laptop battery") >= 0 }))
    }
    function test_header_plural_and_system_battery_without_scope() {
      var battery = Object.assign({}, initialRaw.batteries[0], { scope: "" })
      fixture.raw = Object.assign({}, initialRaw, { sensors: initialRaw.sensors.slice(0, 1), batteries: [battery] })
      wait(20)
      check(texts(view).indexOf("1 sensor · 1 battery") >= 0)
      check(texts(view).some(function (text) { return text.indexOf("Laptop battery · BAT0 · system battery") >= 0 }))
      fixture.raw = Object.assign({}, initialRaw, { sensors: [], batteries: [] })
      wait(20); check(texts(view).indexOf("0 sensors · 0 batteries") >= 0)
      fixture.raw = initialRaw; wait(20)
      check(texts(view).indexOf("4 sensors · 2 batteries") >= 0)
      check(texts(view).some(function (text) { return text.indexOf("mouse · peripheral") >= 0 }))
    }
    function test_battery_diagnostics_are_per_device_and_do_not_invent_values() {
      var values = texts(view)
      check(values.some(function (text) { return text.indexOf("Laptop battery") >= 0 }))
      check(values.some(function (text) { return text.indexOf("Wireless mouse") >= 0 }))
      check(values.indexOf("78%") >= 0); check(values.indexOf("55%") >= 0)
      check(values.indexOf("0.0 W") >= 0); check(values.indexOf("--") >= 0)
      check(values.indexOf("78.1 Wh") >= 0); check(values.indexOf("84.0 Wh") >= 0)
    }
    function test_settings_dropdowns_accept_keyboard_selection() {
      fakePanel.settingsOpen = true; wait(20)
      var unit = findChild(settings, "temperatureUnitChoice")
      mouseClick(unit); tryCompare(unit, "popupOpen", true)
      keyClick(Qt.Key_Down); keyClick(Qt.Key_Return)
      tryCompare(unit, "popupOpen", false)
      equal(fixture.cfg.temperatureUnit, "fahrenheit")
      var pin = findChild(settings, "sensorPinChoice")
      mouseClick(pin); tryCompare(pin, "popupOpen", true)
      keyClick(Qt.Key_Down); keyClick(Qt.Key_Return)
      equal(fixture.cfg.sensorId, fixture.hardwareInventory.sensors[0].id)
      keys.forceActiveFocus(); keyClick(Qt.Key_Escape)
      check(!fakePanel.settingsOpen)
      equal(view.pinnedSensor.id, fixture.cfg.sensorId)
    }
    function test_keyboard_scroll_and_sixth_tab_preserve_shell_tab() {
      win.height = 500; wait(20)
      keyClick(Qt.Key_Down); check(body.contentY > 0)
      keyClick(Qt.Key_Tab); equal(fakePanel.switches, 1)
      keyClick(Qt.Key_Left); equal(fakePanel.currentTab, "net")
      keyClick(Qt.Key_6); equal(fakePanel.currentTab, "hardware")
      keyClick(Qt.Key_Escape); equal(fakePanel.closes, 1)
    }
    function test_one_collector_serves_two_monitors_and_cpu_power_only() {
      var store = realStore()
      var sampler = findChild(store, "hardwareSampler")
      tryCompare(sampler, "running", false)
      equal(store.hardwareReadings, null)
      var count = records().length
      wait(650); equal(records().length, count, "hidden hardware is not polled")
      store.setViewer("one", { open: true, hardwareTab: true })
      store.setViewer("two", { open: true, hardwareTab: true })
      equal(store.hardwareTabViewers, 2)
      tryVerify(function () { return store.hardwareReadings !== null && store.packageReadings.length > 0 && store.packageReadings[0].watts === 0 }, 3000)
      check(store.hardwareReadings.sensors.some(function (s) { return s.kind === "fan" && s.value === 0 }))
      store.clearViewer("one"); equal(store.hardwareTabViewers, 1)
      store.clearViewer("two"); tryCompare(sampler, "running", false)
      equal(store.hardwareReadings, null); equal(store.energyPrevious, null)
      count = records().length; wait(650); equal(records().length, count)
      store.setViewer("cpu", { open: true, cpuTab: true })
      tryVerify(function () { return store.packageReadings.length > 0 }, 2000)
      equal(store.hardwareReadings, null)
      equal(records().slice(-1)[0].mode, "power")
      store.clearViewer("cpu"); tryCompare(sampler, "running", false)
      store.applyHardwareData(JSON.stringify({ ok: true, mode: "list", sensors: [], packages: [], batteries: [] }), "list")
      count = records().length
      store.setViewer("no-package", { open: true, cpuTab: true })
      wait(650); equal(records().length, count, "CPU without package counters adds no hardware polls")
      store.clearViewer("no-package")
    }
    function test_package_labels_and_separate_memory_clocks_reach_cpu_and_gpu() {
      var store = realStore()
      store.settingsRaw = Object.assign({}, store.settingsRaw, { temperatureUnit: "fahrenheit" })
      store.integratedGpu = { card: "card0", vendor: "amd", name: "APU graphics" }
      store.integratedGpuLive = { tempC: 60, powerW: 22, clockMhz: 2100, memoryClockMhz: 1000, memoryClockSource: "pp_dpm_mclk" }
      store.packageReadings = [{ id: "package-0", watts: 40 }]
      var cpu = createTemporaryObject(cpuComponent, win.contentItem, { model: store })
      check(cpu); wait(20)
      var packageRow = findChild(cpu, "cpuPackagePower")
      var apuRow = findChild(cpu, "cpuApuPower")
      check(packageRow.visible); equal(packageRow.value, "40 W"); check(!apuRow.visible)
      check(texts(cpu).indexOf("140°F") >= 0)
      check(texts(cpu).indexOf("1000 MHz") >= 0)
      store.hardwareInventory = { sensors: [], packages: [{ readable: true }, { readable: false }], batteries: [] }
      wait(20); check(!packageRow.visible); check(apuRow.visible)
      store.hardwareInventory = { sensors: [], packages: [], batteries: [] }
      wait(20); check(!packageRow.visible); check(apuRow.visible); equal(apuRow.value, "22 W")
      store.gpu = { card: "card1", vendor: "amd", name: "Dedicated graphics" }
      store.discreteGpuLive = { tempC: 60, powerW: 87, clockMhz: 2100, memoryClockMhz: 1000, memoryClockSource: "pp_dpm_mclk" }
      var gpu = createTemporaryObject(gpuComponent, win.contentItem, { model: store })
      check(gpu); wait(20)
      var memory = findChild(gpu, "gpuMemoryClock")
      check(memory.visible); equal(memory.value, "1000 MHz")
      check(texts(gpu).some(function (text) { return text.toLowerCase() === "gpu power" })); check(texts(gpu).indexOf("140°F") >= 0)
      store.discreteGpuLive = Object.assign({}, store.discreteGpuLive, { memoryClockMhz: null })
      wait(20); equal(memory.value, "--")
      store.discreteGpuLive = Object.assign({}, store.discreteGpuLive, { memoryClockSource: "" })
      wait(20); check(!memory.visible)
    }
    function test_denied_packages_do_not_poll_cpu_but_hardware_and_r_recover() {
      state({ packageDenied: true })
      var store = realStore()
      var sampler = findChild(store, "hardwareSampler")
      tryCompare(sampler, "running", false)
      check(!store.cpuPackagePowerAvailable); check(store.hardwareAvailable)
      var cpu = createTemporaryObject(cpuComponent, win.contentItem, { model: store })
      var hardware = createTemporaryObject(hardwareComponent, win.contentItem, { model: store })
      var row = findChild(cpu, "cpuPackagePower")
      check(!row.visible)
      var count = records().length
      store.setViewer("cpu-denied", { open: true, cpuTab: true })
      wait(650); equal(records().length, count, "CPU does not poll known unreadable package counters")
      store.setViewer("inspect", { open: true, hardwareTab: true })
      tryVerify(function () { return store.packageReadings.some(function (p) { return p.status === "Permission denied" }) }, 2000)
      check(texts(hardware).some(function (text) { return text.indexOf("Permission denied") >= 0 }))
      store.clearViewer("inspect"); tryCompare(sampler, "running", false)
      count = records().length; wait(650); equal(records().length, count)
      state({}); store.refreshHardwareDetails()
      tryVerify(function () { return store.cpuPackagePowerAvailable && store.packageReadings.length && store.packageReadings[0].watts === 0 }, 3000)
      check(row.visible); equal(row.value, "0.0 W")
      store.clearViewer("cpu-denied"); tryCompare(sampler, "running", false)
    }
    function test_late_results_do_not_repopulate_hidden_details_and_r_recovers() {
      var store = realStore()
      var sampler = findChild(store, "hardwareSampler")
      state({ delay: 0.3, marker: 77 })
      store.setViewer("late", { open: true, hardwareTab: true })
      tryCompare(sampler, "running", true)
      tryVerify(function () { return records().slice(-1)[0].marker === 77 }, 1000)
      store.clearViewer("late")
      tryCompare(sampler, "running", false)
      equal(store.hardwareReadings, null); equal(store.energyPrevious, null)
      state({ marker: 36 })
      store.setViewer("new", { open: true, hardwareTab: true })
      store.refreshHardwareDetails(); store.refreshHardwareDetails()
      tryVerify(function () { return store.hardwareReadings !== null && store.hardwareReadings.sensors.some(function (s) { return s.value === 36 }) }, 2000)
      store.clearViewer("new"); tryCompare(sampler, "running", false)
    }
    function test_failure_clears_live_data_but_keeps_identity_and_can_recover() {
      var store = realStore()
      var sampler = findChild(store, "hardwareSampler")
      state({ fail: true })
      store.setViewer("failure", { open: true, hardwareTab: true })
      tryVerify(function () { return store.hardwareSampleError !== "" }, 2000)
      equal(store.hardwareReadings, null); equal(store.packageReadings.length, 0)
      check(store.hardwareInventory.sensors.length > 0)
      state({ marker: 38 }); store.pollHardware()
      tryVerify(function () { return store.hardwareReadings !== null && store.hardwareSampleError === "" }, 2000)
      store.clearViewer("failure"); tryCompare(sampler, "running", false)
    }
    function test_narrow_large_text_layout_data() {
      var cases = []
      for (var width of [320, 440]) for (var scale of [1, 1.5, 2]) cases.push({ tag: width + " " + scale, width: width, scale: scale })
      return cases
    }
    function test_narrow_large_text_layout(data) {
      win.width = data.width
      Commons.Style.applyShellValues({ "font.base-size": 18, "spacing.scale": data.scale })
      fixture.persistSettings({ temperatureUnit: "fahrenheit" }); wait(30)
      fixture.gpus = fixture.gpus.map(function (g) { return Object.assign({}, g, { name: g.name + " very long graphics adapter model with shared naming" }) })
      wait(20)
      for (var tab of fakePanel.tabs) {
        var button = findChild(header, "panelTab_" + tab)
        check(button && button.width >= button.implicitWidth - 0.5, "full six-tab labels fit")
        check(button.x >= 0 && button.x + button.width <= header.width + 0.5)
      }
      function bounds(item) {
        if (item.visible && "text" in item) {
          var x = item.mapToItem(view, 0, 0).x
          check(x >= -0.5 && x + item.width <= view.width + 0.5, "text stays within panel: " + item.text)
        }
        if ("text" in item && /(^[0-9]+(?:\.[0-9]+)?%$|°[CF]|[0-9] RPM|[0-9] (Wh|Ah|W))/.test(item.text))
          check(!item.truncated, "complete metric value: " + item.text)
        for (var child of item.children) bounds(child)
      }
      bounds(view)
      check(texts(view).indexOf("126°F") >= 0)
    }
  }
 }
}
