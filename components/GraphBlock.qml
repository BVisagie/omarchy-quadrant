import QtQuick
import qs.Commons
import "../lib/index.mjs" as Model
import "." as Components

// A graph with its header and legend: title on the left, the window and
// the average / peak of the displayed data on the right (click to switch
// between the last minute and the last hour), then the legend with live
// values. Fine points feed the 60 s view, 10 s buckets feed the hour.
Column {
  id: root

  property string title: ""
  property var finePoints: []
  property var longPoints: []
  property bool longWindow: false
  property var fields: []
  property bool stacked: false
  property real fixedMax: 0
  property bool band: false
  property var formatValue: function (v) { return Model.formatPct(v) }
  property var legend: []
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property real graphHeight: Style.space(88)
  // Seconds between fine samples (the stream cadence); sets the gap threshold.
  property real sampleSeconds: 1

  signal toggleWindow()

  readonly property var points: longWindow ? longPoints : finePoints
  readonly property real windowSeconds: longWindow ? 3600 : 60

  // Average and peak of the displayed total (stacked sum, else the first
  // field) over the points on screen.
  readonly property var stats: {
    var pts = Array.isArray(points) ? points : []
    var fl = Array.isArray(fields) ? fields : []
    if (pts.length === 0 || fl.length === 0) return null
    var sum = 0, n = 0, peak = 0
    for (var i = 0; i < pts.length; i++) {
      var v = 0, any = false
      if (stacked) {
        for (var f = 0; f < fl.length; f++) {
          var x = Number(pts[i][fl[f].key])
          if (isFinite(x)) { v += x; any = true }
        }
      } else {
        var y = Number(pts[i][fl[0].key])
        if (isFinite(y)) { v = y; any = true }
      }
      if (!any) continue
      sum += v; n++
      if (v > peak) peak = v
    }
    if (n === 0) return null
    return { avg: sum / n, peak: peak }
  }

  readonly property string note: {
    var label = longWindow ? "1 h" : "60 s"
    var s = stats
    if (!s) return label + " · collecting…"
    return label + " · avg " + formatValue(s.avg) + " · peak " + formatValue(s.peak)
  }

  spacing: Style.space(6)

  Components.SectionHeader {
    width: parent.width
    text: root.title
    note: root.note
    foreground: root.foreground
    fontFamily: root.fontFamily
    onNoteClicked: root.toggleWindow()
  }

  Components.HistoryGraph {
    width: parent.width
    height: root.graphHeight
    points: root.points
    fields: root.fields
    windowSeconds: root.windowSeconds
    gapSeconds: Model.graphGapSeconds(root.sampleSeconds, root.longWindow)
    stacked: root.stacked
    fixedMax: root.fixedMax
    band: root.band
    formatValue: root.formatValue
    foreground: root.foreground
    fontFamily: root.fontFamily

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.NoButton
      onWheel: function (wheel) { root.toggleWindow(); wheel.accepted = true }
      propagateComposedEvents: true
    }
  }

  Components.Legend {
    width: parent.width
    visible: root.legend.length > 0
    items: root.legend
    foreground: root.foreground
    fontFamily: root.fontFamily
  }
}
