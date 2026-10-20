import QtQuick
import qs.Commons as Commons
import "../lib/index.mjs" as Model

// Overview values use the theme's type and colours. Narrow panels wrap the
// cells, not the font size; unknown metrics remain explicit.
Grid {
  id: root
  property var metrics: []
  readonly property color dim: Model.dimColor(String(Commons.Color.foreground), String(Commons.Color.background))
  readonly property color track: Model.seriesPalette(String(Commons.Color.accent), String(Commons.Color.urgent),
                                                     String(Commons.Color.foreground), String(Commons.Color.background)).track
  columns: width >= Math.max(Commons.Style.space(640), Commons.Style.font.body * 48) ? 4
           : width >= Math.max(Commons.Style.space(260), Commons.Style.font.body * 20) ? 2 : 1
  columnSpacing: Commons.Style.space(1)
  rowSpacing: Commons.Style.space(1)

  Repeater {
    model: root.metrics
    delegate: Rectangle {
      id: cell
      required property var modelData
      objectName: modelData.name || ""
      readonly property string value: modelData.value || "--"
      width: Math.max(0, (root.width - root.columnSpacing * (root.columns - 1)) / root.columns)
      height: content.implicitHeight + Commons.Style.space(20)
      color: "transparent"
      border.width: 1
      border.color: root.track
      Column {
        id: content
        x: Commons.Style.space(10)
        y: Commons.Style.space(10)
        width: Math.max(0, parent.width - x * 2)
        spacing: Commons.Style.space(3)
        Text {
          textFormat: Text.PlainText
          text: String(cell.modelData.label || "").toUpperCase()
          color: root.dim
          font.family: Commons.Style.font.family
          font.pixelSize: Commons.Style.font.caption
          width: parent.width
          wrapMode: Text.Wrap
        }
        Text {
          textFormat: Text.PlainText
          text: cell.value
          color: cell.modelData.color || Commons.Color.foreground
          font.family: Commons.Style.font.family
          font.pixelSize: Commons.Style.font.title
          font.bold: true
          font.features: ({ "tnum": 1 })
          width: parent.width
          wrapMode: Text.Wrap
        }
        Text {
          textFormat: Text.PlainText
          text: cell.modelData.hint || ""
          visible: text !== ""
          color: root.dim
          font.family: Commons.Style.font.family
          font.pixelSize: Commons.Style.font.caption
          width: parent.width
          wrapMode: Text.Wrap
        }
      }
    }
  }
}
