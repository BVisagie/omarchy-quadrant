import QtQuick

// Tiny trend line for a process row: newest value on the right, a thin
// filled area under the line, scaled to `maxValue` (or to the row's own
// peak when 0) so a process climbing shows as a rising edge. Pure paint,
// no interaction, no text.
Canvas {
  id: root

  property var values: []
  property color color: "#cacccc"
  property real maxValue: 0
  property int capacity: 30

  implicitWidth: 36
  implicitHeight: 12

  onValuesChanged: requestPaint()
  onColorChanged: requestPaint()
  onMaxValueChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    var v = Array.isArray(root.values) ? root.values : []
    var n = v.length
    var w = width, h = height
    if (n < 2 || w < 2 || h < 2) return
    var max = root.maxValue
    if (!(max > 0)) {
      max = 0
      for (var i = 0; i < n; i++) { var x = Number(v[i]); if (isFinite(x) && x > max) max = x }
    }
    if (!(max > 0)) max = 1
    var slots = Math.max(n, root.capacity, 2)
    var step = w / (slots - 1)
    var x0 = w - (n - 1) * step
    function px(i) { return x0 + i * step }
    function py(i) { var y = Number(v[i]); if (!isFinite(y) || y < 0) y = 0; return h - 1 - (Math.min(y, max) / max) * (h - 2) }
    ctx.fillStyle = root.color
    ctx.globalAlpha = 0.22
    ctx.beginPath()
    ctx.moveTo(px(0), h)
    for (var j = 0; j < n; j++) ctx.lineTo(px(j), py(j))
    ctx.lineTo(px(n - 1), h)
    ctx.closePath()
    ctx.fill()
    ctx.globalAlpha = 1
    ctx.strokeStyle = root.color
    ctx.lineWidth = 1
    ctx.beginPath()
    ctx.moveTo(px(0), py(0))
    for (var k = 1; k < n; k++) ctx.lineTo(px(k), py(k))
    ctx.stroke()
  }
}
