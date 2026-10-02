import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
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
  readonly property color dim: Model.dimColor(String(Color.foreground), String(Color.background))

  // Last-used tab survives close/reopen; the window choice and the settings
  // view do not.
  property string currentTab: "cpu"
  property bool longWindow: false
  property bool settingsOpen: false

  // Single cursor over the active tab's process rows, driven by ↑/↓ and
  // by the mouse (ProcessList reports hover).
  property int cursorIndex: -1
  property bool cursorActive: false

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
  onCurrentTabChanged: clearCursor()
  onOpenedChanged: {
    if (opened) refreshActiveTab()
    else { settingsOpen = false; clearCursor() }
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

  function rowCount() {
    var item = activeTabItem()
    return item && item.rows ? item.rows.length : 0
  }

  function moveCursor(delta) {
    var n = rowCount()
    if (n === 0) { clearCursor(); return }
    cursorActive = true
    if (cursorIndex < 0) cursorIndex = delta > 0 ? 0 : n - 1
    else cursorIndex = Math.max(0, Math.min(n - 1, cursorIndex + delta))
  }

  function clearCursor() {
    cursorActive = false
    cursorIndex = -1
  }

  function hoverRow(index, on) {
    if (on) { cursorActive = true; cursorIndex = index }
    else if (cursorIndex === index) clearCursor()
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
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: {
      var sp = Style.space(10)
      var natural = header.implicitHeight + headerSep.implicitHeight + bodyColumn.implicitHeight + sp * 2 + Style.space(6)
      return panel.fittedContentHeight(natural)
    }
    Behavior on contentHeight { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.settingsOpen
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onMoveRequested: function (dx, dy) {
        if (dx !== 0) root.stepTab(dx)
        if (dy !== 0) root.moveCursor(dy)
      }
      onTextKey: function (t) {
        if (t === "r" || t === "R") {
          if (root.store) {
            root.store.refreshSysInfo()
            root.store.refreshDiskInfo()
            root.store.pollIgpu()
          }
          root.refreshActiveTab()
          return
        }
        if (t === "h" || t === "H") { root.longWindow = !root.longWindow; return }
        if (t === "s" || t === "S") { root.settingsOpen = !root.settingsOpen; return }
        if (t >= "1" && t <= "9") {
          var n = parseInt(t, 10)
          if (n >= 1 && n <= root.tabs.length) { root.selectTabIndex(n - 1); root.settingsOpen = false }
        }
      }

      // Escape closes the settings view first, then the panel.
      Keys.onEscapePressed: function (event) {
        if (root.settingsOpen) { root.settingsOpen = false; event.accepted = true }
        else event.accepted = false
      }

      ColumnLayout {
        id: contentColumn
        width: parent.width
        height: parent.height
        spacing: Style.space(10)

        // ---- header: tabs · show-in-bar · gear ----
        Item {
          id: header
          Layout.fillWidth: true
          implicitHeight: Math.max(tabStrip.implicitHeight, gear.implicitHeight, barToggleRow.implicitHeight)

          ButtonGroup {
            id: tabStrip
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            options: root.tabOptions
            value: root.settingsOpen ? "" : root.currentTab
            fontSize: Style.font.caption
            onChanged: function (value) { root.currentTab = value; root.settingsOpen = false }
          }

          Row {
            id: barToggleRow
            anchors.right: gear.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)
            visible: !root.settingsOpen && root.store && root.barSegmentKey !== ""

            Text {
              textFormat: Text.PlainText
              text: "in bar"
              color: root.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }
            ToggleSwitch {
              checked: root.barSegmentEnabled
              trackHeight: Math.max(16, Math.round(Style.spacing.controlHeight * 0.5))
              anchors.verticalCenter: parent.verticalCenter
              onToggled: if (root.store) root.store.setBarSegment(root.barSegmentKey, !root.barSegmentEnabled)
            }
          }

          PanelActionButton {
            id: gear
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: root.settingsOpen ? "󰅖" : "󰒓"
            tooltipText: root.settingsOpen ? "Close settings (S)" : "Settings (S)"
            onClicked: root.settingsOpen = !root.settingsOpen
          }
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
            spacing: Style.space(10)

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
                if (!root.store) return Color.urgent
                if (root.store.streamError !== "" || root.store.gpuDetectionError !== "" || root.store.diskInfoError !== "")
                  return Color.urgent
                return root.dim
              }
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Text {
              textFormat: Text.PlainText
              visible: root.store && root.store.gpuDeviceWarning !== ""
              text: root.store ? String(root.store.gpuDeviceWarning || "") : ""
              color: root.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
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
