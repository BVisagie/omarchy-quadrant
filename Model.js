// Quadrant data model — pure functions only.
//
// This file is loaded two ways:
//   - Quickshell/QML:  import "Model.js" as Model   (top-level functions)
//   - Node.js tests:   const Model = require("../Model.js")
//
// Everything here is side-effect free so the whole data layer is testable
// with `node --test` against captured fixtures. Scripts only ever ship raw
// counters plus a timestamp; every delta, rate, and percentage is computed
// here.

// ---------------------------------------------------------------- generics

function clamp(value, lo, hi) {
  var n = Number(value)
  if (!isFinite(n)) return lo
  return n < lo ? lo : (n > hi ? hi : n)
}

// Coerce to a finite number or return fallback (null when omitted).
// null/undefined/"" mean "no data", never 0.
function num(value, fallback) {
  if (value === null || value === undefined || value === "") return fallback === undefined ? null : fallback
  var n = Number(value)
  if (isFinite(n)) return n
  return fallback === undefined ? null : fallback
}

function nonNeg(value) {
  var n = num(value, 0)
  return n < 0 ? 0 : n
}

function safeJson(line) {
  if (typeof line !== "string" || line.length === 0) return null
  try {
    var data = JSON.parse(line)
    return (data && typeof data === "object") ? data : null
  } catch (e) {
    return null
  }
}

// omarchy bar set stores JSON strings; a persist of '"nvme0n1"' can arrive
// with the wrapping quotes still attached. Empty after strip is auto.
function normalizeDeviceSetting(value) {
  var s = String(value === null || value === undefined ? "" : value)
  s = s.replace(/^\s+|\s+$/g, "")
  if (s.length >= 2 && s.charAt(0) === '"' && s.charAt(s.length - 1) === '"')
    s = s.slice(1, -1).replace(/^\s+|\s+$/g, "")
  if (s === "") return "auto"
  return s
}

// ------------------------------------------------------------ stream sample
//
// One line of quadrant-stream output:
// {
//   "v": 1, "ts": 1756560000.12,
//   "cpu": [user, nice, system, idle, iowait, irq, softirq, steal],  // jiffies
//   "mem": { "tot","fre","avl","buf","cac","srec","slab","swtot","swfre" }, // KiB
//   "psi": { "cs10","cs60","cs300","cf10","ms10","ms60","ms300","mf10" } | null,
//   "vm":  { "swpin","swpout" },                  // pages, cumulative
//   "net": [ { "n","rx","tx" } ],                 // bytes, cumulative
//   "disk": [ { "n","rd","rs","wr","ws","io" } ],  // diskstats, cumulative
//   "r4":  [ { "n","m" } ], "r6": [ { "n","m" }], // default routes + metric
//   "gpu": { "busy","mb","vrU","vrT","t","w","mhz","fc","fm","eng","kind" } | null,
//   "t": 52.0 | null,                             // CPU package temp, deg C
//   "load": [l1, l5, l15],
//   "up": 12345.6, "cores": 16,
//   "cf": 4200 | null                             // CPU scaling_cur_freq, MHz
// }

function parseCpuArray(value) {
  if (!Array.isArray(value) || value.length < 8) return null
  var out = []
  for (var i = 0; i < 8; i++) {
    var n = num(value[i], null)
    if (n === null || n < 0) return null
    out.push(n)
  }
  return { user: out[0], nice: out[1], system: out[2], idle: out[3],
           iowait: out[4], irq: out[5], softirq: out[6], steal: out[7] }
}

function parseStreamMem(value) {
  if (!value || typeof value !== "object") return null
  var keys = ["tot", "fre", "avl", "buf", "cac", "srec", "slab", "swtot", "swfre"]
  var out = {}
  for (var i = 0; i < keys.length; i++) {
    var n = num(value[keys[i]], null)
    if (n === null || n < 0) return null
    out[keys[i]] = n
  }
  return out
}

function parseStreamPsi(value) {
  if (value === null || value === undefined) return null
  if (typeof value !== "object") return null
  var keys = ["cs10", "cs60", "cs300", "cf10", "ms10", "ms60", "ms300", "mf10"]
  var out = {}
  var any = false
  for (var i = 0; i < keys.length; i++) {
    var raw = value[keys[i]]
    if (raw === null || raw === undefined || raw === "") {
      out[keys[i]] = null
      continue
    }
    var n = num(raw, null)
    if (n === null) {
      out[keys[i]] = null
      continue
    }
    out[keys[i]] = n < 0 ? 0 : n
    any = true
  }
  return any ? out : null
}

function parseStreamNet(value) {
  if (!Array.isArray(value)) return []
  var out = []
  for (var i = 0; i < value.length; i++) {
    var e = value[i]
    if (!e || typeof e !== "object") continue
    if (typeof e.n !== "string" || e.n.length === 0) continue
    var rx = num(e.rx, null), tx = num(e.tx, null)
    if (rx === null || tx === null || rx < 0 || tx < 0) continue
    out.push({ n: e.n, rx: rx, tx: tx })
  }
  return out
}

function parseStreamDisk(value) {
  if (!Array.isArray(value)) return []
  var out = []
  for (var i = 0; i < value.length && out.length < 16; i++) {
    var e = value[i]
    if (!e || typeof e !== "object") continue
    if (typeof e.n !== "string" || !/^[A-Za-z0-9._+-]+$/.test(e.n)) continue
    if (isExcludedDiskName(e.n) || isPartitionName(e.n)) continue
    var rd = num(e.rd, null), rs = num(e.rs, null)
    var wr = num(e.wr, null), ws = num(e.ws, null)
    var io = num(e.io, null)
    if (rd === null || rs === null || wr === null || ws === null) continue
    if (rd < 0 || rs < 0 || wr < 0 || ws < 0) continue
    out.push({
      n: e.n,
      rd: rd,
      rs: rs,
      wr: wr,
      ws: ws,
      io: io === null || io < 0 ? 0 : io
    })
  }
  return out
}

function parseStreamRoutes(value) {
  if (!Array.isArray(value)) return []
  var out = []
  for (var i = 0; i < value.length; i++) {
    var e = value[i]
    if (!e || typeof e !== "object") continue
    if (typeof e.n !== "string" || e.n.length === 0) continue
    var m = num(e.m, null)
    if (m === null || m < 0) continue
    out.push({ n: e.n, m: m })
  }
  return out
}

function parseGpuEngines(value) {
  var out = []
  if (!value || typeof value !== "object" || Array.isArray(value)) return out
  for (var k in value) {
    if (!Object.prototype.hasOwnProperty.call(value, k)) continue
    if (!/^[a-z0-9_]+$/.test(k)) continue
    var n = num(value[k], null)
    if (n === null || n < 0) continue
    out.push({ id: k, busy: n })
  }
  out.sort(function (a, b) {
    if (a.id < b.id) return -1
    if (a.id > b.id) return 1
    return 0
  })
  return out
}

function parseStreamGpu(value) {
  if (value === null || value === undefined) return null
  if (typeof value !== "object") return null
  var kind = (value.kind === "amd" || value.kind === "intel") ? value.kind : ""
  return {
    busy: num(value.busy, null),
    memBusy: num(value.mb, null),
    vramUsed: num(value.vrU, null),
    vramTotal: num(value.vrT, null),
    tempC: num(value.t, null),
    powerW: num(value.w, null),
    clockMhz: num(value.mhz, null),
    freqCurMhz: num(value.fc, null),
    freqMaxMhz: num(value.fm, null),
    engines: parseGpuEngines(value.eng),
    kind: kind
  }
}

function parseStreamLine(line) {
  var data = safeJson(line)
  if (!data) return null
  if (data.v !== 1) return null
  var ts = num(data.ts, null)
  if (ts === null || ts <= 0) return null
  var cpu = parseCpuArray(data.cpu)
  var mem = parseStreamMem(data.mem)
  if (!cpu || !mem) return null

  var load = [null, null, null]
  if (Array.isArray(data.load)) {
    for (var i = 0; i < 3 && i < data.load.length; i++)
      load[i] = num(data.load[i], null)
  }

  var vm = { swpin: 0, swpout: 0 }
  if (data.vm && typeof data.vm === "object") {
    vm.swpin = nonNeg(data.vm.swpin)
    vm.swpout = nonNeg(data.vm.swpout)
  }

  return {
    ts: ts,
    cpu: cpu,
    mem: mem,
    psi: parseStreamPsi(data.psi),
    vm: vm,
    net: parseStreamNet(data.net),
    r4: parseStreamRoutes(data.r4),
    r6: parseStreamRoutes(data.r6),
    gpu: parseStreamGpu(data.gpu),
    tempC: num(data.t, null),
    load: load,
    uptimeS: nonNeg(data.up),
    cores: Math.max(1, Math.round(nonNeg(data.cores) || 1)),
    cpuFreqMhz: num(data.cf, null),
    disk: parseStreamDisk(data.disk)
  }
}

// ------------------------------------------------------------- CPU / rates

// Percentages since the previous sample. user folds in nice; system folds in
// irq+softirq; iowait and steal stay their own buckets so nothing is silently
// misattributed. Returns null when the counters did not advance.
function cpuDelta(prev, curr) {
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
  out.busy = out.user + out.system
  return out
}

// Per-interface byte rates from cumulative counters. Interfaces are joined by
// name; a counter that moved backwards (interface reset) reports 0 for the
// tick rather than a garbage spike.
function netRates(prevNet, currNet, dtS) {
  if (!Array.isArray(currNet) || !(dtS > 0)) return []
  var prev = {}
  if (Array.isArray(prevNet)) {
    for (var i = 0; i < prevNet.length; i++) prev[prevNet[i].n] = prevNet[i]
  }
  var out = []
  for (var j = 0; j < currNet.length; j++) {
    var c = currNet[j]
    var p = prev[c.n]
    var rxBps = 0, txBps = 0
    if (p) {
      rxBps = Math.max(0, c.rx - p.rx) / dtS
      txBps = Math.max(0, c.tx - p.tx) / dtS
    }
    out.push({ name: c.n, rxBps: rxBps, txBps: txBps, rxTotal: c.rx, txTotal: c.tx })
  }
  return out
}

// ---------------------------------------------------------------- disk

// Virtual / memory-backed names the stream also drops. zram is memory and
// already lives on the Memory tab.
function isExcludedDiskName(name) {
  var n = String(name || "")
  return /^(loop|ram|zram|fd|nbd|sr)[0-9]/.test(n) || n === "loop" || n === "ram"
}

// Partition names as the kernel spells them. Whole devices (sda, nvme0n1,
// mmcblk0, vda, dm-0) return false. Used when /sys/block is unavailable
// (unit tests) and as a second filter on stream JSON.
function isPartitionName(name) {
  var n = String(name || "")
  if (/^nvme[0-9]+n[0-9]+p[0-9]+$/.test(n)) return true
  if (/^mmcblk[0-9]+p[0-9]+$/.test(n)) return true
  if (/^(sd|hd|vd|xvd)[a-z]+[0-9]+$/.test(n)) return true
  return false
}

function parentDiskName(name) {
  var n = String(name || "")
  if (/^nvme[0-9]+n[0-9]+p[0-9]+$/.test(n)) return n.replace(/p[0-9]+$/, "")
  if (/^mmcblk[0-9]+p[0-9]+$/.test(n)) return n.replace(/p[0-9]+$/, "")
  if (/^(sd|hd|vd|xvd)[a-z]+[0-9]+$/.test(n)) return n.replace(/[0-9]+$/, "")
  return n
}

// Device-mapper and md RAID whole devices. Folded onto a unique physical
// parent when disk-info can name one; kept as their own disk otherwise.
function isVirtualDiskName(name) {
  var n = String(name || "")
  return /^dm-/.test(n) || /^md[0-9]/.test(n)
}

function diskSourceBase(sourceOrName) {
  var s = String(sourceOrName || "")
  if (s.indexOf("/dev/") === 0) s = s.slice(5)
  if (s.indexOf("mapper/") === 0) s = s.slice(7)
  return s
}

// Map a df source or sysfs name through disk-info's backing table onto
// the whole disk the Drives tab should follow.
function resolveBackingDisk(sourceOrName, backing) {
  var base = diskSourceBase(sourceOrName)
  if (!base) return ""
  var map = (backing && typeof backing === "object" && !Array.isArray(backing)) ? backing : {}
  if (typeof map[base] === "string" && map[base]) return map[base]
  var parent = parentDiskName(base)
  if (typeof map[parent] === "string" && map[parent]) return map[parent]
  return parent
}

function diskNamePresent(name, disks, rates) {
  if (!name) return false
  var i
  if (Array.isArray(disks)) {
    for (i = 0; i < disks.length; i++)
      if (disks[i] && disks[i].name === name) return true
  }
  if (Array.isArray(rates)) {
    for (i = 0; i < rates.length; i++)
      if (rates[i] && rates[i].name === name) return true
  }
  return false
}

// Parse /proc/diskstats. Whole-device filter matches the stream: drop
// partitions and excluded names. Counters: reads completed, sectors read,
// writes completed, sectors written, io_ticks (ms).
function parseDiskstats(text) {
  var out = []
  if (typeof text !== "string" || text.length === 0) return out
  var lines = text.split("\n")
  for (var i = 0; i < lines.length && out.length < 16; i++) {
    var line = lines[i].replace(/^\s+/, "")
    if (line === "") continue
    var f = line.split(/\s+/)
    if (f.length < 11) continue
    var name = f[2]
    if (!/^[A-Za-z0-9._+-]+$/.test(name)) continue
    if (isExcludedDiskName(name) || isPartitionName(name)) continue
    var rd = num(f[3], null), rs = num(f[5], null)
    var wr = num(f[7], null), ws = num(f[9], null)
    var io = f.length >= 13 ? num(f[12], 0) : 0
    if (rd === null || rs === null || wr === null || ws === null) continue
    if (rd < 0 || rs < 0 || wr < 0 || ws < 0) continue
    out.push({
      n: name,
      rd: rd,
      rs: rs,
      wr: wr,
      ws: ws,
      io: io === null || io < 0 ? 0 : io
    })
  }
  return out
}

// Per-device rates from cumulative diskstats. A counter that moved
// backwards reports 0 for the tick rather than a garbage spike. Sectors
// are 512-byte units (kernel iostats). utilPct is io_ticks-ms / wall-ms.
function diskRates(prevDisk, currDisk, dtS) {
  if (!Array.isArray(currDisk) || !(dtS > 0)) return []
  var prev = {}
  if (Array.isArray(prevDisk)) {
    for (var i = 0; i < prevDisk.length; i++) prev[prevDisk[i].n] = prevDisk[i]
  }
  var out = []
  for (var j = 0; j < currDisk.length; j++) {
    var c = currDisk[j]
    var p = prev[c.n]
    var readBps = 0, writeBps = 0, readIops = 0, writeIops = 0, utilPct = 0
    if (p) {
      readBps = Math.max(0, c.rs - p.rs) * 512 / dtS
      writeBps = Math.max(0, c.ws - p.ws) * 512 / dtS
      readIops = Math.max(0, c.rd - p.rd) / dtS
      writeIops = Math.max(0, c.wr - p.wr) / dtS
      var ioMs = Math.max(0, c.io - p.io)
      utilPct = clamp(100 * ioMs / (dtS * 1000), 0, 100)
    }
    out.push({
      name: c.n,
      readBps: readBps,
      writeBps: writeBps,
      readIops: readIops,
      writeIops: writeIops,
      utilPct: utilPct
    })
  }
  return out
}

var DF_SKIP_TYPES = {
  tmpfs: 1, devtmpfs: 1, overlay: 1, squashfs: 1, proc: 1, sysfs: 1,
  cgroup: 1, cgroup2: 1, devpts: 1, securityfs: 1, pstore: 1, bpf: 1,
  debugfs: 1, tracefs: 1, fusectl: 1, mqueue: 1, hugetlbfs: 1, configfs: 1,
  nsfs: 1, binfmt_misc: 1, autofs: 1, efivarfs: 1, ramfs: 1, rpc_pipefs: 1,
  iso9660: 1
}

// Parse `df -P -B1 -T`. Virtual filesystems are dropped; remaining rows
// keep source, type, byte sizes, use percent, and mount target. Hostile
// names are clipped — they render as PlainText in the panel.
function parseDf(text) {
  var out = []
  if (typeof text !== "string" || text.length === 0) return out
  var lines = text.split("\n")
  for (var i = 0; i < lines.length && out.length < 32; i++) {
    var line = lines[i].replace(/\s+$/g, "")
    if (line === "" || /^Filesystem\b/.test(line)) continue
    var m = line.match(/^(\S+)\s+(\S+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)%\s+(\/\S.*|\/)$/)
    if (!m) continue
    var source = clipStr(m[1], 128)
    var fstype = clipStr(m[2], 32)
    if (fstype === "" || DF_SKIP_TYPES[fstype]) continue
    if (/^\/dev\/(loop|zram|fd|sr)/.test(source)) continue
    var size = num(m[3], null), used = num(m[4], null), avail = num(m[5], null)
    var pct = num(m[6], null)
    if (size === null || used === null || avail === null || pct === null) continue
    if (size < 0 || used < 0 || avail < 0) continue
    out.push({
      source: source,
      fstype: fstype,
      size: size,
      used: used,
      avail: avail,
      pct: clamp(pct, 0, 1000),
      target: clipStr(m[7], 128)
    })
  }
  return out
}

function parseDiskInfoDisks(list) {
  var out = []
  if (!Array.isArray(list)) return out
  for (var i = 0; i < list.length && out.length < 16; i++) {
    var e = list[i]
    if (!e || typeof e !== "object") continue
    if (typeof e.name !== "string" || !/^[A-Za-z0-9._+-]+$/.test(e.name)) continue
    if (isExcludedDiskName(e.name) || isPartitionName(e.name)) continue
    var rot = e.rotational
    var rotational = (rot === true || rot === false) ? rot : null
    var sizeBytes = num(e.sizeBytes, null)
    if (sizeBytes !== null && sizeBytes < 0) sizeBytes = null
    var tempC = num(e.tempC, null)
    out.push({
      name: e.name,
      model: clipStr(e.model, 64),
      rotational: rotational,
      sizeBytes: sizeBytes,
      tempC: tempC
    })
  }
  return out
}

function parseDiskInfoBacking(obj) {
  var out = {}
  if (!obj || typeof obj !== "object" || Array.isArray(obj)) return out
  for (var k in obj) {
    if (!Object.prototype.hasOwnProperty.call(obj, k)) continue
    if (!/^[A-Za-z0-9._+-]+$/.test(k)) continue
    var v = obj[k]
    if (typeof v !== "string" || !/^[A-Za-z0-9._+-]+$/.test(v)) continue
    out[k] = v
  }
  return out
}

function parseDiskInfo(env) {
  if (!env || typeof env !== "object" || env.ok !== true) return null
  var backing = parseDiskInfoBacking(env.backing)
  var disks = parseDiskInfoDisks(env.disks)
  var listed = {}
  var i
  for (i = 0; i < disks.length; i++) listed[disks[i].name] = true
  var visible = []
  for (i = 0; i < disks.length; i++) {
    var mapped = backing[disks[i].name]
    if (mapped && mapped !== disks[i].name && listed[mapped]) continue
    visible.push(disks[i])
  }
  return {
    disks: visible,
    mounts: parseDf(env.dfPayload),
    backing: backing
  }
}

// diskDevice setting: "auto" prefers the disk backing `/`, then the
// largest by sizeBytes, then the first in the rate list. A specific name
// must exist in `disks` (identity) or `rates` (live counters). Mapper
// aliases in `backing` remap onto the physical parent.
function pickDisk(disks, mounts, rates, setting, backing) {
  var wanted = normalizeDeviceSetting(typeof setting === "string" ? setting : "auto")
  if (wanted !== "auto") {
    var remapped = resolveBackingDisk(wanted, backing)
    if (remapped) wanted = remapped
  }
  var names = {}
  var i
  if (Array.isArray(rates)) {
    for (i = 0; i < rates.length; i++) if (rates[i] && rates[i].name) names[rates[i].name] = true
  }
  if (Array.isArray(disks)) {
    for (i = 0; i < disks.length; i++) if (disks[i] && disks[i].name) names[disks[i].name] = true
  }
  function present(n) { return n && names[n] === true }

  if (wanted !== "auto" && wanted !== "")
    return present(wanted) ? wanted : null

  if (Array.isArray(mounts)) {
    for (i = 0; i < mounts.length; i++) {
      if (!mounts[i] || mounts[i].target !== "/") continue
      var resolved = resolveBackingDisk(mounts[i].source, backing)
      if (present(resolved)) return resolved
    }
  }

  var hasPhysical = false
  if (Array.isArray(disks)) {
    for (i = 0; i < disks.length; i++) {
      if (disks[i] && present(disks[i].name) && !isVirtualDiskName(disks[i].name)) {
        hasPhysical = true
        break
      }
    }
  }

  var bestName = ""
  var bestSize = -1
  if (Array.isArray(disks)) {
    for (i = 0; i < disks.length; i++) {
      var d = disks[i]
      if (!d || !present(d.name)) continue
      if (hasPhysical && isVirtualDiskName(d.name)) continue
      var sz = num(d.sizeBytes, 0)
      if (sz > bestSize) { bestSize = sz; bestName = d.name }
    }
  }
  if (bestName) return bestName
  if (Array.isArray(rates) && rates.length > 0) {
    for (i = 0; i < rates.length; i++) {
      if (!rates[i] || !rates[i].name) continue
      if (hasPhysical && isVirtualDiskName(rates[i].name)) continue
      return rates[i].name
    }
    if (rates[0] && rates[0].name) return rates[0].name
  }
  return null
}

// vmstat pswpin/pswpout are cumulative pages; report KiB/s assuming 4 KiB
// pages (true on every arch Omarchy ships on).
function swapRates(prevVm, currVm, dtS, pageKiB) {
  var page = pageKiB || 4
  if (!prevVm || !currVm || !(dtS > 0)) return { inKBs: 0, outKBs: 0 }
  return {
    inKBs: Math.max(0, currVm.swpin - prevVm.swpin) * page / dtS,
    outKBs: Math.max(0, currVm.swpout - prevVm.swpout) * page / dtS
  }
}

// --------------------------------------------------------------- memory

// Composition of physical RAM. Buffers count toward the Cache slice.
// Applications is whatever is neither free, cache, nor unreclaimable kernel
// slab — clamped at zero so a weird meminfo never yields a negative slice.
function memComposition(mem) {
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

function swapUsage(mem) {
  if (!mem) return null
  var used = Math.max(0, mem.swtot - mem.swfre)
  return {
    totalK: mem.swtot,
    usedK: used,
    pct: mem.swtot > 0 ? 100 * used / mem.swtot : 0
  }
}

// --------------------------------------------------------- interface pick

// Default interface across IPv4 AND IPv6 default routes, lowest metric wins;
// IPv4 takes ties. Candidates must exist in the counter list and not be the
// loopback. With no default route at all, fall back to the first non-loopback
// interface that has counters. Returns "" when there is nothing usable.
function pickInterface(r4, r6, net) {
  var names = {}
  var firstNonLo = ""
  if (Array.isArray(net)) {
    for (var i = 0; i < net.length; i++) {
      var n = net[i] && net[i].n
      if (!n || n === "lo") continue
      names[n] = true
      if (firstNonLo === "") firstNonLo = n
    }
  }
  var bestMetric = Infinity
  var bestName = ""
  var lists = [r4, r6]   // v4 first: strictly-less comparison keeps v4 on ties
  for (var l = 0; l < lists.length; l++) {
    var list = lists[l]
    if (!Array.isArray(list)) continue
    for (var j = 0; j < list.length; j++) {
      var e = list[j]
      if (!e || !names[e.n]) continue
      if (e.m < bestMetric) { bestMetric = e.m; bestName = e.n }
    }
  }
  return bestName !== "" ? bestName : firstNonLo
}

// ------------------------------------------------------------------- ps

// Parse `ps -eo pid=,<metric>=,comm=` output. The metric column is pcpu for
// the CPU tab and rss (KiB) for the memory tab. comm is attacker-controlled:
// it travels inside a JSON string and is only ever rendered as PlainText, so
// a hostile name can at worst make its own row look odd — lines that no
// longer parse (e.g. an embedded newline split the row) are skipped.
function parsePs(text, maxRows) {
  var limit = (maxRows === undefined) ? 10 : Math.max(1, Math.round(num(maxRows, 10)))
  var out = []
  if (typeof text !== "string" || text.length === 0) return out
  var lines = text.split("\n")
  for (var i = 0; i < lines.length && out.length < limit; i++) {
    var line = lines[i].replace(/^\s+|\s+$/g, "")
    if (line === "") continue
    var m = line.match(/^(\d+)\s+([0-9]+(?:[.,][0-9]+)?)\s+(\S[\s\S]*)$/)
    if (!m) continue
    var pid = parseInt(m[1], 10)
    var value = parseFloat(m[2].replace(",", "."))
    if (!isFinite(pid) || !isFinite(value)) continue
    var comm = m[3].replace(/\s+$/g, "")
    if (comm.length > 128) comm = comm.slice(0, 128)
    out.push({ pid: pid, value: value, comm: comm })
  }
  return out
}

// ------------------------------------------------------------------- ss
//
// Parse `ss -H -t -i -n -p state established` output into per-socket counter
// records: { pid, comm, rx, tx }. rx is bytes_received; tx is bytes_sent when
// the kernel reports it, else bytes_acked. Sockets whose owning process is
// not visible to us (other users, kernel sockets) keep pid 0 — the caller
// folds them into the honest "Other traffic" row keyed on pid === 0.
//
// comm is attacker-controlled and can contain quotes, a literal '",pid='
// fragment, tabs, or (via prctl) newlines. Extraction therefore anchors on
// the LAST '",pid=' in the users: group — the kernel always appends its own
// `,pid=N,fd=M` trailer after the quoted comm, so a forged inner pid lands
// inside the displayed comm string instead of the parsed pid.

// Strip the port from an ss Local-Address:Port field and normalize so
// IPv4-mapped IPv6 (`::ffff:10.0.0.2`) matches `ip addr` IPv4, and
// scoped link-locals drop the `%iface` zone.
function normalizeAddr(value) {
  var a = String(value || "").replace(/^\s+|\s+$/g, "").toLowerCase()
  if (a === "") return ""
  var pct = a.indexOf("%")
  if (pct >= 0) a = a.slice(0, pct)
  if (a.indexOf("::ffff:") === 0) {
    var v4 = a.slice(7)
    if (/^\d{1,3}(\.\d{1,3}){3}$/.test(v4)) return v4
  }
  return a
}

function stripSsLocal(addrPort) {
  var s = String(addrPort || "")
  if (s.charAt(0) === "[") {
    var close = s.indexOf("]")
    if (close > 1) return normalizeAddr(s.slice(1, close))
  }
  var c = s.lastIndexOf(":")
  if (c <= 0) return normalizeAddr(s)
  return normalizeAddr(s.slice(0, c))
}

function ssParseLocal(line, sock) {
  var m = String(line).match(/^\s*\d+\s+\d+\s+(\S+)/)
  if (!m) return
  sock.localAddr = stripSsLocal(m[1])
}

function ssParseUsers(line, sock) {
  var open = line.indexOf('users:(("')
  if (open < 0) return
  var rest = line.slice(open + 9)   // 'users:(("' is 9 chars; comm starts after it
  var anchor = rest.lastIndexOf('",pid=')
  if (anchor < 0) return
  var comm = rest.slice(0, anchor)
  var tail = rest.slice(anchor + 6)
  var pm = tail.match(/^(\d+)/)
  if (!pm) return
  var pid = parseInt(pm[1], 10)
  if (!isFinite(pid)) return
  if (comm.length > 128) comm = comm.slice(0, 128)
  sock.pid = pid
  sock.comm = comm
}

function ssScanNumbers(line, sock) {
  var m = line.match(/bytes_received:(\d+)/)
  if (m) sock.rx = parseInt(m[1], 10)
  var sent = line.match(/bytes_sent:(\d+)/)
  if (sent) {
    sock.tx = parseInt(sent[1], 10)
  } else {
    var acked = line.match(/bytes_acked:(\d+)/)
    if (acked) sock.tx = parseInt(acked[1], 10)
  }
}

function parseSs(text) {
  var out = []
  if (typeof text !== "string" || text.length === 0) return out
  var lines = text.split("\n")
  var cur = null
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line.replace(/^\s+|\s+$/g, "") === "") continue
    var first = line.charAt(0)
    var indented = (first === " " || first === "\t")
    if (!indented) {
      // New socket record. Note: `ss ... state established` omits the state
      // column entirely, so records may lead with the Recv-Q number rather
      // than "ESTAB" — any non-indented line starts a record.
      cur = { pid: 0, comm: "", rx: null, tx: null, localAddr: "" }
      out.push(cur)
      ssParseLocal(line, cur)
    }
    if (!cur) continue
    ssParseUsers(line, cur)
    ssScanNumbers(line, cur)
  }
  // Drop sockets that reported neither counter; they cannot contribute rates.
  var kept = []
  for (var j = 0; j < out.length; j++) {
    if (out[j].rx === null && out[j].tx === null) continue
    kept.push({ pid: out[j].pid, comm: out[j].comm,
                rx: out[j].rx || 0, tx: out[j].tx || 0,
                localAddr: out[j].localAddr || "" })
  }
  return kept
}

function sumSocketsByPid(sockets) {
  var byPid = {}
  if (!Array.isArray(sockets)) return byPid
  for (var i = 0; i < sockets.length; i++) {
    var s = sockets[i]
    if (!s) continue
    var key = String(s.pid)
    if (!byPid[key]) byPid[key] = { pid: s.pid, comm: s.comm || "", rx: 0, tx: 0 }
    byPid[key].rx += nonNeg(s.rx)
    byPid[key].tx += nonNeg(s.tx)
    if (byPid[key].comm === "" && s.comm) byPid[key].comm = s.comm
  }
  return byPid
}

function socketsOnIface(sockets, ifaceAddrs) {
  if (!Array.isArray(sockets)) return []
  if (!Array.isArray(ifaceAddrs)) return sockets
  var want = {}
  var i
  for (i = 0; i < ifaceAddrs.length; i++) {
    var a = normalizeAddr(ifaceAddrs[i])
    if (a) want[a] = true
  }
  var out = []
  for (i = 0; i < sockets.length; i++) {
    var s = sockets[i]
    if (!s) continue
    if (want[normalizeAddr(s.localAddr)]) out.push(s)
  }
  return out
}

// Per-process network rates plus the honest unattributed remainder.
//   prev/curr:    parseSs output from two samples
//   ifPrev/ifCurr: { rx, tx } interface counters at the same instants
//   ifaceAddrs:   optional list of addresses on the watched interface.
//                 When provided, sockets whose local address is not on
//                 that list are excluded from process rows and land in
//                 Other — ss is global, the interface counters are not.
// Rows carry raw per-interval byte rates. Anything the interface moved that
// could not be attributed to a visible process lands in `other` (pid 0) —
// never silently dropped, never presented as a real process.
function computeNetAppRows(prev, curr, ifPrev, ifCurr, dtS, ifaceAddrs) {
  var empty = { rows: [], other: { rxBps: 0, txBps: 0 }, ifRxBps: 0, ifTxBps: 0 }
  if (!Array.isArray(curr) || !ifCurr || !(dtS > 0)) return empty

  var prevByPid = sumSocketsByPid(socketsOnIface(prev, ifaceAddrs))
  var currByPid = sumSocketsByPid(socketsOnIface(curr, ifaceAddrs))

  var ifRxBps = ifPrev ? Math.max(0, ifCurr.rx - ifPrev.rx) / dtS : 0
  var ifTxBps = ifPrev ? Math.max(0, ifCurr.tx - ifPrev.tx) / dtS : 0

  var rows = []
  var attribRx = 0, attribTx = 0
  for (var key in currByPid) {
    var c = currByPid[key]
    if (c.pid === 0) continue   // unattributed bucket is computed below
    var p = prevByPid[key]
    var rxBps = p ? Math.max(0, c.rx - p.rx) / dtS : 0
    var txBps = p ? Math.max(0, c.tx - p.tx) / dtS : 0
    if (rxBps <= 0 && txBps <= 0) continue
    attribRx += rxBps
    attribTx += txBps
    rows.push({ pid: c.pid, comm: c.comm, rxBps: rxBps, txBps: txBps, sortKey: rxBps + txBps })
  }
  rows.sort(function (a, b) { return b.sortKey - a.sortKey })

  return {
    rows: rows,
    other: {
      rxBps: Math.max(0, ifRxBps - attribRx),
      txBps: Math.max(0, ifTxBps - attribTx)
    },
    ifRxBps: ifRxBps,
    ifTxBps: ifTxBps
  }
}

// -------------------------------------------------------------- roster

// Sticky roster merge: rows that survive from the previous sample keep their
// on-screen position and update in place; newcomers append sorted by sortKey;
// vanished rows drop out. Never reorders existing rows, so the list does not
// jump around every tick. The catch-all row is keyed strictly on pid === 0,
// so a process literally named "Other traffic" cannot collide with it.
function mergeRoster(prevRows, nextRows, maxRows) {
  var limit = Math.max(1, Math.round(num(maxRows, 5)))
  var byPid = {}
  var i
  if (Array.isArray(nextRows)) {
    for (i = 0; i < nextRows.length; i++) {
      var r = nextRows[i]
      if (r) byPid[String(r.pid)] = r
    }
  }
  var out = []
  if (Array.isArray(prevRows)) {
    for (i = 0; i < prevRows.length; i++) {
      var old = prevRows[i]
      if (!old) continue
      var fresh = byPid[String(old.pid)]
      if (fresh === undefined) continue
      delete byPid[String(old.pid)]
      out.push(fresh)
    }
  }
  var newcomers = []
  for (var key in byPid) newcomers.push(byPid[key])
  newcomers.sort(function (a, b) { return (b.sortKey || 0) - (a.sortKey || 0) })
  for (i = 0; i < newcomers.length && out.length < limit; i++) out.push(newcomers[i])
  if (out.length > limit) out.length = limit
  return out
}

// --------------------------------------------------------------- nvidia

// Parse `nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,
// memory.total,temperature.gpu,power.draw,clocks.gr --format=csv,noheader,
// nounits`. Fields may be "N/A" or "[Not Supported]" — those become null.
// GPU names can contain commas; extra fields are rejoined into `name` so
// the last six numeric columns stay aligned. Malformed lines are skipped;
// the row count is capped.
function parseNvidiaCsv(text, maxRows) {
  var limit = (maxRows === undefined) ? 8 : maxRows
  var out = []
  if (typeof text !== "string" || text.length === 0) return out
  var lines = text.split("\n")
  for (var i = 0; i < lines.length && out.length < limit; i++) {
    var line = lines[i].replace(/\s+$/g, "")
    if (line === "") continue
    var f = line.split(",")
    if (f.length < 8) continue
    var extra = f.length - 8
    var index = parseInt(String(f[0]).replace(/^\s+|\s+$/g, ""), 10)
    if (!isFinite(index)) continue
    var name = f.slice(1, 2 + extra).join(",").replace(/^\s+|\s+$/g, "")
    var rest = f.slice(2 + extra)
    var field = function (n) {
      var v = String(rest[n] || "").replace(/^\s+|\s+$/g, "")
      if (v === "" || v === "N/A" || v === "[Not Supported]" || v === "[N/A]") return null
      return num(v, null)
    }
    out.push({
      index: index,
      name: name,
      utilPct: field(0),
      memUsedM: field(1),
      memTotalM: field(2),
      tempC: field(3),
      powerW: field(4),
      clockMhz: field(5)
    })
  }
  return out
}

// ------------------------------------------------------- amd / intel gpu

// gpu-stats ships AMD/Intel sysfs contents as raw `key=value` lines inside
// the JSON envelope; parsing and unit conversion live here so fixtures can
// exercise them. Values stay strings until validated.
function parseKeyValues(text) {
  var out = {}
  if (typeof text !== "string") return out
  var lines = text.split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    var eq = line.indexOf("=")
    if (eq <= 0) continue
    var key = line.slice(0, eq)
    if (!/^[a-z0-9_]+$/.test(key)) continue
    out[key] = line.slice(eq + 1).replace(/\s+$/g, "")
  }
  return out
}

function milliToWhole(value) {
  var n = num(value, null)
  return n === null ? null : n / 1000
}

function microToWhole(value) {
  var n = num(value, null)
  return n === null ? null : n / 1000000
}

function enginesFromKv(kv) {
  var out = []
  if (!kv || typeof kv !== "object") return out
  for (var k in kv) {
    if (k.indexOf("eng_") !== 0) continue
    var id = k.slice(4)
    if (!id || !/^[a-z0-9_]+$/.test(id)) continue
    var n = num(kv[k], null)
    if (n === null || n < 0) continue
    out.push({ id: id, busy: n })
  }
  out.sort(function (a, b) {
    if (a.id < b.id) return -1
    if (a.id > b.id) return 1
    return 0
  })
  return out
}

function normalizeAmdGpu(kv) {
  if (!kv || typeof kv !== "object") return null
  return {
    kind: "amd",
    busy: num(kv.gpu_busy_percent, null),
    memBusy: num(kv.mem_busy_percent, null),
    vramUsed: num(kv.mem_info_vram_used, null),
    vramTotal: num(kv.mem_info_vram_total, null),
    tempC: milliToWhole(kv.temp_edge_mc),        // temp1_input, millidegrees
    tempJunctionC: milliToWhole(kv.temp_junction_mc),
    powerW: microToWhole(kv.power1_average_uw),  // microwatts
    clockMhz: num(kv.sclk_mhz, null),
    engines: enginesFromKv(kv)
  }
}

// Intel exposes no busy percent without CAP_PERFMON, which we refuse to
// require. The frequency ratio is an estimate and is labeled "freq" in the
// UI, never "busy".
function normalizeIntelGpu(kv) {
  if (!kv || typeof kv !== "object") return null
  var cur = num(kv.gt_cur_freq_mhz, null)
  var max = num(kv.gt_max_freq_mhz, null)
  var estimate = null
  if (cur !== null && max !== null && max > 0)
    estimate = clamp(100 * cur / max, 0, 100)
  return {
    kind: "intel",
    busy: null,
    freqEstimate: estimate,
    freqCurMhz: cur,
    freqMaxMhz: max,
    tempC: milliToWhole(kv.temp_package_mc)
  }
}

function normalizeGpuListEntry(e) {
  if (!e || typeof e !== "object") return null
  var vendor = e.vendor
  if (vendor !== "amd" && vendor !== "intel" && vendor !== "nvidia") return null
  if (typeof e.card !== "string" || !/^card[0-9]+$/.test(e.card)) return null
  if (typeof e.path !== "string" || e.path.indexOf("/sys/") !== 0) return null
  return { card: e.card, vendor: vendor, path: e.path, boot: e.boot === true }
}

function normalizeGpuList(data) {
  var out = []
  if (!data || !Array.isArray(data.gpus)) return out
  for (var i = 0; i < data.gpus.length; i++) {
    var g = normalizeGpuListEntry(data.gpus[i])
    if (g) out.push(g)
  }
  return out
}

// gpuDevice setting: "auto" prefers the card driving the boot display, then
// card0, then the first detected card. A specific "cardN" must exist.
function pickGpu(gpus, setting) {
  if (!Array.isArray(gpus) || gpus.length === 0) return null
  var wanted = typeof setting === "string" ? setting : "auto"
  if (wanted !== "auto" && wanted !== "") {
    for (var i = 0; i < gpus.length; i++)
      if (gpus[i].card === wanted) return gpus[i]
    return null
  }
  for (var j = 0; j < gpus.length; j++) if (gpus[j].boot) return gpus[j]
  for (var k = 0; k < gpus.length; k++) if (gpus[k].card === "card0") return gpus[k]
  return gpus[0]
}

// ---------------------------------------------------------- system-info
//
// system-info ships static hardware identity as one JSON envelope. lspci
// -D -mm output is a raw payload string (device names contain brackets
// and quotes) and is parsed here so fixtures can exercise hostile input.

function clipStr(value, max) {
  if (value === null || value === undefined) return ""
  var s = String(value)
  var out = ""
  for (var i = 0; i < s.length && out.length < max; i++) {
    var code = s.charCodeAt(i)
    if (code < 32 || code === 127) continue
    out += s.charAt(i)
  }
  return out
}

function parseLspciMm(text) {
  var out = []
  if (typeof text !== "string" || text.length === 0) return out
  var lines = text.split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line.replace(/^\s+|\s+$/g, "") === "") continue
    // Real `lspci -D -mm` leaves the leading slot unquoted:
    //   0000:03:00.0 "VGA compatible controller" "AMD..." "Navi..."
    // Accept a quoted slot too for compatibility with captured/normalized
    // output, then parse the remaining machine-format quoted fields.
    var slotMatch = line.match(/^\s*"?([0-9a-fA-F:.]+)"?\s+/)
    if (!slotMatch) continue
    var slot = slotMatch[1]
    if (!/^[0-9a-fA-F:.]+$/.test(slot)) continue
    var payload = line.slice(slotMatch[0].length)
    var fields = []
    var re = /"((?:[^"\\]|\\.)*)"/g
    var m
    while ((m = re.exec(payload)) !== null) {
      fields.push(m[1].replace(/\\"/g, '"').replace(/\\\\/g, "\\"))
    }
    if (fields.length < 3) continue
    out.push({
      slot: slot,
      class: clipStr(fields[0], 64),
      vendor: clipStr(fields[1], 64),
      device: clipStr(fields[2], 128)
    })
  }
  return out
}

function parseSystemCpu(c) {
  var empty = {
    modelName: "", vendorId: "", physCores: null, threads: null,
    cacheKb: null, mhzNow: null, governor: "", maxMhz: null
  }
  if (!c || typeof c !== "object") return empty
  var gov = clipStr(c.governor, 32)
  if (gov && !/^[A-Za-z0-9._+-]+$/.test(gov)) gov = ""
  return {
    modelName: clipStr(c.modelName, 128),
    vendorId: clipStr(c.vendorId, 32),
    physCores: (function () { var n = num(c.physCores, null); return n !== null && n > 0 ? Math.round(n) : null })(),
    threads: (function () { var n = num(c.threads, null); return n !== null && n > 0 ? Math.round(n) : null })(),
    cacheKb: (function () { var n = num(c.cacheKb, null); return n !== null && n >= 0 ? n : null })(),
    mhzNow: (function () { var n = num(c.mhzNow, null); return n !== null && n >= 0 ? n : null })(),
    governor: gov,
    maxMhz: (function () { var n = num(c.maxMhz, null); return n !== null && n >= 0 ? n : null })()
  }
}

function parseSystemGpus(list, lspciBySlot) {
  var out = []
  if (!Array.isArray(list)) return out
  for (var i = 0; i < list.length && out.length < 8; i++) {
    var e = list[i]
    if (!e || typeof e !== "object") continue
    if (typeof e.card !== "string" || !/^card[0-9]+$/.test(e.card)) continue
    var vendor = e.vendor
    if (vendor !== "amd" && vendor !== "intel" && vendor !== "nvidia") continue
    var slot = (typeof e.slot === "string" && /^[0-9a-fA-F:.]+$/.test(e.slot)) ? e.slot : ""
    var driver = clipStr(e.driver, 32)
    if (driver && !/^[A-Za-z0-9._+-]+$/.test(driver)) driver = ""
    var pciId = ""
    if (typeof e.pciId === "string" && /^[0-9a-fA-F]{4}:[0-9a-fA-F]{4}$/.test(e.pciId))
      pciId = e.pciId.toLowerCase()
    var name = ""
    if (slot && lspciBySlot && lspciBySlot[slot] && lspciBySlot[slot].device)
      name = lspciBySlot[slot].device
    out.push({ card: e.card, vendor: vendor, slot: slot, driver: driver, pciId: pciId, name: name })
  }
  return out
}

function parseSystemMem(mem) {
  var swaps = []
  var zram = []
  if (!mem || typeof mem !== "object") return { swaps: swaps, zram: zram }
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
  return { swaps: swaps, zram: zram }
}

function parseSystemHost(host) {
  if (!host || typeof host !== "object") return { kernel: "", sysVendor: "", productName: "" }
  return {
    kernel: clipStr(host.kernel, 64),
    sysVendor: clipStr(host.sysVendor, 64),
    productName: clipStr(host.productName, 64)
  }
}

function parseSystemInfo(env) {
  if (!env || typeof env !== "object" || env.ok !== true) return null
  var lspci = parseLspciMm(env.lspciPayload)
  var lspciBySlot = {}
  for (var i = 0; i < lspci.length; i++) lspciBySlot[lspci[i].slot] = lspci[i]
  var gpus = parseSystemGpus(env.gpus, lspciBySlot)
  var byCard = {}
  for (var j = 0; j < gpus.length; j++) byCard[gpus[j].card] = gpus[j]
  return {
    cpu: parseSystemCpu(env.cpu),
    gpus: gpus,
    gpusByCard: byCard,
    mem: parseSystemMem(env.mem),
    host: parseSystemHost(env.host)
  }
}

function cpuVendorLabel(vendorId) {
  var v = String(vendorId || "")
  if (v === "GenuineIntel") return "Intel"
  if (v === "AuthenticAMD") return "AMD"
  if (v === "Apple") return "Apple"
  if (v === "") return "--"
  return v
}

function gpuVendorLabel(vendor) {
  if (vendor === "amd") return "AMD"
  if (vendor === "intel") return "Intel"
  if (vendor === "nvidia") return "NVIDIA"
  return vendor ? String(vendor) : "--"
}

function formatCache(kb) {
  var n = num(kb, null)
  if (n === null || n < 0) return "--"
  if (n >= 1024) return Math.round(n / 1024) + " MB"
  return Math.round(n) + " KB"
}

// ------------------------------------------------------------ formatters

function formatUnit(value, units, suffix) {
  var n = num(value, null)
  if (n === null || n < 0) return "--"
  var i = 0
  while (n >= 1024 && i < units.length - 1) { n /= 1024; i++ }
  var rounded = Math.round(n * 10) / 10
  var text = (i > 0 && n < 10 && rounded % 1 !== 0) ? rounded.toFixed(1) : String(Math.round(n))
  return text + " " + units[i] + suffix
}

function formatBytes(n) {
  return formatUnit(n, ["B", "KiB", "MiB", "GiB", "TiB"], "")
}

function formatRate(bps) {
  return formatUnit(bps, ["B", "KB", "MB", "GB"], "/s")
}

// Bounded bar format, max ~4 significant glyphs: 999B, 1.0K, 9.9K, 99K,
// 999K, 1.0M. One decimal below 10 of a unit, none above. 1000–1023 B
// promote to 1.0K so the label never grows past four characters + unit.
function formatRateCompact(bps) {
  var n = num(bps, null)
  if (n === null || n < 0) return "--"
  var units = ["B", "K", "M", "G", "T"]
  var i = 0
  while (n >= 1024 && i < units.length - 1) { n /= 1024; i++ }
  if (i === 0) {
    var rb = Math.round(n)
    if (rb < 1000) return String(rb) + "B"
    n = n / 1024
    i = 1
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

function formatKiB(kib) {
  var n = num(kib, null)
  if (n === null || n < 0) return "--"
  return formatBytes(n * 1024)
}

function formatPct(value, digits) {
  var n = num(value, null)
  if (n === null) return "--"
  if (digits === 1) return (Math.round(n * 10) / 10).toFixed(1) + "%"
  return Math.round(clamp(n, 0, 1000)) + "%"
}

function formatTemp(c) {
  var n = num(c, null)
  return n === null ? "--" : Math.round(n) + "°C"
}

function formatMhz(v) {
  var n = num(v, null)
  return n === null ? "--" : Math.round(n) + " MHz"
}

function formatWatts(v) {
  var n = num(v, null)
  if (n === null) return "--"
  return (n < 10 ? (Math.round(n * 10) / 10).toFixed(1) : String(Math.round(n))) + " W"
}

function formatLoad(v) {
  var n = num(v, null)
  return n === null ? "--" : (Math.round(n * 100) / 100).toFixed(2)
}

function formatUptime(seconds) {
  var s = num(seconds, null)
  if (s === null || s < 0) return "--"
  var d = Math.floor(s / 86400)
  var h = Math.floor((s % 86400) / 3600)
  var m = Math.floor((s % 3600) / 60)
  if (d > 0) return d + "d " + h + "h"
  if (h > 0) return h + "h " + m + "m"
  return m + "m"
}

// Cap a history buffer at maxLen, dropping the oldest points.
function pushCapped(history, point, maxLen) {
  var limit = Math.max(2, Math.round(num(maxLen, 60)))
  var next = Array.isArray(history) ? history.slice() : []
  next.push(point)
  while (next.length > limit) next.shift()
  return next
}

// Append a timestamped point while preserving a real time window even when
// barIntervalMs is customized. A clock/counter reset starts a fresh window.
function pushTimedWindow(history, point, timestamp, windowSeconds, maxLen) {
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

// ------------------------------------------------------- node test shim
// QML ignores this branch (`module` is undefined there); node uses it.

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    clamp: clamp,
    num: num,
    safeJson: safeJson,
    normalizeDeviceSetting: normalizeDeviceSetting,
    parseStreamLine: parseStreamLine,
    cpuDelta: cpuDelta,
    netRates: netRates,
    isExcludedDiskName: isExcludedDiskName,
    isPartitionName: isPartitionName,
    parentDiskName: parentDiskName,
    isVirtualDiskName: isVirtualDiskName,
    resolveBackingDisk: resolveBackingDisk,
    diskNamePresent: diskNamePresent,
    parseDiskstats: parseDiskstats,
    diskRates: diskRates,
    parseDf: parseDf,
    parseDiskInfo: parseDiskInfo,
    pickDisk: pickDisk,
    swapRates: swapRates,
    memComposition: memComposition,
    swapUsage: swapUsage,
    pickInterface: pickInterface,
    parsePs: parsePs,
    parseSs: parseSs,
    sumSocketsByPid: sumSocketsByPid,
    socketsOnIface: socketsOnIface,
    computeNetAppRows: computeNetAppRows,
    mergeRoster: mergeRoster,
    parseNvidiaCsv: parseNvidiaCsv,
    parseKeyValues: parseKeyValues,
    normalizeAmdGpu: normalizeAmdGpu,
    normalizeIntelGpu: normalizeIntelGpu,
    normalizeGpuList: normalizeGpuList,
    pickGpu: pickGpu,
    parseLspciMm: parseLspciMm,
    parseSystemInfo: parseSystemInfo,
    cpuVendorLabel: cpuVendorLabel,
    gpuVendorLabel: gpuVendorLabel,
    formatCache: formatCache,
    formatBytes: formatBytes,
    formatRate: formatRate,
    formatRateCompact: formatRateCompact,
    formatKiB: formatKiB,
    formatPct: formatPct,
    formatTemp: formatTemp,
    formatMhz: formatMhz,
    formatWatts: formatWatts,
    formatLoad: formatLoad,
    formatUptime: formatUptime,
    pushCapped: pushCapped,
    pushTimedWindow: pushTimedWindow
  }
}
