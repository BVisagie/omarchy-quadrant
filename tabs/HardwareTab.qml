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
  // Only inventory changes rebuild groups; live values update the cells in place.
  readonly property string sensorInventoryKey: JSON.stringify(root.info ? root.info.sensors : [])
  readonly property var sensorGroups: Model.hardwareSensorGroups(JSON.parse(sensorInventoryKey))
  readonly property var processorGroups: sensorGroups.filter(function (g) { return g.kind === "temperature" && g.processor })
  readonly property var otherGroups: sensorGroups.filter(function (g) { return g.kind === "temperature" && !g.processor })
  readonly property var fanGroups: sensorGroups.filter(function (g) { return g.kind === "fan" })
  readonly property string batteryInventoryKey: JSON.stringify(root.info ? root.info.batteries : [])
  readonly property var batteryInventory: JSON.parse(batteryInventoryKey)
  readonly property string packageInventoryKey: JSON.stringify(root.info ? root.info.packages : [])
  readonly property var packageInventory: JSON.parse(packageInventoryKey)
  implicitWidth: 200
  implicitHeight: column.implicitHeight
  onActiveChanged: if (active) refresh()
  function refresh() { if (active && model && typeof model.pollHardware === "function") model.pollHardware() }

  component Note: Text {
    textFormat: Text.PlainText
    color: root.dim
    font.family: Commons.Style.font.family
    font.pixelSize: Commons.Style.font.caption
    width: parent.width
    wrapMode: Text.Wrap
  }
  component SensorRow: Column {
    id: sensorRow
    required property var sensor
    readonly property var reading: sensor ? root.sensorValues[sensor.id] || null : null
    width: parent.width
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
      detailsTarget: root
      title: "Hardware"
      meta: {
        var sensors = root.info ? root.info.sensors.length : 0
        var batteries = root.info ? root.info.batteries.length : 0
        return sensors + (sensors === 1 ? " sensor · " : " sensors · ") + batteries + (batteries === 1 ? " battery" : " batteries")
      }
    }

    Note { text: "↑/↓ scroll · D details · S units and sensor pin" }

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

    Components.SectionCard {
      width: parent.width
      title: "Pinned sensor"
      visible: root.pin !== ""

      Loader {
        width: parent.width
        active: root.pinnedSensor !== null
        sourceComponent: SensorRow { width: parent.width; sensor: root.pinnedSensor }
      }
      Note {
        objectName: "missingSensorPin"
        visible: root.pinnedSensor === null
        text: "The pinned sensor is not available. Its saved identity is retained; R refreshes inventory."
      }
    }

    Components.AdaptiveColumns {
      objectName: "resourceColumns"
      width: parent.width
      primary: [
        Components.SectionCard {
          width: parent.width
          title: "Processor"
          visible: root.processorGroups.length > 0

          Repeater {
            model: root.processorGroups
            delegate: Components.SensorGroup {
              required property var modelData
              width: parent.width
              group: modelData
              readings: root.sensorValues
              temperatureUnit: root.unit
            }
          }
        },
        Components.SectionCard {
          width: parent.width
          title: "Other temperatures"
          visible: root.otherGroups.length > 0

          Repeater {
            model: root.otherGroups
            delegate: Components.SensorGroup {
              required property var modelData
              width: parent.width
              group: modelData
              readings: root.sensorValues
              temperatureUnit: root.unit
            }
          }
        },
        Components.SectionCard {
          width: parent.width
          title: "Graphics inventory"
          visible: graphicsActions.entries.length > 0

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

          Components.Disclosure {
            width: parent.width
            title: "About GPU selection"
            Note { text: "Details opens the current card. Select saves another card for its view; dedicated selection also changes the GPU bar." }
          }
        }
      ]
      secondary: [
        Components.SectionCard {
          width: parent.width
          title: "Batteries"
          visible: root.info && root.info.batteries.length > 0

          Repeater {
            model: root.batteryInventory
            delegate: Column {
              id: batteryRow
              required property var modelData
              readonly property var reading: root.batteryValues[modelData.id] || null
              readonly property bool peripheral: modelData.scope === "Device"
              width: parent.width
              spacing: Commons.Style.space(8)
              Note {
                text: batteryRow.peripheral ? (batteryRow.modelData.model || batteryRow.modelData.name)
                  : "System battery · " + batteryRow.modelData.name
                color: Commons.Color.foreground
                font.bold: true
              }
              Components.MetricReadout {
                objectName: "hardwareBatteryCharge_" + batteryRow.modelData.id
                visible: !batteryRow.peripheral
                width: parent.width
                value: Model.formatPct(batteryRow.reading ? batteryRow.reading.chargePct : null)
                hint: (batteryRow.reading && batteryRow.reading.chargePct !== null ? "" : "Charge unavailable · ")
                  + (batteryRow.reading ? batteryRow.reading.status : "Waiting for a reading…")
              }
              Components.StatRow {
                width: parent.width
                visible: batteryRow.peripheral
                label: "Charge"
                value: Model.formatPct(batteryRow.reading ? batteryRow.reading.chargePct : null)
              }
              Note {
                visible: batteryRow.peripheral
                text: (batteryRow.reading && batteryRow.reading.chargePct !== null ? "" : "Charge unavailable · ")
                  + (batteryRow.reading ? batteryRow.reading.status : "Waiting for a reading…")
              }
              Components.CompositionBar {
                width: parent.width
                visible: !batteryRow.peripheral && batteryRow.reading !== null && batteryRow.reading.chargePct !== null
                segments: [{ fraction: batteryRow.reading ? batteryRow.reading.chargePct / 100 : 0, color: Commons.Color.accent }]
              }
              Components.StatRow { visible: !batteryRow.peripheral || (batteryRow.reading && batteryRow.reading.healthPct !== null); wrapValue: true; width: parent.width; label: "Health / design"; value: Model.formatPct(batteryRow.reading ? batteryRow.reading.healthPct : null, 1) }
              Components.StatRow { visible: !batteryRow.peripheral || (batteryRow.reading && (batteryRow.reading.fullWh !== null || batteryRow.reading.fullAh !== null)); wrapValue: true; width: parent.width; label: "Full capacity"; value: Model.batteryCapacity(batteryRow.reading) }
              Components.StatRow { visible: !batteryRow.peripheral || (batteryRow.reading && batteryRow.reading.cycles !== null); wrapValue: true; width: parent.width; label: "Cycles"; value: batteryRow.reading && batteryRow.reading.cycles !== null ? String(batteryRow.reading.cycles) : "--" }
              Components.Disclosure {
                objectName: "hardwareBatteryDetails_" + batteryRow.modelData.id
                width: parent.width
                title: "Battery details"
                Note { text: batteryRow.modelData.model + " · " + batteryRow.modelData.name + (batteryRow.peripheral ? " · peripheral" : " · system battery") }
                Note { visible: text !== ""; text: batteryRow.modelData.manufacturer }
                Components.StatRow { wrapValue: true; width: parent.width; label: "Design capacity"; value: Model.batteryCapacity(batteryRow.reading, true) }
                Components.StatRow { wrapValue: true; width: parent.width; label: "Power"; value: Model.batteryPower(batteryRow.reading) }
              }
            }
          }

          Components.Disclosure {
            width: parent.width
            title: "About battery readings"
            Note { text: "Readings belong to each device; system and peripheral charge are not combined. Power profiles remain in the shell's Power panel." }
          }
        },
        Components.SectionCard {
          width: parent.width
          title: "Power & cooling"
          visible: root.fanGroups.length > 0 || !!(root.info && root.info.packages.length > 0)

          Repeater {
            model: root.packageInventory
            delegate: Column {
              id: packageRow
              required property var modelData
              readonly property var reading: root.powers[modelData.id] || null
              width: parent.width
              spacing: Commons.Style.space(4)
              Components.StatRow {
                width: parent.width
                wrapValue: true
                label: packageRow.modelData.label
                value: Model.formatWatts(packageRow.reading ? packageRow.reading.watts : null)
              }
              Note {
                visible: text !== ""
                text: packageRow.reading ? packageRow.reading.status : "Waiting for a reading…"
              }
            }
          }

          Repeater {
            model: root.fanGroups
            delegate: Components.SensorGroup {
              required property var modelData
              width: parent.width
              group: modelData
              readings: root.sensorValues
              temperatureUnit: root.unit
            }
          }

          Components.Disclosure {
            width: parent.width
            visible: root.info && root.info.packages.length > 0
            title: "Power details"
            Repeater {
              model: root.packageInventory
              delegate: Note {
                required property var modelData
                text: modelData.label + " · " + modelData.source
              }
            }
            Note { text: "Each CPU package is reported once; core/uncore subdomains are excluded. Package totals can include integrated graphics." }
          }
        }
      ]
    }
    Note {
      visible: !root.info && !(root.model && root.model.hardwareError)
      text: "Waiting for hardware inventory…"
    }
  }
}
