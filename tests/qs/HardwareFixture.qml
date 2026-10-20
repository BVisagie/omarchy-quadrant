import QtQuick
import "lib/index.mjs" as Model

QtObject {
  property var cfg: Model.readSettings({})
  property string hardwareError: ""
  property int barIntervalMs: 1000
  property int panelIntervalMs: 2000
  readonly property bool discreteGpuAvailable: discreteGpus.some(function (g) { return g.telemetryAvailable !== false })
  property var sample: null
  property var diskInfo: null
  property var raw: ({ ok: true, mode: "sample", monotonicS: 12, truncated: false,
    sensors: [
      { id: "hwmon:" + "a".repeat(64), kind: "temperature", driver: "coretemp", owner: "devices/platform/coretemp.0", channel: "temp1", label: "Package id 0", value: 52, criticalC: 100, status: "" },
      { id: "hwmon:" + "b".repeat(64), kind: "temperature", driver: "nvme", owner: "devices/pci0000:00/0000:01:00.0/nvme/controller", channel: "temp1", label: "Composite", value: 41, criticalC: 85, status: "" },
      { id: "hwmon:" + "c".repeat(64), kind: "fan", driver: "board", owner: "devices/platform/board.0", channel: "fan1", label: "Chassis fan", value: 0, status: "" },
      { id: "hwmon:" + "d".repeat(64), kind: "temperature", driver: "amdgpu", owner: "devices/pci0000:00/0000:03:00.0", channel: "temp1", label: "GPU edge", gpu: true, value: null, status: "Read on the GPU detail tab" }
    ],
    packages: [{ id: "package-0", label: "Package 0", source: "intel-rapl:0", readable: true, energyUj: 1080000000, maxEnergyUj: 100000000000, monotonicS: 12, status: "" }],
    batteries: [
      { id: "battery:" + "e".repeat(64), name: "BAT0", model: "Laptop battery", scope: "System", chargePct: 78, healthPct: 93,
        cycles: 62, fullWh: 78.1, designWh: 84, powerW: 0, powerEstimated: false, status: "Not charging" },
      { id: "battery:" + "f".repeat(64), name: "mouse", model: "Wireless mouse", scope: "Device", chargePct: 55, healthPct: null,
        cycles: null, fullWh: null, designWh: null, powerW: null, powerEstimated: false, status: "Discharging" }
    ] })
  readonly property var hardwareReadings: Model.parseHardware(raw)
  readonly property var hardwareInventory: Model.hardwareInventory(hardwareReadings)
  readonly property var previous: ({ monotonicS: 10, packages: [{ id: "package-0", source: "intel-rapl:0", energyUj: 1000000000, maxEnergyUj: 100000000000, monotonicS: 10 }] })
  readonly property var packageReadings: Model.packagePower(previous, hardwareReadings)
  property var gpus: [
    { card: "card0", vendor: "intel", deviceId: "0000:00:02.0", slot: "0000:00:02.0", name: "Integrated graphics", role: "integrated" },
    { card: "card1", vendor: "amd", deviceId: "0000:03:00.0", slot: "0000:03:00.0", name: "Dedicated graphics", role: "discrete" }
  ]
  readonly property var detectedGpus: gpus
  readonly property var integratedGpus: gpus.filter(function (g) { return g.role === "integrated" })
  readonly property var discreteGpus: gpus.filter(function (g) { return g.role !== "integrated" })
  readonly property var gpu: Model.pickGpu(discreteGpus, cfg.gpuDevice, cfg.gpuDeviceId)
  readonly property var integratedGpu: Model.pickGpu(integratedGpus, cfg.integratedGpuDevice, cfg.integratedGpuDeviceId)
  readonly property bool hardwareAvailable: hardwareInventory.sensors.length > 0 || hardwareInventory.batteries.length > 0
    || hardwareInventory.packages.length > 0 || detectedGpus.length > 1 || cfg.sensorId !== "" || hardwareError !== ""
    || detectedGpus.some(function (g) { return g.telemetryAvailable === false })
  property var lastPatch: ({})
  property string selectedGpu: ""
  property string selectedIntegratedGpu: ""
  property int selectionWrites: 0
  property int polls: 0
  function pollHardware() { polls++ }
  function persistSettings(patch) { lastPatch = patch; cfg = Model.readSettings(Model.settingsPatch(cfg, patch)) }
  function selectGpu(value) {
    selectedGpu = value; selectionWrites++
    var target = gpus.find(function (g) { return (g.deviceId || g.card) === value })
    persistSettings({ gpuDevice: target.card, gpuDeviceId: target.deviceId })
  }
  function selectIntegratedGpu(value) {
    selectedIntegratedGpu = value; selectionWrites++
    var target = gpus.find(function (g) { return (g.deviceId || g.card) === value })
    persistSettings({ integratedGpuDevice: target.card, integratedGpuDeviceId: target.deviceId })
  }
}
