//@ pragma OmarchyLoadPatch
import QtQuick
import QtQuick.Window
import Quickshell
import QtTest
import qs.Ui as Ui
import "components" as Components
import "lib/index.mjs" as Model

ShellRoot {
 Window {
  id: testWindow
  visible: true
  width: 440
  height: 800
  QtObject {
    id: fakePanel
    property int switches: 0
    function focusProcessKeys() { catcher.forceActiveFocus() }
    function switchPanel(direction) { switches += direction }
    function scrollProcessCursor(item) { }
  }
  Ui.PanelKeyCatcher {
    id: catcher
    anchors.fill: parent
    blocked: roster.searchFocused
    property int moves: 0
    property int activations: 0
    property int deletions: 0
    property int closes: 0
    onMoveRequested: function (dx, dy) { moves++; if (dy) roster.moveCursor(dy) }
    onActivateRequested: activations++
    onDeleteRequested: deletions++
    onCloseRequested: closes++
    onTabRequested: function (direction) { fakePanel.switchPanel(direction) }
    onTextKey: function (text) { if (text === "/") roster.focusSearch() }
    Components.ProcessList {
      id: roster
      width: parent.width - 20
      x: 10
      panel: fakePanel
      expandable: true
      expandedReady: true
      valueHeader: "CPU"
    }
  }
  TestCase {
    name: "ProcessExploration"
    when: testWindow.visible
    windowShown: true
    function cleanupTestCase() {
      console.log("QPROCESSUI " + JSON.stringify({ passed: qtest_results.passCount, failed: qtest_results.failCount }))
    }
    function group(pid, start, name, value) {
      var r = Model.nameAndCollapse([{ pid: pid, start: start, comm: name, value: value }], 1)[0]
      r.sortKey = value
      r.valueText = String(value)
      return r
    }
    function init() {
      roster.reset()
      roster.errorText = ""
      roster.rows = [group(1, 1, "first", 1), group(2, 2, "second", 2)]
      roster.expandedRows = Array.from({ length: 400 }, function (_, i) { return group(1000 + i, i, "worker-" + i, i) })
      roster.sortMode = "sticky"
      roster.width = 420
      fakePanel.switches = 0
      catcher.moves = 0; catcher.activations = 0; catcher.deletions = 0; catcher.closes = 0
      catcher.forceActiveFocus()
      wait(20)
    }
    function test_editor_receives_navigation_letters_and_printable_keys() {
      keyClick(Qt.Key_Slash)
      tryCompare(roster, "searchFocused", true)
      verify(catcher.blocked)
      keyClick(Qt.Key_H); keyClick(Qt.Key_J); keyClick(Qt.Key_K); keyClick(Qt.Key_L); keyClick(Qt.Key_X)
      keyClick(Qt.Key_Space); keyClick(Qt.Key_A)
      keyClick(Qt.Key_Return); keyClick(Qt.Key_Enter)
      compare(roster.query, "hjklx a")
      compare(catcher.moves, 0)
      compare(catcher.activations, 0)
      compare(catcher.deletions, 0)
      keyClick(Qt.Key_Escape)
      compare(roster.query, "")
      verify(roster.searchFocused)
      compare(catcher.closes, 0)
      keyClick(Qt.Key_Escape)
      tryCompare(roster, "searchFocused", false)
      keyClick(Qt.Key_J)
      compare(catcher.moves, 1)
      compare(roster.cursorIndex, 0)
      keyClick(Qt.Key_Escape)
      compare(catcher.closes, 1)
    }
    function test_tab_keeps_shell_panel_navigation() {
      roster.focusSearch()
      tryCompare(roster, "searchFocused", true)
      keyClick(Qt.Key_Tab)
      compare(fakePanel.switches, 1)
      verify(!roster.searchFocused)
      roster.focusSearch()
      tryCompare(roster, "searchFocused", true)
      keyClick(Qt.Key_Backtab, Qt.ShiftModifier)
      compare(fakePanel.switches, 0)
      verify(!roster.searchFocused)
    }
    function test_search_finds_hidden_rows_and_cap_is_explicit() {
      roster.expanded = true
      compare(roster.displayRows.length, 256)
      compare(roster.results.matches, 400)
      verify(roster.results.limited)
      roster.query = "worker-0"
      compare(roster.displayRows.length, 1)
      compare(roster.displayRows[0].pid, 1000)
      roster.query = "1399"
      compare(roster.displayRows.length, 1)
      compare(roster.displayRows[0].matchedPids[0], 1399)
      roster.query = "not present"
      compare(roster.displayRows.length, 0)
    }
    function test_cursor_retains_member_identity_and_drops_reused_pid() {
      roster.rows = [group(1, 1, "first", 5), group(2, 2, "second", 4)]
      roster.selectRow(0)
      roster.sortMode = "value"
      roster.rows = [group(2, 2, "second", 8), group(1, 1, "first", 1)]
      tryCompare(roster, "cursorIndex", 1)
      compare(roster.selectedRow.pid, 1)
      roster.rows = [group(1, 99, "first", 10), group(2, 2, "second", 8)]
      verify(!roster.cursorActive)
      compare(roster.cursorIndex, -1)
    }
    function test_pid_selection_does_not_follow_replacement_with_other_survivors() {
      function workers(start) {
        return Model.nameAndCollapse([{ pid: 7, start: start, comm: "workers", value: 1 },
                                      { pid: 8, start: 1, comm: "workers", value: 1 }], 1)
      }
      roster.expanded = true
      roster.expandedRows = workers(1)
      roster.query = "7"
      roster.selectRow(0)
      roster.expandedRows = workers(99)
      verify(!roster.cursorActive)
    }
    function test_sorting_in_both_modes() {
      roster.cycleSort()
      compare(roster.displayRows[0].pid, 2)
      roster.cycleSort()
      compare(roster.displayRows[0].pid, 1)
      roster.cycleSort()
      compare(roster.sortMode, "sticky")
      roster.expanded = true
      compare(roster.effectiveSort, "value")
      roster.cycleSort()
      compare(roster.effectiveSort, "name")
      roster.cycleSort()
      compare(roster.effectiveSort, "value")
    }
    function test_virtualized_rows_and_cursor_scroll_narrow() {
      roster.width = 300
      roster.expanded = true
      wait(30)
      var list = findChild(roster, "processRows")
      compare(list.count, 256)
      verify(list.contentItem.children.length < 25, "only visible delegates should be created")
      for (var i = 0; i < 80; i++) roster.moveCursor(1)
      wait(30)
      verify(list.contentY > 0)
      var y = roster.cursorY() - list.y
      verify(y >= 0 && y + roster.rowHeight <= list.height + 1, "cursor stays in the viewport")
      verify(list.contentItem.children.length < 25)
      roster.query = "worker-399"
      verify(!roster.cursorActive, "filtering out the target clears selection")
    }
    function test_retained_target_scrolls_after_clearing_filter() {
      roster.expanded = true
      roster.query = "worker-300"
      wait(20)
      roster.selectRow(0)
      compare(roster.selectedRow.pid, 1300)
      roster.query = ""
      wait(30)
      compare(roster.cursorIndex, 99)
      var list = findChild(roster, "processRows")
      verify(list.contentY > 0)
      var y = roster.cursorY() - list.y
      verify(y >= 0 && y + roster.rowHeight <= list.height + 1)
    }
    function test_pointer_controls_clear_and_show_less() {
      // Activate Show all with the pointer, type, then use its Clear control.
      var button = findChild(roster, "processExpand")
      mouseClick(button)
      tryCompare(roster, "searchFocused", true)
      keyClick(Qt.Key_J)
      compare(roster.query, "j")
      mouseClick(findChild(roster, "processClear"))
      compare(roster.query, "")
      verify(roster.searchFocused)
      mouseClick(button)
      verify(!roster.expanded)
      verify(!roster.searchFocused)
    }
  }
}
}
