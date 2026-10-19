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
  property string graphLayout: "overlay"
  property bool stacked: false
  property real fixedMax: 0
  property real minimumMax: 0
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

  readonly property real windowSeconds: longWindow ? 3600 : 60
  readonly property var points: Model.graphWindow(longWindow ? longPoints : finePoints, windowSeconds)
  readonly property var keys: fields.map(function (field) { return field.key })
  readonly property bool aligned: !stacked && graphLayout === "aligned" && fields.length > 1
  readonly property bool mirrored: !stacked && graphLayout === "mirrored" && fields.length === 2
  property real hoverFraction: -1

  // Summaries cover the same visible window as the plot. An hour's peak is
  // the largest 10 s mean, rather than a peak reconstructed from fine data.
  readonly property var stats: Model.graphStats(points, stacked ? keys : keys.slice(0, 1))
  function summary(label, measurements) {
    return label + " · avg " + (measurements ? formatValue(measurements.avg) : "--")
      + " · peak " + (measurements ? formatValue(measurements.peak) : "--")
  }
  function seriesNote(field) { return summary(String(field.label || field.key), Model.graphStats(points, [field.key])) }
  readonly property string note: {
    if (stacked) return stats ? summary("total", stats) : "Collecting history…"
    if (!fields.some(function (field) { return Model.graphStats(points, [field.key]) !== null })) return "Collecting history…"
    return fields.map(function (field) { return seriesNote(field) }).join("\n")
  }

  FontMetrics {
    id: readoutMetrics
    font.family: root.fontFamily
    font.pixelSize: Commons.Style.font.caption
    font.features: ({ "tnum": 1 })
  }

  // Reserve the widest visible value for each series before hovering, so
  // readouts wrap without moving the plot or covering its curves.
  function readoutTemplate(selectedFields) {
    var bits = ["23:59:59"]
    for (var f = 0; f < selectedFields.length; f++) {
      var field = selectedFields[f], widest = "--"
      var widestWidth = readoutMetrics.advanceWidth(widest)
      for (var i = 0; i < points.length; i++) {
        var value = Model.graphValue(points[i], field.key)
        if (value === null) continue
        var text = formatValue(value), textWidth = readoutMetrics.advanceWidth(text)
        if (textWidth > widestWidth) { widest = text; widestWidth = textWidth }
      }
      bits.push(field.label + " " + widest)
    }
    return bits.join(" · ")
  }

  component SummaryText: Text {
    textFormat: Text.PlainText
    width: parent.width
    wrapMode: Text.WordWrap
    font: readoutMetrics.font
  }
  component Summary: Item {
    property string note: ""
    property string hoverText: ""
    property var readoutFields: []
    width: root.width
    implicitHeight: Math.max(summarySize.implicitHeight, hoverSize.implicitHeight)
    SummaryText { id: summarySize; visible: false; text: parent.note }
    SummaryText { id: hoverSize; visible: false; text: parent.visible ? root.readoutTemplate(parent.readoutFields) : "" }
    SummaryText {
      objectName: "graphReadout"
      text: parent.hoverText || parent.note
      color: parent.hoverText ? root.foreground : Model.dimColor(String(root.foreground), String(Commons.Color.background))
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: root.toggleWindow()
    }
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

  Summary {
    objectName: "graphSummary"
    visible: !root.aligned
    note: root.note
    readoutFields: root.fields
    hoverText: plots.count && plots.itemAt(0) ? plots.itemAt(0).hoverText : ""
  }

  Repeater {
    id: plots
    model: root.aligned ? root.fields.length : 1
    delegate: Column {
      required property int index
      readonly property real plotWidth: history.plotWidth
      readonly property string hoverText: history.hoverText
      width: root.width
      spacing: Commons.Style.space(4)
      Summary {
        objectName: "graphSeriesSummary_" + parent.index
        visible: root.aligned
        note: root.aligned ? root.seriesNote(root.fields[parent.index]) : ""
        readoutFields: history.fields
        hoverText: history.hoverText
      }
      Components.HistoryGraph {
        id: history
        objectName: parent.index === 0 ? "historyPlot" : "historyPlot_" + parent.index
        width: parent.width
        height: root.graphHeight * (root.mirrored ? 1.5 : 1)
        points: root.points
        fields: root.aligned ? [root.fields[parent.index]] : root.fields
        windowSeconds: root.windowSeconds
        gapSeconds: Model.graphGapSeconds(root.sampleSeconds, root.longWindow)
        stacked: root.stacked
        mirrored: root.mirrored
        fixedMax: root.fixedMax
        minimumMax: root.minimumMax
        band: root.band
        formatValue: root.formatValue
        foreground: root.foreground
        fontFamily: root.fontFamily
        syncHover: true
        sharedHoverFraction: root.hoverFraction
        onHovered: function (fraction) { root.hoverFraction = fraction }
        onWheelMoved: root.toggleWindow()
      }
    }
  }

  Item {
    objectName: "graphTimeAxis"
    width: plots.count && plots.itemAt(0) ? plots.itemAt(0).plotWidth : parent.width
    implicitHeight: timeStart.implicitHeight
    Text {
      id: timeStart
      textFormat: Text.PlainText
      text: root.longWindow ? "−1 hour" : "−1 min"
      color: Model.dimColor(String(root.foreground), String(Commons.Color.background))
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.caption
    }
    Text {
      objectName: "graphBucketLabel"
      textFormat: Text.PlainText
      text: root.longWindow ? "10 s means" : ""
      anchors.horizontalCenter: parent.horizontalCenter
      color: timeStart.color
      font: timeStart.font
    }
    Text {
      objectName: "graphEndTime"
      textFormat: Text.PlainText
      text: root.points.length ? Qt.formatTime(new Date(root.points[root.points.length - 1].t * 1000), "hh:mm:ss") : "--"
      anchors.right: parent.right
      color: timeStart.color
      font: timeStart.font
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
