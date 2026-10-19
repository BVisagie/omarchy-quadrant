import QtQuick
import qs.Commons as Commons
import qs.Ui
import "../lib/index.mjs" as Model
import "." as Components

// Explicit copy/open controls. A enters the same visible action cursor used
// by clicks; panel shortcuts and shell-owned Tab remain on PanelKeys.
Column {
  id: root
  property var panel: null
  property var entries: []
  property string context: ""
  property bool keyboardActive: false
  property string selectedKey: ""
  property alias runner: localRunner
  readonly property int selectedIndex: {
    // Read outside the callback so selection changes notify this binding.
    var key = selectedKey
    return entries.findIndex(function (entry) { return entry.key === key })
  }
  readonly property color dim: Model.dimColor(String(Commons.Color.foreground), String(Commons.Color.background))
  spacing: Commons.Style.space(6)

  function leaveFocus() { keyboardActive = false; selectedKey = "" }
  function focusEntry(index) {
    if (!entries.length) return false
    index = Math.max(0, Math.min(entries.length - 1, index))
    selectedKey = entries[index].key
    keyboardActive = true
    if (panel && panel.currentProcessList && typeof panel.currentProcessList.clearCursor === "function") panel.currentProcessList.clearCursor()
    if (panel && typeof panel.focusProcessKeys === "function") panel.focusProcessKeys()
    var item = actionRows.itemAt(index)
    if (item && panel && typeof panel.scrollActionItem === "function") panel.scrollActionItem(item)
    return true
  }
  function toggleFocus() {
    if (keyboardActive) { leaveFocus(); return }
    focusEntry(selectedIndex >= 0 ? selectedIndex : 0)
  }
  function moveCursor(delta) { focusEntry(selectedIndex < 0 ? 0 : selectedIndex + delta) }
  function activate() { if (selectedIndex >= 0) trigger(selectedIndex) }
  function revealFeedback() {
    if (keyboardActive && panel && panel.opened && !panel.settingsOpen && !panel.searchFocused
        && panel.currentActions === root && runner.message !== ""
        && typeof panel.scrollActionItem === "function") panel.scrollActionItem(feedback)
  }
  function trigger(index) {
    var entry = entries[index]
    if (!entry || runner.busy) return
    focusEntry(index)
    if (entry.available === false) {
      runner.error = true; runner.message = "Cannot open " + entry.value + ": this mount path is incomplete"
      return
    }
    runner.run(entry.kind, entry.value)
  }
  onContextChanged: { leaveFocus(); if (localRunner) localRunner.clear() }
  onEntriesChanged: {
    var key = selectedKey
    if (key !== "" && !entries.some(function (entry) { return entry.key === key })) leaveFocus()
  }

  Components.LocalAction { id: localRunner }
  Connections {
    target: localRunner
    function onMessageChanged() { if (localRunner.message !== "") Qt.callLater(root.revealFeedback) }
  }
  Repeater {
    id: actionRows
    model: root.entries
    delegate: Column {
      id: row
      required property var modelData
      required property int index
      objectName: "actionRow_" + index
      width: root.width
      spacing: Commons.Style.space(3)
      Item {
        width: parent.width
        implicitHeight: Math.max(labels.implicitHeight, actionButton.implicitHeight)
        Column {
          id: labels
          width: Math.max(1, parent.width - actionButton.width - Commons.Style.space(8))
          anchors.verticalCenter: parent.verticalCenter
          spacing: Commons.Style.space(2)
          Text {
            textFormat: Text.PlainText
            text: row.modelData.label
            color: root.dim
            font.family: Commons.Style.font.family
            font.pixelSize: Commons.Style.font.caption
          }
          Text {
            objectName: "actionValue_" + row.index
            textFormat: Text.PlainText
            text: row.modelData.value
            color: Commons.Color.foreground
            font.family: Commons.Style.font.family
            font.pixelSize: Commons.Style.font.body
            width: parent.width
            wrapMode: Text.WrapAnywhere
            maximumLineCount: row.modelData.kind === "copy" ? 10 : 2
            elide: row.modelData.kind === "copy" ? Text.ElideNone : Text.ElideMiddle
          }
        }
        Button {
          id: actionButton
          objectName: "actionButton_" + row.index
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: row.modelData.kind === "copy" ? "Copy" : "Open"
          fontSize: Commons.Style.font.caption
          bordered: true
          focusable: true
          hasCursor: root.keyboardActive && root.selectedKey === row.modelData.key
          enabled: !runner.busy
          opacity: enabled ? 1 : 0.5
          tooltipText: (row.modelData.kind === "copy" ? "Copy " : "Open ") + row.modelData.value + " · A for keyboard actions"
          Accessible.role: Accessible.Button
          Accessible.name: (row.modelData.kind === "copy" ? "Copy " : "Open ") + row.modelData.label + " " + row.modelData.value
          Accessible.onPressAction: root.trigger(row.index)
          onClicked: root.trigger(row.index)
        }
      }
      Text {
        textFormat: Text.PlainText
        visible: row.modelData.kind === "open-mount"
        text: Model.formatBytes(row.modelData.used) + " of " + Model.formatBytes(row.modelData.size) + " · " + Model.formatPct(row.modelData.pct)
        color: root.dim
        font.family: Commons.Style.font.family
        font.pixelSize: Commons.Style.font.caption
        width: parent.width
        wrapMode: Text.WordWrap
      }
      Components.CompositionBar {
        visible: row.modelData.kind === "open-mount"
        width: parent.width
        barHeight: Commons.Style.space(4)
        segments: [{ fraction: Math.max(0, Math.min(100, Number(row.modelData.pct) || 0)) / 100,
          color: Model.heatColor(row.modelData.pct, String(Commons.Color.accent), String(Commons.Color.accent), String(Commons.Color.urgent), 80) }]
      }
    }
  }
  Text {
    textFormat: Text.PlainText
    visible: root.entries.length > 0
    text: root.keyboardActive ? "↑/↓ choose · Enter activate · Esc return" : "A · keyboard actions"
    color: root.dim
    font.family: Commons.Style.font.family
    font.pixelSize: Commons.Style.font.caption
    width: parent.width
    wrapMode: Text.WordWrap
  }
  Text {
    id: feedback
    objectName: "actionFeedback"
    textFormat: Text.PlainText
    visible: runner.message !== ""
    text: runner.message
    color: runner.error ? Commons.Color.urgent : Commons.Color.accent
    font.family: Commons.Style.font.family
    font.pixelSize: Commons.Style.font.caption
    width: parent.width
    wrapMode: Text.WrapAnywhere
    Accessible.role: Accessible.AlertMessage
    Accessible.name: text
  }
}
