import QtQuick
import qs.Commons
import "../lib/index.mjs" as Model

// Legend row under a graph: swatch, label and the live value, wrapping
// onto a second line when the panel is narrow. An item with `visible:
// false` is skipped (steal when it is zero, for instance).
//   items — [{ label, color, value, visible }]
Flow {
  id: root

  property var items: []
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property color dim: Model.dimColor(String(foreground), String(Color.background))

  spacing: Style.space(12)

  Repeater {
    model: root.items

    delegate: Row {
      required property var modelData
      visible: !(modelData && modelData.visible === false)
      spacing: Style.space(5)

      Rectangle {
        width: Style.space(8)
        height: Style.space(8)
        radius: Style.space(2)
        color: parent.modelData && parent.modelData.color ? parent.modelData.color : "transparent"
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        textFormat: Text.PlainText
        text: parent.modelData ? String(parent.modelData.label || "") : ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        textFormat: Text.PlainText
        visible: text !== ""
        text: parent.modelData && parent.modelData.value !== undefined && parent.modelData.value !== null
              ? String(parent.modelData.value) : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.features: ({ "tnum": 1 })
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }
}
