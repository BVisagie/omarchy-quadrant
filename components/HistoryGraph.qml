import QtQuick
import qs.Commons
import "../lib/index.mjs" as Model

// Time-series graph for n fields sharing one x axis.
//   points        — [{ t, <key>: Number, ... }] oldest first; t in seconds
//   fields        — [{ key, label, color }]  (drawn bottom-up when stacked)
//   windowSeconds — width of the x axis; the newest point sits at the right
//   stacked       — cumulative filled areas (CPU user+system+iowait)
//   fixedMax      — y ceiling; 0 auto-scales to the visible peak (rounded up)
//   band          — frame the y axis on the data's own min..max instead of 0
//   gapSeconds    — two points further apart than this are not joined
//   formatValue   — function(Number) → string for the axis and the readout
// Hovering shows a cursor line and the values under it; `hoverInfo` holds
// them for a caller that wants to render them elsewhere.
Item {
  id: root

  property var points: []
  property var fields: []
  property real windowSeconds: 60
  property bool stacked: false
  property real fixedMax: 0
  property bool band: false
  property real gapSeconds: 30
  property var formatValue: function (v) { return Model.formatPct(v) }
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool showAxis: true

  readonly property var pal: Model.seriesPalette(String(Color.accent), String(Color.urgent), String(foreground), String(Color.background))
  readonly property color dim: pal.dim

  property int hoverIndex: -1
  readonly property var hoverInfo: hoverIndex >= 0 && hoverIndex < points.length ? points[hoverIndex] : null

  implicitWidth: 200
  implicitHeight: Style.space(96)

  // ---- scale -----------------------------------------------------------
  function valueOf(p, key) {
    var v = p ? Number(p[key]) : NaN
    return isFinite(v) ? v : null
  }

  readonly property var axis: {
    var pts = Array.isArray(points) ? points : []
    var fl = Array.isArray(fields) ? fields : []
    var lo = Infinity, hi = -Infinity
    for (var i = 0; i < pts.length; i++) {
      var acc = 0, any = false
      for (var f = 0; f < fl.length; f++) {
        var v = valueOf(pts[i], fl[f].key)
        if (v === null) continue
        any = true
        if (stacked) acc += v
        else { if (v < lo) lo = v; if (v > hi) hi = v }
      }
      if (stacked && any) { if (acc < lo) lo = acc; if (acc > hi) hi = acc }
    }
    if (!(hi > -Infinity)) { lo = 0; hi = 0 }
    var min = 0, max = fixedMax
    if (!(max > 0)) {
      max = niceCeiling(hi)
    }
    if (band && hi > lo) {
      var span = Math.max(hi - lo, Math.max(1e-9, hi) * 0.03)
      var pad = span * 0.25
      min = Math.max(0, lo - pad)
      max = hi + pad
      if (fixedMax > 0 && max > fixedMax) max = fixedMax
    }
    if (!(max > min)) max = min + 1
    return { min: min, max: max, lo: lo, hi: hi }
  }

  function niceCeiling(v) {
    if (!(v > 0)) return 1
    var exp = Math.pow(10, Math.floor(Math.log(v) / Math.LN10))
    var m = v / exp
    var nice = m <= 1 ? 1 : m <= 2 ? 2 : m <= 2.5 ? 2.5 : m <= 5 ? 5 : 10
    return nice * exp
  }

  readonly property real axisWidth: showAxis ? Math.ceil(Math.max(axisTop.implicitWidth, axisMid.implicitWidth)) + Style.space(6) : 0

  onPointsChanged: canvas.requestPaint()
  onFieldsChanged: canvas.requestPaint()
  onStackedChanged: canvas.requestPaint()
  onFixedMaxChanged: canvas.requestPaint()
  onBandChanged: canvas.requestPaint()
  onWindowSecondsChanged: canvas.requestPaint()
  onWidthChanged: canvas.requestPaint()
  onHeightChanged: canvas.requestPaint()
  onHoverIndexChanged: canvas.requestPaint()
  onForegroundChanged: canvas.requestPaint()

  // Axis labels sit in the right gutter: ceiling, midpoint, floor.
  Text {
    id: axisTop
    visible: root.showAxis
    textFormat: Text.PlainText
    text: root.formatValue(root.axis.max)
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.features: ({ "tnum": 1 })
    anchors.right: parent.right
    anchors.top: parent.top
  }
  Text {
    id: axisMid
    visible: root.showAxis
    textFormat: Text.PlainText
    text: root.formatValue((root.axis.max + root.axis.min) / 2)
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.features: ({ "tnum": 1 })
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
  }
  Text {
    visible: root.showAxis && root.band
    textFormat: Text.PlainText
    text: root.formatValue(root.axis.min)
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.features: ({ "tnum": 1 })
    anchors.right: parent.right
    anchors.bottom: parent.bottom
  }

  Canvas {
    id: canvas
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.right: parent.right
    anchors.rightMargin: root.axisWidth

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var w = width, h = height
      if (w < 2 || h < 2) return
      var pts = Array.isArray(root.points) ? root.points : []
      var fl = Array.isArray(root.fields) ? root.fields : []
      var sc = root.axis

      ctx.strokeStyle = root.pal.grid
      ctx.lineWidth = 1
      for (var g = 0; g <= 2; g++) {
        var gy = Math.round(h * g / 2) + 0.5
        if (g === 2) gy = h - 0.5
        ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(w, gy); ctx.stroke()
      }
      var n = pts.length
      if (n < 1 || fl.length === 0) return

      var tEnd = Number(pts[n - 1].t)
      var tStart = tEnd - root.windowSeconds
      function xFor(t) { return (Number(t) - tStart) / root.windowSeconds * (w - 1) }
      function yFor(v) {
        var f = (v - sc.min) / (sc.max - sc.min)
        if (f < 0) f = 0
        if (f > 1) f = 1
        return h - 1 - f * (h - 2)
      }
      function gapBefore(i) {
        return i > 0 && (Number(pts[i].t) - Number(pts[i - 1].t)) > root.gapSeconds
      }

      var i, f
      if (root.stacked) {
        var cum = []
        for (i = 0; i < n; i++) cum.push(0)
        for (f = 0; f < fl.length; f++) {
          var prev = cum.slice()
          for (i = 0; i < n; i++) { var v = root.valueOf(pts[i], fl[f].key); cum[i] += v === null ? 0 : v }
          ctx.fillStyle = fl[f].color
          ctx.globalAlpha = 0.8
          // One filled run per contiguous segment.
          var run = 0
          while (run < n) {
            var end = run
            while (end + 1 < n && !gapBefore(end + 1)) end++
            if (end > run) {
              ctx.beginPath()
              ctx.moveTo(xFor(pts[run].t), yFor(cum[run]))
              for (i = run + 1; i <= end; i++) ctx.lineTo(xFor(pts[i].t), yFor(cum[i]))
              for (i = end; i >= run; i--) ctx.lineTo(xFor(pts[i].t), yFor(prev[i]))
              ctx.closePath()
              ctx.fill()
            }
            run = end + 1
          }
          ctx.globalAlpha = 1
        }
      } else {
        for (f = 0; f < fl.length; f++) {
          var key = fl[f].key
          var seg = 0
          while (seg < n) {
            var stop = seg
            while (stop + 1 < n && !gapBefore(stop + 1) && root.valueOf(pts[stop + 1], key) !== null) stop++
            if (root.valueOf(pts[seg], key) === null) { seg++; continue }
            if (stop > seg) {
              ctx.fillStyle = fl[f].color
              ctx.globalAlpha = 0.14
              ctx.beginPath()
              ctx.moveTo(xFor(pts[seg].t), h)
              for (i = seg; i <= stop; i++) ctx.lineTo(xFor(pts[i].t), yFor(root.valueOf(pts[i], key)))
              ctx.lineTo(xFor(pts[stop].t), h)
              ctx.closePath()
              ctx.fill()
              ctx.globalAlpha = 1
              ctx.strokeStyle = fl[f].color
              ctx.lineWidth = 1.5
              ctx.beginPath()
              ctx.moveTo(xFor(pts[seg].t), yFor(root.valueOf(pts[seg], key)))
              for (i = seg + 1; i <= stop; i++) ctx.lineTo(xFor(pts[i].t), yFor(root.valueOf(pts[i], key)))
              ctx.stroke()
            } else {
              // A lone point between gaps is still a reading: draw a dot.
              ctx.fillStyle = fl[f].color
              ctx.beginPath()
              ctx.arc(xFor(pts[seg].t), yFor(root.valueOf(pts[seg], key)), 1.5, 0, 2 * Math.PI)
              ctx.fill()
            }
            seg = stop + 1
          }
        }
      }

      if (root.hoverIndex >= 0 && root.hoverIndex < n) {
        var hx = Math.round(xFor(pts[root.hoverIndex].t)) + 0.5
        ctx.strokeStyle = root.pal.hairline
        ctx.lineWidth = 1
        ctx.beginPath(); ctx.moveTo(hx, 0); ctx.lineTo(hx, h); ctx.stroke()
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      onPositionChanged: function (mouse) { root.hoverIndex = root.indexAtX(mouse.x, width) }
      onExited: root.hoverIndex = -1
    }
  }

  function indexAtX(x, w) {
    var pts = Array.isArray(points) ? points : []
    var n = pts.length
    if (n === 0 || w < 2) return -1
    var tEnd = Number(pts[n - 1].t)
    var t = tEnd - windowSeconds + x / (w - 1) * windowSeconds
    var best = -1, bestD = Infinity
    for (var i = 0; i < n; i++) {
      var d = Math.abs(Number(pts[i].t) - t)
      if (d < bestD) { bestD = d; best = i }
    }
    return bestD <= Math.max(gapSeconds, windowSeconds / 20) ? best : -1
  }

  // Readout for the hovered point: "label value · label value".
  readonly property string hoverText: {
    var p = hoverInfo
    if (!p) return ""
    var fl = Array.isArray(fields) ? fields : []
    var bits = []
    for (var f = 0; f < fl.length; f++) {
      var v = valueOf(p, fl[f].key)
      if (v === null) continue
      bits.push(fl[f].label + " " + formatValue(v))
    }
    return bits.join(" · ")
  }

  Text {
    visible: root.hoverText !== ""
    textFormat: Text.PlainText
    text: root.hoverText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.features: ({ "tnum": 1 })
    anchors.left: parent.left
    anchors.leftMargin: Style.space(4)
    anchors.top: parent.top
  }
}
