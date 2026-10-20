// Hardware inventory is independent of live values and display units. Pins
// never use hwmonN, and package watts never share a baseline across sources.
import { clipStr } from "./core.mjs"
import { formatTemp, formatWatts } from "./format.mjs"
import { gpuDisplayName, gpuIdentityEqual, gpuVendorLabel } from "./gpu.mjs"

function measured(value, lo, hi) {
  return typeof value === "number" && isFinite(value) && value >= lo && value <= hi ? value : null
}

export function panelTabs(gpu, hardware) {
  var tabs = ["cpu"]
  if (gpu) tabs.push("gpu")
  tabs.push("mem", "disk", "net")
  if (hardware) tabs.push("hardware")
  return tabs
}

export function parseHardware(env) {
  if (!env || env.ok !== true || ["list", "power", "sample"].indexOf(env.mode) < 0
      || !Array.isArray(env.sensors) || !Array.isArray(env.packages) || !Array.isArray(env.batteries)) return null
  var out = { mode: env.mode, monotonicS: measured(env.monotonicS, 0, 1e12),
    sensors: [], packages: [], batteries: [], truncated: env.truncated === true }
  var seen = {}
  for (var sensor of env.sensors.slice(0, 128)) {
    if (!sensor || !/^hwmon:[a-f0-9]{64}$/.test(sensor.id) || seen[sensor.id]
        || ["temperature", "fan"].indexOf(sensor.kind) < 0) continue
    seen[sensor.id] = true
    out.sensors.push({ id: sensor.id, label: clipStr(sensor.label, 80), owner: clipStr(sensor.owner, 512),
      driver: clipStr(sensor.driver, 64), channel: clipStr(sensor.channel, 24), kind: sensor.kind, gpu: sensor.gpu === true,
      value: measured(sensor.value, sensor.kind === "temperature" ? -273.15 : 0, sensor.kind === "temperature" ? 1000 : 100000),
      criticalC: measured(sensor.criticalC, -273.15, 1000), status: clipStr(sensor.status, 100) })
  }
  for (var pack of env.packages.slice(0, 16)) {
    if (!pack || !/^package-[0-9]{1,3}$/.test(pack.id) || seen[pack.id]) continue
    seen[pack.id] = true
    out.packages.push({ id: pack.id, label: clipStr(pack.label, 80), source: clipStr(pack.source, 80),
      readable: pack.readable === true,
      energyUj: measured(pack.energyUj, 0, 9007199254740991),
      maxEnergyUj: measured(pack.maxEnergyUj, 1, 9007199254740991), monotonicS: measured(pack.monotonicS, 0, 1e12), status: clipStr(pack.status, 100) })
    var parsedPack = out.packages[out.packages.length - 1]
    if (parsedPack.energyUj !== null && (Math.floor(parsedPack.energyUj) !== parsedPack.energyUj
        || parsedPack.maxEnergyUj === null || Math.floor(parsedPack.maxEnergyUj) !== parsedPack.maxEnergyUj
        || parsedPack.energyUj >= parsedPack.maxEnergyUj)) {
      parsedPack.energyUj = null; parsedPack.status = "Invalid energy counter"
    }
  }
  for (var battery of env.batteries.slice(0, 16)) {
    if (!battery || typeof battery.id !== "string" || battery.id === "" || battery.id.length > 512 || seen[battery.id]) continue
    seen[battery.id] = true
    var row = { id: battery.id, name: clipStr(battery.name, 80), model: clipStr(battery.model, 80),
      manufacturer: clipStr(battery.manufacturer, 80), scope: clipStr(battery.scope, 24),
      status: clipStr(battery.status, 32), powerEstimated: battery.powerEstimated === true }
    row.healthBasis = battery.healthBasis === "charge" || battery.healthBasis === "energy" ? battery.healthBasis : ""
    for (var field of ["chargePct", "healthPct", "cycles", "powerW", "fullWh", "designWh", "fullAh", "designAh"])
      row[field] = measured(battery[field], 0, field === "chargePct" ? 100 : field === "healthPct" ? 200 : field === "cycles" ? 1000000 : 10000)
    out.batteries.push(row)
  }
  out.truncated = out.truncated || env.sensors.length > 128 || env.packages.length > 16 || env.batteries.length > 16
  return out
}

export function hardwareInventory(snapshot) {
  if (!snapshot) return null
  return { truncated: snapshot.truncated,
    sensors: snapshot.sensors.map(function (s) { return { id: s.id, label: s.label, owner: s.owner,
      driver: s.driver, channel: s.channel, kind: s.kind, gpu: s.gpu } }),
    packages: snapshot.packages.map(function (p) { return { id: p.id, label: p.label, source: p.source, readable: p.readable } }),
    batteries: snapshot.batteries.map(function (b) { return { id: b.id, name: b.name, model: b.model,
      manufacturer: b.manufacturer, scope: b.scope } }) }
}

export function hardwareValues(rows) {
  var out = {}
  for (var row of (Array.isArray(rows) ? rows : [])) out[row.id] = row
  return out
}

function sensorDriverName(driver) {
  return driver === "nvme" ? "NVMe"
    : /^iwlwifi(?:_|$)/.test(driver) ? "Wireless"
    : driver === "acpitz" ? "ACPI thermal zone"
    : driver === "acpi_fan" ? "ACPI fan" : driver
}

// Separate devices can use the same driver or channel labels. The owner
// path and sensor kind, not a friendly label, define a display group.
export function hardwareSensorGroups(sensors) {
  var groups = [], byKey = Object.create(null), drivers = Object.create(null)
  for (var sensor of (Array.isArray(sensors) ? sensors : [])) {
    var key = JSON.stringify([sensor.kind, sensor.driver, sensor.owner])
    if (!byKey[key]) {
      var group = { key: key, kind: sensor.kind, driver: sensor.driver, owner: sensor.owner, sensors: [] }
      byKey[key] = group
      groups.push(group)
      if (!drivers[sensor.driver]) drivers[sensor.driver] = new Set()
      drivers[sensor.driver].add(sensor.owner)
    }
    byKey[key].sensors.push(sensor)
  }
  for (var entry of groups) {
    var parts = entry.owner.split("/"), depth = 1
    while (depth < parts.length && groups.some(function (other) {
      return other.driver === entry.driver && other.owner !== entry.owner
        && other.owner.split("/").slice(-depth).join("/") === parts.slice(-depth).join("/")
    })) depth++
    var suffix = drivers[entry.driver].size > 1 ? " · " + parts.slice(-depth).join("/") : ""
    entry.title = entry.driver + suffix
    // Only recognized drivers gain a friendly name. Keep unknown devices
    // and the disambiguating owner suffix; never infer identity from values.
    entry.processor = ["coretemp", "k10temp", "zenpower", "cpu_thermal"].indexOf(entry.driver) >= 0
    var friendly = sensorDriverName(entry.driver)
    var sharedName = groups.some(function (other) {
      return other.driver !== entry.driver && sensorDriverName(other.driver) === friendly
    })
    entry.displayTitle = friendly + (sharedName ? " · " + entry.driver : "") + suffix
  }
  return groups
}

// Collapsing a core grid must not conceal missing readings or hardware-
// reported critical temperatures. Compare in Celsius, independently of units.
export function coreTemperatureSummary(sensors, readings) {
  var out = { count: sensors.length, available: 0, missing: 0, critical: 0, min: null, max: null }
  for (var sensor of sensors) {
    var row = readings[sensor.id]
    if (!row || typeof row.value !== "number" || !isFinite(row.value)) { out.missing++; continue }
    out.available++
    out.min = out.min === null ? row.value : Math.min(out.min, row.value)
    out.max = out.max === null ? row.value : Math.max(out.max, row.value)
    if (typeof row.criticalC === "number" && isFinite(row.criticalC) && row.value >= row.criticalC) out.critical++
  }
  return out
}

export function sensorValue(sensor, reading, unit) {
  if (!reading || reading.value === null || reading.value === undefined) return "--"
  if (sensor.kind === "temperature") return formatTemp(reading.value, unit)
  return Math.round(reading.value) + " RPM" + (reading.value === 0 ? " · stopped" : "")
}

export function sensorOptions(info) {
  var out = [{ value: "", label: "No pinned sensor" }]
  for (var sensor of (info ? info.sensors : []))
    out.push({ value: sensor.id, label: sensor.driver + " · " + sensor.label + " · " + sensor.owner })
  return out
}

export function packagePower(previous, current, maxGapS) {
  if (!current) return []
  var prev = hardwareValues(previous ? previous.packages : [])
  return current.packages.map(function (pack) {
    var row = { id: pack.id, label: pack.label, source: pack.source, watts: null, status: pack.status }
    if (pack.energyUj === null || pack.maxEnergyUj === null) return row
    var old = prev[pack.id]
    var currentTime = pack.monotonicS === null || pack.monotonicS === undefined ? current.monotonicS : pack.monotonicS
    var oldTime = old && old.monotonicS !== null && old.monotonicS !== undefined ? old.monotonicS : previous ? previous.monotonicS : null
    var dt = currentTime !== null && oldTime !== null ? currentTime - oldTime : 0
    if (!old || old.source !== pack.source || old.maxEnergyUj !== pack.maxEnergyUj || old.energyUj === null
        || !(dt >= 0.1) || dt > Math.min(120, maxGapS || 120)) {
      row.status = "Measuring package power…"; return row
    }
    // A generous per-package bound rejects spikes and intervals in which
    // one or more complete wraps could be hidden. Values are never clamped.
    var ceilingW = 2000, range = pack.maxEnergyUj
    if (dt * ceilingW * 1000000 >= range) {
      row.status = "Counter interval is ambiguous"; return row
    }
    var delta = pack.energyUj - old.energyUj
    if (delta < 0) {
      if (old.energyUj >= range * 0.9 && pack.energyUj <= range * 0.1) delta += range
      else { row.status = "Counter reset; measuring again"; return row }
    }
    var watts = delta / 1000000 / dt
    if (!isFinite(watts) || watts < 0 || watts > ceilingW) {
      row.status = "Implausible counter change"; return row
    }
    row.watts = watts; row.status = ""
    return row
  })
}

export function totalPackageWatts(rows) {
  if (!Array.isArray(rows) || rows.length === 0) return null
  var sum = 0
  for (var row of rows) { if (row.watts === null || row.watts === undefined) return null; sum += row.watts }
  return sum
}

export function gpuOverviewEntries(gpus, integrated, selectedGpu, selectedIntegratedGpu) {
  if (!Array.isArray(gpus) || (gpus.length < 2 && !gpus.some(function (g) { return g.telemetryAvailable === false }))) return []
  return gpus.map(function (gpu) {
    var igpu = gpu.role === "integrated" || (Array.isArray(integrated) ? integrated : []).some(function (g) { return gpuIdentityEqual(g, gpu) })
    var selected = gpuIdentityEqual(gpu, igpu ? selectedIntegratedGpu : selectedGpu)
    return { key: "gpu:" + (gpu.deviceId || gpu.card), kind: "gpu-details", actionText: selected ? "Details" : "Select",
      label: (gpuDisplayName(gpu) || gpuVendorLabel(gpu.vendor)) + " · " + (igpu ? "integrated" : "dedicated"),
      value: gpu.deviceId || gpu.slot || gpu.card, target: gpu.deviceId || gpu.card, gpu: gpu, integrated: igpu,
      unavailableReason: gpu.telemetryAvailable === false ? "Telemetry is unavailable on this card" : "" }
  })
}

export function batteryCapacity(battery, design) {
  if (!battery) return "--"
  var unit = battery.healthBasis === "charge" ? "Ah" : battery.healthBasis === "energy" ? "Wh"
    : typeof battery.fullWh === "number" ? "Wh" : typeof battery.fullAh === "number" ? "Ah"
    : typeof battery.designWh === "number" ? "Wh" : "Ah"
  var value = battery[(design ? "design" : "full") + unit]
  return value === null || value === undefined ? "--" : value.toFixed(1) + " " + unit
}

export function batteryPower(battery) {
  return battery ? formatWatts(battery.powerW) + (battery.powerEstimated && battery.powerW !== null ? " · estimated" : "") : "--"
}
