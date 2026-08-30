import QtQuick
import qs.Commons

// Responsive hardware identity header. Unlike the shell PanelHero, the title
// gets the full panel width and may use two lines; compact details sit on a
// second row so long CPU/GPU marketing names are not sacrificed to a badge.
Item {
  id: root

  property string title: ""
  property string meta: ""
  property string detail: ""
  property color foreground: "#cacccc"
  property string fontFamily: Style.font.family

  implicitWidth: 200
  implicitHeight: content.implicitHeight

  Column {
    id: content
    width: parent.width
    spacing: Style.space(4)

    Text {
      textFormat: Text.PlainText
      text: root.title
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.subtitle
      font.bold: true
      width: parent.width
      wrapMode: Text.Wrap
      maximumLineCount: 2
      elide: Text.ElideRight
    }

    Row {
      width: parent.width
      spacing: Style.space(8)
      visible: root.meta !== "" || root.detail !== ""

      Text {
        textFormat: Text.PlainText
        text: root.meta
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1
        width: detailBadge.visible
               ? Math.max(0, parent.width - detailBadge.width - parent.spacing)
               : parent.width
        elide: Text.ElideRight
        anchors.verticalCenter: parent.verticalCenter
      }

      Rectangle {
        id: detailBadge
        visible: root.detail !== ""
        width: detailText.implicitWidth + Style.space(12)
        height: detailText.implicitHeight + Style.space(6)
        radius: Style.cornerRadius
        color: "transparent"
        border.width: 1
        border.color: Qt.darker(root.foreground, 1.8)

        Text {
          id: detailText
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: root.detail
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }
    }
  }
}
