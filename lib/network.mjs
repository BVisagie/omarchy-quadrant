// Interface rates, default-route interface pick, and per-process TCP
// attribution from `ss -tinp`.

import { nonNeg } from "./core.mjs"

// Per-interface byte rates from cumulative counters. Interfaces are joined by
// name; a counter that moved backwards (interface reset) reports 0 for the
// tick rather than a garbage spike.
export function netRates(prevNet, currNet, dtS) {
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

// Default interface across IPv4 AND IPv6 default routes, lowest metric wins;
// IPv4 takes ties. Candidates must exist in the counter list and not be the
// loopback. With no default route at all, fall back to the first non-loopback
// interface that has counters. Returns "" when there is nothing usable.
export function pickInterface(r4, r6, net) {
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

// Strip the port from an ss Local-Address:Port field and normalize so
// IPv4-mapped IPv6 (`::ffff:10.0.0.2`) matches `ip addr` IPv4, and
// scoped link-locals drop the `%iface` zone.
export function normalizeAddr(value) {
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

export function stripSsLocal(addrPort) {
  var s = String(addrPort || "")
  if (s.charAt(0) === "[") {
    var close = s.indexOf("]")
    if (close > 1) return normalizeAddr(s.slice(1, close))
  }
  var c = s.lastIndexOf(":")
  if (c <= 0) return normalizeAddr(s)
  return normalizeAddr(s.slice(0, c))
}

export function ssParseLocal(line, sock) {
  var m = String(line).match(/^\s*\d+\s+\d+\s+(\S+)/)
  if (!m) return
  sock.localAddr = stripSsLocal(m[1])
}

export function ssParseUsers(line, sock) {
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

export function ssScanNumbers(line, sock) {
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

export function parseSs(text) {
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

export function sumSocketsByPid(sockets) {
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

export function socketsOnIface(sockets, ifaceAddrs) {
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
export function computeNetAppRows(prev, curr, ifPrev, ifCurr, dtS, ifaceAddrs) {
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
