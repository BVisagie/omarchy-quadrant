import QtQuick
import qs.Commons
import "../Theme.js" as Theme

// Stacked horizontal meter for a bar segment. `segments` is an ordered list
// of { fraction: 0..1, color } painted left to right on a muted track.
// Height defaults to a 3px hairline so the meter reads as a gauge under a
// percentage rather than a swatch; radius is half the height so the fill
// is a capsule.
Item {
  id: root

  property var segments: []
  property color trackColor: Theme.trackFor("#cacccc")
  property real radius: Math.max(0, Math.min(width, height) / 2)

  implicitWidth: Style.space(32)
  implicitHeight: Style.space(Theme.metrics.barMeterThickness)

  function offsetFor(index) {
    var sum = 0
    for (var i = 0; i < index && i < segments.length; i++) {
      var f = Number(segments[i] && segments[i].fraction) || 0
      sum += f < 0 ? 0 : (f > 1 ? 1 : f)
    }
    return sum
  }

  Rectangle {
    anchors.fill: parent
    radius: root.radius
    color: root.trackColor
  }

  Item {
    anchors.fill: parent
    clip: true

    Repeater {
      model: root.segments

      delegate: Rectangle {
        required property var modelData
        required property int index

        readonly property real fraction: {
          var f = Number(modelData && modelData.fraction) || 0
          return f < 0 ? 0 : (f > 1 ? 1 : f)
        }

        x: root.offsetFor(index) * root.width
        width: fraction * root.width
        height: root.height
        color: (modelData && modelData.color) || "transparent"
        visible: width > 0
      }
    }
  }
}
