import QtQuick
import qs.Commons
import "../Theme.js" as Theme

// Canvas time-series graph for n series sharing one x axis. Values are
// oldest-first; the newest sample hugs the right edge.
//   series   — [{ label, color, values: [Number] }]
//   stacked  — cumulative filled areas (CPU user+system+iowait)
//   fixedMax — y-axis ceiling; 0 means auto-scale to the visible peak
Canvas {
  id: root

  property var series: []
  property bool stacked: false
  property real fixedMax: 0
  property color gridColor: Theme.gridFor("#cacccc")
  property color foreground: "#cacccc"

  implicitWidth: 200
  implicitHeight: Style.space(Theme.metrics.graphHeight)

  onSeriesChanged: requestPaint()
  onStackedChanged: requestPaint()
  onFixedMaxChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  function pointCount() {
    var n = 0
    for (var i = 0; i < series.length; i++) {
      var v = series[i] && series[i].values
      if (v && v.length > n) n = v.length
    }
    return n
  }

  function valueAt(si, i) {
    var v = series[si] && series[si].values
    if (!v || i < 0 || i >= v.length) return 0
    var n = Number(v[i])
    return isFinite(n) && n > 0 ? n : 0
  }

  function peak(n) {
    var max = 0
    for (var i = 0; i < n; i++) {
      var acc = 0
      for (var s = 0; s < series.length; s++) {
        acc += valueAt(s, i)
        if (!stacked && valueAt(s, i) > max) max = valueAt(s, i)
      }
      if (stacked && acc > max) max = acc
    }
    return max
  }

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    var w = width
    var h = height
    if (w < 2 || h < 2) return

    var n = pointCount()
    var max = root.fixedMax > 0 ? root.fixedMax : peak(n)
    if (!(max > 0)) max = 1

    // muted grid: quarter lines, derived from the bar foreground by Theme.js
    ctx.strokeStyle = root.gridColor
    ctx.lineWidth = 1
    for (var g = 1; g <= 3; g++) {
      var gy = Math.round(h * g / 4) + 0.5
      ctx.beginPath()
      ctx.moveTo(0, gy)
      ctx.lineTo(w, gy)
      ctx.stroke()
    }

    if (n < 2 || series.length === 0) return

    var stepX = w / (n - 1)
    var yFor = function (v) { return h - (v / max) * (h - 2) - 1 }

    if (root.stacked) {
      // Fill between successive cumulative curves, top series first so lower
      // layers stay visible under translucent fills.
      var cum = []
      var i, s
      for (i = 0; i < n; i++) cum.push(0)
      for (s = 0; s < series.length; s++) {
        var prev = cum.slice()
        for (i = 0; i < n; i++) cum[i] += valueAt(s, i)
        ctx.fillStyle = series[s].color
        ctx.globalAlpha = 0.85
        ctx.beginPath()
        ctx.moveTo(0, yFor(cum[0]))
        for (i = 1; i < n; i++) ctx.lineTo(i * stepX, yFor(cum[i]))
        for (i = n - 1; i >= 0; i--) ctx.lineTo(i * stepX, yFor(prev[i]))
        ctx.closePath()
        ctx.fill()
        ctx.globalAlpha = 1
      }
    } else {
      for (s = 0; s < series.length; s++) {
        // subtle fill under the line, then the line itself
        ctx.fillStyle = series[s].color
        ctx.globalAlpha = 0.15
        ctx.beginPath()
        ctx.moveTo(0, yFor(valueAt(s, 0)))
        for (i = 1; i < n; i++) ctx.lineTo(i * stepX, yFor(valueAt(s, i)))
        ctx.lineTo((n - 1) * stepX, h)
        ctx.lineTo(0, h)
        ctx.closePath()
        ctx.fill()
        ctx.globalAlpha = 1
        ctx.strokeStyle = series[s].color
        ctx.lineWidth = 1.5
        ctx.beginPath()
        ctx.moveTo(0, yFor(valueAt(s, 0)))
        for (i = 1; i < n; i++) ctx.lineTo(i * stepX, yFor(valueAt(s, i)))
        ctx.stroke()
      }
    }
  }
}
