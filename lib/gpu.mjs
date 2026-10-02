// GPU identity and live metrics: nvidia-smi CSV, amd/intel sysfs,
// card inventory, integrated vs dedicated roles.

import { nameAndCollapse } from "./processes.mjs"
import { clamp, clipStr, collapseSpaces, num } from "./core.mjs"
import { normalizeDeviceSetting, normalizeIntegratedGpuDevice } from "./settings.mjs"
import { mergeGpuLive } from "./drm.mjs"

// Parse `nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,
// memory.total,temperature.gpu,power.draw,clocks.gr --format=csv,noheader,
// nounits`. Fields may be "N/A" or "[Not Supported]" — those become null.
// GPU names can contain commas; extra fields are rejoined into `name` so
// the last six numeric columns stay aligned. Malformed lines are skipped;
// the row count is capped.
export function parseNvidiaCsv(text, maxRows) {
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

// nvidia-smi compute apps as "pid<TAB>usedMiB<TAB>comm" lines built by
// gpu-stats → [{ pid, memUsedM, comm }].
export function parseNvidiaApps(text, maxRows) {
  var limit = (maxRows === undefined) ? 32 : maxRows
  var out = []
  if (typeof text !== "string" || text.length === 0) return out
  var lines = text.split("\n")
  for (var i = 0; i < lines.length && out.length < limit; i++) {
    var f = lines[i].split("\t")
    if (f.length < 2) continue
    var pid = num(f[0], null)
    var mem = num(f[1], null)
    if (pid === null || pid <= 0 || mem === null || mem < 0) continue
    out.push({ pid: Math.round(pid), memUsedM: mem, comm: clipStr(f.length > 2 ? f[2] : "", 128) })
  }
  return out
}

// gpu-stats ships AMD/Intel sysfs contents as raw `key=value` lines inside
// the JSON envelope; parsing and unit conversion live here so fixtures can
// exercise them. Values stay strings until validated.
export function parseKeyValues(text) {
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

export function milliToWhole(value) {
  var n = num(value, null)
  return n === null ? null : n / 1000
}

export function microToWhole(value) {
  var n = num(value, null)
  return n === null ? null : n / 1000000
}

export function enginesFromKv(kv) {
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

export function normalizeAmdGpu(kv) {
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

// Intel sysfs still has no busy percent without CAP_PERFMON. Frequency
// ratio is an estimate labeled "freq" until DRM fdinfo supplies a measured
// busy overlay (mergeGpuLive).
export function normalizeIntelGpu(kv) {
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

export function clipPciClass(value) {
  var s = String(value || "").toLowerCase()
  if (s.indexOf("0x") === 0) s = s.slice(2)
  if (!/^[0-9a-f]{4,8}$/.test(s)) return ""
  return "0x" + s
}

export function normalizeGpuListEntry(e) {
  if (!e || typeof e !== "object") return null
  var vendor = e.vendor
  if (vendor !== "amd" && vendor !== "intel" && vendor !== "nvidia") return null
  if (typeof e.card !== "string" || !/^card[0-9]+$/.test(e.card)) return null
  if (typeof e.path !== "string" || e.path.indexOf("/sys/") !== 0) return null
  var slot = (typeof e.slot === "string" && /^[0-9a-fA-F:.]+$/.test(e.slot)) ? e.slot : ""
  var driver = clipStr(e.driver, 32)
  if (driver && !/^[A-Za-z0-9._+-]+$/.test(driver)) driver = ""
  var pciId = ""
  if (typeof e.pciId === "string" && /^[0-9a-fA-F]{4}:[0-9a-fA-F]{4}$/.test(e.pciId))
    pciId = e.pciId.toLowerCase()
  return {
    card: e.card,
    vendor: vendor,
    path: e.path,
    boot: e.boot === true,
    slot: slot,
    pciClass: clipPciClass(e.pciClass),
    pciId: pciId,
    driver: driver
  }
}

export function normalizeGpuList(data) {
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
export function pickGpu(gpus, setting) {
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

export function isIntelIgpuSlot(slot) {
  return /^[0-9a-fA-F]+:00:02\./.test(String(slot || ""))
}

export function amdLooksIntegrated(name) {
  var s = String(name || "")
  if (/Radeon Graphics/i.test(s)) return true
  if (/Radeon \d{3}M\b/i.test(s)) return true
  if (/\b(Phoenix|Raphael|Rembrandt|Cezanne|Renoir|Strix|Krackan|Barcelo|Lucienne|Mendocino|Picasso|Raven)[0-9]*\b/i.test(s)) return true
  if (/Hawk Point|Granite Ridge/i.test(s)) return true
  return false
}

export function classifyGpuRole(gpu, setting, name) {
  var mode = normalizeIntegratedGpuDevice(setting)
  if (!gpu || typeof gpu !== "object") return "discrete"
  if (mode === "none") return "discrete"
  if (mode !== "auto") return gpu.card === mode ? "integrated" : "discrete"
  if (gpu.vendor === "nvidia") return "discrete"
  if (gpu.vendor === "intel") return isIntelIgpuSlot(gpu.slot) ? "integrated" : "discrete"
  if (gpu.vendor === "amd") return amdLooksIntegrated(name || gpu.name) ? "integrated" : "discrete"
  return "discrete"
}

export function pickIntegratedGpu(list) {
  if (!Array.isArray(list) || list.length === 0) return null
  var i
  for (i = 0; i < list.length; i++) if (list[i].boot) return list[i]
  return list[0]
}

// Topology reconciliation allocates a new object every pass. Identity is
// card + vendor + path so a same-card rebuild does not drop live samples.
export function gpuIdentityEqual(a, b) {
  if (a === b) return true
  if (!a || !b) return false
  return String(a.card || "") === String(b.card || "")
      && String(a.vendor || "") === String(b.vendor || "")
      && String(a.path || "") === String(b.path || "")
}

// quadrant-stream only samples AMD/Intel sysfs. NVIDIA, missing cards, and
// path-less rows produce "" so a name-only topology rebuild does not look
// like a different sampler target.
export function gpuStreamVendor(gpu) {
  if (!gpu || typeof gpu !== "object") return ""
  var vendor = String(gpu.vendor || "")
  if (vendor !== "amd" && vendor !== "intel") return ""
  if (String(gpu.path || "") === "") return ""
  return vendor
}

export function gpuStreamPath(gpu) {
  if (gpuStreamVendor(gpu) === "") return ""
  return String(gpu.path || "")
}

export function gpuStreamSignature(gpu) {
  var vendor = gpuStreamVendor(gpu)
  if (vendor === "") return ""
  return vendor + ":" + gpuStreamPath(gpu)
}

export function gpuDevicePinMessage(gpus, setting) {
  var wanted = normalizeDeviceSetting(setting)
  if (wanted === "auto" || wanted === "") return ""
  if (!Array.isArray(gpus)) return ""
  var i
  for (i = 0; i < gpus.length; i++) {
    if (gpus[i].card === wanted && gpus[i].role === "integrated")
      return "Pinned GPU " + wanted + " is integrated; it is shown on the CPU tab"
  }
  return ""
}

export function reconcileGpuTopology(rawGpus, sysInfo, integratedSetting) {
  var list = Array.isArray(rawGpus) ? rawGpus : []
  var byCard = sysInfo && sysInfo.gpusByCard ? sysInfo.gpusByCard : {}
  var merged = []
  var discrete = []
  var integrated = []
  var i
  for (i = 0; i < list.length; i++) {
    var g = list[i]
    if (!g) continue
    var info = byCard[g.card] || null
    var slot = g.slot || (info && info.slot) || ""
    var driver = g.driver || (info && info.driver) || ""
    var pciId = g.pciId || (info && info.pciId) || ""
    var name = (info && info.name) || ""
    var row = {
      card: g.card,
      vendor: g.vendor,
      path: g.path,
      boot: g.boot === true,
      slot: slot,
      pciClass: g.pciClass || "",
      pciId: pciId,
      driver: driver,
      name: name
    }
    row.role = classifyGpuRole(row, integratedSetting, name)
    merged.push(row)
    if (row.role === "integrated") integrated.push(row)
    else discrete.push(row)
  }
  return {
    gpus: merged,
    discreteGpus: discrete,
    integratedGpus: integrated,
    integratedGpu: pickIntegratedGpu(integrated)
  }
}

export function parseSystemGpus(list, lspciBySlot) {
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

export function gpuVendorLabel(vendor) {
  if (vendor === "amd") return "AMD"
  if (vendor === "intel") return "Intel"
  if (vendor === "nvidia") return "NVIDIA"
  return vendor ? String(vendor) : "--"
}

export function cleanGpuName(raw) {
  var name = collapseSpaces(raw)
  if (!name) return ""
  name = name.replace(/\s*\([^)]*rev[^)]*\)/i, "")
  name = name.replace(/\s*\((Ice Lake|Comet Lake|Tiger Lake|Alder Lake|Raptor Lake|Meteor Lake|Arrow Lake|Lunar Lake|Panther Lake|Coffee Lake|Haswell|Skylake|Kaby Lake|Whiskey Lake|Amber Lake)[^)]*\)/i, "")
  name = name.replace(/^Advanced Micro Devices, Inc\.?\s*/i, "")
  name = name.replace(/^(AMD\/ATI|ATI)\s*/i, "AMD ")
  name = name.replace(/^Intel Corporation\s*/i, "Intel ")
  name = name.replace(/^NVIDIA Corporation\s*/i, "NVIDIA ")
  name = name.replace(/\s+Corporation\b/g, "")
  name = collapseSpaces(name)
  var branded = name.match(/^[^[\]]+\[([^[\]]+)\]\s*$/)
  if (branded) {
    var inside = collapseSpaces(branded[1].split("/")[0])
    if (inside) name = inside
  }
  return name || collapseSpaces(raw)
}

export function nvidiaMiBToBytes(mib) {
  var n = num(mib, null)
  if (n === null || n < 0) return null
  return n * 1024 * 1024
}

// VRAM in use as a percentage for any live GPU shape we know (stream
// sysfs, DRM overlay, nvidia-smi rows); null when either side is unknown.
export function gpuVramPct(live) {
  if (!live || typeof live !== "object") return null
  var used = num(live.vramUsed, null)
  var total = num(live.vramTotal, null)
  if (used === null || total === null) {
    var mu = num(live.memUsedM, null)
    var mt = num(live.memTotalM, null)
    if (mu !== null && mt !== null) { used = mu; total = mt }
  }
  if (used === null || total === null || !(total > 0)) return null
  return clamp(100 * used / total, 0, 100)
}

// Per-process GPU rows for the panel: collapse same-app rows first, then
// rank by busy share and resident memory, and only then apply the row
// limit — NVIDIA rows carry no busy figure, so ranking by value alone
// would drop the biggest memory consumers before they were ever sorted.
//   raw — [{ pid, comm, value: busy %, vram: bytes }]
export function rankGpuRows(raw, limit) {
  var list = Array.isArray(raw) ? raw : []
  var cap = Math.max(1, Math.round(num(limit, 5)))
  var collapsed = nameAndCollapse(list.map(function (r) {
    return { pid: r.pid, comm: r.comm, exe: "", cmd: "", script: "", value: num(r.value, 0) || 0, read: num(r.vram, 0) || 0 }
  }), 4096)
  var out = []
  for (var i = 0; i < collapsed.length; i++) {
    out.push({ pid: collapsed[i].pid, comm: collapsed[i].comm, value: collapsed[i].value, vram: collapsed[i].read,
               sortKey: collapsed[i].value * 1e12 + collapsed[i].read })
  }
  out.sort(function (a, b) { return b.sortKey - a.sortKey || a.pid - b.pid })
  return out.slice(0, cap)
}
