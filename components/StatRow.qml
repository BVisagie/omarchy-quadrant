import QtQuick
import qs.Commons

// Label/value row used across panel tabs. Both texts are PlainText: values
// can carry script output.
Item {
  id: root

  property string label: ""
  property string value: ""
  property color labelColor: Qt.darker(foreground, 1.4)
  property color valueColor: foreground
  property color foreground: "#cacccc"
  property string fontFamily: Style.font.family
  property bool valueBold: false

  implicitWidth: 200
  implicitHeight: Math.max(labelText.implicitHeight, valueText.implicitHeight)

  Text {
    id: labelText
    textFormat: Text.PlainText
    text: root.label
    color: root.labelColor
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    elide: Text.ElideRight
    width: Math.min(implicitWidth, parent.width * 0.6)
  }

  Text {
    id: valueText
    textFormat: Text.PlainText
    text: root.value
    color: root.valueColor
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    font.bold: root.valueBold
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    horizontalAlignment: Text.AlignRight
    elide: Text.ElideLeft
    width: Math.min(implicitWidth, parent.width * 0.7)
  }
}
