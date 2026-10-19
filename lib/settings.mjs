// Typed settings: shell.json entry → normalised values, segment lists,
// and the entry to persist.

import { clamp, num, safeJsonValue } from "./core.mjs"

// omarchy bar set stores JSON strings; a persist of '"nvme0n1"' can arrive
// with the wrapping quotes still attached. Empty after strip is auto.
export function normalizeDeviceSetting(value) {
  var s = String(value === null || value === undefined ? "" : value)
  s = s.replace(/^\s+|\s+$/g, "")
  if (s.length >= 2 && s.charAt(0) === '"' && s.charAt(s.length - 1) === '"')
    s = s.slice(1, -1).replace(/^\s+|\s+$/g, "")
  if (s === "") return "auto"
  return s
}

// Canonical bar-segment order. Unknown names are dropped so a typo in
// shell.json cannot invent a sixth meter. An empty list is valid and
// means "icon-only fallback" rather than "reset to defaults".
export var BAR_SEGMENTS = ["cpu", "gpu", "memory", "disk", "network"]

export var DEFAULT_BAR_SEGMENTS = ["cpu", "gpu", "memory", "network"]

export function segmentKeyForTab(tab) {
  var name = String(tab || "")
  if (name === "mem") return "memory"
  if (name === "net") return "network"
  if (name === "cpu" || name === "gpu" || name === "disk") return name
  return ""
}

export function normalizeSegments(list) {
  var seen = {}
  var i
  if (Array.isArray(list)) {
    for (i = 0; i < list.length; i++) {
      var name = String(list[i] || "")
      if (BAR_SEGMENTS.indexOf(name) >= 0) seen[name] = true
    }
  }
  var out = []
  for (i = 0; i < BAR_SEGMENTS.length; i++) {
    if (seen[BAR_SEGMENTS[i]]) out.push(BAR_SEGMENTS[i])
  }
  return out
}

// Initial QML properties can arrive as QVariantList sequences rather than
// JavaScript arrays. Round-trip only that representation; plain objects do
// not become segment lists just because they expose numeric keys/length.
function settingArray(value) {
  if (Array.isArray(value)) return value
  if (!value || typeof value !== "object") return null
  try {
    var parsed = safeJsonValue(JSON.stringify(value))
    return Array.isArray(parsed) ? parsed : null
  } catch (e) { return null }
}

// Accepts a real array (typed entry), a JSON-encoded array (what an
// `omarchy bar set` without --json stored) or a comma list.
export function segmentsFromSetting(value) {
  var typed = settingArray(value)
  if (typed) return normalizeSegments(typed)
  if (typeof value === "string") {
    var s = unquoteSetting(value)
    if (s.charAt(0) === "[") {
      var parsed = safeJsonValue(s)
      if (Array.isArray(parsed)) return normalizeSegments(parsed)
      return DEFAULT_BAR_SEGMENTS.slice()
    }
    if (s === "") return DEFAULT_BAR_SEGMENTS.slice()
    return normalizeSegments(s.split(",").map(function (t) { return t.replace(/^\s+|\s+$/g, "") }))
  }
  return DEFAULT_BAR_SEGMENTS.slice()
}

// Order is independent of enabled membership and hardware availability. A
// partial or older preference keeps its first occurrences, then appends the
// remaining names in canonical order so hidden devices retain a position.
export function barOrderFromSetting(value) {
  var list = value
  if (typeof value === "string") {
    var raw = unquoteSetting(value)
    list = raw.charAt(0) === "[" ? safeJsonValue(raw) : raw.split(",")
  }
  list = settingArray(list) || []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var key = String(list[i] || "").replace(/^\s+|\s+$/g, "")
    if (BAR_SEGMENTS.indexOf(key) >= 0 && out.indexOf(key) < 0) out.push(key)
  }
  for (var j = 0; j < BAR_SEGMENTS.length; j++) {
    if (out.indexOf(BAR_SEGMENTS[j]) < 0) out.push(BAR_SEGMENTS[j])
  }
  return out
}

export function moveBarSegment(order, name, direction) {
  var out = barOrderFromSetting(order), index = out.indexOf(name)
  if (index < 0 || (direction !== -1 && direction !== 1)) return out
  var target = index + direction
  if (target < 0 || target >= out.length) return out
  out[index] = out[target]
  out[target] = name
  return out
}

// Strip one layer of wrapping quotes and surrounding whitespace.
export function unquoteSetting(value) {
  var s = String(value === null || value === undefined ? "" : value)
  s = s.replace(/^\s+|\s+$/g, "")
  if (s.length >= 2 && s.charAt(0) === '"' && s.charAt(s.length - 1) === '"')
    s = s.slice(1, -1).replace(/^\s+|\s+$/g, "")
  return s
}

export function parseIntSetting(value, fallback, lo, hi) {
  var raw = typeof value === "string" ? unquoteSetting(value) : value
  var n = num(raw, null)
  if (n === null) n = fallback
  return Math.round(clamp(n, lo, hi))
}

export function parseEnumSetting(value, options, fallback) {
  var s = unquoteSetting(value).toLowerCase()
  return options.indexOf(s) >= 0 ? s : fallback
}

// ---- typed settings --------------------------------------------------
// shell.json entries written before 1.0 hold strings for everything
// (`"processCount": "8"`, `"diskDevice": "\"nvme0n1\""`,
// `"segments": "[\"cpu\"]"`). readSettings accepts both those and typed
// values, so an old entry keeps working and the first persist migrates it.
export var SETTING_DEFAULTS = {
  segments: DEFAULT_BAR_SEGMENTS.slice(),
  barOrder: BAR_SEGMENTS.slice(),
  barStyle: "text",
  barGraphWidth: 32,
  processCount: 5,
  barIntervalMs: 1000,
  panelIntervalMs: 2000,
  networkInterface: "auto",
  gpuDevice: "auto",
  gpuDeviceId: "",
  integratedGpuDevice: "auto",
  integratedGpuDeviceId: "",
  diskDevice: "auto",
  diskDeviceId: "",
  diskFallbackWithoutGpu: true,
  barPalette: "theme",
  barLabels: "glyph",
  rateUnit: "bytes",
  temperatureUnit: "celsius",
  sensorId: "",
  gpuGraphLayout: "overlay",
  networkGraphLayout: "overlay",
  diskGraphLayout: "overlay"
}

export var BAR_PALETTES = ["theme", "heat", "vivid"]

export var BAR_LABEL_MODES = ["glyph", "letter", "none"]

export var RATE_UNITS = ["bytes", "bits"]

export function readSettings(raw) {
  var r = raw && typeof raw === "object" ? raw : {}
  var d = SETTING_DEFAULTS
  return {
    segments: segmentsFromSetting(r.segments),
    barOrder: barOrderFromSetting(r.barOrder),
    barStyle: parseEnumSetting(r.barStyle, ["text", "graph-text"], d.barStyle),
    barGraphWidth: parseIntSetting(r.barGraphWidth, d.barGraphWidth, 16, 64),
    processCount: parseIntSetting(r.processCount, d.processCount, 1, 10),
    barIntervalMs: parseIntSetting(r.barIntervalMs, d.barIntervalMs, 250, 60000),
    panelIntervalMs: parseIntSetting(r.panelIntervalMs, d.panelIntervalMs, 500, 60000),
    networkInterface: normalizeInterfaceSetting(r.networkInterface),
    gpuDevice: normalizeGpuDeviceSetting(r.gpuDevice),
    gpuDeviceId: normalizeGpuDeviceId(r.gpuDeviceId),
    integratedGpuDevice: normalizeIntegratedGpuDevice(r.integratedGpuDevice),
    integratedGpuDeviceId: normalizeGpuDeviceId(r.integratedGpuDeviceId),
    diskDevice: normalizeDiskSetting(r.diskDevice),
    diskDeviceId: normalizeDiskDeviceId(r.diskDeviceId),
    diskFallbackWithoutGpu: parseBoolSetting(
      typeof r.diskFallbackWithoutGpu === "string" ? unquoteSetting(r.diskFallbackWithoutGpu) : r.diskFallbackWithoutGpu,
      d.diskFallbackWithoutGpu),
    barPalette: parseEnumSetting(r.barPalette, BAR_PALETTES, d.barPalette),
    barLabels: parseEnumSetting(r.barLabels, BAR_LABEL_MODES, d.barLabels),
    rateUnit: parseEnumSetting(r.rateUnit, RATE_UNITS, d.rateUnit),
    temperatureUnit: parseEnumSetting(r.temperatureUnit, ["celsius", "fahrenheit"], d.temperatureUnit),
    sensorId: /^hwmon:[a-f0-9]{64}$/.test(unquoteSetting(r.sensorId)) ? unquoteSetting(r.sensorId) : "",
    gpuGraphLayout: parseEnumSetting(r.gpuGraphLayout, ["overlay", "aligned"], d.gpuGraphLayout),
    networkGraphLayout: parseEnumSetting(r.networkGraphLayout, ["overlay", "mirrored"], d.networkGraphLayout),
    diskGraphLayout: parseEnumSetting(r.diskGraphLayout, ["overlay", "mirrored"], d.diskGraphLayout)
  }
}

export function settingEquals(a, b) {
  if (Array.isArray(a) || Array.isArray(b)) return JSON.stringify(a) === JSON.stringify(b)
  return a === b
}

// The entry to persist after applying `patch` to the current raw entry:
// every known key normalised to its typed form, keys at their default
// dropped, unknown keys the user added kept verbatim, `id` never included
// (the shell writes it). Pass the result whole to updateEntryInline.
export function settingsPatch(raw, patch) {
  var merged = {}
  var k
  var r = raw && typeof raw === "object" ? raw : {}
  for (k in r) {
    if (Object.prototype.hasOwnProperty.call(r, k) && k !== "id") merged[k] = r[k]
  }
  // Only known keys may be written; unknown keys already in the entry are
  // the user's and stay, but a patch cannot add new ones.
  var p = patch && typeof patch === "object" ? patch : {}
  for (k in p) {
    if (!Object.prototype.hasOwnProperty.call(p, k)) continue
    if (!Object.prototype.hasOwnProperty.call(SETTING_DEFAULTS, k)) continue
    merged[k] = p[k]
  }
  var typed = readSettings(merged)
  var out = {}
  for (k in merged) {
    if (!Object.prototype.hasOwnProperty.call(merged, k)) continue
    if (Object.prototype.hasOwnProperty.call(SETTING_DEFAULTS, k)) continue
    out[k] = merged[k]
  }
  for (k in SETTING_DEFAULTS) {
    if (!Object.prototype.hasOwnProperty.call(SETTING_DEFAULTS, k)) continue
    if (settingEquals(typed[k], SETTING_DEFAULTS[k])) continue
    out[k] = typed[k]
  }
  return out
}

export function toggleSegment(list, name, enabled) {
  var key = String(name || "")
  if (BAR_SEGMENTS.indexOf(key) < 0) return normalizeSegments(list)
  var current = normalizeSegments(list)
  var seen = {}
  var i
  for (i = 0; i < current.length; i++) seen[current[i]] = true
  if (enabled) seen[key] = true
  else delete seen[key]
  var out = []
  for (i = 0; i < BAR_SEGMENTS.length; i++) {
    if (seen[BAR_SEGMENTS[i]]) out.push(BAR_SEGMENTS[i])
  }
  return out
}

export function parseBoolSetting(value, fallback) {
  if (value === true || value === "true" || value === 1 || value === "1") return true
  if (value === false || value === "false" || value === 0 || value === "0") return false
  return fallback === undefined ? true : !!fallback
}

// Display-time bar list. Never persist this result. A missing dedicated GPU
// enables Drives at Drives' own saved position; an explicit disk token and a
// substitute therefore produce one cell, without erasing the GPU preference.
export function effectiveSegments(configured, topologyReady, discreteGpuAvailable, fallbackEnabled, gpuInventoryOk, order) {
  var list = normalizeSegments(configured)
  if (topologyReady && gpuInventoryOk !== false && !discreteGpuAvailable && fallbackEnabled !== false && list.indexOf("gpu") >= 0) {
    list = list.filter(function (key) { return key !== "gpu" })
    if (list.indexOf("disk") < 0) list.push("disk")
  }
  return barOrderFromSetting(order).filter(function (key) { return list.indexOf(key) >= 0 })
}

// The panel's effective Drives switch may represent a fallback as well as
// an explicit segment. Enabling it must also work when GPU is disabled.
export function barSegmentPatch(cfg, name, enabled, missingGpu) {
  if (BAR_SEGMENTS.indexOf(name) < 0) return {}
  var segments = segmentsFromSetting(cfg && cfg.segments)
  if (name === "disk" && missingGpu) {
    if (enabled && segments.indexOf("gpu") >= 0) return { diskFallbackWithoutGpu: true }
    var patch = { segments: toggleSegment(segments, name, enabled) }
    if (!enabled) patch.diskFallbackWithoutGpu = false
    return patch
  }
  return { segments: toggleSegment(segments, name, enabled) }
}

// Ordered bar cells that actually paint. Segment tokens stay
// cpu/gpu/memory/disk/network; cell tokens are cpu/gpu/mem/disk/net so
// they match MetricCell.metric. GPU and disk still require live hardware.
export function visibleBarCells(effectiveList, discreteGpuAvailable, diskAvailable) {
  var list = Array.isArray(effectiveList) ? effectiveList : []
  var out = []
  var i
  for (i = 0; i < list.length; i++) {
    var s = list[i]
    if (s === "cpu") out.push("cpu")
    else if (s === "gpu") {
      if (discreteGpuAvailable) out.push("gpu")
    } else if (s === "memory") out.push("mem")
    else if (s === "disk") {
      if (diskAvailable) out.push("disk")
    } else if (s === "network") out.push("net")
  }
  return out
}

// Device-name settings are shape-checked here, before anything is matched
// or launched: a Linux interface name is at most 15 characters of
// [A-Za-z0-9._@:+-]; a dedicated GPU is "auto" or cardN; a disk is a
// sysfs block name. Anything else falls back to auto. The helpers that
// receive these names validate again on their side.
var INTERFACE_NAME = /^[A-Za-z0-9._@:+-]{1,15}$/
var CARD_NAME = /^card[0-9]{1,5}$/
var DISK_NAME = /^[A-Za-z0-9._+-]{1,64}$/

export function normalizeInterfaceSetting(value) {
  var s = normalizeDeviceSetting(value)
  if (s === "auto") return "auto"
  return INTERFACE_NAME.test(s) && s !== "lo" ? s : "auto"
}

export function normalizeGpuDeviceSetting(value) {
  var s = normalizeDeviceSetting(value)
  return CARD_NAME.test(s) ? s : "auto"
}

export function normalizeDiskSetting(value) {
  var s = normalizeDeviceSetting(value)
  if (s === "auto") return "auto"
  return DISK_NAME.test(s) && s.indexOf("..") === -1 ? s : "auto"
}

export function normalizeIntegratedGpuDevice(value) {
  var s = normalizeDeviceSetting(value)
  if (s === "none") return "none"
  if (CARD_NAME.test(s)) return s
  return "auto"
}

// Persistent IDs are inventory lookup keys, never paths or helper arguments.
// PCI device/function numbers are bounded by the PCI address format.
export function normalizeGpuDeviceId(value) {
  var s = unquoteSetting(value).toLowerCase()
  return /^[0-9a-f]{4}:[0-9a-f]{2}:[01][0-9a-f]\.[0-7]$/.test(s) ? s : ""
}

export function normalizeDiskDeviceId(value) {
  var s = unquoteSetting(value)
  if (!/^[A-Za-z0-9][A-Za-z0-9._:+-]{0,254}$/.test(s)) return ""
  if (s.indexOf("..") !== -1 || /-part[0-9]+$/.test(s)) return ""
  return s
}
