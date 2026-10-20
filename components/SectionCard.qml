import QtQuick
import qs.Commons as Commons
import "../lib/index.mjs" as Model

// One semantic group. The panel owns scrolling; this surface only adds
// consistent framing and space around its existing controls.
Rectangle {
  id: root
  default property alias content: body.data
  property string title: ""
  property real padding: Commons.Style.space(12)
  readonly property bool sectionCard: true
  implicitWidth: 200
  implicitHeight: column.implicitHeight + padding * 2
  color: Model.withAlpha(String(Commons.Color.foreground), 0.025)
  border.width: 1
  border.color: Model.withAlpha(String(Commons.Color.foreground), 0.12)
  radius: Commons.Style.cornerRadius

  data: [
    Column {
      id: column
      x: root.padding
      y: root.padding
      width: Math.max(0, root.width - root.padding * 2)
      spacing: Commons.Style.space(12)
      Text {
        textFormat: Text.PlainText
        visible: root.title !== ""
        text: root.title
        color: Commons.Color.foreground
        font.family: Commons.Style.font.family
        font.pixelSize: Commons.Style.font.caption
        font.bold: true
        width: parent.width
        wrapMode: Text.Wrap
      }
      Column {
        id: body
        width: parent.width
        spacing: Commons.Style.space(10)
      }
    }
  ]
}
