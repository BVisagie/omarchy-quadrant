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

export function processAppIndex(entries) {
  var result = { keys: {}, executables: {}, aliases: {} }
  var values = entries || []
  for (var i = 0; i < values.length; i++) {
    var entry = values[i]
    if (!entry || entry.noDisplay === true) continue
    var executable = executableName(entry.command)
    add(result.executables, executable, entry)
    var keys = [entry.id, entry.name, entry.icon, entry.startupClass, executable]
    for (var j = 0; j < keys.length; j++) {
      var key = processAppKey(keys[j])
      if (key && !genericExecutable(key)) add(result.keys, key, entry)
    }
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

function uniqueMatch(index, keys, exactCase) {
  var entry = null
  for (var i = 0; i < keys.length; i++) {
    if (!keys[i] || genericExecutable(keys[i])) continue
    var key = exactCase ? String(keys[i]).slice(String(keys[i]).lastIndexOf("/") + 1) : processAppKey(keys[i])
    var found = index["n" + key]
    if (found === null || (found && entry && found.id !== entry.id)) return { ambiguous: true, entry: null }
    if (found) entry = found
  }
  return { ambiguous: false, entry: entry }
}

export function processDesktopEntry(index, row) {
  if (!index || !row || row.appKeysTruncated) return null
  var keys = row.appKeys || [row.exe, row.script, row.comm]
  var match = uniqueMatch(index.executables, keys, true)
  if (match.ambiguous || match.entry) return match.entry
  match = uniqueMatch(index.keys, keys, false)
  if (match.ambiguous || match.entry) return match.entry
  var friendly = genericExecutable(row.comm) ? undefined : index.keys["n" + processAppKey(row.comm)]
  if (friendly !== undefined) return friendly
  match = uniqueMatch(index.aliases, keys.concat([row.comm]), false)
  return match.entry
}
