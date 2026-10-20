// Desktop identity matching only. Never interpret or execute an Exec string
// or infer ownership from arbitrary arguments in a process command line.
import { INTERPRETER_COMMS, labelFromHints } from "./processes.mjs"

export function processAppKey(value) {
  var key = String(value || "").toLowerCase()
  key = key.slice(key.lastIndexOf("/") + 1)
  if (key.slice(-8) === ".desktop") key = key.slice(0, -8)
  return key
}

function genericExecutable(value) {
  var key = processAppKey(value)
  return !!(INTERPRETER_COMMS[key] || /^electron[0-9]*$/.test(key)
    || /^python[23]\.[0-9]+$/.test(key)
    || /^(env|flatpak|snap|gtk-launch|uwsm|uwsm-app|application-x-executable)$/.test(key))
}

function executableName(command) {
  if (!command || !command.length) return ""
  var i = 0, name = String(command[i] || "")
  // Quickshell already parsed quoting into command[]. Only unwrap simple env
  // assignments; options and shell/runtime launchers remain metadata-only.
  if (processAppKey(name) === "env") {
    i++
    while (i < command.length && /^[A-Za-z_][A-Za-z0-9_]*=/.test(command[i])) i++
    name = String(command[i] || "")
    if (name.charAt(0) === "-") return ""
  }
  name = name.slice(name.lastIndexOf("/") + 1)
  return name && !genericExecutable(name) ? name : ""
}

function add(index, key, entry) {
  if (!key) return
  key = "n" + key
  var previous = index[key]
  if (previous === undefined) index[key] = entry
  else if (previous && previous.id !== entry.id) index[key] = null
}

function addKeys(index, values, entry) {
  for (var i = 0; i < values.length; i++) {
    var key = processAppKey(values[i])
    if (key && !genericExecutable(key)) add(index, key, entry)
  }
}

export function processAppIndex(entries) {
  var result = { ids: {}, startupClasses: {}, keys: {}, executables: {}, aliases: {} }
  var values = entries || []
  for (var i = 0; i < values.length; i++) {
    var entry = values[i]
    if (!entry || entry.noDisplay === true) continue
    var executable = executableName(entry.command)
    add(result.executables, executable, entry)
    addKeys(result.ids, [entry.id], entry)
    addKeys(result.startupClasses, [entry.startupClass], entry)
    addKeys(result.keys, [entry.name, entry.icon], entry)
    // Known application families cover launch wrappers such as brave-origin
    // -> brave. Ambiguous family aliases never pick an arbitrary variant.
    var identities = [entry.id, entry.startupClass, executable]
    for (var k = 0; k < identities.length; k++) {
      var label = labelFromHints(identities[k], "")
      if (label) add(result.aliases, processAppKey(label), entry)
    }
  }
  return result
}

function matchHint(index, hint) {
  if (!hint || genericExecutable(hint)) return null
  var executable = String(hint).slice(String(hint).lastIndexOf("/") + 1)
  var key = "n" + processAppKey(hint)
  // A shared inventory key supplies no evidence. Apply precedence per hint
  // so a desktop ID can disambiguate a shared launcher or startup class.
  return index.executables["n" + executable] || index.ids[key] || index.startupClasses[key]
    || index.keys[key] || index.aliases[key] || null
}

function uniqueMatch(index, keys) {
  var entry = null
  for (var i = 0; i < keys.length; i++) {
    var found = matchHint(index, keys[i])
    // Distinct retained hints must agree even when they match different tiers.
    if (found && entry && found.id !== entry.id) return { ambiguous: true, entry: null }
    if (found) entry = found
  }
  return { ambiguous: false, entry: entry }
}

export function processDesktopEntry(index, row) {
  if (!index || !row || row.appKeysTruncated) return null
  var keys = row.appKeys || [row.exe, row.script]
  var match = uniqueMatch(index, keys)
  if (match.ambiguous || match.entry) return match.entry
  // Group labels are generated for display, so only consult them when raw
  // identity hints provide neither a match nor a conflict.
  return matchHint(index, row.comm)
}
