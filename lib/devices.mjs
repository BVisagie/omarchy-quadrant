// Migrate a legacy pin only while its name can be resolved by inventory.
// An ID takes precedence; keep its current kernel name for older releases.
import { pickGpu } from "./gpu.mjs"
import { pickDisk } from "./disk.mjs"

// A live policy change means "unpin" when the ID did not also change.
// Initial settings and ID-only edits retain the identity's precedence.
export function devicePolicyResetPatch(previous, next) {
  var patch = {}
  if (!previous || !next) return patch
  var names = ["gpuDevice", "integratedGpuDevice", "diskDevice"]
  for (var i = 0; i < names.length; i++) {
    var key = names[i]
    var idKey = key + "Id"
    var policy = next[key]
    if (policy !== "auto" && !(key === "integratedGpuDevice" && policy === "none")) continue
    if (previous[key] === policy || !next[idKey] || previous[idKey] !== next[idKey]) continue
    patch[idKey] = ""
  }
  return patch
}

export function devicePinMigration(cfg, gpus, diskInfo) {
  var patch = {}
  var names = ["gpuDevice", "integratedGpuDevice"]
  if (Array.isArray(gpus)) {
    for (var i = 0; i < names.length; i++) {
      var key = names[i]
      var idKey = key + "Id"
      if (!cfg[idKey] && (cfg[key] === "auto" || cfg[key] === "none")) continue
      var gpu = pickGpu(gpus, cfg[key], cfg[idKey])
      if (!gpu) continue
      if (cfg[key] !== gpu.card) patch[key] = gpu.card
      if (!cfg[idKey] && gpu.deviceId) patch[idKey] = gpu.deviceId
    }
  }
  if (diskInfo && (cfg.diskDeviceId || cfg.diskDevice !== "auto")) {
    var name = pickDisk(diskInfo.disks, diskInfo.mounts, [], cfg.diskDevice, diskInfo.backing, cfg.diskDeviceId)
    for (var j = 0; j < diskInfo.disks.length; j++) {
      var disk = diskInfo.disks[j]
      if (disk.name !== name) continue
      if (cfg.diskDevice !== name) patch.diskDevice = name
      if (!cfg.diskDeviceId && disk.deviceId) patch.diskDeviceId = disk.deviceId
      break
    }
  }
  return patch
}
