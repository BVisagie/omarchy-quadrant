import QtQuick
import qs.Commons
import qs.Ui
import "../lib/index.mjs" as Model

// Tab hero: bold title, a muted meta line in normal case (units such as
// GiB and MT/s must keep their case), and a detail pill on the right.
Item {
  id: root

  property string title: ""
  property string meta: ""
  property string detail: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  readonly property color dim: Model.dimColor(String(foreground), String(Color.background))

  implicitWidth: 200
  implicitHeight: Math.max(labels.implicitHeight, pill.implicitHeight)

  Column {
    id: labels
    anchors.left: parent.left
    anchors.right: pill.visible ? pill.left : parent.right
    anchors.rightMargin: pill.visible ? Style.space(10) : 0
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    Text {
      textFormat: Text.PlainText
      text: root.title
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
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
      font.pixelSize: Style.font.caption
      width: parent.width
      wrapMode: Text.Wrap
      maximumLineCount: 2
      elide: Text.ElideRight
    }
  }

  BorderSurface {
    id: pill
    visible: root.detail !== ""
    implicitWidth: detailText.implicitWidth + Style.space(10)
    implicitHeight: detailText.implicitHeight + Style.space(4)
    anchors.right: parent.right
    anchors.top: parent.top
    color: "transparent"
    borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
    radius: Style.cornerRadius

    Text {
      id: detailText
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: root.detail
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
      font.features: ({ "tnum": 1 })
    }
  }
}
