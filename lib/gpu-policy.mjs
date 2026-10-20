// Pure control serialization and freshness rules shared by Store tests.
export function gpuControlSignature(gpu, igpu, wanted, integratedWanted) {
  return JSON.stringify([gpu && gpu.path, gpu && gpu.vendor, gpu && gpu.deviceId,
    igpu && igpu.path, igpu && igpu.vendor, igpu && igpu.deviceId, !!wanted, !!integratedWanted,
    gpu && [gpu.pciId, gpu.subsystemId, gpu.revision], igpu && [igpu.pciId, igpu.subsystemId, igpu.revision]])
}

export function gpuControlText(generation, expires, gpu, igpu, wanted, integratedWanted) {
  function fields(device, demand) {
    if (!device || !/^(amd|intel)$/.test(device.vendor) || !/^\/[^\s]*\/class\/drm\/card[0-9]+\/device$/.test(device.path || ""))
      return [0, "-", "-"]
    return [demand ? 1 : 0, device.path, device.vendor]
  }
  return [1, generation, Math.floor(expires)].concat(fields(gpu, wanted), fields(igpu, integratedWanted)).join("\t") + "\n"
}

export function gpuReadingLabel(state, pm, acquiredMs, nowMs, staleMs) {
  var age = acquiredMs > 0 ? Math.max(0, nowMs - acquiredMs) : null
  var label = state === "sleeping" ? "Sleeping" : state === "transitioning" ? "Power transition"
    : state === "failed" ? "Collection failed" : state === "held" ? "Held"
    : state !== "fresh" ? "Waiting for a reading" : age !== null && age > staleMs ? "Stale" : "Live"
  if (pm === "disabled") label += " · runtime PM disabled"
  else if (pm === "unavailable" || pm === "unsupported") label += " · runtime PM unavailable"
  return label + (age === null ? "" : " · last read " + Math.floor(age / 1000) + "s ago")
}
