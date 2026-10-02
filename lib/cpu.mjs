// CPU deltas, per-core usage keyed by cpu id, topology classification
// and the core grid layout.

import { clipStr, collapseSpaces, num } from "./core.mjs"
import { formatPct } from "./format.mjs"
import { parseCpuArray } from "./stream.mjs"

// Percentages since the previous sample. user folds in nice; system folds in
// irq+softirq; iowait and steal stay their own buckets so nothing is silently
// misattributed. Returns null when the counters did not advance.
export function cpuDelta(prev, curr) {
  if (!prev || !curr) return null
  var d = {
    user: (curr.user + curr.nice) - (prev.user + prev.nice),
    system: (curr.system + curr.irq + curr.softirq) - (prev.system + prev.irq + prev.softirq),
    iowait: curr.iowait - prev.iowait,
    steal: curr.steal - prev.steal,
    idle: curr.idle - prev.idle
  }
  // Clamp counter resets per-bucket first; only give up when nothing
  // advanced at all.
  for (var k in d) if (d[k] < 0) d[k] = 0
  var total = d.user + d.system + d.iowait + d.steal + d.idle
  if (total <= 0) return null
  var out = {}
  for (var j in d) out[j] = 100 * d[j] / total
  // busy = compute time (user+system). nonIdle is the bar glance:
  // anything that is not idle, including iowait and steal.
  out.busy = out.user + out.system
  out.nonIdle = out.user + out.system + out.iowait + out.steal
  return out
}

export function parseCpuCoreArray(value) {
  if (!Array.isArray(value)) return []
  var out = []
  for (var i = 0; i < value.length && out.length < 128; i++) {
    var c = parseCpuArray(value[i])
    if (!c) continue
    out.push(c)
  }
  return out
}

// Per-logical cpu ids that match a `cc` array. /proc/stat lists online
// CPUs only, so ids can be sparse; when the stream sends none, positions
// are the ids (older streams and fixtures).
export function parseCpuCoreIds(value, count) {
  var out = []
  var i
  if (Array.isArray(value) && value.length === count) {
    for (i = 0; i < count; i++) {
      var id = num(value[i], null)
      if (id === null || id < 0 || id > 4095 || Math.round(id) !== id) { out = null; break }
      out.push(id)
    }
    if (out) return out
    out = []
  }
  for (i = 0; i < count; i++) out.push(i)
  return out
}

// Per-logical non-idle percent, keyed by cpu id. Samples are matched by
// id, so a core that goes offline between samples (or comes back) never
// borrows another core's counters.
export function cpuCoreDeltas(prevCores, currCores, prevIds, currIds) {
  var prev = Array.isArray(prevCores) ? prevCores : []
  var curr = Array.isArray(currCores) ? currCores : []
  var pids = parseCpuCoreIds(prevIds, prev.length)
  var cids = parseCpuCoreIds(currIds, curr.length)
  var prevById = {}
  var i
  for (i = 0; i < prev.length; i++) prevById[pids[i]] = prev[i]
  var out = []
  for (i = 0; i < curr.length; i++) {
    var id = cids[i]
    var before = prevById[id]
    if (!before) continue
    var d = cpuDelta(before, curr[i])
    out.push({
      id: id,
      busy: d ? d.nonIdle : 0
    })
  }
  return out
}

export function cpuBarTooltip(d) {
  if (!d) return "CPU --"
  var text = "CPU " + formatPct(d.nonIdle)
  var bits = []
  if (d.iowait >= 1) bits.push(formatPct(d.iowait) + " iowait")
  if (d.steal >= 1) bits.push(formatPct(d.steal) + " steal")
  if (bits.length) text += " (" + bits.join(" · ") + ")"
  return text
}

export function parseCpuTopoEntry(e) {
  if (!e || typeof e !== "object") return null
  var id = num(e.id, null)
  if (id === null || id < 0 || id > 4095) return null
  var core = num(e.core, id)
  if (core === null || core < 0) core = id
  var cls = String(e.cls || "")
  if (cls !== "performance" && cls !== "efficiency" && cls !== "lowpower") cls = ""
  var maxKhz = num(e.maxKhz, 0)
  if (maxKhz === null || maxKhz < 0) maxKhz = 0
  var cap = num(e.cap, 0)
  if (cap === null || cap < 0) cap = 0
  var l3 = clipStr(e.l3, 64)
  var pkg = num(e.pkg, 0)
  if (pkg === null || pkg < 0) pkg = 0
  return {
    id: Math.round(id),
    core: Math.round(core),
    pkg: Math.round(pkg),
    cls: cls,
    maxKhz: maxKhz,
    cap: cap,
    l3: l3
  }
}

// core_id is only unique within a package; this is the key that is.
export function physicalCoreKey(e) {
  return String(e.pkg || 0) + ":" + String(e.core)
}

export function parseCpuTopo(list) {
  var out = []
  if (!Array.isArray(list)) return out
  for (var i = 0; i < list.length && out.length < 128; i++) {
    var e = parseCpuTopoEntry(list[i])
    if (e) out.push(e)
  }
  out.sort(function (a, b) { return a.id - b.id })
  return out
}

export function classifyUnlabeledCpus(topo) {
  var unlabeled = []
  var i
  for (i = 0; i < topo.length; i++) {
    if (!topo[i].cls) unlabeled.push(topo[i])
  }
  if (unlabeled.length === 0) return
  var useCap = false
  for (i = 0; i < unlabeled.length; i++) {
    if (unlabeled[i].cap > 0) { useCap = true; break }
  }
  var keys = []
  for (i = 0; i < unlabeled.length; i++) {
    var key = useCap ? unlabeled[i].cap : unlabeled[i].maxKhz
    keys.push(key)
  }
  keys.sort(function (a, b) { return a - b })
  var unique = []
  for (i = 0; i < keys.length; i++) {
    if (i === 0 || keys[i] !== keys[i - 1]) unique.push(keys[i])
  }
  if (unique.length === 0) {
    for (i = 0; i < unlabeled.length; i++) unlabeled[i].cls = "performance"
    return
  }
  var groups = []
  var current = [unique[0]]
  for (i = 1; i < unique.length; i++) {
    if (unique[i] > unique[i - 1] * 112 / 100) {
      groups.push(current)
      current = [unique[i]]
    } else {
      current.push(unique[i])
    }
  }
  groups.push(current)
  function groupIndex(key) {
    var g
    for (g = 0; g < groups.length; g++) {
      var j
      for (j = 0; j < groups[g].length; j++) {
        if (groups[g][j] === key) return g
      }
    }
    return groups.length - 1
  }
  var last = groups.length - 1
  var three = groups.length >= 3
  for (i = 0; i < unlabeled.length; i++) {
    var k = useCap ? unlabeled[i].cap : unlabeled[i].maxKhz
    var gi = groupIndex(k)
    if (groups.length === 1 || gi === last) unlabeled[i].cls = "performance"
    else if (three && gi === 0) unlabeled[i].cls = "lowpower"
    else unlabeled[i].cls = "efficiency"
  }
}

export function classifyCpuTopology(topo) {
  var values = parseCpuTopo(topo)
  classifyUnlabeledCpus(values)
  for (var i = 0; i < values.length; i++) {
    if (!values[i].cls) values[i].cls = "performance"
  }
  return values
}

export function cpuClassCounts(topo) {
  var phys = {}
  var i
  for (i = 0; i < topo.length; i++) {
    var key = physicalCoreKey(topo[i]) + ":" + topo[i].cls
    if (!phys[key]) phys[key] = topo[i].cls
  }
  var counts = { performance: 0, efficiency: 0, lowpower: 0 }
  for (var k in phys) {
    if (!Object.prototype.hasOwnProperty.call(phys, k)) continue
    counts[phys[k]]++
  }
  return counts
}

export function formatCpuClassMix(counts) {
  if (!counts) return ""
  var bits = []
  if (counts.performance) bits.push(counts.performance + "P")
  if (counts.efficiency) bits.push(counts.efficiency + "E")
  if (counts.lowpower) bits.push(counts.lowpower + "LP")
  if (bits.length < 2) return ""
  return bits.join(" · ")
}

export function coreGridLayout(topo, usageById) {
  var classified = classifyCpuTopology(topo)
  var usage = usageById && typeof usageById === "object" ? usageById : {}
  var byCore = {}
  var coreOrder = []
  var i
  for (i = 0; i < classified.length; i++) {
    var e = classified[i]
    var key = physicalCoreKey(e)
    if (!byCore[key]) {
      byCore[key] = { core: e.core, pkg: e.pkg, cls: e.cls, logicals: [], usage: 0 }
      coreOrder.push(key)
    }
    byCore[key].logicals.push(e.id)
    var u = num(usage[e.id], 0)
    if (u > byCore[key].usage) byCore[key].usage = u
    if (e.cls === "performance") byCore[key].cls = "performance"
  }

  var kinds = ["performance", "efficiency", "lowpower"]
  var present = {}
  for (i = 0; i < coreOrder.length; i++) present[byCore[coreOrder[i]].cls] = true
  var kindCount = 0
  for (i = 0; i < kinds.length; i++) if (present[kinds[i]]) kindCount++

  function cellsOf(kind) {
    var cells = []
    for (var c = 0; c < coreOrder.length; c++) {
      var cell = byCore[coreOrder[c]]
      if (kind && cell.cls !== kind) continue
      cells.push({
        core: cell.core,
        pkg: cell.pkg,
        cls: cell.cls,
        logicals: cell.logicals.slice(),
        usage: cell.usage
      })
    }
    return cells
  }

  if (kindCount <= 1) {
    return { mode: "uniform", rows: [{ kind: "same", cells: cellsOf(null) }] }
  }
  var rows = []
  for (i = 0; i < kinds.length; i++) {
    var cells = cellsOf(kinds[i])
    if (cells.length) rows.push({ kind: kinds[i], cells: cells })
  }
  return { mode: "hybrid", rows: rows }
}

export function parseSystemCpu(c) {
  var empty = {
    modelName: "", vendorId: "", physCores: null, threads: null,
    cacheKb: null, mhzNow: null, governor: "", maxMhz: null,
    topo: [], classes: { performance: 0, efficiency: 0, lowpower: 0 }
  }
  if (!c || typeof c !== "object") return empty
  var gov = clipStr(c.governor, 32)
  if (gov && !/^[A-Za-z0-9._+-]+$/.test(gov)) gov = ""
  var topo = classifyCpuTopology(c.topo)
  var physCores = (function () { var n = num(c.physCores, null); return n !== null && n > 0 ? Math.round(n) : null })()
  var threads = (function () { var n = num(c.threads, null); return n !== null && n > 0 ? Math.round(n) : null })()
  if (topo.length > 0) {
    var seen = {}
    var phys = 0
    for (var i = 0; i < topo.length; i++) {
      var ck = physicalCoreKey(topo[i])
      if (!seen[ck]) { seen[ck] = true; phys++ }
    }
    physCores = phys
    threads = topo.length
  }
  return {
    modelName: clipStr(c.modelName, 128),
    vendorId: clipStr(c.vendorId, 32),
    physCores: physCores,
    threads: threads,
    cacheKb: (function () { var n = num(c.cacheKb, null); return n !== null && n >= 0 ? n : null })(),
    mhzNow: (function () { var n = num(c.mhzNow, null); return n !== null && n >= 0 ? n : null })(),
    governor: gov,
    maxMhz: (function () { var n = num(c.maxMhz, null); return n !== null && n >= 0 ? n : null })(),
    topo: topo,
    classes: cpuClassCounts(topo)
  }
}

// Display names for HardwareHero. Raw firmware / PCI-DB strings stay in
// the parsed identity objects so tests can still see the unfiltered text.
export function cleanCpuName(raw) {
  var name = collapseSpaces(raw)
  if (!name) return ""
  name = name.replace(/\(R\)|\(TM\)|\(tm\)|\(r\)/g, "")
  name = name.replace(/\s*CPU\s*@\s*[\d.]+\s*GHz/i, "")
  name = name.replace(/\s*\d+-Core Processor.*/i, "")
  name = name.replace(/\s+Processor\s*$/i, "")
  name = collapseSpaces(name.replace(/[ ,]+$/g, ""))
  return name || collapseSpaces(raw)
}

export function formatCache(kb) {
  var n = num(kb, null)
  if (n === null || n < 0) return "--"
  if (n >= 1024) return Math.round(n / 1024) + " MB"
  return Math.round(n) + " KB"
}
