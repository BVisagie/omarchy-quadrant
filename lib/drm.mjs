// DRM fdinfo snapshots: busy percent per card and per process, idle
// residency fallback, live-metric overlay.

import { clamp, clipStr, num } from "./core.mjs"

export function drmEnginePreferred(name) {
  var n = String(name || "").toLowerCase()
  return n.indexOf("render") >= 0 || n === "gfx" || n.indexOf("compute") >= 0
}

export function parseDrmSnapshot(data) {
  if (!data || typeof data !== "object" || data.ok === false) return null
  var tsNs = num(data.tsNs, null)
  if (tsNs === null || tsNs < 0) return null
  var engines = []
  var list = Array.isArray(data.engines) ? data.engines : []
  var i
  for (i = 0; i < list.length && engines.length < 256; i++) {
    var e = list[i]
    if (!e || typeof e !== "object") continue
    var name = clipStr(e.name, 32)
    if (!name) continue
    var pid = num(e.pid, null)
    engines.push({
      client: clipStr(e.client, 64),
      pid: pid !== null && pid > 0 ? Math.round(pid) : null,
      name: name,
      ns: num(e.ns, null),
      cycles: num(e.cycles, null),
      total: num(e.total, null),
      capacity: Math.max(1, num(e.capacity, 1) || 1)
    })
  }
  var clients = []
  var cl = Array.isArray(data.clients) ? data.clients : []
  for (i = 0; i < cl.length && clients.length < 256; i++) {
    var c = cl[i]
    if (!c || typeof c !== "object") continue
    var cpid = num(c.pid, null)
    if (cpid === null || cpid <= 0) continue
    clients.push({
      pid: Math.round(cpid),
      comm: clipStr(c.comm, 128),
      client: clipStr(c.client, 64),
      dedicated: Math.max(0, num(c.dedicated, 0) || 0),
      shared: Math.max(0, num(c.shared, 0) || 0)
    })
  }
  var rc6 = []
  var rc = Array.isArray(data.rc6) ? data.rc6 : []
  for (i = 0; i < rc.length && rc6.length < 8; i++) {
    if (!rc[i] || typeof rc[i] !== "object") continue
    var ms = num(rc[i].ms, null)
    if (ms === null || ms < 0) continue
    rc6.push({ id: clipStr(rc[i].id, 128), card: clipStr(rc[i].card, 16), ms: ms })
  }
  return {
    tsNs: tsNs,
    slot: clipStr(data.slot, 32),
    engines: engines,
    clients: clients,
    rc6: rc6,
    memDedicated: Math.max(0, num(data.memDedicated, 0) || 0),
    memShared: Math.max(0, num(data.memShared, 0) || 0)
  }
}

// Busy nanoseconds per engine name over one interval, divided by the
// engine's capacity so a multi-instance engine (two video decoders) tops
// out at 100%. `filterPid` restricts the sum to one process.
export function drmEngineBusyNs(prev, curr, dtNs, filterPid) {
  var before = {}
  var i
  for (i = 0; i < prev.engines.length; i++) {
    var p = prev.engines[i]
    before[p.client + "\t" + p.name] = p
  }
  var totals = {}
  var saw = false
  for (i = 0; i < curr.engines.length; i++) {
    var c = curr.engines[i]
    if (filterPid !== undefined && filterPid !== null && c.pid !== filterPid) continue
    saw = true
    var prevE = before[c.client + "\t" + c.name]
    var cap = c.capacity > 0 ? c.capacity : 1
    if (c.ns !== null) {
      var prevNs = prevE && prevE.ns !== null ? prevE.ns : c.ns
      var delta = c.ns - prevNs
      if (delta > 0) totals[c.name] = (totals[c.name] || 0) + delta / cap
    } else if (c.cycles !== null && c.total !== null && prevE && prevE.cycles !== null && prevE.total !== null) {
      var dBusy = c.cycles - prevE.cycles
      var dTotal = c.total - prevE.total
      if (dBusy > 0 && dTotal > 0) {
        totals[c.name] = (totals[c.name] || 0) + (dBusy / dTotal) * dtNs
      }
    }
  }
  return saw ? totals : null
}

export function drmBusyFromTotals(totals, dtNs) {
  var names = Object.keys(totals)
  if (names.length === 0) return 0
  var preferred = []
  var all = []
  for (var i = 0; i < names.length; i++) {
    all.push(totals[names[i]])
    if (drmEnginePreferred(names[i])) preferred.push(totals[names[i]])
  }
  var chosen = preferred.length ? Math.max.apply(null, preferred) : Math.max.apply(null, all)
  return clamp(100 * chosen / dtNs, 0, 100)
}

// Per-process GPU rows from two snapshots: busy % of the preferred engine
// (render/gfx/compute, else the busiest) plus resident memory from the
// current snapshot. Processes with no engine time and no memory are
// dropped; the rest are sorted by busy, then memory.
// Longest gap between two snapshots that still yields a rate. The store
// passes a multiple of its panel cadence; 10 s is the default for callers
// that have no cadence to offer.
export function drmMaxIntervalNs(maxSeconds) {
  var s = num(maxSeconds, null)
  if (s === null || !(s > 0)) s = 10
  return s * 1e9
}

export function drmProcessRows(prev, curr, maxSeconds) {
  if (!prev || !curr) return []
  var dtNs = curr.tsNs - prev.tsNs
  if (!(dtNs >= 4e8 && dtNs <= drmMaxIntervalNs(maxSeconds))) return []
  var pids = {}
  var order = []
  var i
  function slot(pid) {
    if (!pids[pid]) {
      pids[pid] = { pid: pid, comm: "", busy: 0, dedicated: 0, shared: 0 }
      order.push(pid)
    }
    return pids[pid]
  }
  for (i = 0; i < curr.clients.length; i++) {
    var c = curr.clients[i]
    var row = slot(c.pid)
    row.dedicated += c.dedicated
    row.shared += c.shared
    if (!row.comm && c.comm) row.comm = c.comm
  }
  for (i = 0; i < curr.engines.length; i++) {
    if (curr.engines[i].pid !== null) slot(curr.engines[i].pid)
  }
  var out = []
  for (i = 0; i < order.length; i++) {
    var r = pids[order[i]]
    var totals = drmEngineBusyNs(prev, curr, dtNs, r.pid)
    r.busy = totals ? drmBusyFromTotals(totals, dtNs) : 0
    if (r.busy > 0 || r.dedicated > 0 || r.shared > 0) out.push(r)
  }
  out.sort(function (a, b) {
    if (b.busy !== a.busy) return b.busy - a.busy
    if (b.dedicated !== a.dedicated) return b.dedicated - a.dedicated
    return a.pid - b.pid
  })
  return out.slice(0, 32)
}

export function drmBusyFromEngines(prev, curr, dtNs) {
  var totals = drmEngineBusyNs(prev, curr, dtNs, null)
  if (!totals) return null
  return drmBusyFromTotals(totals, dtNs)
}

export function drmBusyFromRc6(prev, curr, dtNs) {
  var dtMs = dtNs / 1e6
  if (!(dtMs > 0)) return null
  var before = {}
  var i
  for (i = 0; i < prev.rc6.length; i++) before[prev.rc6[i].id] = prev.rc6[i].ms
  var best = null
  for (i = 0; i < curr.rc6.length; i++) {
    var start = before[curr.rc6[i].id]
    if (start === undefined) continue
    var idle = (curr.rc6[i].ms - start) * 100 / dtMs
    var busy = clamp(100 - idle, 0, 100)
    best = best === null ? busy : Math.max(best, busy)
  }
  return best
}

export function drmBusyPercent(prev, curr, maxSeconds) {
  if (!prev || !curr) return null
  var dtNs = curr.tsNs - prev.tsNs
  if (!(dtNs >= 4e8 && dtNs <= drmMaxIntervalNs(maxSeconds))) return null
  var fromEngines = drmBusyFromEngines(prev, curr, dtNs)
  if (fromEngines !== null) return fromEngines
  return drmBusyFromRc6(prev, curr, dtNs)
}

export function drmMemoryKind(snap) {
  if (!snap) return "unknown"
  if (snap.memDedicated > 0) return "vram"
  if (snap.memShared > 0) return "shared"
  return "unknown"
}

export function mergeGpuLive(base, drmBusy, drmSnap) {
  var out = {}
  var k
  if (base && typeof base === "object") {
    for (k in base) {
      if (Object.prototype.hasOwnProperty.call(base, k)) out[k] = base[k]
    }
  }
  if (out.busy !== null && out.busy !== undefined) {
    if (!out.busySource) out.busySource = "sysfs"
  } else if (drmBusy !== null && drmBusy !== undefined) {
    out.busy = drmBusy
    out.busySource = "drm"
  }
  if (drmSnap) {
    if (out.vramTotal) {
      if (!out.memKind) out.memKind = "vram"
    } else if (drmSnap.memDedicated > 0) {
      out.vramUsed = drmSnap.memDedicated
      out.memKind = "vram"
    } else if (drmSnap.memShared > 0) {
      out.vramUsed = drmSnap.memShared
      out.memKind = "shared"
    }
    if (drmSnap.memShared > 0) out.sharedUsed = drmSnap.memShared
  }
  return out
}
