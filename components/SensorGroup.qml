import QtQuick
import qs.Commons as Commons
import "../lib/index.mjs" as Model

// Group only inventory identities. Live updates never replace the delegates
// or collapse an open disclosure, and a failed reading never becomes zero.
Column {
  id: root
  property var group: ({ sensors: [], driver: "", owner: "", kind: "temperature" })
  property var readings: ({})
  property string temperatureUnit: "celsius"
  readonly property var cores: group.kind === "temperature" ? group.sensors.filter(function (s) { return /^Core\s+\d+$/.test(s.label) }) : []
  readonly property var other: group.sensors.filter(function (s) { return root.cores.indexOf(s) < 0 })
  readonly property var coreSummary: Model.coreTemperatureSummary(cores, readings)
  readonly property color dim: Model.dimColor(String(Commons.Color.foreground), String(Commons.Color.background))
  readonly property color track: Model.seriesPalette(String(Commons.Color.accent), String(Commons.Color.urgent),
                                                     String(Commons.Color.foreground), String(Commons.Color.background)).track
  spacing: Commons.Style.space(6)

  component Reading: Item {
    id: cell
    required property var sensor
    property bool tile: false
    readonly property var reading: root.readings[sensor.id] || null
    readonly property string value: Model.sensorValue(sensor, reading, root.temperatureUnit)
    readonly property color valueColor: sensor.kind === "temperature" && reading
      && reading.value !== null && reading.criticalC !== null && reading.value >= reading.criticalC
      ? Commons.Color.urgent : Commons.Color.foreground
    objectName: "hardwareSensorValue_" + sensor.id
    implicitHeight: content.implicitHeight + (tile ? Commons.Style.space(12) : 0)
    Rectangle {
      visible: cell.tile
      anchors.fill: parent
      color: "transparent"
      border.width: 1
      border.color: root.track
    }
    Column {
      id: content
      x: cell.tile ? Commons.Style.space(6) : 0
      y: x
      width: Math.max(0, parent.width - x * 2)
      spacing: Commons.Style.space(2)
      StatRow {
        width: parent.width
        visible: !cell.tile
        label: cell.sensor.label
        value: cell.value
        valueColor: cell.valueColor
        wrapValue: true
      }
      Text {
        textFormat: Text.PlainText
        visible: cell.tile
        text: cell.sensor.label
        color: root.dim
        font.family: Commons.Style.font.family
        font.pixelSize: Commons.Style.font.caption
        width: parent.width
        wrapMode: Text.Wrap
      }
      Text {
        textFormat: Text.PlainText
        visible: cell.tile
        text: cell.value
        color: cell.valueColor
        font.family: Commons.Style.font.family
        font.pixelSize: Commons.Style.font.body
        font.features: ({ "tnum": 1 })
        width: parent.width
        wrapMode: Text.Wrap
      }
      Text {
        textFormat: Text.PlainText
        text: cell.reading ? cell.reading.status
              : cell.sensor.gpu ? "Read on the GPU detail tab" : "Waiting for a reading…"
        visible: text !== ""
        color: root.dim
        font.family: Commons.Style.font.family
        font.pixelSize: Commons.Style.font.caption
        width: parent.width
        wrapMode: Text.Wrap
      }
    }
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    text: root.group.displayTitle || root.group.title || root.group.driver || "Sensors"
    color: root.dim
    font.family: Commons.Style.font.family
    font.pixelSize: Commons.Style.font.caption
    font.bold: true
    wrapMode: Text.Wrap
  }
  Repeater {
    model: root.other
    delegate: Reading {
      required property var modelData
      width: root.width
      sensor: modelData
    }
  }
  StatRow {
    objectName: "coreTemperatureRange"
    width: parent.width
    visible: root.cores.length > 0
    label: root.coreSummary.count + " cores"
    value: root.coreSummary.available ? Model.formatTemp(root.coreSummary.min, root.temperatureUnit)
      + " – " + Model.formatTemp(root.coreSummary.max, root.temperatureUnit) : "--"
    wrapValue: true
  }
  Text {
    objectName: "coreTemperatureWarnings"
    textFormat: Text.PlainText
    width: parent.width
    visible: root.cores.length > 0 && (root.coreSummary.missing > 0 || root.coreSummary.critical > 0)
    text: {
      var bits = []
      if (root.coreSummary.missing) bits.push(root.coreSummary.missing + " unavailable")
      if (root.coreSummary.critical) bits.push(root.coreSummary.critical + " at or above critical temperature")
      return bits.join(" · ")
    }
    color: root.coreSummary.critical > 0 ? Commons.Color.urgent : root.dim
    font.family: Commons.Style.font.family
    font.pixelSize: Commons.Style.font.caption
    wrapMode: Text.Wrap
  }
  Disclosure {
    objectName: "coreTemperatureDetails"
    width: parent.width
    visible: root.cores.length > 0
    title: "Core temperatures"
    Grid {
      id: grid
      width: parent.width
      columns: Math.max(1, Math.min(4, Math.floor(width / Math.max(Commons.Style.space(70), Commons.Style.font.body * 5.5))))
      spacing: Commons.Style.space(5)
      Repeater {
        model: root.cores
        delegate: Reading {
          required property var modelData
          width: (grid.width - grid.spacing * (grid.columns - 1)) / grid.columns
          sensor: modelData
          tile: true
        }
      }
    }
  }
  Disclosure {
    objectName: "sensorDeviceDetails"
    width: parent.width
    title: "Device details"
    Text {
      textFormat: Text.PlainText
      text: root.group.driver + " · " + root.group.owner
      color: root.dim
      font.family: Commons.Style.font.family
      font.pixelSize: Commons.Style.font.caption
      width: parent.width
      wrapMode: Text.Wrap
    }
  }
}
