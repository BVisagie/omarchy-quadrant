import QtQuick
import qs.Commons as Commons
import qs.Ui
import "../lib/index.mjs" as Model

// Tab hero: bold identity, muted metadata (preserving unit case), and a
// detail pill that moves below the identity when the panel is narrow.
Item {
  id: root

  property string title: ""
  property string meta: ""
  property string detail: ""
  property color foreground: Commons.Color.foreground
  property string fontFamily: Commons.Style.font.family
  readonly property color dim: Model.dimColor(String(foreground), String(Commons.Color.background))
  readonly property bool stackedDetail: detail !== "" && width < Commons.Style.space(200) + pill.implicitWidth + Commons.Style.space(10)

  implicitWidth: 200
  implicitHeight: stackedDetail ? labels.implicitHeight + Commons.Style.space(6) + pill.implicitHeight
                               : Math.max(labels.implicitHeight, pill.implicitHeight)

  Column {
    id: labels
    objectName: "heroLabels"
    width: root.detail !== "" && !root.stackedDetail ? Math.max(0, root.width - pill.width - Commons.Style.space(10)) : root.width
    spacing: Commons.Style.space(2)

    Text {
      textFormat: Text.PlainText
      text: root.title
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.title
      font.bold: true
      width: parent.width
      wrapMode: Text.WordWrap
      maximumLineCount: 2
      elide: Text.ElideRight
    }
    Text {
      textFormat: Text.PlainText
      visible: root.meta !== ""
      text: root.meta
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.caption
      width: parent.width
      wrapMode: Text.Wrap
      maximumLineCount: 2
      elide: Text.ElideRight
    }
  }

  BorderSurface {
    id: pill
    objectName: "heroDetail"
    visible: root.detail !== ""
    implicitWidth: detailText.implicitWidth + Commons.Style.space(10)
    implicitHeight: detailText.implicitHeight + Commons.Style.space(4)
    width: Math.min(implicitWidth, root.width)
    x: root.stackedDetail ? 0 : root.width - width
    y: root.stackedDetail ? labels.implicitHeight + Commons.Style.space(6) : 0
    color: "transparent"
    borderSpec: Commons.Border.controlSpec("normal", root.foreground, Commons.Color.accent)
    radius: Commons.Style.cornerRadius

    Text {
      id: detailText
      textFormat: Text.PlainText
      anchors.centerIn: parent
      width: Math.max(0, parent.width - Commons.Style.space(10))
      text: root.detail
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.body
      font.bold: true
      font.features: ({ "tnum": 1 })
      elide: Text.ElideRight
    }
  }
}
