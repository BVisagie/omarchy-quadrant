// Block devices: diskstats rates, df parsing, mapper/RAID folding and
// disk selection.

import { clamp, clipStr, num } from "./core.mjs"
import { normalizeDeviceSetting } from "./settings.mjs"

// Virtual / memory-backed names the stream also drops. zram is memory and
// already lives on the Memory tab.
export function isExcludedDiskName(name) {
  var n = String(name || "")
  return /^(loop|ram|zram|fd|nbd|sr)[0-9]/.test(n) || n === "loop" || n === "ram"
}

// Partition names as the kernel spells them. Whole devices (sda, nvme0n1,
// mmcblk0, vda, dm-0) return false. Used when /sys/block is unavailable
// (unit tests) and as a second filter on stream JSON.
export function isPartitionName(name) {
  var n = String(name || "")
  if (/^nvme[0-9]+n[0-9]+p[0-9]+$/.test(n)) return true
  if (/^mmcblk[0-9]+p[0-9]+$/.test(n)) return true
  if (/^(sd|hd|vd|xvd)[a-z]+[0-9]+$/.test(n)) return true
  return false
}

export function parentDiskName(name) {
  var n = String(name || "")
  if (/^nvme[0-9]+n[0-9]+p[0-9]+$/.test(n)) return n.replace(/p[0-9]+$/, "")
  if (/^mmcblk[0-9]+p[0-9]+$/.test(n)) return n.replace(/p[0-9]+$/, "")
  if (/^(sd|hd|vd|xvd)[a-z]+[0-9]+$/.test(n)) return n.replace(/[0-9]+$/, "")
  return n
}

// Device-mapper and md RAID whole devices. Folded onto a unique physical
// parent when disk-info can name one; kept as their own disk otherwise.
export function isVirtualDiskName(name) {
  var n = String(name || "")
  return /^dm-/.test(n) || /^md[0-9]/.test(n)
}

export function diskSourceBase(sourceOrName) {
  var s = String(sourceOrName || "")
  if (s.indexOf("/dev/") === 0) s = s.slice(5)
  if (s.indexOf("mapper/") === 0) s = s.slice(7)
  return s
}

// Map a df source or sysfs name through disk-info's backing table onto
// the whole disk the Drives tab should follow.
export function resolveBackingDisk(sourceOrName, backing) {
  var base = diskSourceBase(sourceOrName)
  if (!base) return ""
  var map = (backing && typeof backing === "object" && !Array.isArray(backing)) ? backing : {}
  if (typeof map[base] === "string" && map[base]) return map[base]
  var parent = parentDiskName(base)
  if (typeof map[parent] === "string" && map[parent]) return map[parent]
  return parent
}

export function diskNamePresent(name, disks, rates) {
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
export function parseDiskstats(text) {
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
export function diskRates(prevDisk, currDisk, dtS) {
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

export var DF_SKIP_TYPES = {
  tmpfs: 1, devtmpfs: 1, overlay: 1, squashfs: 1, proc: 1, sysfs: 1,
  cgroup: 1, cgroup2: 1, devpts: 1, securityfs: 1, pstore: 1, bpf: 1,
  debugfs: 1, tracefs: 1, fusectl: 1, mqueue: 1, hugetlbfs: 1, configfs: 1,
  nsfs: 1, binfmt_misc: 1, autofs: 1, efivarfs: 1, ramfs: 1, rpc_pipefs: 1,
  iso9660: 1
}

// Parse `df -P -B1 -T`. Virtual filesystems are dropped; remaining rows
// keep source, type, byte sizes, use percent, and mount target. Hostile
// names are clipped — they render as PlainText in the panel.
export function parseDf(text) {
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
  return collapseMounts(out)
}

// Bind mounts and subvolumes of the same filesystem share size+used.
// Keep the shortest path ("/" wins) so the Drives tab does not list the
// same fill four times.
export function collapseMounts(list) {
  if (!Array.isArray(list) || list.length < 2) return Array.isArray(list) ? list.slice() : []
  var groups = {}
  var order = []
  var i
  for (i = 0; i < list.length; i++) {
    var m = list[i]
    if (!m) continue
    var key = String(m.size) + "\t" + String(m.used) + "\t" + String(m.fstype || "")
    if (!groups[key]) {
      groups[key] = []
      order.push(key)
    }
    groups[key].push(m)
  }
  var out = []
  for (i = 0; i < order.length; i++) {
    var rows = groups[order[i]]
    var best = rows[0]
    var j
    for (j = 1; j < rows.length; j++) {
      var t = String(rows[j].target || "")
      var b = String(best.target || "")
      if (t === "/") best = rows[j]
      else if (b !== "/" && t.length > 0 && t.length < b.length) best = rows[j]
    }
    out.push(best)
  }
  return out
}

export function parseDiskInfoDisks(list) {
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

export function parseDiskInfoBacking(obj) {
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

export function parseDiskInfo(env) {
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

// `disk-info usage` envelope → { mounts, temps } merged onto the identity.
export function parseDiskUsage(env) {
  if (!env || typeof env !== "object" || env.ok !== true) return null
  var temps = {}
  var t = env.temps && typeof env.temps === "object" ? env.temps : {}
  for (var k in t) {
    if (!Object.prototype.hasOwnProperty.call(t, k)) continue
    if (!/^[A-Za-z0-9._+-]+$/.test(k)) continue
    var v = num(t[k], null)
    if (v !== null) temps[k] = v
  }
  return { mounts: parseDf(env.dfPayload), temps: temps }
}

export function mergeDiskUsage(info, usage) {
  if (!info) return info
  if (!usage) return info
  var disks = []
  for (var i = 0; i < info.disks.length; i++) {
    var d = info.disks[i]
    var copy = { name: d.name, model: d.model, rotational: d.rotational, sizeBytes: d.sizeBytes, tempC: d.tempC }
    if (Object.prototype.hasOwnProperty.call(usage.temps, d.name)) copy.tempC = usage.temps[d.name]
    disks.push(copy)
  }
  return { disks: disks, mounts: usage.mounts, backing: info.backing }
}

// diskDevice setting: "auto" prefers the disk backing `/`, then the
// largest by sizeBytes, then the first in the rate list. A specific name
// must exist in `disks` (identity) or `rates` (live counters). Mapper
// aliases in `backing` remap onto the physical parent.
export function pickDisk(disks, mounts, rates, setting, backing) {
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
