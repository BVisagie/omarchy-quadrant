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
//   "r4":  [ { "n","m" } ], "r6": [ { "n","m" }], // default routes + metric
//   "gpu": { "busy","vrU","vrT","t","w","mhz","kind" } | null,
//   "t": 52.0 | null,                             // CPU package temp, deg C
//   "load": [l1, l5, l15],
//   "up": 12345.6, "cores": 16
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
  for (var i = 0; i < keys.length; i++) {
    out[keys[i]] = nonNeg(value[keys[i]])
  }
  return out
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

function parseStreamGpu(value) {
  if (value === null || value === undefined) return null
  if (typeof value !== "object") return null
  var kind = (value.kind === "amd" || value.kind === "intel") ? value.kind : ""
  return {
    busy: num(value.busy, null),
    vramUsed: num(value.vrU, null),
    vramTotal: num(value.vrT, null),
    tempC: num(value.t, null),
    powerW: num(value.w, null),
    clockMhz: num(value.mhz, null),
    freqCurMhz: num(value.fc, null),
    freqMaxMhz: num(value.fm, null),
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
    cores: Math.max(1, Math.round(nonNeg(data.cores) || 1))
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
      cur = { pid: 0, comm: "", rx: null, tx: null }
      out.push(cur)
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
                rx: out[j].rx || 0, tx: out[j].tx || 0 })
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

// Per-process network rates plus the honest unattributed remainder.
//   prev/curr:    parseSs output from two samples
//   ifPrev/ifCurr: { rx, tx } interface counters at the same instants
// Rows carry raw per-interval byte rates. Anything the interface moved that
// could not be attributed to a visible process lands in `other` (pid 0) —
// never silently dropped, never presented as a real process.
function computeNetAppRows(prev, curr, ifPrev, ifCurr, dtS) {
  var empty = { rows: [], other: { rxBps: 0, txBps: 0 }, ifRxBps: 0, ifTxBps: 0 }
  if (!Array.isArray(curr) || !ifCurr || !(dtS > 0)) return empty

  var prevByPid = sumSocketsByPid(prev)
  var currByPid = sumSocketsByPid(curr)

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
// Malformed lines are skipped; the row count is capped.
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
    var index = parseInt(f[0].replace(/^\s+|\s+$/g, ""), 10)
    if (!isFinite(index)) continue
    var field = function (n) {
      var v = String(f[n] || "").replace(/^\s+|\s+$/g, "")
      if (v === "" || v === "N/A" || v === "[Not Supported]" || v === "[N/A]") return null
      return num(v, null)
    }
    out.push({
      index: index,
      name: String(f[1] || "").replace(/^\s+|\s+$/g, ""),
      utilPct: field(2),
      memUsedM: field(3),
      memTotalM: field(4),
      tempC: field(5),
      powerW: field(6),
      clockMhz: field(7)
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

function normalizeAmdGpu(kv) {
  if (!kv || typeof kv !== "object") return null
  return {
    kind: "amd",
    busy: num(kv.gpu_busy_percent, null),
    vramUsed: num(kv.mem_info_vram_used, null),
    vramTotal: num(kv.mem_info_vram_total, null),
    tempC: milliToWhole(kv.temp_edge_mc),        // temp1_input, millidegrees
    tempJunctionC: milliToWhole(kv.temp_junction_mc),
    powerW: microToWhole(kv.power1_average_uw),  // microwatts
    clockMhz: num(kv.sclk_mhz, null)
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

// ------------------------------------------------------- node test shim
// QML ignores this branch (`module` is undefined there); node uses it.

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    clamp: clamp,
    num: num,
    safeJson: safeJson,
    parseStreamLine: parseStreamLine,
    cpuDelta: cpuDelta,
    netRates: netRates,
    swapRates: swapRates,
    memComposition: memComposition,
    swapUsage: swapUsage,
    pickInterface: pickInterface,
    parsePs: parsePs,
    parseSs: parseSs,
    sumSocketsByPid: sumSocketsByPid,
    computeNetAppRows: computeNetAppRows,
    mergeRoster: mergeRoster,
    parseNvidiaCsv: parseNvidiaCsv,
    parseKeyValues: parseKeyValues,
    normalizeAmdGpu: normalizeAmdGpu,
    normalizeIntelGpu: normalizeIntelGpu,
    normalizeGpuList: normalizeGpuList,
    pickGpu: pickGpu,
    formatBytes: formatBytes,
    formatRate: formatRate,
    formatKiB: formatKiB,
    formatPct: formatPct,
    formatTemp: formatTemp,
    formatMhz: formatMhz,
    formatWatts: formatWatts,
    formatLoad: formatLoad,
    formatUptime: formatUptime,
    pushCapped: pushCapped
  }
}
