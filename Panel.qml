import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons as Commons
import qs.Ui
import "lib/index.mjs" as Model
import "tabs" as Tabs
import "components" as Components

// Quadrant detail panel: one KeyboardPanel with a tab strip, a Show-in-bar
// switch, a settings view behind the gear, and one cursor shared by the
// keyboard and the mouse. Tab keeps its shell meaning (switch to the
// adjacent bar panel); Quadrant's own tabs move with ←/→ and 1–N.
Panel {
  id: root
  moduleName: "dev.bvisagie.quadrant"
  manageIpc: false   // this panel owns the plugin's single IpcHandler

  property var anchorItem: null
  property var hostWidget: null
  readonly property var store: hostWidget ? hostWidget.store : null

  readonly property int processCount: store ? store.processCount : 5
  readonly property int panelIntervalMs: store ? store.panelIntervalMs : 2000
  readonly property color dim: Model.dimColor(String(Commons.Color.foreground), String(Commons.Color.background))

  // Last-used tab and history-window choice survive close/reopen for this
  // panel instance. The settings view closes with the panel.
  property string currentTab: "cpu"
  property bool longWindow: false
  property bool settingsOpen: false

  // Single cursor over the active tab's process rows, driven by ↑/↓ and
  // by the mouse. The list retains the selected member identity.
  readonly property var currentProcessList: {
    var item = activeTabItem()
    return item ? item.processList : null
  }
  readonly property bool expandedProcesses: opened && !settingsOpen && currentProcessList
                                            ? currentProcessList.expandable && currentProcessList.expanded : false
  readonly property bool searchFocused: currentProcessList ? currentProcessList.searchFocused : false

  readonly property bool gpuAvailable: store ? store.discreteGpuAvailable === true : false
  readonly property var tabs: {
    var all = ["cpu", "gpu", "mem", "disk", "net"]
    if (gpuAvailable) return all
    return all.filter(function (t) { return t !== "gpu" })
  }
  readonly property var tabLabels: ({ "cpu": "CPU", "gpu": "GPU", "mem": "Memory", "disk": "Drives", "net": "Network" })
  readonly property var tabOptions: {
    var out = []
    for (var i = 0; i < tabs.length; i++) out.push({ value: tabs[i], label: tabLabels[tabs[i]] || tabs[i] })
    return out
  }
  readonly property string barSegmentKey: Model.segmentKeyForTab(currentTab)
  readonly property bool barSegmentEnabled: store && barSegmentKey !== "" ? store.segmentEnabled(barSegmentKey) : false

  onTabsChanged: {
    if (tabs.indexOf(currentTab) < 0) currentTab = tabs[0]
  }
  onCurrentTabChanged: { clearCursor(); focusProcessKeys() }
  onSettingsOpenChanged: {
    if (settingsOpen && currentProcessList) currentProcessList.suspendSearch()
  }
  onOpenedChanged: {
    if (opened) refreshActiveTab()
    else { settingsOpen = false; resetProcessViews() }
  }

  function open() { controller.show() }
  function close() { controller.hide() }

  // IPC entry point: deep-link a tab, opening the panel. Unknown or
  // unavailable tabs are ignored rather than throwing.
  function showTab(tab) {
    var name = String(tab || "")
    if (tabs.indexOf(name) < 0) return
    currentTab = name
    settingsOpen = false
    open()
  }

  function stepTab(direction) {
    var i = tabs.indexOf(currentTab)
    if (i < 0) { currentTab = tabs[0]; return }
    currentTab = tabs[(i + direction + tabs.length) % tabs.length]
  }

  function selectTabIndex(i) {
    if (i >= 0 && i < tabs.length) currentTab = tabs[i]
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function activeTabItem() {
    var map = { "cpu": cpuTab, "mem": memTab, "gpu": gpuTab, "net": netTab, "disk": diskTab }
    return map[currentTab] || null
  }

  function refreshActiveTab() {
    var item = activeTabItem()
    if (item && item.refresh) item.refresh()
  }

  function moveCursor(delta) {
    if (currentProcessList) currentProcessList.moveCursor(delta)
  }
  function clearCursor() {
    if (currentProcessList) currentProcessList.clearCursor()
  }
  function resetProcessViews() {
    var items = [cpuTab, memTab, diskTab, gpuTab, netTab]
    for (var i = 0; i < items.length; i++) if (items[i] && items[i].processList) items[i].processList.reset()
  }
  function focusProcessKeys() { if (keyCatcher) keyCatcher.forceActiveFocus() }
  function scrollProcessCursor(item) {
    var y = item.mapToItem(bodyColumn, 0, item.cursorY()).y
    if (y < bodyFlick.contentY) bodyFlick.contentY = Math.max(0, y)
    else if (y + item.rowHeight > bodyFlick.contentY + bodyFlick.height)
      bodyFlick.contentY = Math.min(Math.max(0, bodyFlick.contentHeight - bodyFlick.height), y + item.rowHeight - bodyFlick.height)
  }

  IpcHandler {
    target: "dev.bvisagie.quadrant"

    function showTab(tab: string): void { root.showTab(tab) }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function settings(): void { root.settingsOpen = true; root.open() }
    // Scriptable settings: `setBarSegment cpu false`, `set processCount 8`.
    function setBarSegment(name: string, enabled: bool): void {
      if (root.store) root.store.setBarSegment(name, enabled)
    }
    function set(key: string, valueJson: string): void {
      if (!root.store) return
      var value = Model.safeJsonValue(valueJson)
      if (value === undefined) return
      var patch = {}
      patch[key] = value
      root.store.persistSettings(patch)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Commons.Style.space(440))
    contentHeight: {
      var sp = Commons.Style.space(10)
      var natural = header.implicitHeight + headerSep.implicitHeight + bodyColumn.implicitHeight + sp * 2 + Commons.Style.space(6)
      return panel.fittedContentHeight(natural)
    }
    Behavior on contentHeight { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    Components.PanelKeys {
      id: keyCatcher
      anchors.fill: parent
      panel: root

      ColumnLayout {
        id: contentColumn
        width: parent.width
        height: parent.height
        spacing: Commons.Style.space(10)

        Components.PanelHeader {
          id: header
          Layout.fillWidth: true
          options: root.tabOptions
          currentTab: root.currentTab
          settingsOpen: root.settingsOpen
          barToggleVisible: root.store !== null && root.barSegmentKey !== ""
          barEnabled: root.barSegmentEnabled
          resourceName: root.tabLabels[root.currentTab] || root.currentTab
          onTabSelected: function (value) { root.currentTab = value; root.settingsOpen = false }
          onToggleBar: if (root.store) root.store.setBarSegment(root.barSegmentKey, !root.barSegmentEnabled)
          onToggleSettings: root.settingsOpen = !root.settingsOpen
        }

        PanelSeparator {
          id: headerSep
          Layout.fillWidth: true
        }

        Flickable {
          id: bodyFlick
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.preferredHeight: bodyColumn.implicitHeight
          Layout.minimumHeight: 0
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          contentWidth: width
          contentHeight: bodyColumn.implicitHeight
          interactive: contentHeight > height
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          Column {
            id: bodyColumn
            width: bodyFlick.width
            spacing: Commons.Style.space(10)

            // Keep last-good metrics on screen, but never leave stale or
            // failed async data looking live. Waiting is first-load only.
            Text {
              textFormat: Text.PlainText
              visible: {
                if (!root.store) return false
                if (root.store.gpuDetectionError !== "") return true
                if (root.store.diskInfoError !== "") return true
                if (root.store.streamError !== "") return true
                return root.store.streamLive !== true && !root.store.sample
              }
              text: {
                if (!root.store) return ""
                var messages = []
                if (root.store.streamError !== "") messages.push(root.store.streamError)
                else if (root.store.streamLive !== true && !root.store.sample) messages.push("Waiting for the system sampler…")
                if (root.store.gpuDetectionError !== "") messages.push(root.store.gpuDetectionError)
                if (root.store.diskInfoError !== "") messages.push(root.store.diskInfoError)
                return messages.join(" · ")
              }
              color: {
                if (!root.store) return Commons.Color.urgent
                if (root.store.streamError !== "" || root.store.gpuDetectionError !== "" || root.store.diskInfoError !== "")
                  return Commons.Color.urgent
                return root.dim
              }
              font.family: Commons.Style.font.family
              font.pixelSize: Commons.Style.font.caption
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Text {
              textFormat: Text.PlainText
              visible: text !== ""
              text: root.store ? [root.store.gpuDeviceWarning, root.store.integratedGpuWarning].filter(function (s) { return s !== "" }).join(" · ") : ""
              color: root.dim
              font.family: Commons.Style.font.family
              font.pixelSize: Commons.Style.font.caption
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Components.SettingsView {
              width: parent.width
              visible: root.settingsOpen
              store: root.store
            }

            // ---- tab content ----
            // A plain container, not a StackLayout: a Layout keeps the height
            // of its tallest child, which left short tabs with a blank
            // bottom. Only the current tab is visible; all stay alive so
            // their rosters keep their sticky order.
            Item {
              id: stack
              width: parent.width
              visible: !root.settingsOpen
              implicitHeight: {
                var item = root.activeTabItem()
                return visible && item ? item.implicitHeight : 0
              }

              Tabs.CpuTab { id: cpuTab; width: parent.width; visible: root.currentTab === "cpu"; panel: root; model: root.store }
              Tabs.MemoryTab { id: memTab; width: parent.width; visible: root.currentTab === "mem"; panel: root; model: root.store }
              Tabs.GpuTab { id: gpuTab; width: parent.width; visible: root.currentTab === "gpu"; panel: root; model: root.store }
              Tabs.NetworkTab { id: netTab; width: parent.width; visible: root.currentTab === "net"; panel: root; model: root.store }
              Tabs.DiskTab { id: diskTab; width: parent.width; visible: root.currentTab === "disk"; panel: root; model: root.store }
            }
          }
        }
      }
    }
  }
}
