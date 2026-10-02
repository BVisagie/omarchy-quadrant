// One line of quadrant-stream output → a validated sample object.

import { nonNeg, num, safeJson } from "./core.mjs"
import { parseCpuCoreArray, parseCpuCoreIds } from "./cpu.mjs"
import { isExcludedDiskName, isPartitionName } from "./disk.mjs"

export function parseCpuArray(value) {
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

export function parseStreamMem(value) {
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

export function parseStreamPsi(value) {
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

export function parseStreamNet(value) {
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

export function parseStreamDisk(value) {
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

export function parseStreamRoutes(value) {
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

export function parseGpuEngines(value) {
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

export function parseStreamGpu(value) {
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

export function parseStreamLine(line) {
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
    cpuCores: parseCpuCoreArray(data.cc),
    cpuCoreIds: parseCpuCoreIds(data.ci, parseCpuCoreArray(data.cc).length),
    disk: parseStreamDisk(data.disk)
  }
}
