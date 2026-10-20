//@ pragma OmarchyLoadPatch
import QtQuick
import QtQuick.Window
import Quickshell
import QtTest
import qs.Commons as Commons
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
    property var detailItem: null
    function activeTabItem() { return detailItem }
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
  Component { id: headerComponent; Components.PanelHeader { } }
  TestCase {
    id: testCase
    name: "PanelClarity"
    when: testWindow.visible
    windowShown: true
    property var initialStyle: ({})
    function initTestCase() {
      wait(20)
      initialStyle = Object.assign({}, Commons.Color.shellValues)
    }
    function cleanupTestCase() {
      console.log("QPANELUI " + JSON.stringify({ passed: qtest_results.passCount, failed: qtest_results.failCount }))
    }
    function cleanup() {
      if (qtest_results.failed) console.error("QPANELUI failure: " + qtest_results.functionName + " " + qtest_results.dataTag)
    }
    function init() {
      Commons.Style.applyShellValues(initialStyle)
      fakePanel.settingsOpen = false; fakePanel.longWindow = false
      fakePanel.gpuAvailable = true; fakePanel.barAvailable = true; fakePanel.barEnabled = false
      fakePanel.currentTab = "cpu"
      fakePanel.detailItem = null
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
    function test_header_width_sweep_data() {
      var cases = []
      for (var font = 12; font <= 18; font++) {
        for (var spacing of [1, 1.5, 2]) {
          for (var gpu of [false, true])
            cases.push({ tag: font + "px spacing " + spacing + " " + (gpu ? "five" : "four"), font: font, spacing: spacing, gpu: gpu })
        }
      }
      return cases
    }
    function test_header_measures_current_labels_and_text_size() {
      var view = createTemporaryObject(headerComponent, keys, { width: 440, currentTab: "mem", options: [
        { value: "cpu", label: "CPU" }, { value: "mem", label: "Very detailed memory statistics" }, { value: "net", label: "Net" }
      ] })
      verify(view)
      wait(20)
      var memory = findChild(view, "panelTab_mem")
      verify(memory.width >= memory.implicitWidth, "measure the current labels, including a new widest label")
      view.options = [{ value: "cpu", label: "CPU" }, { value: "mem", label: "RAM" }, { value: "net", label: "Net" }]
      wait(20)
      memory = findChild(view, "panelTab_mem")
      compare(memory.y, findChild(view, "panelTab_cpu").y, "shorter options can share a row again")
      Commons.Style.applyShellValues({ "font.base-size": 18, "spacing.scale": 1.5 })
      wait(20)
      for (var name of ["cpu", "mem", "net"]) {
        var button = findChild(view, "panelTab_" + name)
        verify(button.width >= button.implicitWidth, "live text sizing updates label measurement")
      }
    }
    function test_header_width_sweep(data) {
      // Only this throwaway process changes; no user config is written.
      Commons.Style.applyShellValues({ "font.base-size": data.font, "spacing.scale": data.spacing })
      var options = (data.gpu ? ["cpu", "gpu", "mem", "disk", "net"] : ["cpu", "mem", "disk", "net"])
                    .map(function (t) { return { value: t, label: fakePanel.labels[t] } })
      var view = createTemporaryObject(headerComponent, keys, { width: Commons.Style.space(440), options: options, currentTab: "net" })
      verify(view)
      wait(20)
      var flow = findChild(view, "panelTabs")
      var gear = findChild(view, "panelSettings")
      var buttons = options.map(function (o) { return findChild(view, "panelTab_" + o.value) })
      var widest = Math.max.apply(null, buttons.map(function (b) { return b.implicitWidth }))
      var reserved = view.width - flow.width
      // Skip widths too small to fit even one full label plus the settings action.
      for (var width = Math.max(240, Math.ceil(widest + reserved)); width <= Commons.Style.space(440); width++) {
        view.width = width
        flow.forceLayout()
        for (var i = 0; i < buttons.length; i++) {
          var button = buttons[i]
          verify(button.width + 0.01 >= button.implicitWidth, "labels fit at width " + width)
          verify(button.x >= 0 && button.x + button.width <= flow.width + 0.01)
          if (i > 0 && button.y > buttons[i - 1].y) {
            var nextX = buttons[i - 1].x + buttons[i - 1].width + flow.spacing
            var fits = nextX + button.width <= flow.width + 0.01
            if (fits) console.error("QPANELUI avoidable wrap at width " + width + " for " + data.tag)
            verify(!fits, "a tab must not wrap while its full slot fits on the previous row")
          }
        }
        verify(flow.width < gear.x)
      }
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
    function test_wide_header_shares_a_row_and_reflows_without_overlap() {
      var options = ["cpu", "gpu", "mem", "disk", "net", "hardware"].map(function (t) {
        return { value: t, label: t === "hardware" ? "Hardware" : fakePanel.labels[t] }
      })
      var view = createTemporaryObject(headerComponent, keys, {
        width: Commons.Style.space(720), options: options, barToggleVisible: true, resourceName: "Memory"
      })
      verify(view); wait(20)
      verify(view.inlineActions)
      var flow = findChild(view, "panelTabs"), toggle = findChild(view, "barVisibility"), gear = findChild(view, "panelSettings")
      verify(flow.x + flow.width <= toggle.x)
      verify(toggle.x + toggle.width < gear.x)
      verify(toggle.y < flow.implicitHeight)
      view.width = Commons.Style.space(320); wait(20)
      verify(!view.inlineActions)
      verify(toggle.y >= flow.implicitHeight)
      verify(view.implicitHeight >= toggle.y + toggle.implicitHeight)
    }
    function test_responsive_columns_preserve_process_view_and_disclosure_state() {
      var view = createTemporaryObject(memoryComponent, keys, { width: Commons.Style.space(720) })
      verify(view); wait(20)
      var columns = findChild(view, "resourceColumns")
      var first = findChild(columns, "primaryColumn"), second = findChild(columns, "secondaryColumn")
      var roster = view.processList
      verify(columns.wide)
      compare(second.y, 0)
      verify(second.x >= first.width)
      verify(second.x + second.width <= columns.width)
      roster.expanded = true; roster.query = "123"; roster.sortMode = "name"
      var accounting = findChild(view, "memoryAccounting").parent.parent
      accounting.expanded = true; wait(20)
      view.width = Commons.Style.space(320); wait(20)
      verify(!columns.wide)
      compare(second.x, 0)
      verify(second.y >= first.implicitHeight)
      compare(view.processList, roster, "resize keeps the same searchable list")
      verify(roster.expanded); compare(roster.query, "123"); compare(roster.sortMode, "name")
      verify(accounting.expanded, "resize keeps the disclosure open")
      view.width = Commons.Style.space(720); wait(20)
      verify(columns.wide); compare(second.y, 0)
      verify(columns.implicitHeight >= second.implicitHeight)
      verify(columns.implicitHeight >= first.implicitHeight)
    }
    function test_details_keyboard_shortcut_preserves_shell_tab_and_search_typing() {
      var view = createTemporaryObject(memoryComponent, keys, { width: Commons.Style.space(720) })
      verify(view); wait(20)
      fakePanel.detailItem = view
      var accounting = findChild(view, "memoryAccounting").parent.parent
      verify(!accounting.expanded)
      keys.forceActiveFocus()
      keyClick(Qt.Key_D); verify(accounting.expanded)
      keyClick(Qt.Key_D); verify(!accounting.expanded)
      keyClick(Qt.Key_Tab); compare(fakePanel.switches, 1)
      keyClick(Qt.Key_Slash); tryCompare(editor, "activeFocus", true)
      keyClick(Qt.Key_D); compare(editor.text, "d")
      verify(!accounting.expanded, "typing a search never expands hidden details")
    }
    function test_swap_devices_only_appears_when_inventory_has_rows() {
      var model = { sample: null, memComp: null, swapRate: null, sysInfo: null, memRows: [], memHistory: [],
        memLong: [], procStats: null, procError: "", barIntervalMs: 1000 }
      var view = createTemporaryObject(memoryComponent, keys, { width: Commons.Style.space(720), model: model })
      verify(view)
      wait(20)
      var devices = findChild(view, "swapDevices")
      verify(!devices.visible, "inventory has not arrived")
      view.model = Object.assign({}, model, { sysInfo: { mem: { swaps: [] } } })
      wait(20); verify(!devices.visible, "no swap is configured")
      view.model = Object.assign({}, model, { sysInfo: { mem: { swaps: [{ kind: "file", file: "/swapfile", sizeKb: 1024 }] } } })
      wait(20); verify(devices.visible)
      fakePanel.detailItem = view
      keys.forceActiveFocus(); keyClick(Qt.Key_D)
      verify(devices.expanded)
      compare(view.swapDeviceRows.length, 1)
      view.model = Object.assign({}, model, { sysInfo: { mem: { swaps: [] } } })
      wait(20); verify(!devices.visible, "removing the last device hides the disclosure")
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
    function test_pressure_overview_reports_actual_psi_without_a_gauge_scale() {
      var view = createTemporaryObject(memoryComponent, keys, { width: 288, model: {
        sample: { psi: { ms10: 31.2 }, mem: { swtot: 0, swfre: 0 } },
        memComp: Model.memComposition({ tot: 1000, avl: 400, fre: 200, buf: 50, cac: 100, srec: 10, slab: 20 }),
        sysInfo: null, swapRate: null, memRows: [], memHistory: [], memLong: [], procStats: null, procError: "", barIntervalMs: 1000
      } })
      verify(view)
      wait(20)
      var pressure = findChild(view, "memoryPressure")
      compare(pressure.value, "31.2%")
      verify(!findChild(view, "memoryPressureScale"), "numeric pressure needs no gauge ceiling")
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
