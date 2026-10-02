import QtQuick
import qs.Commons
import "../lib/index.mjs" as Model

// Small uppercase section label with an optional right-aligned note.
Item {
  id: root

  property string text: ""
  property string note: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  readonly property color dim: Model.dimColor(String(foreground), String(Color.background))

  signal noteClicked()

  implicitWidth: 200
  implicitHeight: Math.max(label.implicitHeight, noteText.implicitHeight)

  Text {
    id: label
    textFormat: Text.PlainText
    text: root.text
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
  }

  Text {
    id: noteText
    textFormat: Text.PlainText
    visible: root.note !== ""
    text: root.note
    color: noteMouse.containsMouse ? root.foreground : root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.features: ({ "tnum": 1 })
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter

    MouseArea {
      id: noteMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.noteClicked()
    }
  }
}
