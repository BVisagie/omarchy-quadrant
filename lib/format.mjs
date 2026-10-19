// Human-readable formatting of bytes, rates, percentages, clocks and
// durations.

import { clamp, num } from "./core.mjs"

export function formatUnit(value, units, suffix) {
  var n = num(value, null)
  if (n === null || n < 0) return "--"
  var i = 0
  while (n >= 1024 && i < units.length - 1) { n /= 1024; i++ }
  var rounded = Math.round(n * 10) / 10
  var text = (i > 0 && n < 10 && rounded % 1 !== 0) ? rounded.toFixed(1) : String(Math.round(n))
  return text + " " + units[i] + suffix
}

export function formatBytes(n) {
  return formatUnit(n, ["B", "KiB", "MiB", "GiB", "TiB"], "")
}

export function formatRate(bps) {
  return formatUnit(bps, ["B", "KiB", "MiB", "GiB"], "/s")
}

// Network rate in the user's unit: bytes ("1.2 MiB/s") or bits ("9.6 Mb/s").
export function formatRateUnit(bps, unit) {
  if (String(unit) !== "bits") return formatRate(bps)
  var n = num(bps, null)
  if (n === null || n < 0) return "--"
  var bits = n * 8
  var units = ["b", "kb", "Mb", "Gb", "Tb"]
  var i = 0
  while (bits >= 1000 && i < units.length - 1) { bits /= 1000; i++ }
  var rounded = Math.round(bits * 10) / 10
  var text = (i > 0 && bits < 10 && rounded % 1 !== 0) ? rounded.toFixed(1) : String(Math.round(bits))
  return text + " " + units[i] + "/s"
}

// At most four characters including the binary-unit marker. Promote before
// rounded values overflow; rates beyond the final unit use a bounded lower
// bound. Full rates remain available in the tooltip and panel.
export function formatRateCompact(bps) {
  var n = num(bps, null)
  if (n === null || n < 0) return "--"
  var units = ["B", "K", "M", "G", "T", "P", "E"]
  var i = 0
  while (n >= 1024 && i < units.length - 1) { n /= 1024; i++ }
  if (i === 0) {
    var rb = Math.round(n)
    if (rb < 1000) return String(rb) + "B"
    n = n / 1024
    i = 1
  }
  // Promote rounded 1000–1024 values before they exceed four characters.
  // Even hostile finite inputs stay bounded; full rates remain in tooltips.
  if (Math.round(n) >= 1000) {
    if (i === units.length - 1) return ">99E"
    n /= 1024
    i++
  }
  var text
  if (n < 10) {
    text = (Math.round(n * 10) / 10).toFixed(1)
    if (text === "10.0") text = "10"
  } else {
    text = String(Math.round(n))
  }
  return text + units[i]
}

export function formatKiB(kib) {
  var n = num(kib, null)
  if (n === null || n < 0) return "--"
  return formatBytes(n * 1024)
}

export function formatPct(value, digits) {
  var n = num(value, null)
  if (n === null) return "--"
  if (digits === 1) return (Math.round(n * 10) / 10).toFixed(1) + "%"
  return Math.round(clamp(n, 0, 1000)) + "%"
}

export function formatTemp(c, unit) {
  var n = num(c, null)
  if (n === null) return "--"
  return unit === "fahrenheit" ? Math.round(n * 9 / 5 + 32) + "°F" : Math.round(n) + "°C"
}

export function formatMhz(v) {
  var n = num(v, null)
  return n === null ? "--" : Math.round(n) + " MHz"
}

// GPU DPM can park the clock at 0. Call that IDLE rather than "0 MHz".
// CPU frequency still uses formatMhz — a parked core is not idle silicon.
export function formatGpuClock(v) {
  var n = num(v, null)
  if (n === null) return "--"
  if (n <= 0) return "IDLE"
  return formatMhz(n)
}

export function formatWatts(v) {
  var n = num(v, null)
  if (n === null) return "--"
  return (n < 10 ? (Math.round(n * 10) / 10).toFixed(1) : String(Math.round(n))) + " W"
}

export function formatLoad(v) {
  var n = num(v, null)
  return n === null ? "--" : (Math.round(n * 100) / 100).toFixed(2)
}

export function formatUptime(seconds) {
  var s = num(seconds, null)
  if (s === null || s < 0) return "--"
  var d = Math.floor(s / 86400)
  var h = Math.floor((s % 86400) / 3600)
  var m = Math.floor((s % 3600) / 60)
  if (d > 0) return d + "d " + h + "h"
  if (h > 0) return h + "h " + m + "m"
  return m + "m"
}
