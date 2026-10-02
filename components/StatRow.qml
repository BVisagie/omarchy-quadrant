import QtQuick
import qs.Commons
import "../lib/index.mjs" as Model

// One "label ........ value" line. Values use tabular numerals so a column
// of them stays aligned while digits change.
Item {
  id: root

  property string label: ""
  property string value: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property color labelColor: Model.dimColor(String(foreground), String(Color.background))
  property color valueColor: foreground
  property bool valueBold: false
  property real labelMaximumRatio: 0.42
  property real textSpacing: Style.space(8)

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
    width: Math.min(implicitWidth, parent.width * root.labelMaximumRatio)
  }

  Text {
    id: valueText
    textFormat: Text.PlainText
    text: root.value
    color: root.valueColor
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    font.bold: root.valueBold
    font.features: ({ "tnum": 1 })
    anchors.left: labelText.right
    anchors.leftMargin: root.textSpacing
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    horizontalAlignment: Text.AlignRight
    elide: Text.ElideLeft
  }
}
