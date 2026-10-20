import QtQuick
import qs.Commons as Commons
import "../lib/index.mjs" as Model
import "../components" as Components

// Additional diagnostics, not a new bar meter. Inventory rows remain stable
// while their values update. GPUs retain their existing detail collectors.
Item {
  id: root
  property var panel: null
  property var model: null
  property var processList: null
  property alias actionList: graphicsActions
  readonly property bool active: panel && panel.opened && !panel.settingsOpen && panel.currentTab === "hardware"
  readonly property var info: model ? model.hardwareInventory : null
  readonly property var live: model ? model.hardwareReadings : null
  readonly property var sensorValues: Model.hardwareValues(live ? live.sensors : [])
  readonly property var batteryValues: Model.hardwareValues(live ? live.batteries : [])
  readonly property var powers: Model.hardwareValues(model && model.packageReadings ? model.packageReadings : [])
  readonly property string unit: model && model.cfg ? (model.cfg.temperatureUnit || "celsius") : "celsius"
  readonly property string pin: model && model.cfg ? (model.cfg.sensorId || "") : ""
  readonly property var pinnedSensor: {
    var id = pin
    return info ? info.sensors.find(function (s) { return s.id === id }) || null : null
  }
  readonly property color dim: Model.dimColor(String(Commons.Color.foreground), String(Commons.Color.background))
  implicitWidth: 200
  implicitHeight: column.implicitHeight
  onActiveChanged: if (active) refresh()
  function refresh() { if (active && model && typeof model.pollHardware === "function") model.pollHardware() }

  component Note: Text {
    textFormat: Text.PlainText
    color: root.dim
    font.family: Commons.Style.font.family
    font.pixelSize: Commons.Style.font.caption
    width: root.width
    wrapMode: Text.Wrap
  }
  component SensorRow: Column {
    id: sensorRow
    required property var sensor
    readonly property var reading: sensor ? root.sensorValues[sensor.id] || null : null
    width: root.width
    spacing: Commons.Style.space(3)
    Components.StatRow {
      objectName: "hardwareSensorValue_" + (sensorRow.sensor ? sensorRow.sensor.id : "")
      wrapValue: true
      width: parent.width
      label: sensorRow.sensor ? sensorRow.sensor.label : ""
      value: Model.sensorValue(sensorRow.sensor, sensorRow.reading, root.unit)
      valueColor: sensorRow.sensor && sensorRow.reading && sensorRow.sensor.kind === "temperature"
        && sensorRow.reading.value !== null && sensorRow.reading.criticalC !== null
        && sensorRow.reading.value >= sensorRow.reading.criticalC ? Commons.Color.urgent : Commons.Color.foreground
    }
    Note { text: sensorRow.sensor ? sensorRow.sensor.driver + " · " + sensorRow.sensor.owner : "" }
    Note {
      visible: text !== ""
      text: sensorRow.reading ? sensorRow.reading.status : (sensorRow.sensor && sensorRow.sensor.gpu ? "Read on the GPU detail tab" : "Waiting for a reading…")
    }
  }

  Column {
    id: column
    width: root.width
    spacing: Commons.Style.space(12)
    Components.Hero {
      width: parent.width
      title: "Hardware"
      meta: {
        var sensors = root.info ? root.info.sensors.length : 0
        var batteries = root.info ? root.info.batteries.length : 0
        return sensors + (sensors === 1 ? " sensor · " : " sensors · ") + batteries + (batteries === 1 ? " battery" : " batteries")
      }
    }
    Note { text: "↑/↓ scroll · S for units and sensor pin" }
    Note {
      objectName: "hardwareError"
      text: root.model ? String(root.model.hardwareError || "") : ""
      visible: text !== ""
      color: Commons.Color.urgent
    }
    Note {
      visible: root.info && root.info.truncated
      text: "Hardware inventory reached its limit; some channels or devices are omitted."
      color: Commons.Color.urgent
    }
    Column {
      width: parent.width
      spacing: Commons.Style.space(6)
      visible: root.pin !== ""
      Components.SectionHeader { width: parent.width; text: "PINNED SENSOR" }
      Loader {
        width: parent.width
        active: root.pinnedSensor !== null
        sourceComponent: SensorRow { sensor: root.pinnedSensor }
      }
      Note {
        objectName: "missingSensorPin"
        visible: root.pinnedSensor === null
        text: "The pinned sensor is not available. Its saved identity is retained; R refreshes inventory."
      }
    }
    Column {
      width: parent.width
      spacing: Commons.Style.space(6)
      visible: graphicsActions.entries.length > 0
      Components.SectionHeader { width: parent.width; text: "GRAPHICS INVENTORY" }
      Note { text: "Details opens the current card. Select saves another card for its view; dedicated selection also changes the GPU bar." }
      Components.PanelActions {
        id: graphicsActions
        objectName: "hardwareGpuActions"
        width: parent.width
        panel: root.panel
        context: "gpu-inventory"
        entries: Model.gpuOverviewEntries(root.model ? (root.model.detectedGpus || root.model.gpus) : [], root.model ? root.model.integratedGpus : [],
          root.model ? root.model.gpu : null, root.model ? root.model.integratedGpu : null)
        onRequested: function (entry) {
          if (!root.model || !root.panel || entry.kind !== "gpu-details") return
          var current = entry.integrated ? root.model.integratedGpu : root.model.gpu
          if (!Model.gpuIdentityEqual(current, entry.gpu)) {
            if (entry.integrated) root.model.selectIntegratedGpu(entry.target)
            else root.model.selectGpu(entry.target)
          }
          root.panel.showTab(entry.integrated ? "cpu" : "gpu")
        }
      }
    }
    Repeater {
      model: ["temperature", "fan"]
      delegate: Column {
        id: sensorSection
        required property string modelData
        readonly property var entries: root.info ? root.info.sensors.filter(function (s) { return s.kind === sensorSection.modelData }) : []
        width: root.width
        visible: entries.length > 0
        spacing: Commons.Style.space(8)
        Components.SectionHeader { width: parent.width; text: sensorSection.modelData === "temperature" ? "TEMPERATURES" : "FANS" }
        Repeater {
          model: sensorSection.entries
          delegate: SensorRow {
            required property var modelData
            sensor: modelData
          }
        }
      }
    }
    Column {
      width: parent.width
      spacing: Commons.Style.space(6)
      visible: root.info && root.info.packages.length > 0
      Components.SectionHeader { width: parent.width; text: "PACKAGE POWER" }
      Note { text: "Each CPU package is reported once; core/uncore subdomains are excluded. Package totals can include integrated graphics." }
      Repeater {
        model: root.info ? root.info.packages : []
        delegate: Column {
          id: packageRow
          required property var modelData
          readonly property var reading: root.powers[modelData.id] || null
          width: root.width
          spacing: Commons.Style.space(3)
          Components.StatRow {
            wrapValue: true
            width: parent.width
            label: packageRow.modelData.label
            value: Model.formatWatts(packageRow.reading ? packageRow.reading.watts : null)
          }
          Note { text: packageRow.modelData.source + (packageRow.reading && packageRow.reading.status ? " · " + packageRow.reading.status : "") }
        }
      }
    }
    Column {
      width: parent.width
      spacing: Commons.Style.space(8)
      visible: root.info && root.info.batteries.length > 0
      Components.SectionHeader { width: parent.width; text: "BATTERIES & PERIPHERALS" }
      Note { text: "Readings belong to each device; system and peripheral charge are not combined. Power profiles remain in the shell's Power panel." }
      Repeater {
        model: root.info ? root.info.batteries : []
        delegate: Column {
          id: batteryRow
          required property var modelData
          readonly property var reading: root.batteryValues[modelData.id] || null
          width: root.width
          spacing: Commons.Style.space(4)
          Note {
            text: (batteryRow.modelData.model || batteryRow.modelData.name) + " · " + batteryRow.modelData.name
              + (batteryRow.modelData.scope === "Device" ? " · peripheral" : " · system battery")
            color: Commons.Color.foreground
            font.bold: true
          }
          Components.StatRow { wrapValue: true; width: parent.width; label: "Charge"; value: Model.formatPct(batteryRow.reading ? batteryRow.reading.chargePct : null) }
          Components.StatRow { wrapValue: true; width: parent.width; label: "Health / design"; value: Model.formatPct(batteryRow.reading ? batteryRow.reading.healthPct : null, 1) }
          Components.StatRow { wrapValue: true; width: parent.width; label: "Full capacity"; value: Model.batteryCapacity(batteryRow.reading) }
          Components.StatRow { wrapValue: true; width: parent.width; label: "Design capacity"; value: Model.batteryCapacity(batteryRow.reading, true) }
          Components.StatRow { wrapValue: true; width: parent.width; label: "Cycles"; value: batteryRow.reading && batteryRow.reading.cycles !== null ? String(batteryRow.reading.cycles) : "--" }
          Components.StatRow { wrapValue: true; width: parent.width; label: "Power"; value: Model.batteryPower(batteryRow.reading) }
          Note { text: batteryRow.reading ? batteryRow.reading.status : "Waiting for a reading…" }
        }
      }
    }
    Note {
      visible: !root.info && !(root.model && root.model.hardwareError)
      text: "Waiting for hardware inventory…"
    }
  }
}
