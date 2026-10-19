//@ pragma OmarchyLoadPatch
import QtQuick
import QtQuick.Window
import Quickshell
import QtTest
import qs.Commons as Commons
import "components" as Components
import "tabs" as Tabs

ShellRoot {
 Window {
  id: win
  visible: true
  width: 440
  height: 1800
  ActionFixture { id: fixture }
  readonly property var helper: ["python3", decodeURIComponent(String(Qt.resolvedUrl("action-helper.py")).replace(/^file:\/\//, ""))]
  QtObject {
    id: fakePanel
    property bool opened: true
    property bool settingsOpen: false
    property bool longWindow: false
    property string currentTab: "net"
    property int switches: 0
    property int closes: 0
    property int moves: 0
    property string lastReveal: ""
    property var store: null
    property var tabs: ["net", "disk"]
    readonly property var currentProcessList: currentTab === "net" ? (network ? network.processList : null) : (disk ? disk.processList : null)
    readonly property var currentActions: currentTab === "net" ? (network ? network.actionList : null) : (disk ? disk.actionList : null)
    readonly property bool searchFocused: currentProcessList ? currentProcessList.searchFocused : false
    onCurrentTabChanged: { leaveActions(); keys.forceActiveFocus() }
    onSettingsOpenChanged: leaveActions()
    function leaveActions() { if (network) network.actionList.leaveFocus(); if (disk) disk.actionList.leaveFocus() }
    function focusProcessKeys() { keys.forceActiveFocus() }
    function scrollActionItem(item) { lastReveal = item.objectName }
    function stepTab(d) { currentTab = currentTab === "net" ? "disk" : "net" }
    function selectTabIndex(index) { currentTab = tabs[index] }
    function switchPanel(d) { switches += d }
    function close() { closes++; opened = false; leaveActions() }
    function moveCursor(d) { moves += d }
    function refreshActiveTab() { }
  }
  Components.PanelKeys {
    id: keys
    anchors.fill: parent
    panel: fakePanel
    Column {
      x: 16; y: 16
      width: parent.width - 32
      Tabs.NetworkTab { id: network; width: parent.width; visible: fakePanel.currentTab === "net"; panel: fakePanel; model: fixture }
      Tabs.DiskTab { id: disk; width: parent.width; visible: fakePanel.currentTab === "disk"; panel: fakePanel; model: fixture }
    }
  }
  Component { id: runnerComponent; Components.LocalAction { } }
  TestCase {
    name: "LocalPanelActions"
    when: win.visible
    windowShown: true
    property var style: ({})
    property var initialInfo: null
    function initTestCase() { wait(20); style = Object.assign({}, Commons.Color.shellValues); initialInfo = fixture.sysInfo }
    function cleanupTestCase() { console.log("QACTIONSUI " + JSON.stringify({ passed: qtest_results.passCount, failed: qtest_results.failCount })) }
    function cleanup() { if (qtest_results.failed) console.error("QACTIONSUI failure: " + qtest_results.functionName + " " + qtest_results.dataTag) }
    function check(condition, message) {
      if (!condition) console.error("QACTIONSUI check " + (message || "") + " " + new Error().stack)
      verify(condition, message)
    }
    function equal(actual, expected, message) {
      if (actual !== expected) console.error("QACTIONSUI compare " + JSON.stringify({ actual: actual, expected: expected, message: message }) + " " + new Error().stack)
      compare(actual, expected, message)
    }
    function init() {
      Commons.Style.applyShellValues(style)
      win.width = 440
      fakePanel.opened = true; fakePanel.currentTab = "net"; fakePanel.settingsOpen = false
      fakePanel.switches = 0; fakePanel.closes = 0; fakePanel.moves = 0
      fakePanel.lastReveal = ""
      fixture.sysInfo = initialInfo
      fixture.netRows = []
      fixture.selectInterface("auto"); fixture.selectDisk("sda"); fixture.selects = 0
      for (var group of [network.actionList, disk.actionList]) {
        group.leaveFocus(); group.runner.clear(); group.runner.helperCommand = win.helper
      }
      keys.forceActiveFocus()
      wait(30)
    }
    function test_keyboard_copy_and_staged_escape_keep_shell_tab() {
      var group = network.actionList
      keyClick(Qt.Key_A)
      check(group.keyboardActive); equal(group.selectedIndex, 0)
      equal(group.runner.message, "", "focus does not read or write the clipboard")
      keyClick(Qt.Key_Down); equal(group.selectedIndex, 1)
      keyClick(Qt.Key_Return)
      tryCompare(group.runner, "busy", false)
      equal(group.runner.message, "Copied 192.0.2.4")
      check(!group.runner.error)
      tryCompare(fakePanel, "lastReveal", "actionFeedback")
      keyClick(Qt.Key_Tab); equal(fakePanel.switches, 1)
      keyClick(Qt.Key_Backtab, Qt.ShiftModifier); equal(fakePanel.switches, 0)
      keyClick(Qt.Key_Escape); check(!group.keyboardActive); equal(fakePanel.closes, 0)
      keyClick(Qt.Key_Escape); equal(fakePanel.closes, 1)
    }
    function test_pointer_copies_exact_visible_mac_and_ipv6() {
      var group = network.actionList
      for (var index of [0, 2]) {
        var value = findChild(group, "actionValue_" + index)
        var button = findChild(group, "actionButton_" + index)
        if (index === 0) { button.forceActiveFocus(); keyClick(Qt.Key_Space) }
        else mouseClick(button)
        tryCompare(group.runner, "busy", false)
        equal(group.runner.message, "Copied " + value.text)
        check(!group.runner.error)
        check(keys.activeFocus, "pointer actions return keys to the panel dispatcher")
      }
    }
    function test_open_uses_literal_full_mount_target() {
      fakePanel.currentTab = "disk"; wait(20)
      var group = disk.actionList
      var value = group.entries[1].value
      check(value.indexOf("$(touch NO)") >= 0)
      mouseClick(findChild(group, "actionButton_1"))
      tryCompare(group.runner, "busy", false)
      equal(group.runner.message, "Open request sent for " + value)
      check(!group.runner.error)
    }
    function test_adjacent_selectors_keep_their_meaning() {
      var group = network.actionList
      mouseClick(findChild(findChild(network, "interfaceChoices"), "deviceChoice_2"))
      wait(20)
      equal(fixture.effectiveInterface, "wlan0"); equal(fixture.selects, 1)
      equal(group.runner.message, "")
      mouseClick(findChild(group, "actionButton_0")); tryCompare(group.runner, "busy", false)
      equal(fixture.selects, 1)
      equal(group.runner.message, "Copied 00:11:22:33:44:55")
      fakePanel.currentTab = "disk"; wait(20)
      mouseClick(findChild(findChild(disk, "diskChoices"), "deviceChoice_1"))
      equal(fixture.effectiveDisk, "sdb"); equal(fixture.selects, 2)
      equal(disk.actionList.runner.message, "")
    }
    function test_focus_survives_reordering_but_not_a_removed_value_or_context() {
      var group = network.actionList
      keyClick(Qt.Key_A); keyClick(Qt.Key_Down)
      var key = group.selectedKey
      var old = fixture.sysInfo
      fixture.sysInfo = { net: { byName: { eth0: { mac: old.net.byName.eth0.mac, addrs: ["2001:db8::5/64", "192.0.2.4/24"] } } } }
      equal(group.selectedKey, key); equal(group.selectedIndex, 2)
      fixture.sysInfo = { net: { byName: { eth0: { mac: old.net.byName.eth0.mac, addrs: [] } } } }
      check(!group.keyboardActive)
      fixture.sysInfo = old
      keyClick(Qt.Key_A); check(group.keyboardActive)
      fixture.selectInterface("wlan0")
      check(!group.keyboardActive); equal(group.runner.message, "")
    }
    function test_actions_do_not_steal_search_or_panel_shortcuts() {
      fakePanel.currentTab = "disk"; wait(20)
      keyClick(Qt.Key_A); check(disk.actionList.keyboardActive)
      keyClick("/"); wait(20)
      check(fakePanel.searchFocused); check(!disk.actionList.keyboardActive)
      for (var letter of "aardvark") keyClick(letter)
      equal(disk.processList.query, "aardvark")
      equal(disk.actionList.runner.message, "")
      keyClick(Qt.Key_Escape); keyClick(Qt.Key_Escape); wait(20)
      check(!fakePanel.searchFocused)
      keyClick(Qt.Key_A); check(disk.actionList.keyboardActive)
      keyClick(Qt.Key_S); check(fakePanel.settingsOpen); check(!disk.actionList.keyboardActive)
      keyClick(Qt.Key_Escape); check(!fakePanel.settingsOpen)
    }
    function test_selecting_a_process_returns_navigation_from_actions() {
      fixture.netRows = [{ pid: 42, comm: "fixture-client", sortKey: 1000, rx: 700, tx: 300, history: [] }]
      wait(20)
      keyClick(Qt.Key_A); check(network.actionList.keyboardActive)
      network.processList.selectRow(0)
      check(network.processList.cursorActive)
      check(!network.actionList.keyboardActive)
      keyClick(Qt.Key_Down); equal(fakePanel.moves, 1)
      equal(network.actionList.runner.message, "")
    }
    function test_runner_failures_and_late_results_remain_visible_and_isolated() {
      var runner = createTemporaryObject(runnerComponent, win.contentItem, { helperCommand: win.helper, timeoutMs: 2000 })
      check(runner)
      for (var value of ["FAIL", "MISMATCH", "EXIT"]) {
        check(runner.run("copy", value)); tryCompare(runner, "busy", false)
        check(runner.error); check(runner.message !== "")
        var message = runner.message
        wait(20); equal(runner.message, message)
      }
      runner.timeoutMs = 80
      check(runner.run("copy", "SLOW")); tryCompare(runner, "busy", false)
      check(runner.error); check(runner.message.indexOf("timed out") >= 0)
      tryVerify(function () { return runner.children.length === 0 }, 1000, "the timed-out job is reaped after process exit")
      runner.timeoutMs = 2000
      runner.run("copy", "SLOW"); runner.clear()
      check(!runner.run("copy", "new"), "an old desktop request finishes before another is accepted")
      tryCompare(runner, "busy", false)
      equal(runner.message, "", "old-context feedback is discarded")
      check(runner.run("copy", 'new "quote" \\ café\n'))
      tryCompare(runner, "busy", false)
      check(!runner.error)
      var message = runner.message
      wait(450); equal(runner.message, message, "old completion cannot overwrite the newer request")
    }
    function test_late_feedback_does_not_scroll_settings_or_a_different_view() {
      fixture.sysInfo = { net: { byName: { eth0: { mac: "SLOW", addrs: [] } } } }
      wait(20)
      var group = network.actionList
      for (var mode of ["settings", "tab", "leave"]) {
        group.trigger(0)
        check(group.runner.busy)
        if (mode === "settings") fakePanel.settingsOpen = true
        else if (mode === "tab") fakePanel.currentTab = "disk"
        else group.leaveFocus()
        fakePanel.lastReveal = ""
        tryCompare(group.runner, "busy", false)
        wait(20)
        equal(fakePanel.lastReveal, "", "late feedback preserves the user's current view")
        fakePanel.settingsOpen = false; fakePanel.currentTab = "net"
      }
    }
    function test_failed_copy_feedback_stays_visible_until_context_changes() {
      fixture.sysInfo = { net: { byName: { eth0: { mac: "FAIL", addrs: [] }, wlan0: initialInfo.net.byName.wlan0 } } }
      wait(20)
      var group = network.actionList
      mouseClick(findChild(group, "actionButton_0")); tryCompare(group.runner, "busy", false)
      check(group.runner.error)
      var feedback = findChild(group, "actionFeedback")
      check(feedback.visible); equal(feedback.text, "Copy failed for FAIL: Fixture action failed")
      wait(100); equal(feedback.text, "Copy failed for FAIL: Fixture action failed")
      fixture.selectInterface("wlan0")
      equal(group.runner.message, "")
    }
    function test_action_rows_fit_and_copy_values_are_complete_data() {
      var cases = []
      for (var width of [320, 440]) for (var scale of [1, 1.5, 2])
        cases.push({ tag: width + " " + scale, width: width, scale: scale })
      return cases
    }
    function test_action_rows_fit_and_copy_values_are_complete(data) {
      win.width = data.width
      Commons.Style.applyShellValues({ "font.base-size": 18, "spacing.scale": data.scale })
      wait(30)
      for (var tab of [network, disk]) {
        for (var i = 0; i < tab.actionList.entries.length; i++) {
          var value = findChild(tab.actionList, "actionValue_" + i)
          var button = findChild(tab.actionList, "actionButton_" + i)
          check(value.width > 0)
          check(button.x >= value.width)
          check(button.x + button.width <= tab.actionList.width + 0.5)
          if (tab === network) {
            check(!value.truncated, "the entire copied address remains visible")
            equal(value.text, tab.actionList.entries[i].value)
          }
        }
      }
    }
  }
 }
}
