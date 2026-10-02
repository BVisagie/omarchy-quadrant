// Process rows: ps / process-sample parsing, wrapper-aware naming,
// per-app collapsing and the sticky roster.

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

// One process-sample payload (scripts/qproc.py) → validated lists.
export function parseProcessRowList(list, cap) {
  var out = []
  if (!Array.isArray(list)) return out
  for (var i = 0; i < list.length && out.length < cap; i++) {
    var e = list[i]
    if (!e || typeof e !== "object") continue
    var pid = num(e.pid, null)
    var value = num(e.value, null)
    if (pid === null || pid <= 0 || value === null || value < 0) continue
    var row = {
      pid: Math.round(pid),
      value: value,
      comm: clipStr(e.comm, 128),
      exe: clipStr(e.exe, 64),
      cmd: clipStr(e.cmd, 160),
      script: clipStr(e.script, 64)
    }
    if (e.core !== undefined) row.core = Math.max(0, num(e.core, 0) || 0)
    if (e.read !== undefined) row.read = Math.max(0, num(e.read, 0) || 0)
    if (e.write !== undefined) row.write = Math.max(0, num(e.write, 0) || 0)
    if (e.kind === "pss" || e.kind === "rss") row.kind = e.kind
    out.push(row)
  }
  return out
}

export function parseProcessSample(text) {
  var data = typeof text === "string" ? safeJson(text) : (text && typeof text === "object" ? text : null)
  if (!data) return null
  return {
    dt: Math.max(0, num(data.dt, 0) || 0),
    ncpu: Math.max(1, Math.round(num(data.ncpu, 1) || 1)),
    procs: Math.max(0, Math.round(num(data.procs, 0) || 0)),
    running: Math.max(0, Math.round(num(data.running, 0) || 0)),
    threads: Math.max(0, Math.round(num(data.threads, 0) || 0)),
    ioVisible: Math.max(0, Math.round(num(data.ioVisible, 0) || 0)),
    ioHidden: Math.max(0, Math.round(num(data.ioHidden, 0) || 0)),
    cpu: parseProcessRowList(data.cpu, 32),
    mem: parseProcessRowList(data.mem, 32),
    io: parseProcessRowList(data.io, 32)
  }
}

export function nameAndCollapse(rows, maxRows) {
  var limit = Math.max(1, Math.round(num(maxRows, 5)))
  var list = Array.isArray(rows) ? rows : []
  var groups = {}
  var order = []
  var i
  for (i = 0; i < list.length; i++) {
    var r = list[i]
    if (!r) continue
    var name = displayName(r.comm, r.exe, r.cmd, r.script)
    if (!name) continue
    var key = name.toLowerCase()
    if (!groups[key]) {
      groups[key] = { pid: r.pid, comm: name, value: 0, n: 0, read: 0, write: 0, core: 0 }
      order.push(key)
    }
    var g = groups[key]
    g.value += num(r.value, 0) || 0
    g.read += num(r.read, 0) || 0
    g.write += num(r.write, 0) || 0
    g.core += num(r.core, 0) || 0
    if (r.kind) g.kind = g.kind === "rss" ? "rss" : String(r.kind)
    g.n += 1
    if (r.pid < g.pid) g.pid = r.pid
  }
  var out = []
  for (i = 0; i < order.length; i++) out.push(groups[order[i]])
  out.sort(function (a, b) { return b.value - a.value || a.pid - b.pid })
  if (out.length > limit) out.length = limit
  return out
}

// Sticky roster merge: rows that survive from the previous sample keep their
// on-screen position and update in place; newcomers append sorted by sortKey;
// vanished rows drop out. Never reorders existing rows, so the list does not
// jump around every tick. The catch-all row is keyed strictly on pid === 0,
// so a process literally named "Other traffic" cannot collide with it.
export function mergeRoster(prevRows, nextRows, maxRows) {
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
