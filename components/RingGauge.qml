import QtQuick
import qs.Commons
import "../Theme.js" as Theme

// Percentage ring with an optional segmented mode.
//   fraction  — single-arc mode, 0..1, painted in `color`
//   segments  — [{ fraction, color }] composition mode; takes precedence
// Center shows centerText over subText (both PlainText).
Item {
  id: root
  clip: true

  property real fraction: 0
  property var segments: []
  property color color: "#7aa2f7"
  property color trackColor: Theme.trackFor("#cacccc")
  property real thickness: Style.space(Theme.metrics.ringThickness)
  property string centerText: ""
  property string subText: ""
  property color foreground: "#cacccc"
  property string fontFamily: Style.font.family
  property real size: Style.space(Theme.metrics.ringSize)

  implicitWidth: size
  implicitHeight: size

  onFractionChanged: canvas.requestPaint()
  onSegmentsChanged: canvas.requestPaint()
  onColorChanged: canvas.requestPaint()
  onTrackColorChanged: canvas.requestPaint()
  onThicknessChanged: canvas.requestPaint()

  Canvas {
    id: canvas
    anchors.fill: parent

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var cx = width / 2
      var cy = height / 2
      var t = root.thickness
      var r = Math.max(1, Math.min(cx, cy) - t / 2)
      var start = -Math.PI / 2

      ctx.lineWidth = t
      ctx.lineCap = "round"

      // track
      ctx.strokeStyle = root.trackColor
      ctx.beginPath()
      ctx.arc(cx, cy, r, 0, 2 * Math.PI)
      ctx.stroke()

      var segs = root.segments
      if (segs && segs.length > 0) {
        // Flat joins keep adjacent composition segments crisp instead of
        // letting rounded caps paint over the neighboring color.
        ctx.lineCap = "butt"
        var angle = start
        for (var i = 0; i < segs.length; i++) {
          var f = Number(segs[i] && segs[i].fraction) || 0
          f = f < 0 ? 0 : (f > 1 ? 1 : f)
          if (f <= 0) continue
          var end = angle + f * 2 * Math.PI
          ctx.strokeStyle = segs[i].color
          ctx.beginPath()
          ctx.arc(cx, cy, r, angle, end)
          ctx.stroke()
          angle = end
        }
      } else {
        var frac = Number(root.fraction) || 0
        frac = frac < 0 ? 0 : (frac > 1 ? 1 : frac)
        if (frac > 0) {
          ctx.strokeStyle = root.color
          ctx.beginPath()
          ctx.arc(cx, cy, r, start, start + frac * 2 * Math.PI)
          ctx.stroke()
        }
      }
    }
  }

  Column {
    anchors.centerIn: parent
    width: Math.max(0, root.width - root.thickness * 2 - Style.space(8))
    spacing: 0

    Text {
      textFormat: Text.PlainText
      text: root.centerText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.subtitle
      font.bold: true
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideMiddle
    }

    Text {
      textFormat: Text.PlainText
      text: root.subText
      color: Qt.darker(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideMiddle
      visible: root.subText !== ""
    }
  }
}
