// Memory composition, swap, and DIMM identity from udev DMI.

import { clipStr, collapseSpaces, num } from "./core.mjs"

// vmstat pswpin/pswpout are cumulative pages; report KiB/s assuming 4 KiB
// pages (true on every arch Omarchy ships on).
export function swapRates(prevVm, currVm, dtS, pageKiB) {
  var page = pageKiB || 4
  if (!prevVm || !currVm || !(dtS > 0)) return { inKBs: 0, outKBs: 0 }
  return {
    inKBs: Math.max(0, currVm.swpin - prevVm.swpin) * page / dtS,
    outKBs: Math.max(0, currVm.swpout - prevVm.swpout) * page / dtS
  }
}

// Composition of physical RAM. Buffers count toward the Cache slice.
// Applications is whatever is neither free, cache, nor unreclaimable kernel
// slab — clamped at zero so a weird meminfo never yields a negative slice.
export function memComposition(mem) {
  if (!mem) return null
  var cache = mem.buf + mem.cac + mem.srec
  var kernel = Math.max(0, mem.slab - mem.srec)
  var free = mem.fre
  var apps = Math.max(0, mem.tot - free - cache - kernel)
  var used = mem.tot - mem.avl
  if (used < 0) used = 0
  return {
    appsK: apps,
    kernelK: kernel,
    cacheK: cache,
    freeK: free,
    totalK: mem.tot,
    usedK: used,
    usedPct: mem.tot > 0 ? 100 * used / mem.tot : 0
  }
}

export function swapUsage(mem) {
  if (!mem) return null
  var used = Math.max(0, mem.swtot - mem.swfre)
  return {
    totalK: mem.swtot,
    usedK: used,
    pct: mem.swtot > 0 ? 100 * used / mem.swtot : 0
  }
}

export var JUNK_RAM_TYPES = {
  unknown: 1, other: 1, none: 1, no: 1, not: 1, empty: 1, uninstalled: 1,
  "n/a": 1, n: 1, na: 1, ram: 1, dimm: 1, "<out of spec>": 1
}

export var JUNK_RAM_MAKERS = {
  unknown: 1, none: 1, "n/a": 1, n: 1, na: 1, "not specified": 1,
  "to be filled by o.e.m.": 1, oem: 1, "oem manufacturer": 1,
  manufacturer00: 1, manufacturer0: 1, defaultstring: 1, "default string": 1,
  "no dimm": 1, empty: 1, null: 1
}

export function ramTypeRanked(type) {
  var t = String(type || "")
  return /^(LP)?DDR|GDDR|HBM/i.test(t)
}

export function cleanRamMaker(value) {
  var t = collapseSpaces(value)
  if (!t) return ""
  if (JUNK_RAM_MAKERS[t.toLowerCase()]) return ""
  if (/^manufacturer\d+$/i.test(t)) return ""
  return clipStr(t, 48)
}

export function dimmGiB(bytes) {
  var n = num(bytes, 0)
  if (!(n > 0)) return 0
  var g = n / (1024 * 1024 * 1024)
  var r = Math.round(g)
  if (r > 0 && Math.abs(g - r) / r < 0.02) return r
  return Math.round(g * 10) / 10
}

export function formatRamKit(modules) {
  var list = Array.isArray(modules) ? modules : []
  if (list.length === 0) return ""
  var groups = []
  var order = []
  var i
  for (i = 0; i < list.length; i++) {
    var g = dimmGiB(list[i].bytes)
    if (!(g > 0)) continue
    var key = String(g)
    if (!groups[key]) {
      groups[key] = 0
      order.push(g)
    }
    groups[key]++
  }
  if (order.length === 0) return ""
  order.sort(function (a, b) { return b - a })
  var bits = []
  for (i = 0; i < order.length; i++) {
    var size = order[i]
    var count = groups[String(size)]
    var sizeText = (size % 1 === 0) ? String(size) : size.toFixed(1)
    if (count === 1 && order.length === 1) bits.push(sizeText + " GiB")
    else bits.push(count + "\u00d7" + sizeText + " GiB")
  }
  return bits.join(" + ")
}

export function formatRamMaker(modules) {
  var list = Array.isArray(modules) ? modules : []
  var seen = {}
  var names = []
  var i
  for (i = 0; i < list.length; i++) {
    var m = cleanRamMaker(list[i].maker)
    if (!m) continue
    var key = m.toLowerCase()
    if (seen[key]) continue
    seen[key] = true
    names.push(m)
    if (names.length >= 2) break
  }
  if (names.length === 1) return names[0]
  if (names.length === 2) return names[0] + " + " + names[1]
  return ""
}

export function parseUdevRam(text) {
  var empty = { type: "", speedMTs: null, label: "", maker: "", kit: "", modules: [] }
  if (typeof text !== "string" || text.length === 0) return empty
  var devices = {}
  var lines = text.split("\n")
  var i
  for (i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line.indexOf("E:") === 0) line = line.slice(2)
    var m = line.match(/^MEMORY_DEVICE_(\d+)_(.+?)=(.*)$/)
    if (!m) continue
    var id = m[1]
    if (!devices[id]) devices[id] = {}
    devices[id][m[2]] = m[3]
  }
  var types = []
  var configured = []
  var rated = []
  var modules = []
  for (var did in devices) {
    if (!Object.prototype.hasOwnProperty.call(devices, did)) continue
    var d = devices[did]
    if (d.PRESENT === "0") continue
    var size = num(d.SIZE, 0)
    if (!(size > 0)) continue
    var typ = collapseSpaces(d.TYPE)
    if (typ && !JUNK_RAM_TYPES[typ.toLowerCase()]) types.push(typ)
    var conf = num(d.CONFIGURED_SPEED_MTS, 0)
    var gts = num(d.CONFIGURED_SPEED_GTS, 0)
    if (conf > 0) configured.push(conf)
    else if (gts > 0) configured.push(Math.round(gts * 1000))
    var spd = num(d.SPEED_MTS, 0)
    var sgts = num(d.SPEED_GTS, 0)
    if (spd > 0) rated.push(spd)
    else if (sgts > 0) rated.push(Math.round(sgts * 1000))
    if (modules.length < 8) {
      modules.push({
        bytes: size,
        maker: cleanRamMaker(d.MANUFACTURER),
        part: clipStr(collapseSpaces(d.PART_NUMBER), 48)
      })
    }
  }
  var type = ""
  for (i = 0; i < types.length; i++) {
    if (ramTypeRanked(types[i])) { type = types[i]; break }
  }
  if (!type && types.length) type = types[0]
  var speed = null
  function minOf(list) {
    if (!list.length) return null
    var m = list[0]
    for (var j = 1; j < list.length; j++) if (list[j] < m) m = list[j]
    return m
  }
  speed = minOf(configured)
  if (speed === null) speed = minOf(rated)
  var maker = formatRamMaker(modules)
  var kit = formatRamKit(modules)
  var spec = formatRamLabel(type, speed)
  var bits = []
  if (maker && kit) bits.push(maker + " " + kit)
  else if (kit) bits.push(kit)
  else if (maker) bits.push(maker)
  if (spec) bits.push(spec)
  return {
    type: type,
    speedMTs: speed,
    maker: maker,
    kit: kit,
    modules: modules,
    label: bits.join(" · ")
  }
}

export function formatRamLabel(type, speedMTs) {
  var t = collapseSpaces(type)
  var n = num(speedMTs, null)
  if (t && n !== null && n > 0) return t + " " + Math.round(n) + " MT/s"
  if (t) return t
  if (n !== null && n > 0) return Math.round(n) + " MT/s"
  return ""
}

export function parseSystemMem(mem) {
  var swaps = []
  var zram = []
  var ram = { type: "", speedMTs: null, label: "", maker: "", kit: "", modules: [] }
  if (!mem || typeof mem !== "object") return { swaps: swaps, zram: zram, ram: ram }
  ram = parseUdevRam(mem.udevPayload)
  var i
  if (Array.isArray(mem.swaps)) {
    for (i = 0; i < mem.swaps.length && swaps.length < 16; i++) {
      var s = mem.swaps[i]
      if (!s || typeof s !== "object") continue
      var file = clipStr(s.file, 128)
      if (file === "") continue
      var kind = String(s.kind || "")
      if (kind !== "partition" && kind !== "file" && kind !== "zram") kind = "file"
      var sizeKb = num(s.sizeKb, null)
      if (sizeKb === null || sizeKb < 0) sizeKb = 0
      swaps.push({ file: file, kind: kind, sizeKb: sizeKb })
    }
  }
  if (Array.isArray(mem.zram)) {
    for (i = 0; i < mem.zram.length && zram.length < 8; i++) {
      var z = mem.zram[i]
      if (!z || typeof z !== "object") continue
      var dev = clipStr(z.dev, 16)
      if (!/^zram[0-9]+$/.test(dev)) continue
      var alg = clipStr(z.alg, 16)
      if (alg && !/^[A-Za-z0-9_+-]+$/.test(alg)) alg = ""
      var diskBytes = num(z.diskBytes, null)
      if (diskBytes === null || diskBytes < 0) diskBytes = 0
      zram.push({ dev: dev, alg: alg, diskBytes: diskBytes })
    }
  }
  return { swaps: swaps, zram: zram, ram: ram }
}
