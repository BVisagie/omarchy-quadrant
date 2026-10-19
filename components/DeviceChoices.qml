import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui

// Keep full device names in tooltips and accessibility while wrapping
// choices and eliding a single label that is wider than the panel.
Flow {
  id: root
  property var options: []
  property string value: ""
  property real fontSize: Commons.Style.font.caption
  signal changed(string value)
  spacing: Commons.Style.space(6)

  Ui.Button {
    id: chrome
    visible: false
    bordered: true
    fontSize: root.fontSize
  }
  Repeater {
    model: root.options
    delegate: Ui.Button {
      id: choice
      required property var modelData
      required property int index
      objectName: "deviceChoice_" + index
      width: Math.min(implicitWidth, root.width)
      clip: true
      text: metrics.elidedText
      tooltipText: modelData.label + (modelData.tooltip ? "\n" + modelData.tooltip : "")
      selected: root.value === modelData.value
      bordered: true
      fontSize: root.fontSize
      Accessible.role: Accessible.RadioButton
      Accessible.name: modelData.label
      Accessible.checkable: true
      Accessible.checked: selected
      Accessible.onPressAction: root.changed(modelData.value)
      onClicked: root.changed(modelData.value)
      TextMetrics {
        id: metrics
        font.family: Commons.Style.font.family
        font.pixelSize: root.fontSize
        font.bold: true
        text: choice.modelData.label
        elide: Text.ElideRight
        elideWidth: Math.max(0, root.width - chrome.implicitWidth)
      }
    }
  }
}
