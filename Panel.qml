import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "tabs" as Tabs

// Quadrant detail panel: one KeyboardPanel with a tab strip. Keyboard
// contract follows Quattro conventions — Tab keeps its shell meaning
// (switch to the adjacent bar panel), so Quadrant's own tabs move with
// Left/Right and 1-N (N = visible tabs); R refreshes the active tab; Esc closes.
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
        if (t >= "1" && t <= "9") {
          var n = parseInt(t, 10)
          if (n >= 1 && n <= root.tabs.length) root.selectTabIndex(n - 1)
        }
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
                color: Color.accent
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

        // Keep last-good metrics on screen, but never leave stale or failed
        // async data looking live. GPU probe failures are distinct from a
        // legitimate no-GPU result.
        Text {
          textFormat: Text.PlainText
          visible: root.hostWidget
                   && (root.hostWidget.streamLive !== true
                       || root.hostWidget.gpuDetectionError !== "")
          text: {
            if (!root.hostWidget) return ""
            var messages = []
            if (root.hostWidget.streamLive !== true) {
              messages.push(root.hostWidget.streamError !== ""
                ? root.hostWidget.streamError
                : "Waiting for the system sampler…")
            }
            if (root.hostWidget.gpuDetectionError !== "")
              messages.push(root.hostWidget.gpuDetectionError)
            return messages.join(" · ")
          }
          color: Color.urgent
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          width: parent.width
          wrapMode: Text.WordWrap
        }

        // ---- tab content ----
        StackLayout {
          id: stack
          width: parent.width
          // Children are always cpu/mem/gpu/net in that order. Map by tab
          // id rather than by the filtered `tabs` array — otherwise a
          // no-GPU machine puts Network at index 2, which is GpuTab.
          currentIndex: {
            var map = { "cpu": 0, "mem": 1, "gpu": 2, "net": 3 }
            var i = map[root.currentTab]
            return (i === undefined) ? 0 : i
          }
          // StackLayout otherwise reports the tallest child as its implicit
          // height. That made short tabs (notably GPU) inherit the CPU or
          // Memory tab height and left a large blank gap above the footer.
          implicitHeight: currentIndex >= 0 && children[currentIndex]
                          ? children[currentIndex].implicitHeight : 0

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
          text: "←/→ or 1-" + root.tabs.length + " switch tab · R refresh · Esc close"
          color: Qt.darker(root.barForeground, 1.6)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
