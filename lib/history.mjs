// Fine 60 s history windows, 10 s mean buckets over one hour, and the
// persisted history file format.

import { clipStr, hasOwn, num } from "./core.mjs"

// Append a timestamped point while preserving a real time window even when
// barIntervalMs is customized. A clock/counter reset starts a fresh window.
export function pushTimedWindow(history, point, timestamp, windowSeconds, maxLen) {
  var ts = num(timestamp, null)
  if (ts === null) return Array.isArray(history) ? history.slice() : []
  var seconds = Math.max(1, num(windowSeconds, 60))
  var limit = Math.max(2, Math.round(num(maxLen, 242)))
  var next = Array.isArray(history) ? history.slice() : []
  if (next.length > 0 && num(next[next.length - 1].t, ts) > ts) next = []
  var stamped = {}
  if (point && typeof point === "object") {
    for (var key in point)
      if (Object.prototype.hasOwnProperty.call(point, key)) stamped[key] = point[key]
  }
  stamped.t = ts
  next.push(stamped)
  var cutoff = ts - seconds
  while (next.length > 0 && num(next[0].t, ts) < cutoff) next.shift()
  while (next.length > limit) next.shift()
  return next
}

export function pushBucket(history, point, timestamp, bucketSeconds, windowSeconds) {
  var ts = num(timestamp, null)
  var next = Array.isArray(history) ? history.slice() : []
  if (ts === null) return next
  var width = Math.max(1, num(bucketSeconds, 10))
  var span = Math.max(width, num(windowSeconds, 3600))
  var start = Math.floor(ts / width) * width
  if (next.length > 0 && num(next[next.length - 1].t, start) > start) next = []
  var last = next.length > 0 ? next[next.length - 1] : null
  var key
  var src = point && typeof point === "object" ? point : {}
  if (last && num(last.t, null) === start) {
    var merged = {}
    var n = Math.max(1, num(last.n, 1))
    for (key in last) if (hasOwn(last, key)) merged[key] = last[key]
    for (key in src) {
      if (!hasOwn(src, key)) continue
      var v = num(src[key], null)
      if (v === null) continue
      var prev = num(last[key], null)
      merged[key] = prev === null ? v : (prev * n + v) / (n + 1)
    }
    merged.n = n + 1
    merged.t = start
    next[next.length - 1] = merged
  } else {
    var fresh = { t: start, n: 1 }
    for (key in src) {
      if (!hasOwn(src, key)) continue
      var val = num(src[key], null)
      if (val !== null) fresh[key] = val
    }
    next.push(fresh)
  }
  var cutoff = start - span
  while (next.length > 0 && num(next[0].t, start) <= cutoff) next.shift()
  var limit = Math.ceil(span / width) + 2
  while (next.length > limit) next.shift()
  return next
}

// Buckets from a previous run, prepended to what the live run has already
// collected. Only buckets older than the first live bucket survive, so the
// live data is never overwritten by stale averages.
export function mergeBuckets(older, newer) {
  var live = Array.isArray(newer) ? newer : []
  var old = Array.isArray(older) ? older : []
  if (old.length === 0) return live.slice()
  var firstLive = live.length > 0 ? num(live[0].t, null) : null
  var out = []
  for (var i = 0; i < old.length; i++) {
    if (firstLive !== null && num(old[i].t, firstLive) >= firstLive) break
    out.push(old[i])
  }
  return out.concat(live)
}

export var HISTORY_FILE_VERSION = 1

export var HISTORY_SERIES = ["cpu", "mem", "gpu", "net", "disk"]

// One persisted series: only objects with a finite `t` inside the window
// and finite numeric fields survive; order by t, duplicate t keeps the
// later entry, length capped to the window.
export function sanitizeBuckets(list, nowTs, windowSeconds, bucketSeconds) {
  if (!Array.isArray(list)) return []
  var now = num(nowTs, null)
  if (now === null) return []
  var span = Math.max(1, num(windowSeconds, 3600))
  var width = Math.max(1, num(bucketSeconds, 10))
  var byT = {}
  var ts = []
  for (var i = 0; i < list.length && i < 4096; i++) {
    var e = list[i]
    if (!e || typeof e !== "object") continue
    var t = num(e.t, null)
    if (t === null || t < now - span || t > now + 60) continue
    var clean = { t: t, n: Math.max(1, Math.round(num(e.n, 1) || 1)) }
    for (var k in e) {
      if (!hasOwn(e, k) || k === "t" || k === "n") continue
      if (!/^[a-z][a-zA-Z0-9]{0,15}$/.test(k)) continue
      var v = num(e[k], null)
      if (v === null) continue
      clean[k] = v
    }
    if (!hasOwn(byT, String(t))) ts.push(t)
    byT[String(t)] = clean
  }
  ts.sort(function (a, b) { return a - b })
  var out = []
  for (var j = 0; j < ts.length; j++) out.push(byT[String(ts[j])])
  var limit = Math.ceil(span / width) + 2
  while (out.length > limit) out.shift()
  return out
}

// Parsed history file → { series: {cpu,mem,gpu,net,disk}, tags: {gpu,iface,disk} }
// or null when the file is not ours. Tags say which card / interface /
// disk the gpu, net and disk series were recorded for; the store only
// reuses a series whose tag still matches.
export function loadHistoryFile(data, nowTs, windowSeconds, bucketSeconds) {
  if (!data || typeof data !== "object") return null
  if (data.v !== HISTORY_FILE_VERSION) return null
  var series = {}
  var any = false
  for (var i = 0; i < HISTORY_SERIES.length; i++) {
    var name = HISTORY_SERIES[i]
    series[name] = sanitizeBuckets(data[name], nowTs, windowSeconds, bucketSeconds)
    if (series[name].length > 0) any = true
  }
  var tags = data.tags && typeof data.tags === "object" ? data.tags : {}
  return {
    series: series,
    tags: {
      gpu: clipStr(tags.gpu, 32),
      iface: clipStr(tags.iface, 64),
      disk: clipStr(tags.disk, 64)
    },
    any: any
  }
}

export function historyFilePayload(series, tags, nowTs) {
  var out = { v: HISTORY_FILE_VERSION, saved: num(nowTs, 0), tags: {} }
  var t = tags && typeof tags === "object" ? tags : {}
  out.tags.gpu = clipStr(t.gpu, 32)
  out.tags.iface = clipStr(t.iface, 64)
  out.tags.disk = clipStr(t.disk, 64)
  var src = series && typeof series === "object" ? series : {}
  for (var i = 0; i < HISTORY_SERIES.length; i++) {
    var name = HISTORY_SERIES[i]
    out[name] = Array.isArray(src[name]) ? src[name] : []
  }
  return out
}
