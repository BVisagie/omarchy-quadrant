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
  property var details: ({})
  property string context: ""
  property bool keyboardActive: false
  property string selectedKey: ""
  property alias runner: localRunner
  signal requested(var entry)
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
  function unavailableReason(entry) {
    if (entry.unavailableReason) return entry.unavailableReason
    if (entry.available === false) return "this mount path is incomplete"
    var detail = details[entry.value]
    return detail && detail.unavailableReason ? detail.unavailableReason : ""
  }
  function trigger(index) {
    var entry = entries[index]
    if (!entry || runner.busy) return
    focusEntry(index)
    var reason = unavailableReason(entry)
    if (reason) {
      runner.error = true; runner.message = (entry.kind === "gpu-details" ? "Cannot show details for " : "Cannot open ") + entry.value + ": " + reason
      return
    }
    if (entry.kind === "copy" || entry.kind === "open-mount") runner.run(entry.kind, entry.value)
    else requested(entry)
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
      readonly property var detail: root.details[modelData.value] || ({})
      readonly property string unavailableReason: root.unavailableReason(modelData)
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
            width: parent.width
            wrapMode: Text.Wrap
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
          text: row.modelData.actionText || (row.modelData.kind === "copy" ? "Copy" : "Open")
          fontSize: Commons.Style.font.caption
          bordered: true
          focusable: true
          hasCursor: root.keyboardActive && root.selectedKey === row.modelData.key
          enabled: !runner.busy && row.unavailableReason === ""
          opacity: enabled ? 1 : 0.5
          tooltipText: text + " " + row.modelData.value
            + (row.unavailableReason ? "\n" + row.unavailableReason + " · R to refresh" : " · A for keyboard actions")
          Accessible.role: Accessible.Button
          Accessible.name: text + " " + row.modelData.label + " " + row.modelData.value
            + (row.unavailableReason ? ": " + row.unavailableReason : "")
          Accessible.onPressAction: root.trigger(row.index)
          onClicked: root.trigger(row.index)
        }
        // A disabled Button cannot receive hover. Keep its explanation on an
        // enabled sibling that does not accept clicks or change selection.
        MouseArea {
          id: blockedHover
          objectName: "actionUnavailableHover_" + row.index
          property alias explanation: unavailableTooltip
          anchors.fill: actionButton
          enabled: row.unavailableReason !== ""
          hoverEnabled: true
          acceptedButtons: Qt.NoButton
          PanelToolTip {
            id: unavailableTooltip
            visible: blockedHover.containsMouse
            text: actionButton.tooltipText
            width: Math.min(implicitWidth, root.width)
            contentItem: Text {
              textFormat: Text.PlainText
              text: unavailableTooltip.text
              wrapMode: Text.WrapAnywhere
              color: unavailableTooltip.panelForeground
              font.family: unavailableTooltip.fontFamily
              font.pixelSize: unavailableTooltip.fontSize
              leftPadding: Commons.Border.left(unavailableTooltip.panelBorderSpec) + Commons.Style.spacing.controlPaddingX
              rightPadding: Commons.Border.right(unavailableTooltip.panelBorderSpec) + Commons.Style.spacing.controlPaddingX
              topPadding: Commons.Border.top(unavailableTooltip.panelBorderSpec) + Commons.Style.spacing.controlPaddingY
              bottomPadding: Commons.Border.bottom(unavailableTooltip.panelBorderSpec) + Commons.Style.spacing.controlPaddingY
            }
          }
        }
      }
      Text {
        objectName: "actionUsage_" + row.index
        textFormat: Text.PlainText
        visible: row.modelData.kind === "open-mount"
        text: Model.formatBytes(row.detail.used) + " of " + Model.formatBytes(row.detail.size) + " · " + Model.formatPct(row.detail.pct)
        color: root.dim
        font.family: Commons.Style.font.family
        font.pixelSize: Commons.Style.font.caption
        width: parent.width
        wrapMode: Text.WordWrap
      }
      Components.CompositionBar {
        objectName: "actionUsageBar_" + row.index
        visible: row.modelData.kind === "open-mount"
        width: parent.width
        barHeight: Commons.Style.space(4)
        segments: [{ fraction: Math.max(0, Math.min(100, Number(row.detail.pct) || 0)) / 100,
          color: Model.heatColor(row.detail.pct, String(Commons.Color.accent), String(Commons.Color.accent), String(Commons.Color.urgent), 80) }]
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
