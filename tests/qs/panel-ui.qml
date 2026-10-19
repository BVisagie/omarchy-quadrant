//@ pragma OmarchyLoadPatch
import QtQuick
import QtQuick.Window
import Quickshell
import QtTest
import qs.Ui as Ui
import "components" as Components
import "tabs" as Tabs
import "lib/index.mjs" as Model

ShellRoot {
 Window {
  id: testWindow
  visible: true
  width: 440
  height: 1000
  QtObject {
    id: fakePanel
    property bool settingsOpen: false
    property bool longWindow: false
    property bool gpuAvailable: true
    property bool barAvailable: true
    property bool barEnabled: false
    property string currentTab: "cpu"
    property int switches: 0
    property int closes: 0
    property int moves: 0
    property int refreshes: 0
    property var store: null
    property var currentProcessList: searchTarget
    readonly property bool searchFocused: editor.activeFocus
    readonly property var tabs: gpuAvailable ? ["cpu", "gpu", "mem", "disk", "net"] : ["cpu", "mem", "disk", "net"]
    readonly property var labels: ({ cpu: "CPU", gpu: "GPU", mem: "Memory", disk: "Drives", net: "Network" })
    function stepTab(d) { currentTab = tabs[(tabs.indexOf(currentTab) + d + tabs.length) % tabs.length] }
    function selectTabIndex(i) { currentTab = tabs[i] }
    function switchPanel(d) { switches += d }
    function close() { closes++ }
    function moveCursor(d) { moves += d }
    function refreshActiveTab() { refreshes++ }
  }
  QtObject { id: searchTarget; function focusSearch() { editor.forceActiveFocus() } }
  Components.PanelKeys {
    id: keys
    anchors.fill: parent
    panel: fakePanel
    Column {
      width: parent.width - 32
      x: 16
      spacing: 10
      Components.PanelHeader {
        id: header
        width: parent.width
        options: fakePanel.tabs.map(function (t) { return { value: t, label: fakePanel.labels[t] } })
        currentTab: fakePanel.currentTab
        settingsOpen: fakePanel.settingsOpen
        resourceName: fakePanel.labels[fakePanel.currentTab]
        barToggleVisible: fakePanel.barAvailable
        barEnabled: fakePanel.barEnabled
        onTabSelected: function (value) { fakePanel.currentTab = value; fakePanel.settingsOpen = false }
        onToggleBar: fakePanel.barEnabled = !fakePanel.barEnabled
        onToggleSettings: fakePanel.settingsOpen = !fakePanel.settingsOpen
      }
      Components.GraphBlock {
        id: firstGraph
        width: parent.width
        title: "TRAFFIC"
        fields: [{ key: "rx", label: "down", color: "#70b7be" }, { key: "tx", label: "up", color: "#9070be" }]
        longWindow: fakePanel.longWindow
        onToggleWindow: fakePanel.longWindow = !fakePanel.longWindow
      }
      Components.GraphBlock {
        id: secondGraph
        width: parent.width
        title: "USED"
        fields: [{ key: "u", label: "used", color: "#70b7be" }]
        longWindow: fakePanel.longWindow
        onToggleWindow: fakePanel.longWindow = !fakePanel.longWindow
      }
      Ui.TextField { id: editor; width: parent.width }
    }
  }
  Component { id: heroComponent; Components.Hero { } }
  Component { id: memoryComponent; Tabs.MemoryTab { } }
  Component { id: storeComponent; Components.Store { } }
  Component { id: choicesComponent; Components.DeviceChoices { onChanged: function (value) { this.value = value } } }
  TestCase {
    id: testCase
    name: "PanelClarity"
    when: testWindow.visible
    windowShown: true
    function cleanupTestCase() {
      console.log("QPANELUI " + JSON.stringify({ passed: qtest_results.passCount, failed: qtest_results.failCount }))
    }
    function cleanup() {
      if (qtest_results.failed) console.error("QPANELUI failure: " + qtest_results.functionName + " " + qtest_results.dataTag)
    }
    function init() {
      fakePanel.settingsOpen = false; fakePanel.longWindow = false
      fakePanel.gpuAvailable = true; fakePanel.barAvailable = true; fakePanel.barEnabled = false
      fakePanel.currentTab = "cpu"
      fakePanel.switches = 0; fakePanel.closes = 0; fakePanel.moves = 0; fakePanel.refreshes = 0
      testWindow.width = 440
      firstGraph.finePoints = []; firstGraph.longPoints = []; firstGraph.stacked = false
      editor.text = ""; editor.focus = false
      keys.forceActiveFocus()
      wait(20)
    }
    function test_duration_buttons_share_window_without_toggling_selected_choice() {
      var hour = findChild(firstGraph, "graphHour")
      var minute = findChild(secondGraph, "graphMinute")
      mouseClick(hour)
      verify(fakePanel.longWindow)
      verify(firstGraph.longWindow && secondGraph.longWindow)
      verify(findChild(secondGraph, "graphHour").selected)
      mouseClick(hour)
      verify(fakePanel.longWindow, "activating the selected duration is a no-op")
      mouseClick(minute)
      verify(!firstGraph.longWindow && !secondGraph.longWindow)
      compare(firstGraph.windowSeconds, 60)
      mouseClick(findChild(firstGraph, "graphSummary"))
      verify(fakePanel.longWindow, "the existing summary click still switches windows")
      compare(secondGraph.windowSeconds, 3600)
    }
    function test_uppercase_history_lowercase_navigation_and_shell_tab() {
      keyClick("H", Qt.ShiftModifier)
      verify(fakePanel.longWindow)
      keyClick(Qt.Key_H)
      compare(fakePanel.currentTab, "net")
      verify(fakePanel.longWindow, "lowercase h moves tabs without changing history")
      keyClick(Qt.Key_3)
      compare(fakePanel.currentTab, "mem")
      keyClick(Qt.Key_Down)
      compare(fakePanel.moves, 1)
      keyClick(Qt.Key_Tab)
      compare(fakePanel.switches, 1)
      keyClick(Qt.Key_Backtab, Qt.ShiftModifier)
      compare(fakePanel.switches, 0)
      keyClick(Qt.Key_R)
      compare(fakePanel.refreshes, 1)
    }
    function test_graph_wheel_keeps_shared_window_behavior() {
      var graph = findChild(firstGraph, "historyPlot")
      mouseWheel(graph, graph.width / 2, graph.height / 2, 0, 120)
      verify(firstGraph.longWindow && secondGraph.longWindow)
    }
    function test_search_receives_history_shortcut_as_text() {
      keyClick(Qt.Key_Slash)
      tryCompare(editor, "activeFocus", true)
      keyClick("H", Qt.ShiftModifier)
      compare(editor.text, "H")
      verify(!fakePanel.longWindow)
    }
    function test_settings_esc_and_missing_bar_segment() {
      fakePanel.barAvailable = false
      mouseClick(findChild(header, "panelSettings"))
      verify(fakePanel.settingsOpen)
      verify(!findChild(header, "barVisibility").visible)
      keyClick(Qt.Key_Escape)
      verify(!fakePanel.settingsOpen)
      compare(fakePanel.closes, 0)
      keyClick(Qt.Key_2)
      compare(fakePanel.currentTab, "gpu")
      keyClick(Qt.Key_Escape)
      compare(fakePanel.closes, 1)
    }
    function test_header_tabs_fit_data() {
      return [{ tag: "wide five", width: 440, gpu: true }, { tag: "narrow five", width: 320, gpu: true },
              { tag: "wide four", width: 440, gpu: false }, { tag: "narrow four", width: 320, gpu: false }]
    }
    function test_header_tabs_fit(data) {
      testWindow.width = data.width; fakePanel.gpuAvailable = data.gpu
      wait(20)
      var flow = findChild(header, "panelTabs")
      var gear = findChild(header, "panelSettings")
      var toggleRow = findChild(header, "barVisibility")
      for (var i = 0; i < fakePanel.tabs.length; i++) {
        var button = findChild(header, "panelTab_" + fakePanel.tabs[i])
        verify(button.width + 0.5 >= button.implicitWidth, "full tab labels fit even when selected")
        verify(button.x >= 0 && button.x + button.width <= flow.width + 0.5)
        verify(button.y + button.height <= flow.implicitHeight + 0.5)
        fuzzyCompare(button.width, findChild(header, "panelTab_cpu").width, 0.5)
      }
      verify(flow.width < gear.x, "settings never overlaps a tab")
      verify(toggleRow.y >= flow.implicitHeight, "bar control is below all tab rows")
      verify(header.implicitHeight >= toggleRow.y + toggleRow.implicitHeight)
      var durations = findChild(firstGraph, "graphDuration")
      verify(durations.x >= 0 && durations.x + durations.width <= firstGraph.width + 0.5)
      if (data.width === 320 && data.gpu) verify(findChild(header, "panelTab_net").y > 0, "narrow tabs wrap")
      mouseClick(findChild(header, "panelTab_net"))
      compare(fakePanel.currentTab, "net")
      var toggle = findChild(header, "barVisibilitySwitch")
      compare(toggle.Accessible.name, "Show Network in bar")
      mouseClick(toggle)
      verify(fakePanel.barEnabled)
      verify(toggle.Accessible.checked)
    }
    function test_graph_summary_names_series_and_skips_unknowns() {
      firstGraph.finePoints = [{ t: 1, rx: null, tx: 900 }, { t: 2, rx: 20, tx: 800 }, { t: 3, tx: 700 }]
      compare(firstGraph.stats.avg, 20)
      compare(firstGraph.stats.peak, 20)
      verify(firstGraph.note.indexOf("down · avg") === 0)
      firstGraph.finePoints = [{ t: 1, rx: null, tx: null }]
      compare(firstGraph.stats, null)
      compare(firstGraph.note, "Collecting history…")
      firstGraph.stacked = true
      firstGraph.finePoints = [{ t: 1, rx: null, tx: null }, { t: 2, rx: 20, tx: 10 }]
      compare(firstGraph.stats.avg, 30)
      verify(firstGraph.note.indexOf("total · avg") === 0)
    }
    function test_device_choices_fit_without_losing_full_names() {
      var name = "A very long GPU or drive model name that exceeds a narrow panel width"
      var choices = createTemporaryObject(choicesComponent, keys, { width: 288, options: [
        { value: "first", label: name, tooltip: "0000:03:00.0" }, { value: "second", label: "Second device" }
      ] })
      verify(choices)
      wait(20)
      var first = findChild(choices, "deviceChoice_0")
      var second = findChild(choices, "deviceChoice_1")
      verify(first.width <= choices.width)
      verify(second.y >= first.height, "multiple long choices wrap instead of clipping")
      verify(first.text.length < name.length)
      compare(first.Accessible.name, name)
      verify(first.tooltipText.indexOf(name) === 0)
      mouseClick(second)
      compare(choices.value, "second")
      verify(second.selected)
    }
    function test_hero_wraps_identity_and_bounds_detail() {
      var hero = createTemporaryObject(heroComponent, keys, {
        width: 288, title: "A long hardware model with useful identity", meta: "driver · topology · capacity", detail: "12.3 GiB used"
      })
      verify(hero)
      wait(20)
      var detail = findChild(hero, "heroDetail")
      var labels = findChild(hero, "heroLabels")
      verify(hero.stackedDetail)
      verify(detail.y >= labels.y + labels.height)
      verify(detail.x >= 0 && detail.x + detail.width <= hero.width)
      hero.width = 500
      wait(20)
      verify(!hero.stackedDetail)
      verify(labels.x + labels.width <= detail.x)
      hero.detail = "An unusually long capacity or frequency detail that must remain inside the panel"
      wait(20)
      verify(detail.width <= hero.width)
    }
    function test_pressure_scale_does_not_replace_actual_psi() {
      var view = createTemporaryObject(memoryComponent, keys, { width: 288, model: {
        sample: { psi: { ms10: 31.2 }, mem: { swtot: 0, swfre: 0 } },
        memComp: Model.memComposition({ tot: 1000, avl: 400, fre: 200, buf: 50, cac: 100, srec: 10, slab: 20 }),
        sysInfo: null, swapRate: null, memRows: [], memHistory: [], memLong: [], procStats: null, procError: "", barIntervalMs: 1000
      } })
      verify(view)
      wait(20)
      var pressure = findChild(view, "memoryPressure")
      compare(pressure.centerText, "31.2%")
      compare(pressure.fraction, 1)
      verify(findChild(view, "memoryPressureScale").text.indexOf("0–25%") >= 0)
      verify(findChild(view, "memoryAccounting").text.indexOf("total − available") >= 0)
    }
    function test_minute_history_survives_slower_cadence() {
      var store = createTemporaryObject(storeComponent, testCase, { settingsRaw: { barIntervalMs: 250 }, saveIntervalMs: 60000 })
      verify(store)
      function sample(ts, tick) {
        store.handleSample(JSON.stringify({ v: 1, ts: ts, up: 1000,
          cpu: [100 + tick * 10, 0, 20 + tick, 500 + tick * 10, 0, 0, 0, 0],
          mem: { tot: 1000, fre: 200, avl: 400, buf: 50, cac: 100, srec: 10, slab: 20, swtot: 0, swfre: 0 }, net: [], disk: [] }))
      }
      // Run synchronously so real stream callbacks cannot interleave with the fixture.
      for (var i = 0; i <= 240; i++) sample(1000 + i * 0.25, i)
      compare(store.memHistory.length, 241)
      store.applySettings({ barIntervalMs: 10000 })
      sample(1070, 241)
      compare(store.barIntervalMs, 10000)
      for (var history of [store.cpuHistory, store.memHistory]) {
        compare(history[0].t, 1010, "old-cadence points remain until they age out")
        compare(history[history.length - 1].t, 1070)
        compare(history.length, 202)
      }
      store.applySettings({ barIntervalMs: 60000 })
      sample(1130, 242)
      compare(store.memHistory.length, 2)
      compare(store.memHistory[0].t, 1070, "retention remains time-bounded")
    }
  }
 }
}
