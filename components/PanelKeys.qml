import QtQuick
import qs.Ui as Ui

// Keep the panel's shell shortcuts together so the real dispatch path can
// also be exercised offscreen without creating a layer-shell window.
Ui.PanelKeyCatcher {
  id: root
  property var panel: null
  blocked: !panel || panel.settingsOpen || panel.searchFocused

  onCloseRequested: if (panel) panel.close()
  onTabRequested: function (direction) { if (panel) panel.switchPanel(direction) }
  onMoveRequested: function (dx, dy) {
    if (!panel) return
    if (dx !== 0) panel.stepTab(dx)
    if (dy !== 0) panel.moveCursor(dy)
  }
  onTextKey: function (t) {
    if (!panel) return
    if (t === "/" && panel.currentProcessList) { panel.currentProcessList.focusSearch(); return }
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
