import QtQuick
import qs.Commons as Commons
import "../lib/index.mjs" as Model

// All layouts share time, measurement and gap rules. Mirroring changes only
// drawing direction: both rates, axis magnitudes and readouts stay positive.
Item {
  id: root

  property var points: []
  property var fields: []
  property real windowSeconds: 60
  property bool stacked: false
  property bool mirrored: false
  property real fixedMax: 0
  property real minimumMax: 0
  property bool band: false
  property real gapSeconds: 30
  property var formatValue: function (v) { return Model.formatPct(v) }
  property color foreground: Commons.Color.foreground
  property string fontFamily: Commons.Style.font.family
  property bool showAxis: true
  property bool syncHover: false
  property real sharedHoverFraction: -1
  property real localHoverFraction: -1
  signal hovered(real fraction)
  signal wheelMoved()

  readonly property var pal: Model.seriesPalette(String(Commons.Color.accent), String(Commons.Color.urgent), String(foreground), String(Commons.Color.background))
  readonly property color dim: pal.dim
  readonly property var keys: fields.map(function (field) { return field.key })
  readonly property var axis: Model.graphAxis(points, keys, { stacked: stacked, fixedMax: fixedMax, minimumMax: minimumMax, band: band })
  readonly property real plotWidth: canvas.width
  readonly property real hoverFraction: syncHover ? sharedHoverFraction : localHoverFraction
  readonly property int hoverIndex: hoverFraction >= 0 ? indexAtX(hoverFraction * (plotWidth - 1), plotWidth) : -1
  readonly property var hoverInfo: hoverIndex >= 0 && hoverIndex < points.length ? points[hoverIndex] : null
  readonly property real axisWidth: showAxis ? Math.ceil(Math.max(axisTop.implicitWidth, axisMid.implicitWidth, axisBottom.implicitWidth)) + Commons.Style.space(6) : 0

  implicitWidth: 200
  implicitHeight: Commons.Style.space(96)

  function valueOf(point, key) { return Model.graphValue(point, key) }
  function setHover(fraction) { localHoverFraction = fraction; hovered(fraction) }

  onPointsChanged: canvas.requestPaint()
  onFieldsChanged: canvas.requestPaint()
  onAxisChanged: canvas.requestPaint()
  onStackedChanged: canvas.requestPaint()
  onMirroredChanged: canvas.requestPaint()
  onGapSecondsChanged: canvas.requestPaint()
  onWindowSecondsChanged: canvas.requestPaint()
  onWidthChanged: canvas.requestPaint()
  onHeightChanged: canvas.requestPaint()
  onHoverIndexChanged: canvas.requestPaint()
  onPalChanged: canvas.requestPaint()

  Text {
    id: axisTop
    objectName: "axisTop"
    visible: root.showAxis
    textFormat: Text.PlainText
    text: (root.mirrored && root.fields.length ? root.fields[0].label + "\n" : "") + root.formatValue(root.axis.max)
    horizontalAlignment: Text.AlignRight
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Commons.Style.font.caption
    font.features: ({ "tnum": 1 })
    anchors.right: parent.right
    anchors.top: parent.top
  }
  Text {
    id: axisMid
    visible: root.showAxis
    textFormat: Text.PlainText
    text: root.formatValue(root.mirrored ? 0 : (root.axis.max + root.axis.min) / 2)
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Commons.Style.font.caption
    font.features: ({ "tnum": 1 })
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
  }
  Text {
    id: axisBottom
    objectName: "axisBottom"
    visible: root.showAxis
    textFormat: Text.PlainText
    text: root.mirrored && root.fields.length > 1 ? root.fields[1].label + "\n" + root.formatValue(root.axis.max) : root.formatValue(root.axis.min)
    horizontalAlignment: Text.AlignRight
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Commons.Style.font.caption
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
      var pts = root.points, fl = root.fields, sc = root.axis
      ctx.strokeStyle = root.pal.grid
      ctx.lineWidth = 1
      for (var g = 0; g <= 2; g++) {
        var gy = Math.min(h - 0.5, Math.round(h * g / 2) + 0.5)
        ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(w, gy); ctx.stroke()
      }
      var n = pts.length
      if (n < 1 || fl.length === 0) return
      var tEnd = Number(pts[n - 1].t)
      function xFor(t) { return (Number(t) - tEnd + root.windowSeconds) / root.windowSeconds * (w - 1) }
      function yFor(v, direction) {
        var fraction = Math.max(0, Math.min(1, (v - sc.min) / (sc.max - sc.min)))
        return root.mirrored ? h / 2 - direction * fraction * (h / 2 - 1) : h - 1 - fraction * (h - 2)
      }
      function dot(i, value, direction, color) {
        ctx.fillStyle = color
        ctx.beginPath(); ctx.arc(xFor(pts[i].t), yFor(value, direction), 1.5, 0, 2 * Math.PI); ctx.fill()
      }
      var i, f, r, run, runs
      if (root.stacked) {
        // A partial stack is unknown, not a smaller total.
        runs = Model.graphRuns(pts, root.keys, root.gapSeconds)
        var cum = pts.map(function () { return 0 })
        for (f = 0; f < fl.length; f++) {
          var prev = cum.slice()
          for (i = 0; i < n; i++) cum[i] += root.valueOf(pts[i], fl[f].key) || 0
          ctx.fillStyle = fl[f].color
          ctx.globalAlpha = 0.8
          for (r = 0; r < runs.length; r++) {
            run = runs[r]
            if (run.end === run.start) { dot(run.start, cum[run.start], 1, fl[f].color); continue }
            ctx.beginPath()
            ctx.moveTo(xFor(pts[run.start].t), yFor(cum[run.start], 1))
            for (i = run.start + 1; i <= run.end; i++) ctx.lineTo(xFor(pts[i].t), yFor(cum[i], 1))
            for (i = run.end; i >= run.start; i--) ctx.lineTo(xFor(pts[i].t), yFor(prev[i], 1))
            ctx.closePath(); ctx.fill()
          }
          ctx.globalAlpha = 1
        }
      } else {
        for (f = 0; f < fl.length; f++) {
          var key = fl[f].key, direction = root.mirrored && f === 1 ? -1 : 1
          var baseline = root.mirrored ? h / 2 : h - 1
          runs = Model.graphRuns(pts, [key], root.gapSeconds)
          for (r = 0; r < runs.length; r++) {
            run = runs[r]
            if (run.end === run.start) { dot(run.start, root.valueOf(pts[run.start], key), direction, fl[f].color); continue }
            ctx.fillStyle = fl[f].color
            ctx.globalAlpha = 0.14
            ctx.beginPath(); ctx.moveTo(xFor(pts[run.start].t), baseline)
            for (i = run.start; i <= run.end; i++) ctx.lineTo(xFor(pts[i].t), yFor(root.valueOf(pts[i], key), direction))
            ctx.lineTo(xFor(pts[run.end].t), baseline)
            ctx.closePath(); ctx.fill()
            ctx.globalAlpha = 1
            ctx.strokeStyle = fl[f].color
            ctx.lineWidth = 1.5
            ctx.beginPath(); ctx.moveTo(xFor(pts[run.start].t), yFor(root.valueOf(pts[run.start], key), direction))
            for (i = run.start + 1; i <= run.end; i++) ctx.lineTo(xFor(pts[i].t), yFor(root.valueOf(pts[i], key), direction))
            ctx.stroke()
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
      onPositionChanged: function (mouse) { root.setHover(Math.max(0, Math.min(1, mouse.x / Math.max(1, width - 1)))) }
      onExited: root.setHover(-1)
      onWheel: function (wheel) { root.wheelMoved(); wheel.accepted = true }
    }
  }

  function indexAtX(x, w) {
    if (!points.length || w < 2) return -1
    var end = Number(points[points.length - 1].t)
    var t = end - windowSeconds + x / (w - 1) * windowSeconds
    return Model.graphHoverIndex(points, t, gapSeconds, Math.min(gapSeconds / 2, 3 * windowSeconds / (w - 1)))
  }

  readonly property string hoverText: {
    var point = hoverInfo
    if (!point) return ""
    var bits = [Qt.formatTime(new Date(point.t * 1000), "hh:mm:ss")]
    for (var f = 0; f < fields.length; f++) {
      var value = valueOf(point, fields[f].key)
      bits.push(fields[f].label + " " + (value === null ? "--" : formatValue(value)))
    }
    return bits.join(" · ")
  }
  Rectangle {
    visible: root.hoverText !== ""
    x: Commons.Style.space(2)
    y: Commons.Style.space(2)
    width: Math.min(canvas.width - x, readout.implicitWidth + Commons.Style.space(8))
    height: readout.implicitHeight + Commons.Style.space(4)
    color: Commons.Color.background
    opacity: 0.95
    Text {
      id: readout
      objectName: "graphReadout"
      x: Commons.Style.space(4)
      y: Commons.Style.space(2)
      width: parent.width - Commons.Style.space(8)
      textFormat: Text.PlainText
      text: root.hoverText
      wrapMode: Text.WordWrap
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.caption
      font.features: ({ "tnum": 1 })
    }
  }
}
