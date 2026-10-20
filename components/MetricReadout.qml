import QtQuick
import qs.Commons as Commons
import "../lib/index.mjs" as Model

Column {
  id: root
  property string label: ""
  property string value: "--"
  property string hint: ""
  property color valueColor: Commons.Color.foreground
  readonly property color dim: Model.dimColor(String(Commons.Color.foreground), String(Commons.Color.background))
  spacing: Commons.Style.space(3)
  Text {
    textFormat: Text.PlainText
    visible: root.label !== ""
    text: root.label
    color: root.dim
    font.family: Commons.Style.font.family
    font.pixelSize: Commons.Style.font.caption
    width: parent.width
    wrapMode: Text.Wrap
  }
  Text {
    textFormat: Text.PlainText
    text: root.value
    color: root.valueColor
    font.family: Commons.Style.font.family
    font.pixelSize: Commons.Style.font.title * 1.25
    font.bold: true
    font.features: ({ "tnum": 1 })
    width: parent.width
    wrapMode: Text.Wrap
  }
  Text {
    textFormat: Text.PlainText
    visible: root.hint !== ""
    text: root.hint
    color: root.dim
    font.family: Commons.Style.font.family
    font.pixelSize: Commons.Style.font.caption
    width: parent.width
    wrapMode: Text.Wrap
  }
}
