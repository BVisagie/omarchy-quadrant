import QtQuick
import qs.Commons
import "../lib/index.mjs" as Model

// Percentage ring: fraction 0..1 painted in `color` over a faint track,
// centre value and caption. The arc animates between readings.
Item {
  id: root
  clip: true

  property real fraction: 0
  property color color: Color.accent
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property real thickness: Style.space(9)
  property string centerText: ""
  property string subText: ""
  property real size: Style.space(96)

  readonly property color trackColor: Model.withAlpha(String(foreground).length === 9 ? "#" + String(foreground).slice(3) : String(foreground), 0.10)
  readonly property color dim: Model.dimColor(String(foreground), String(Color.background))

  property real shown: 0
  Behavior on shown { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
  onFractionChanged: shown = Math.max(0, Math.min(1, fraction))
  Component.onCompleted: shown = Math.max(0, Math.min(1, fraction))

  implicitWidth: size
  implicitHeight: size

  onShownChanged: canvas.requestPaint()
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
      ctx.strokeStyle = root.trackColor
      ctx.beginPath()
      ctx.arc(cx, cy, r, 0, 2 * Math.PI)
      ctx.stroke()

      var f = root.shown
      if (f > 0) {
        ctx.strokeStyle = root.color
        ctx.beginPath()
        ctx.arc(cx, cy, r, start, start + 2 * Math.PI * f)
        ctx.stroke()
      }
    }
  }

  Column {
    anchors.centerIn: parent
    spacing: 0
    width: parent.width - root.thickness * 2 - Style.space(6)

    Text {
      textFormat: Text.PlainText
      text: root.centerText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.subtitle
      font.bold: true
      font.features: ({ "tnum": 1 })
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
    }
    Text {
      textFormat: Text.PlainText
      visible: root.subText !== ""
      text: root.subText
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
    }
  }
}
