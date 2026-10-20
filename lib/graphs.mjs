// Shared measurement and time geometry for every graph layout. Mirroring is
// a drawing choice: stored rates and summaries remain positive magnitudes.
import { num } from "./core.mjs"

export function graphValue(point, key) {
  if (point && point.gap === 1) return null
  var value = num(point && typeof point === "object" ? point[key] : null, null)
  return value !== null && value >= 0 ? value : null
}

export function graphWindow(points, windowSeconds) {
  if (!Array.isArray(points)) return []
  var end = null
  for (var i = points.length - 1; i >= 0 && end === null; i--) end = num(points[i] && points[i].t, null)
  if (end === null) return []
  var start = end - Math.max(1, num(windowSeconds, 60))
  return points.filter(function (point) {
    var t = num(point && point.t, null)
    return t !== null && t >= start && t <= end
  })
}

function totalAt(point, keys) {
  var total = 0
  if (!keys.length) return null
  for (var i = 0; i < keys.length; i++) {
    var value = graphValue(point, keys[i])
    if (value === null) return null
    total += value
  }
  return total
}

export function graphStats(points, keys) {
  var count = 0, sum = 0, peak = 0
  for (var i = 0; i < points.length; i++) {
    var value = totalAt(points[i], keys)
    if (value === null) continue
    count++
    sum += value
    peak = Math.max(peak, value)
  }
  return count ? { avg: sum / count, peak: peak } : null
}

function niceCeiling(value) {
  if (!(value > 0)) return 1
  var power = Math.pow(10, Math.floor(Math.log(value) / Math.LN10))
  var m = value / power
  return (m <= 1 ? 1 : m <= 2 ? 2 : m <= 2.5 ? 2.5 : m <= 5 ? 5 : 10) * power
}

export function graphAxis(points, keys, options) {
  var cfg = options || {}
  var lo = Infinity, hi = -Infinity
  for (var i = 0; i < points.length; i++) {
    var values = cfg.stacked ? [totalAt(points[i], keys)] : keys.map(function (key) { return graphValue(points[i], key) })
    for (var j = 0; j < values.length; j++) {
      if (values[j] === null) continue
      lo = Math.min(lo, values[j])
      hi = Math.max(hi, values[j])
    }
  }
  if (hi === -Infinity) { lo = 0; hi = 0 }
  var fixed = Math.max(0, num(cfg.fixedMax, 0))
  var min = 0, max = fixed || Math.max(niceCeiling(hi), num(cfg.minimumMax, 0))
  if (cfg.band && hi > lo) {
    var pad = Math.max(hi - lo, Math.max(1e-9, hi) * 0.03) * 0.25
    min = Math.max(0, lo - pad)
    max = fixed > 0 ? Math.min(fixed, hi + pad) : hi + pad
  }
  if (!(max > min)) max = min + 1
  return { min: min, max: max, lo: lo, hi: hi }
}

// Inclusive index ranges. Missing fields, backwards time, and long gaps
// break a run; a lone measured point remains visible as a dot.
export function graphRuns(points, keys, gapSeconds) {
  var runs = [], start = -1, previous = null
  var gap = Math.max(0, num(gapSeconds, 30))
  for (var i = 0; i < points.length; i++) {
    var t = num(points[i] && points[i].t, null)
    var valid = t !== null && totalAt(points[i], keys) !== null
    if (start >= 0 && (!valid || t < previous || t - previous > gap)) {
      runs.push({ start: start, end: i - 1 })
      start = -1
    }
    if (valid && start < 0) start = i
    previous = valid ? t : null
  }
  if (start >= 0) runs.push({ start: start, end: points.length - 1 })
  return runs
}

// Hover follows connected samples, with a small snap radius around isolated
// endpoints. A blank gap must not present an old reading as its measurement.
export function graphHoverIndex(points, timestamp, gapSeconds, snapSeconds) {
  var target = num(timestamp, null)
  if (target === null) return -1
  var best = -1, distance = Infinity, connected = false
  for (var i = 0; i < points.length; i++) {
    var t = num(points[i] && points[i].t, null)
    if (t === null) continue
    var delta = Math.abs(t - target)
    if (delta < distance) { best = i; distance = delta }
    var prev = i > 0 ? num(points[i - 1] && points[i - 1].t, null) : null
    if (prev !== null && prev <= target && target <= t && t - prev <= gapSeconds) connected = true
  }
  return connected || distance <= Math.max(0, num(snapSeconds, 0)) ? best : -1
}

// The compact bar uses the same minute history as the panel. Percentage
// plots match their text (CPU includes iowait/steal, Drives uses busy), and
// network retains both positive directions on one shared rate scale.
export function barTrendPoints(points, metric) {
  var visible = graphWindow(points, 60)
  if (metric === "net") return visible
  var keys = metric === "cpu" ? ["u", "s", "io", "st"] : metric === "mem" ? ["u"]
    : metric === "gpu" || metric === "disk" ? ["b"] : []
  if (!keys.length) return []
  return visible.map(function (point) { return { t: point.t, v: totalAt(point, keys) } })
}
