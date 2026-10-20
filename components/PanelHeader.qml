import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui
import "../lib/index.mjs" as Model

// Share one row when all measured labels and actions fit; otherwise give the
// bar switch its own row and wrap tabs without covering another control.
Item {
  id: root

  property var options: []
  property string currentTab: "cpu"
  property bool settingsOpen: false
  property bool barToggleVisible: false
  property bool barEnabled: false
  property string resourceName: "CPU"
  readonly property string barLabel: "Show " + resourceName + " in bar"
  readonly property color dim: Model.dimColor(String(Commons.Color.foreground), String(Commons.Color.background))

  signal tabSelected(string value)
  signal toggleBar()
  signal toggleSettings()

  readonly property bool inlineActions: barToggleRow.visible && width >=
    Math.ceil(tabMeasure.implicitWidth) * options.length + Commons.Style.space(4) * Math.max(0, options.length - 1)
    + barToggleRow.implicitWidth + gear.width + Commons.Style.space(24)
  implicitHeight: barToggleRow.visible && !inlineActions ? barToggleRow.y + barToggleRow.implicitHeight : topHeight
  readonly property real topHeight: Math.max(tabFlow.implicitHeight, gear.implicitHeight, inlineActions ? barToggleRow.implicitHeight : 0)

  // Measure the widest selected label with the same theme chrome as the
  // real buttons; a bold selection must not make an equal slot too small.
  Column {
    id: tabMeasure
    visible: false
    Repeater {
      model: root.options
      delegate: Ui.Button {
        required property var modelData
        text: modelData.label
        fontSize: Commons.Style.font.caption
        selected: true
        bordered: true
      }
    }
  }

  Flow {
    id: tabFlow
    objectName: "panelTabs"
    width: Math.max(0, root.width - gear.width - Commons.Style.space(8)
                      - (root.inlineActions ? barToggleRow.implicitWidth + Commons.Style.space(16) : 0))
    spacing: Commons.Style.space(4)
    // Round the minimum up and each slot down so Flow cannot wrap a fitting
    // tab because floating-point sums exceed the available width slightly.
    readonly property int maxColumns: Math.max(1, Math.floor((width + spacing) / (Math.ceil(tabMeasure.implicitWidth) + spacing)))
    readonly property int rows: Math.ceil((root.options.length || 1) / maxColumns)
    readonly property int columns: Math.ceil((root.options.length || 1) / rows)

    Repeater {
      model: root.options
      delegate: Ui.Button {
        required property var modelData
        objectName: "panelTab_" + modelData.value
        width: Math.max(0, Math.floor((tabFlow.width - tabFlow.spacing * (tabFlow.columns - 1)) / tabFlow.columns))
        text: modelData.label
        tooltipText: modelData.label
        selected: !root.settingsOpen && root.currentTab === modelData.value
        fontSize: Commons.Style.font.caption
        bordered: true
        Accessible.role: Accessible.PageTab
        Accessible.name: modelData.label
        Accessible.selected: selected
        Accessible.onPressAction: root.tabSelected(modelData.value)
        onClicked: root.tabSelected(modelData.value)
      }
    }
  }

  Ui.PanelActionButton {
    id: gear
    objectName: "panelSettings"
    anchors.right: parent.right
    y: (root.topHeight - height) / 2
    iconText: root.settingsOpen ? "󰅖" : "󰒓"
    tooltipText: root.settingsOpen ? "Close settings (Esc)" : "Settings (S)"
    Accessible.role: Accessible.Button
    Accessible.name: tooltipText
    Accessible.onPressAction: root.toggleSettings()
    onClicked: root.toggleSettings()
  }

  Row {
    id: barToggleRow
    objectName: "barVisibility"
    x: root.inlineActions ? gear.x - width - Commons.Style.space(8) : 0
    y: root.inlineActions ? (root.topHeight - implicitHeight) / 2 : root.topHeight + Commons.Style.space(4)
    visible: root.barToggleVisible && !root.settingsOpen
    spacing: Commons.Style.space(6)

    Ui.ToggleSwitch {
      id: barToggle
      objectName: "barVisibilitySwitch"
      checked: root.barEnabled
      trackHeight: Math.max(16, Math.round(Commons.Style.spacing.controlHeight * 0.5))
      Accessible.role: Accessible.CheckBox
      Accessible.name: root.barLabel
      Accessible.checkable: true
      Accessible.checked: checked
      Accessible.onToggleAction: root.toggleBar()
      onToggled: root.toggleBar()
      Ui.PanelToolTip { visible: barToggle.containsMouse; text: root.barLabel }
    }
    Text {
      textFormat: Text.PlainText
      text: root.barLabel
      color: root.dim
      font.family: Commons.Style.font.family
      font.pixelSize: Commons.Style.font.caption
      anchors.verticalCenter: parent.verticalCenter
    }
  }
}
