import QtQuick
import "../lib/index.mjs" as Model

// A minute of shared history, with fixed percentage scales and a shared
// rate scale for down/up. No input handlers, timers or collection of its own.
Canvas {
  id: root
  property var points: []
  property string metric: "cpu"
  property color color: "#cacccc"
  property color secondaryColor: "#999999"
  property real gapSeconds: 8
  readonly property var samples: Model.barTrendPoints(points, metric)
  readonly property var keys: metric === "net" ? ["rx", "tx"] : ["v"]
  readonly property var axis: Model.graphAxis(samples, keys, { fixedMax: metric === "net" ? 0 : 100, minimumMax: metric === "net" ? 1024 : 0 })

  onSamplesChanged: requestPaint()
  onAxisChanged: requestPaint()
  onColorChanged: requestPaint()
  onSecondaryColorChanged: requestPaint()
  onGapSecondsChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    var w = width, h = height, pts = root.samples
    if (w < 2 || h < 2 || !pts.length) return
    var end = pts[pts.length - 1].t
    function xFor(i) { return (pts[i].t - end + 60) / 60 * (w - 1) }
    function yFor(i, key) { return h - 1 - Math.min(1, Model.graphValue(pts[i], key) / root.axis.max) * (h - 2) }
    for (var f = 0; f < root.keys.length; f++) {
      var key = root.keys[f], color = f === 0 ? root.color : root.secondaryColor
      var runs = Model.graphRuns(pts, [key], root.gapSeconds)
      ctx.strokeStyle = color
      ctx.fillStyle = color
      ctx.lineWidth = 1
      for (var r = 0; r < runs.length; r++) {
        var run = runs[r], i
        if (run.start === run.end) {
          ctx.beginPath(); ctx.arc(xFor(run.start), yFor(run.start, key), 1, 0, Math.PI * 2); ctx.fill()
          continue
        }
        ctx.globalAlpha = 0.16
        ctx.beginPath(); ctx.moveTo(xFor(run.start), h - 1)
        for (i = run.start; i <= run.end; i++) ctx.lineTo(xFor(i), yFor(i, key))
        ctx.lineTo(xFor(run.end), h - 1); ctx.closePath(); ctx.fill()
        ctx.globalAlpha = 1
        ctx.beginPath(); ctx.moveTo(xFor(run.start), yFor(run.start, key))
        for (i = run.start + 1; i <= run.end; i++) ctx.lineTo(xFor(i), yFor(i, key))
        ctx.stroke()
      }
    }
  }
}
