import QtQuick
import qs.Commons
import "../lib/index.mjs" as Model

// Stacked horizontal bar: segments [{ fraction, color }] left to right over
// a faint track. Widths animate so a changing composition slides rather
// than jumps.
Item {
  id: root

  property var segments: []
  property color foreground: Color.foreground
  property real barHeight: Style.space(8)
  readonly property color trackColor: Model.withAlpha(String(foreground).length === 9 ? "#" + String(foreground).slice(3) : String(foreground), 0.10)

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
    clip: true

    Repeater {
      model: root.segments
      delegate: Rectangle {
        required property var modelData
        height: row.height
        width: {
          var f = Number(modelData && modelData.fraction) || 0
          if (f < 0) f = 0
          if (f > 1) f = 1
          return Math.round(row.width * f)
        }
        color: modelData && modelData.color ? modelData.color : "transparent"
        visible: width > 0
        Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
      }
    }
  }
}
