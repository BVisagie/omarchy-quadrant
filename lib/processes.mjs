// Process rows: ps / process-sample parsing, wrapper-aware naming,
// per-app collapsing and the sticky roster.

import { formatKiB, formatPct, formatRate } from "./format.mjs"
import { clipStr, collapseSpaces, num, safeJson } from "./core.mjs"

// Parse `ps -eo pid=,<metric>=,comm=` output. The metric column is pcpu for
// the CPU tab and rss (KiB) for the memory tab. comm is attacker-controlled:
// it travels inside a JSON string and is only ever rendered as PlainText, so
// a hostile name can at worst make its own row look odd — lines that no
// longer parse (e.g. an embedded newline split the row) are skipped.
export function parsePs(text, maxRows) {
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

// Friendly names for the top-N roster. Wrapper binaries (electron, chrome)
// take a label from exe basename or cmdline tokens against a fixed map —
// never a free-form substring of argv. Kernel threads get a short class.
export var WRAPPER_COMMS = {
  electron: 1, chrome: 1, chromium: 1, "chromium-browser": 1,
  firefox: 1, "firefox-bin": 1
}

export var APP_LABELS = [
  ["brave-browser", "Brave"],
  ["brave-bin", "Brave"],
  ["brave", "Brave"],
  ["google-chrome", "Chrome"],
  ["microsoft-edge", "Edge"],
  ["msedge", "Edge"],
  ["vivaldi-bin", "Vivaldi"],
  ["vivaldi", "Vivaldi"],
  ["signal-desktop", "Signal"],
  ["telegram-desktop", "Telegram"],
  ["code-oss", "Code"],
  ["vscodium", "Codium"],
  ["codium", "Codium"],
  ["obsidian", "Obsidian"],
  ["1password", "1Password"],
  ["discord", "Discord"],
  ["spotify", "Spotify"],
  ["slack", "Slack"],
  ["steam", "Steam"],
  ["cursor", "Cursor"],
  ["ghostty", "Ghostty"],
  ["chromium", "Chromium"],
  ["chrome", "Chrome"],
  ["firefox", "Firefox"],
  ["code", "Code"]
]

export var KWORKER_TASK = {
  events: "kworker events",
  events_unbound: "kworker events",
  events_power_efficient: "kworker events",
  "mm_percpu_wq": "kworker mm",
  netns: "kworker netns",
  kcryptd: "kcryptd"
}

export function basenameToken(path) {
  var s = collapseSpaces(path)
  if (!s) return ""
  var slash = s.lastIndexOf("/")
  if (slash >= 0) s = s.slice(slash + 1)
  return s.replace(/\s+/g, "")
}

export function hintTokens(exe, cmd) {
  var s = (basenameToken(exe) + " " + String(cmd || "")).toLowerCase()
  return s.split(/[^a-z0-9._+-]+/)
}

export function labelFromHints(exe, cmd) {
  var tokens = hintTokens(exe, cmd)
  var seen = {}
  var t
  for (t = 0; t < tokens.length; t++) {
    if (tokens[t]) seen[tokens[t]] = true
  }
  var i
  for (i = 0; i < APP_LABELS.length; i++) {
    if (seen[APP_LABELS[i][0]]) return APP_LABELS[i][1]
  }
  return ""
}

export function kworkerLabel(comm) {
  var m = String(comm || "").match(/^kworker\/[^-\s]*-(.+)$/i)
  if (!m) return "kworker"
  var task = m[1].toLowerCase()
  if (KWORKER_TASK[task]) return KWORKER_TASK[task]
  if (task.indexOf("events") === 0) return "kworker events"
  if (task.indexOf("btrfs") === 0) return "kworker btrfs"
  if (task.indexOf("flush") === 0) return "kworker flush"
  return "kworker"
}

export var INTERPRETER_COMMS = {
  python: true, python3: true, python2: true, node: true, nodejs: true, bun: true, deno: true,
  ruby: true, perl: true, bash: true, sh: true, zsh: true, dash: true, fish: true, lua: true,
  php: true, java: true, rscript: true
}

export function displayName(comm, exe, cmd, script) {
  var raw = clipStr(collapseSpaces(comm), 64)
  if (!raw) return ""
  // `python3 foo.py` is foo.py, not one of six "python3" rows.
  var scriptName = clipStr(collapseSpaces(script), 64)
  if (scriptName && /^[^\/\s]+$/.test(scriptName)) {
    var ikey = raw.toLowerCase()
    if (INTERPRETER_COMMS[ikey] || /^python3\.[0-9]+$/.test(ikey)) return scriptName
  }
  if (/^kworker\//i.test(raw)) return kworkerLabel(raw)
  if (/^kswapd/i.test(raw)) return "kswapd"
  if (/^ksoftirqd/i.test(raw)) return "ksoftirqd"
  if (/^kcompactd/i.test(raw)) return "kcompactd"
  if (/^khugepaged$/i.test(raw)) return "khugepaged"
  if (/^migration\//i.test(raw)) return "migration"
  if (/^watchdog\//i.test(raw)) return "watchdog"
  var key = raw.toLowerCase()
  if (WRAPPER_COMMS[key]) {
    var hinted = labelFromHints(exe, cmd)
    if (hinted) return hinted
    var exeBase = basenameToken(exe)
    if (exeBase && exeBase.toLowerCase() !== key) return clipStr(exeBase, 64)
  }
  var direct = labelFromHints(raw, "")
  if (direct && !WRAPPER_COMMS[key]) {
    // comm itself is a known app id
    if (raw.toLowerCase() === direct.toLowerCase()) return direct
  }
  return raw
}

export function parseProcRows(text, maxRows) {
  var cap = (maxRows === undefined) ? 32 : Math.max(1, Math.round(num(maxRows, 32)))
  if (typeof text === "string") {
    var trimmed = text.replace(/^\s+/, "")
    if (trimmed.charAt(0) === "[") {
      var parsed = safeJson(trimmed)
      var out = []
      if (Array.isArray(parsed)) {
        var i
        for (i = 0; i < parsed.length && out.length < cap; i++) {
          var e = parsed[i]
          if (!e || typeof e !== "object") continue
          var pid = num(e.pid, null)
          var value = num(e.value, null)
          if (pid === null || value === null) continue
          out.push({
            pid: Math.round(pid),
            value: value,
            comm: clipStr(e.comm, 128),
            exe: clipStr(e.exe, 64),
            cmd: clipStr(e.cmd, 160)
          })
        }
      }
      return out
    }
  }
  return parsePs(text, cap)
}

// One process-sample payload → validated lists. Transport is bounded at
// 1 MiB by helper-envelope; expanded rows are never clipped before grouping
// or search. Missing rates remain null, including genuinely restricted I/O.
function rate(value) {
  var n = num(value, null)
  return n !== null && n >= 0 ? n : null
}

function processIdentity(e) {
  var pid = num(e.pid, null)
  if (pid === null || pid <= 0) return null
  var row = { pid: Math.round(pid), comm: clipStr(e.comm, 128), exe: clipStr(e.exe, 64),
              cmd: clipStr(e.cmd, 160), script: clipStr(e.script, 64) }
  var start = rate(e.start)
  if (start !== null) row.start = Math.round(start)
  return row
}

export function parseProcessRowList(list, cap) {
  var out = []
  if (!Array.isArray(list)) return out
  for (var i = 0; i < list.length && out.length < cap; i++) {
    var e = list[i]
    if (!e || typeof e !== "object") continue
    var row = processIdentity(e)
    var value = rate(e.value)
    if (!row || value === null) continue
    row.value = value
    if (e.core !== undefined) row.core = rate(e.core)
    if (e.read !== undefined) row.read = rate(e.read)
    if (e.write !== undefined) row.write = rate(e.write)
    if (e.kind === "pss" || e.kind === "rss") row.kind = e.kind
    out.push(row)
  }
  return out
}

export function parseProcessSample(text) {
  var data = typeof text === "string" ? safeJson(text) : (text && typeof text === "object" ? text : null)
  if (!data) return null
  if (data.skipped === true) return { skipped: true, retryAfterMs: Math.max(1, num(data.retryAfterMs, 400)) }
  var expanded = data.mode === "expanded"
  if (expanded && !Array.isArray(data.rows)) return null
  var out = { mode: expanded ? "expanded" : "compact", dt: rate(data.dt) || 0,
              rateState: clipStr(data.rateState, 16), rows: [],
              cpu: parseProcessRowList(data.cpu, 32), mem: parseProcessRowList(data.mem, 32),
              io: parseProcessRowList(data.io, 32) }
  var counts = ["procs", "observed", "unreadable", "running", "threads", "ioVisible", "ioHidden", "cpuReady", "ioReady", "candidateLimit"]
  for (var c = 0; c < counts.length; c++) out[counts[c]] = Math.round(rate(data[counts[c]]) || 0)
  out.ncpu = Math.max(1, Math.round(rate(data.ncpu) || 1))
  if (expanded) {
    for (var i = 0; i < data.rows.length; i++) {
      var e = data.rows[i]
      if (!e || typeof e !== "object") continue
      var row = processIdentity(e)
      if (!row || row.start === undefined) continue
      row.cpu = rate(e.cpu)
      row.core = rate(e.core)
      row.memory = rate(e.memory)
      row.kind = e.kind === "pss" || e.kind === "rss" ? e.kind : "unknown"
      row.read = rate(e.read)
      row.write = rate(e.write)
      row.ioVisible = e.ioVisible === true
      out.rows.push(row)
    }
    out.unreadable += data.rows.length - out.rows.length
  }
  return out
}

export function processMemberKey(row) {
  return String(row.pid) + (row.start === undefined ? "" : ":" + row.start)
}

export function processRowKey(row) {
  return row.groupKey || processMemberKey(row)
}

// A name alone is not an identity: retain history/order/selection only when
// at least one PID:starttime member survives. Legacy network/GPU rows remain
// per-process and use their original PID identity.
export function sameProcessRow(a, b) {
  if (!a || !b || processRowKey(a) !== processRowKey(b)) return false
  if (!a.members || !b.members) return processMemberKey(a) === processMemberKey(b)
  var keys = {}
  for (var i = 0; i < a.members.length; i++) keys["p" + processMemberKey(a.members[i])] = true
  for (var j = 0; j < b.members.length; j++) if (keys["p" + processMemberKey(b.members[j])]) return true
  return false
}

export function nameAndCollapse(rows, maxRows) {
  var limit = Math.max(1, Math.round(num(maxRows, 5)))
  var list = Array.isArray(rows) ? rows : []
  var groups = {}
  var order = []
  for (var i = 0; i < list.length; i++) {
    var r = list[i]
    if (!r) continue
    var name = displayName(r.comm, r.exe, r.cmd, r.script)
    if (!name) continue
    var key = "group:" + name.toLowerCase()
    if (!groups[key]) {
      groups[key] = { groupKey: key, pid: r.pid, comm: name, value: null, n: 0, known: 0,
                      read: null, write: null, core: null, hidden: 0, members: [] }
      order.push(key)
    }
    var g = groups[key]
    var value = rate(r.value)
    if (value !== null) { g.value = (g.value || 0) + value; g.known++ }
    var fields = ["read", "write", "core"]
    for (var f = 0; f < fields.length; f++) {
      var v = rate(r[fields[f]])
      if (v !== null) g[fields[f]] = (g[fields[f]] || 0) + v
    }
    if (r.kind) g.kind = g.kind && g.kind !== r.kind ? "mixed" : r.kind
    if (r.ioVisible === false) g.hidden++
    g.n++
    g.members.push({ pid: r.pid, start: r.start })
    if (r.pid < g.pid) g.pid = r.pid
  }
  var out = []
  for (var j = 0; j < order.length; j++) out.push(groups[order[j]])
  out.sort(function (a, b) { return (b.value === null ? -1 : b.value) - (a.value === null ? -1 : a.value) || a.pid - b.pid })
  if (out.length > limit) out.length = limit
  return out
}

// All eligible members are grouped before a presentation limit. Compact
// arrays retain their explicitly limited candidate scope.
export function processGroups(sample, metric, totalK) {
  var src = sample[metric] || []
  if (sample.mode === "expanded") {
    src = sample.rows.map(function (r) {
      var copy = {}
      for (var k in r) copy[k] = r[k]
      copy.value = metric === "cpu" ? r.cpu : metric === "mem" ? r.memory
                   : (r.read === null || r.write === null ? null : r.read + r.write)
      return copy
    })
  }
  var groups = nameAndCollapse(src, Math.max(1, src.length))
  for (var i = 0; i < groups.length; i++) {
    var g = groups[i]
    g.sortKey = g.value === null ? -1 : g.value
    if (metric === "mem") g.pct = totalK > 0 && g.value !== null ? 100 * g.value / totalK : null
  }
  return groups
}

export function mergeRoster(prevRows, nextRows, maxRows) {
  var limit = Math.max(1, Math.round(num(maxRows, 5)))
  var byKey = {}
  var i
  if (Array.isArray(nextRows)) for (i = 0; i < nextRows.length; i++) {
    var r = nextRows[i]
    if (r) byKey["r" + processRowKey(r)] = r
  }
  var out = []
  if (Array.isArray(prevRows)) for (i = 0; i < prevRows.length; i++) {
    var old = prevRows[i]
    if (!old) continue
    var key = "r" + processRowKey(old)
    var fresh = byKey[key]
    if (!sameProcessRow(old, fresh)) continue
    delete byKey[key]
    out.push(fresh)
  }
  var newcomers = []
  for (var k in byKey) newcomers.push(byKey[k])
  newcomers.sort(function (a, b) { return (b.sortKey || 0) - (a.sortKey || 0) })
  for (i = 0; i < newcomers.length && out.length < limit; i++) out.push(newcomers[i])
  if (out.length > limit) out.length = limit
  return out
}

// Search runs over complete groups before the display cap; a PID match
// retains the whole group's totals and explicitly identifies its members.
export function filterProcessGroups(rows, query, desktopNames, maxRows, sortMode) {
  var q = collapseSpaces(query).toLowerCase()
  var list = Array.isArray(rows) ? rows : []
  var matches = []
  for (var i = 0; i < list.length; i++) {
    var r = list[i]
    var name = desktopNames && desktopNames["n" + r.comm.toLowerCase()] || ""
    var pids = []
    var members = r.members || [{ pid: r.pid }]
    for (var j = 0; j < members.length; j++) if (q && String(members[j].pid).indexOf(q) >= 0) pids.push(members[j].pid)
    if (q && r.comm.toLowerCase().indexOf(q) < 0 && String(name).toLowerCase().indexOf(q) < 0 && pids.length === 0) continue
    var copy = {}
    for (var k in r) copy[k] = r[k]
    copy.matchedPids = pids
    matches.push(copy)
  }
  if (sortMode === "value") matches.sort(function (a, b) { return (b.sortKey === undefined ? -1 : b.sortKey) - (a.sortKey === undefined ? -1 : a.sortKey) || a.pid - b.pid })
  else if (sortMode === "name") matches.sort(function (a, b) { return String(a.comm).toLowerCase().localeCompare(String(b.comm).toLowerCase()) || a.pid - b.pid })
  var count = matches.length
  var cap = Math.max(1, Math.round(num(maxRows, 256)))
  return { rows: matches.slice(0, cap), matches: count, groups: list.length, limited: count > cap }
}

export function formatProcessGroups(rows, metric) {
  return (rows || []).map(function (r) {
    var out = {}
    for (var k in r) out[k] = r[k]
    var partial = r.known < r.n
    var prefix = partial && r.value !== null ? "≥ " : ""
    if (r.value === null) out.valueText = metric === "io" && r.hidden === r.n ? "Restricted" : metric === "mem" ? "Unavailable" : "Measuring…"
    else out.valueText = prefix + (metric === "mem" ? formatKiB(r.value) : metric === "cpu" ? formatPct(r.value, 1) : "R " + formatRate(r.read))
    out.secondaryValueText = metric === "mem" ? formatPct(r.pct, 1) + " · " + (r.kind === "mixed" ? "PSS/RSS" : r.kind === "pss" ? "PSS" : r.kind === "rss" ? "RSS" : "unknown")
                             : metric === "io" && r.write !== null ? prefix + "W " + formatRate(r.write) : ""
    out.hint = metric === "cpu" && r.core !== null ? formatPct(r.core, 0) + " of one core" : metric === "mem" ? (r.kind === "mixed" ? "Mixed proportional/resident accounting" : r.kind === "pss" ? "Proportional memory" : "Resident memory; shared pages count per process") : "All devices; process read_bytes/write_bytes"
    return out
  })
}

export function processScope(stats, metric, expanded) {
  if (!stats) return "Measuring process data…"
  if (expanded && stats.mode !== "expanded") return "Collecting the full eligible roster…"
  var text = stats.mode === "expanded" ? stats.procs + " eligible processes · grouped by name."
             : "Up to " + stats.candidateLimit + " candidates per metric; group counts cover those candidates."
  if (stats.unreadable > 0) text += " " + stats.unreadable + " unreadable or exited during collection."
  if (metric === "mem" && stats.mode === "expanded") text += " RSS: shared pages count per process."
  if (metric === "cpu") text += " CPU is % of the whole machine."
  if (metric === "io") text += " All devices; " + stats.ioHidden + " processes with restricted I/O."
  if (metric !== "mem" && !(stats.dt > 0)) text += " Measuring rates…"
  return text
}
