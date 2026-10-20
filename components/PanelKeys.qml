import QtQuick
import qs.Ui as Ui

// Keep the panel's shell shortcuts together so the real dispatch path can
// also be exercised offscreen without creating a layer-shell window.
Ui.PanelKeyCatcher {
  id: root
  property var panel: null
  blocked: !panel || panel.settingsOpen || panel.searchFocused

  // Tab belongs to the shell, so disclosures also need a direct keyboard
  // path. Traverse the active tab only, retaining each existing control.
  function toggleDetails(item) {
    if (!item) return
    var details = []
    function collect(parent) {
      if (!parent.visible) return
      if ("detailsDisclosure" in parent && parent.detailsDisclosure) details.push(parent)
      for (var child of parent.children) collect(child)
    }
    collect(item)
    var expand = details.some(function (detail) { return !detail.expanded })
    for (var detail of details) detail.expanded = expand
  }

  onCloseRequested: {
    if (!panel) return
    if (panel.currentActions && panel.currentActions.keyboardActive) panel.currentActions.leaveFocus()
    else panel.close()
  }
  onTabRequested: function (direction) { if (panel) panel.switchPanel(direction) }
  onMoveRequested: function (dx, dy) {
    if (!panel) return
    if (dx !== 0) panel.stepTab(dx)
    if (dy !== 0) {
      if (panel.currentActions && panel.currentActions.keyboardActive) panel.currentActions.moveCursor(dy)
      else panel.moveCursor(dy)
    }
  }
  onActivateRequested: if (panel && panel.currentActions && panel.currentActions.keyboardActive) panel.currentActions.activate()
  onTextKey: function (t) {
    if (!panel) return
    if (t === "/" && panel.currentProcessList) {
      if (panel.currentActions) panel.currentActions.leaveFocus()
      panel.currentProcessList.focusSearch(); return
    }
    if ((t === "a" || t === "A") && panel.currentActions) { panel.currentActions.toggleFocus(); return }
    if ((t === "d" || t === "D") && panel.activeTabItem) { root.toggleDetails(panel.activeTabItem()); return }
    if (t === "r" || t === "R") {
      if (panel.store) {
        panel.store.refreshHardware()
        panel.store.pollIgpu()
      }
      panel.refreshActiveTab()
      return
    }
    if (t === "H") { panel.longWindow = !panel.longWindow; return }
    if (t === "s" || t === "S") { panel.settingsOpen = !panel.settingsOpen; return }
    if (t >= "1" && t <= "9") {
      var n = parseInt(t, 10)
      if (n >= 1 && n <= panel.tabs.length) { panel.selectTabIndex(n - 1); panel.settingsOpen = false }
    }
  }
  Keys.onEscapePressed: function (event) {
    if (panel && panel.settingsOpen) { panel.settingsOpen = false; event.accepted = true }
    else event.accepted = false
  }
}
