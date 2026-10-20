"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const Model = require("../../lib/index.mjs");
const Released = require("../fixtures/settings-v1.mjs");
const sensorId = "hwmon:" + "a".repeat(64);
function sample(time, energy, extra = {}) {
  return { ok: true, mode: "sample", monotonicS: time, sensors: [], batteries: [],
    packages: [{ id: "package-0", label: "Package 0", source: "intel-rapl:0", energyUj: energy,
      maxEnergyUj: 100000000000, monotonicS: time, readable: true, status: "", ...extra }] };
}

test("temperature conversion only changes display, including zero and negative values", () => {
  assert.equal(Model.formatTemp(0), "0°C");
  assert.equal(Model.formatTemp(0, "fahrenheit"), "32°F");
  assert.equal(Model.formatTemp(-40, "fahrenheit"), "-40°F");
  assert.equal(Model.formatTemp(100, "fahrenheit"), "212°F");
  assert.equal(Model.formatTemp(null, "fahrenheit"), "--");
  const reading = { value: 90, criticalC: 100 };
  const before = structuredClone(reading);
  assert.equal(Model.sensorValue({ kind: "temperature" }, reading, "fahrenheit"), "194°F");
  assert.deepEqual(reading, before);
  assert.equal(Model.sensorValue({ kind: "fan" }, { value: 0 }), "0 RPM · stopped");
  assert.equal(Model.sensorValue({ kind: "fan" }, { value: null }), "--");
});

test("hardware settings normalize, persist, reset and survive an older writer", () => {
  assert.equal(Model.readSettings({ temperatureUnit: '"FAHRENHEIT"', sensorId }).temperatureUnit, "fahrenheit");
  assert.equal(Model.readSettings({ sensorId }).sensorId, sensorId);
  for (const value of [null, "hwmon2", "../temp1_input", "hwmon:" + "z".repeat(64)])
    assert.equal(Model.readSettings({ sensorId: value }).sensorId, "");
  assert.equal(Model.readSettings({ temperatureUnit: "kelvin" }).temperatureUnit, "celsius");
  const saved = Model.settingsPatch({ unknownFutureKey: 7 }, { temperatureUnit: "fahrenheit", sensorId });
  const downgraded = Released.settingsPatch(saved, { processCount: 8 });
  assert.equal(downgraded.temperatureUnit, "fahrenheit");
  assert.equal(downgraded.sensorId, sensorId);
  assert.equal(Model.settingsPatch(saved, { temperatureUnit: "celsius", sensorId: "" }).sensorId, undefined);
});

test("inventory identities exclude changing readings, statuses and sample times", () => {
  const raw = sample(10, 1000000000);
  raw.sensors = [{ id: sensorId, kind: "temperature", driver: "coretemp", owner: "devices/platform/cpu.0", channel: "temp1", label: "Package", value: 50, status: "" }];
  const first = Model.parseHardware(raw);
  raw.sensors[0].value = null; raw.sensors[0].status = "Permission denied";
  raw.packages[0].energyUj += 123;
  const second = Model.parseHardware(raw);
  assert.deepEqual(Model.hardwareInventory(first), Model.hardwareInventory(second));
  assert.equal(Model.sensorOptions(Model.hardwareInventory(first))[1].value, sensorId);
  assert.equal(Model.hardwareValues(second.sensors)[sensorId].value, null);
  assert.equal(Model.hardwareInventory(null), null);
});

test("malformed hardware numbers stay unavailable and caps are visible", () => {
  const raw = sample(1, true);
  raw.sensors = [{ id: sensorId, kind: "fan", value: false }];
  let parsed = Model.parseHardware(raw);
  assert.equal(parsed.packages[0].energyUj, null);
  assert.equal(parsed.sensors[0].value, null);
  for (const energy of ["12 uJ", 1.5, 1e20, -1, 100000000000]) {
    parsed = Model.parseHardware(sample(1, energy));
    assert.equal(parsed.packages[0].energyUj, null);
  }
  assert.equal(Model.parseHardware({ ok: true }), null);
  raw.sensors = Array.from({ length: 129 }, (_, i) => ({ id: "hwmon:" + i.toString(16).padStart(64, "0"), kind: "fan", value: 0 }));
  parsed = Model.parseHardware(raw);
  assert.equal(parsed.sensors.length, 128); assert.equal(parsed.truncated, true);
});

test("package watts use elapsed counter time and preserve a measured zero", () => {
  const old = Model.parseHardware(sample(10, 1000000000));
  const current = Model.parseHardware(sample(12, 1080000000));
  current.monotonicS = 40; // unrelated slow sensor reads cannot bias watts
  assert.equal(Model.packagePower(old, current)[0].watts, 40);
  assert.equal(Model.packagePower(old, old)[0].watts, null);
  assert.equal(Model.packagePower(null, current)[0].watts, null);
  assert.equal(Model.packagePower(old, Model.parseHardware(sample(12, 1000000000)))[0].watts, 0);
});

test("package access is explicit inventory metadata, not a measured value", () => {
  for (const value of [undefined, false, "true", 1, true]) {
    const parsed = Model.parseHardware(sample(1, null, { readable: value }));
    assert.equal(parsed.packages[0].readable, value === true);
    assert.equal(Model.hardwareInventory(parsed).packages[0].readable, value === true);
  }
});

test("package wrap is conservative and resets, gaps, source changes and spikes are unknown", () => {
  const before = Model.parseHardware(sample(10, 99800000000));
  assert.equal(Model.packagePower(before, Model.parseHardware(sample(12, 100000000)))[0].watts, 150);
  const old = Model.parseHardware(sample(10, 1000000000));
  const rejected = [sample(12, 500000000), sample(10, 1080000000), sample(9, 1080000000),
    sample(12, 1080000000, { source: "intel-rapl-mmio:0" }),
    sample(12, 1080000000, { maxEnergyUj: 200000000000 }),
    sample(70, 1080000000), sample(10.1, 20000000000)];
  for (const raw of rejected) assert.equal(Model.packagePower(old, Model.parseHardware(raw))[0].watts, null);
  assert.equal(Model.packagePower(old, Model.parseHardware(sample(20, 1080000000)), 5)[0].watts, null);
  const denied = Model.parseHardware(sample(12, null, { status: "Permission denied" }));
  assert.equal(Model.packagePower(old, denied)[0].status, "Permission denied");
  assert.equal(Model.totalPackageWatts([{ watts: 20 }, { watts: null }]), null);
  assert.equal(Model.totalPackageWatts([{ watts: 20 }, { watts: 30 }]), 50);
  assert.equal(Model.totalPackageWatts([]), null);
});

test("battery formatting keeps Wh and Ah distinct, including real zero power", () => {
  assert.equal(Model.batteryCapacity({ fullWh: 50, designWh: 60 }), "50.0 Wh");
  assert.equal(Model.batteryCapacity({ fullWh: 50, designWh: 60 }, true), "60.0 Wh");
  assert.equal(Model.batteryCapacity({ fullWh: null, fullAh: 3, designAh: 4 }), "3.0 Ah");
  assert.equal(Model.batteryCapacity({ healthBasis: "charge", fullWh: 50, fullAh: 3, designAh: 4 }, true), "4.0 Ah");
  assert.equal(Model.batteryCapacity(null), "--");
  assert.equal(Model.batteryPower({ powerW: 0, powerEstimated: false }), "0.0 W");
  assert.equal(Model.batteryPower({ powerW: null, powerEstimated: false }), "--");
  assert.equal(Model.batteryPower({ powerW: 12, powerEstimated: true }), "12 W · estimated");
});

test("conditional navigation and GPU overview retain identities without live telemetry", () => {
  assert.deepEqual(Model.panelTabs(false, false), ["cpu", "mem", "disk", "net"]);
  assert.equal(Model.panelTabs(true, true).length, 6);
  const integrated = { card: "card0", vendor: "intel", deviceId: "0000:00:02.0", name: "Integrated" };
  const dedicated = { card: "card2", vendor: "amd", deviceId: "0000:03:00.0", name: "Dedicated" };
  const entries = Model.gpuOverviewEntries([integrated, dedicated], [integrated], dedicated, integrated);
  assert.deepEqual(entries.map(entry => entry.integrated), [true, false]);
  assert.equal(entries[1].target, dedicated.deviceId);
  assert.ok(entries[0].label.includes("integrated"));
  assert.deepEqual(entries.map(entry => entry.actionText), ["Details", "Details"]);
  const alternate = { ...dedicated, card: "card3", deviceId: "0000:04:00.0" };
  const choices = Model.gpuOverviewEntries([integrated, dedicated, alternate], [integrated], dedicated, integrated);
  assert.deepEqual(choices.map(entry => entry.actionText), ["Details", "Details", "Select"]);
  assert.equal(choices[2].target, alternate.deviceId);
  assert.deepEqual(choices[2].gpu, alternate);
  assert.deepEqual(Model.gpuOverviewEntries([integrated], [integrated]), []);
  const raw = { card: "card2", vendor: "amd", path: "/sys/class/drm/card2/device", slot: "0000:03:00.0", telemetryAvailable: false };
  const inventory = Model.normalizeGpuInventory({ gpus: [], inventory: [raw] });
  assert.equal(inventory[0].telemetryAvailable, false);
  const topology = Model.reconcileGpuTopology(inventory, {}, "auto", "");
  assert.equal(topology.gpus[0].telemetryAvailable, false);
  assert.ok(Model.gpuOverviewEntries(topology.gpus, [])[0].unavailableReason.includes("unavailable"));
  assert.equal(Model.normalizeGpuInventory({ gpus: [raw] })[0].telemetryAvailable, false);
  assert.equal(Model.normalizeGpuInventory({ gpus: [{ ...raw, telemetryAvailable: undefined }] })[0].telemetryAvailable, true);
  assert.deepEqual(Model.normalizeGpuInventory({}), []);
});

test("GPU memory clocks have a distinct source and never derive from core clocks", () => {
  let live = Model.normalizeAmdGpu({ sclk_mhz: "2000" });
  assert.equal(live.memoryClockMhz, null); assert.equal(live.memoryClockSource, "");
  live = Model.normalizeAmdGpu({ sclk_mhz: "2000", mclk_mhz: "1000", mclk_source: "pp_dpm_mclk" });
  assert.equal(live.memoryClockMhz, 1000); assert.equal(live.memoryClockSource, "pp_dpm_mclk");
  const rows = Model.parseNvidiaCsv("0, NVIDIA Model, Laptop, 12, 1024, 8192, 50, 35, 1800, 7001\n", 8, true);
  assert.equal(rows[0].name, "NVIDIA Model, Laptop");
  assert.equal(rows[0].clockMhz, 1800); assert.equal(rows[0].memoryClockMhz, 7001);
  assert.equal(Model.parseNvidiaCsv("0, NVIDIA, 0, 0, 8192, 50, 5, 0, N/A\n", 8, true)[0].memoryClockMhz, null);
});
