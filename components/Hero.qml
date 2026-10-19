import QtQuick
import qs.Commons as Commons
import qs.Ui
import "../lib/index.mjs" as Model

// Tab hero: bold title, a muted meta line in normal case (units such as
// GiB and MT/s must keep their case), and a detail pill on the right.
Item {
  id: root

  property string title: ""
  property string meta: ""
  property string detail: ""
  property color foreground: Commons.Color.foreground
  property string fontFamily: Commons.Style.font.family
  readonly property color dim: Model.dimColor(String(foreground), String(Commons.Color.background))

  implicitWidth: 200
  implicitHeight: Math.max(labels.implicitHeight, pill.implicitHeight)

  Column {
    id: labels
    anchors.left: parent.left
    anchors.right: pill.visible ? pill.left : parent.right
    anchors.rightMargin: pill.visible ? Commons.Style.space(10) : 0
    anchors.verticalCenter: parent.verticalCenter
    spacing: Commons.Style.space(2)

    Text {
      textFormat: Text.PlainText
      text: root.title
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.title
      font.bold: true
      width: parent.width
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
    visible: root.detail !== ""
    implicitWidth: detailText.implicitWidth + Commons.Style.space(10)
    implicitHeight: detailText.implicitHeight + Commons.Style.space(4)
    anchors.right: parent.right
    anchors.top: parent.top
    color: "transparent"
    borderSpec: Commons.Border.controlSpec("normal", root.foreground, Commons.Color.accent)
    radius: Commons.Style.cornerRadius

    Text {
      id: detailText
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: root.detail
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.body
      font.bold: true
      font.features: ({ "tnum": 1 })
    }
  }
}
