import QtQuick
import qs.Commons

// Horizontal stacked composition bar. Segments are [{ fraction, color }].
Item {
  id: root

  property var segments: []
  property color trackColor: "#1acacccc"
  property real barHeight: Style.space(8)

  implicitWidth: 200
  implicitHeight: barHeight

  Rectangle {
    anchors.fill: parent
    radius: height / 2
    color: root.trackColor
  }

  Row {
    id: row
    anchors.fill: parent
    spacing: 0

    Repeater {
      model: root.segments

      delegate: Rectangle {
        required property var modelData
        required property int index
        height: row.height
        width: {
          var f = Number(modelData && modelData.fraction) || 0
          if (f < 0) f = 0
          if (f > 1) f = 1
          return Math.round(row.width * f)
        }
        color: modelData && modelData.color ? modelData.color : "transparent"
        visible: width > 0
      }
    }
  }
}
