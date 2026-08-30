import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "Theme.js" as Theme
import "tabs" as Tabs

// Quadrant detail panel: one KeyboardPanel with a tab strip. Keyboard
// contract follows Quattro conventions — Tab keeps its shell meaning
// (switch to the adjacent bar panel), so Quadrant's own tabs move with
// Left/Right and 1-4; R refreshes the active tab; Esc closes.
Panel {
  id: root
  moduleName: "dev.bvisagie.quadrant"
  manageIpc: false   // this panel owns the plugin's single IpcHandler

  property var anchorItem: null
  property var hostWidget: null

  readonly property int processCount: Model.clamp(setting("processCount", 5), 1, 10)
  readonly property int panelIntervalMs: Model.clamp(setting("panelIntervalMs", 2000), 500, 60000)

  // Last-used tab survives close/reopen.
  property string currentTab: "cpu"

  readonly property bool gpuAvailable: hostWidget ? hostWidget.gpuAvailable === true : false
  readonly property var tabs: {
    var all = ["cpu", "mem", "gpu", "net"]
    if (gpuAvailable) return all
    return all.filter(function (t) { return t !== "gpu" })
  }
  readonly property var tabLabels: ({ "cpu": "CPU", "mem": "MEMORY", "gpu": "GPU", "net": "NETWORK" })

  onTabsChanged: {
    if (tabs.indexOf(currentTab) < 0) currentTab = tabs[0]
  }

  function open() { controller.show() }
  function close() { controller.hide() }

  // IPC entry point: deep-link a tab, opening the panel. Unknown or
  // unavailable tabs are ignored rather than throwing.
  function showTab(tab) {
    var name = String(tab || "")
    if (tabs.indexOf(name) < 0) return
    currentTab = name
    open()
  }

  function stepTab(direction) {
    var i = tabs.indexOf(currentTab)
    if (i < 0) { currentTab = tabs[0]; return }
    var next = (i + direction + tabs.length) % tabs.length
    currentTab = tabs[next]
  }

  function selectTabIndex(i) {
    if (i >= 0 && i < tabs.length) currentTab = tabs[i]
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function refreshActiveTab() {
    var item = [cpuTab, memTab, gpuTab, netTab][["cpu", "mem", "gpu", "net"].indexOf(currentTab)]
    if (item && item.refresh) item.refresh()
  }

  onOpenedChanged: if (opened) refreshActiveTab()

  IpcHandler {
    target: "dev.bvisagie.quadrant"

    function showTab(tab: string) { root.showTab(tab) }
    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.stepTab(dx)
      }
      onTextKey: function(t) {
        if (t === "r" || t === "R") { root.refreshActiveTab(); return }
        if (t >= "1" && t <= "4") root.selectTabIndex(parseInt(t, 10) - 1)
      }

      Column {
        id: contentColumn
        width: parent.width
        spacing: Style.space(10)

        // ---- tab strip ----
        Row {
          id: tabStrip
          width: parent.width
          spacing: Style.space(14)

          Repeater {
            model: root.tabs

            delegate: Item {
              id: tabButton
              required property string modelData
              required property int index

              readonly property bool current: root.currentTab === modelData

              implicitWidth: tabLabel.implicitWidth
              implicitHeight: tabLabel.implicitHeight + Style.space(4)

              Text {
                id: tabLabel
                textFormat: Text.PlainText
                text: root.tabLabels[tabButton.modelData] || tabButton.modelData
                color: tabButton.current ? root.barForeground : Qt.darker(root.barForeground, 1.5)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
                font.bold: tabButton.current
              }

              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: Style.space(2)
                radius: 1
                color: Theme.series.cpuUser
                visible: tabButton.current
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.currentTab = tabButton.modelData
              }
            }
          }
        }

        PanelSeparator {
          foreground: root.barForeground
        }

        // ---- tab content ----
        StackLayout {
          id: stack
          width: parent.width
          currentIndex: Math.max(0, root.tabs.indexOf(root.currentTab))

          Tabs.CpuTab {
            id: cpuTab
            panel: root
            model: root.hostWidget
          }
          Tabs.MemoryTab {
            id: memTab
            panel: root
            model: root.hostWidget
          }
          Tabs.GpuTab {
            id: gpuTab
            panel: root
            model: root.hostWidget
          }
          Tabs.NetworkTab {
            id: netTab
            panel: root
            model: root.hostWidget
          }
        }

        // ---- footer hint ----
        Text {
          textFormat: Text.PlainText
          text: "←/→ or 1-4 switch tab · R refresh · Esc close"
          color: Qt.darker(root.barForeground, 1.6)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
