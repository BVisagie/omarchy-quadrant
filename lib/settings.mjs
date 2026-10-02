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

// Accepts a real array (typed entry), a JSON-encoded array (what an
// `omarchy bar set` without --json stored) or a comma list.
export function segmentsFromSetting(value) {
  if (Array.isArray(value)) return normalizeSegments(value)
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
  processCount: 5,
  barIntervalMs: 1000,
  panelIntervalMs: 2000,
  networkInterface: "auto",
  gpuDevice: "auto",
  integratedGpuDevice: "auto",
  diskDevice: "auto",
  diskFallbackWithoutGpu: true,
  barPalette: "theme",
  barLabels: "glyph",
  rateUnit: "bytes"
}

export var BAR_PALETTES = ["theme", "heat", "vivid"]

export var BAR_LABEL_MODES = ["glyph", "letter", "none"]

export var RATE_UNITS = ["bytes", "bits"]

export function readSettings(raw) {
  var r = raw && typeof raw === "object" ? raw : {}
  var d = SETTING_DEFAULTS
  return {
    segments: segmentsFromSetting(r.segments),
    processCount: parseIntSetting(r.processCount, d.processCount, 1, 10),
    barIntervalMs: parseIntSetting(r.barIntervalMs, d.barIntervalMs, 250, 60000),
    panelIntervalMs: parseIntSetting(r.panelIntervalMs, d.panelIntervalMs, 500, 60000),
    networkInterface: normalizeDeviceSetting(r.networkInterface),
    gpuDevice: normalizeDeviceSetting(r.gpuDevice),
    integratedGpuDevice: normalizeIntegratedGpuDevice(r.integratedGpuDevice),
    diskDevice: normalizeDeviceSetting(r.diskDevice),
    diskFallbackWithoutGpu: parseBoolSetting(
      typeof r.diskFallbackWithoutGpu === "string" ? unquoteSetting(r.diskFallbackWithoutGpu) : r.diskFallbackWithoutGpu,
      d.diskFallbackWithoutGpu),
    barPalette: parseEnumSetting(r.barPalette, BAR_PALETTES, d.barPalette),
    barLabels: parseEnumSetting(r.barLabels, BAR_LABEL_MODES, d.barLabels),
    rateUnit: parseEnumSetting(r.rateUnit, RATE_UNITS, d.rateUnit)
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
  var p = patch && typeof patch === "object" ? patch : {}
  for (k in p) {
    if (Object.prototype.hasOwnProperty.call(p, k)) merged[k] = p[k]
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

// Display-time bar list. Never persist this result: a missing dedicated GPU
// substitutes disk for the configured gpu token when fallback is enabled.
export function effectiveSegments(configured, topologyReady, discreteGpuAvailable, fallbackEnabled, gpuInventoryOk) {
  var list = normalizeSegments(configured)
  if (!topologyReady || gpuInventoryOk === false) return list
  if (discreteGpuAvailable) return list
  if (fallbackEnabled === false) return list
  var hasGpu = false
  var i
  for (i = 0; i < list.length; i++) if (list[i] === "gpu") hasGpu = true
  if (!hasGpu) return list
  var seen = {}
  for (i = 0; i < list.length; i++) {
    if (list[i] === "gpu") continue
    seen[list[i]] = true
  }
  seen.disk = true
  var out = []
  for (i = 0; i < BAR_SEGMENTS.length; i++) {
    if (seen[BAR_SEGMENTS[i]]) out.push(BAR_SEGMENTS[i])
  }
  return out
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

export function normalizeIntegratedGpuDevice(value) {
  var s = normalizeDeviceSetting(value)
  if (s === "none") return "none"
  if (/^card[0-9]+$/.test(s)) return s
  return "auto"
}
