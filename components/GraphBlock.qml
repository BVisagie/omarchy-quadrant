import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui
import "../lib/index.mjs" as Model
import "." as Components

// Labelled duration controls, a summary naming its series, and a graph with
// live legend. Fine points feed the minute, 10 s mean buckets feed the hour.
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
  property color foreground: Commons.Color.foreground
  property string fontFamily: Commons.Style.font.family
  property real graphHeight: Commons.Style.space(88)
  // Seconds between fine samples (the stream cadence); sets the gap threshold.
  property real sampleSeconds: 1

  signal toggleWindow()

  function selectWindow(longer) { if (longer !== longWindow) toggleWindow() }

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
          var x = Model.num(pts[i][fl[f].key], null)
          if (x !== null) { v += x; any = true }
        }
      } else {
        var y = Model.num(pts[i][fl[0].key], null)
        if (y !== null) { v = y; any = true }
      }
      if (!any) continue
      sum += v; n++
      if (v > peak) peak = v
    }
    if (n === 0) return null
    return { avg: sum / n, peak: peak }
  }

  readonly property string note: {
    var label = stacked ? "total" : fields.length > 0 ? String(fields[0].label || fields[0].key) : ""
    var s = stats
    if (!s) return "Collecting history…"
    return label + " · avg " + formatValue(s.avg) + " · peak " + formatValue(s.peak)
  }

  spacing: Commons.Style.space(6)

  Item {
    width: parent.width
    implicitHeight: Math.max(graphTitle.implicitHeight, durationControls.implicitHeight)
    Text {
      id: graphTitle
      textFormat: Text.PlainText
      text: root.title
      color: Model.dimColor(String(root.foreground), String(Commons.Color.background))
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.caption
      font.bold: true
      anchors.left: parent.left
      anchors.right: durationControls.left
      anchors.rightMargin: Commons.Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
    }
    Row {
      id: durationControls
      objectName: "graphDuration"
      anchors.right: parent.right
      spacing: Commons.Style.space(4)
      Ui.Button {
        objectName: "graphMinute"
        text: "1 min"
        selected: !root.longWindow
        bordered: true
        fontSize: Commons.Style.font.caption
        tooltipText: "Last minute (H to switch all graphs)"
        Accessible.role: Accessible.RadioButton
        Accessible.name: root.title + ": last minute"
        Accessible.checkable: true
        Accessible.checked: selected
        Accessible.onPressAction: root.selectWindow(false)
        onClicked: root.selectWindow(false)
      }
      Ui.Button {
        objectName: "graphHour"
        text: "1 hour"
        selected: root.longWindow
        bordered: true
        fontSize: Commons.Style.font.caption
        tooltipText: "Last hour (H to switch all graphs)"
        Accessible.role: Accessible.RadioButton
        Accessible.name: root.title + ": last hour"
        Accessible.checkable: true
        Accessible.checked: selected
        Accessible.onPressAction: root.selectWindow(true)
        onClicked: root.selectWindow(true)
      }
    }
  }

  Text {
    objectName: "graphSummary"
    textFormat: Text.PlainText
    text: root.note
    width: parent.width
    wrapMode: Text.WordWrap
    color: Model.dimColor(String(root.foreground), String(Commons.Color.background))
    font.family: root.fontFamily
    font.pixelSize: Commons.Style.font.caption
    font.features: ({ "tnum": 1 })
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: root.toggleWindow()
    }
  }

  Components.HistoryGraph {
    objectName: "historyPlot"
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
