// Hardware identity from system-info: lspci, host DMI, and the merged
// sysInfo object.

import { clipStr, collapseSpaces } from "./core.mjs"
import { parseSystemCpu } from "./cpu.mjs"
import { parseSystemMem } from "./memory.mjs"
import { parseSystemGpus } from "./gpu.mjs"

export function parseLspciMm(text) {
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

export function parseSystemHost(host) {
  if (!host || typeof host !== "object") return { kernel: "", sysVendor: "", productName: "" }
  return {
    kernel: clipStr(host.kernel, 64),
    sysVendor: clipStr(host.sysVendor, 64),
    productName: clipStr(host.productName, 64)
  }
}

export function parseSystemInfo(env) {
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

// sys_vendor + product_name, without repeating the vendor when the
// product already starts with it ("Framework Laptop 16").
export function junkDmi(value) {
  var t = collapseSpaces(value).toLowerCase()
  if (!t) return true
  return t === "system product name" || t === "system manufacturer"
    || t === "to be filled by o.e.m." || t === "to be filled by oem"
    || t === "default string" || t === "not specified" || t === "none"
    || t === "n/a" || t === "na" || t === "oem"
}

export function hostLine(host) {
  if (!host || typeof host !== "object") return ""
  var vendor = collapseSpaces(host.sysVendor)
  var product = collapseSpaces(host.productName)
  if (junkDmi(vendor)) vendor = ""
  if (junkDmi(product)) product = ""
  if (vendor && product) {
    if (product.toLowerCase().indexOf(vendor.toLowerCase()) === 0) return product
    return vendor + " " + product
  }
  return product || vendor
}
