import test from "node:test"
import assert from "node:assert/strict"
import { gpuControlText, gpuControlSignature, gpuReadingLabel, pushTimedWindow,
  pushBucket, pushHistoryGap, sanitizeBuckets, graphRuns, graphStats } from "../../lib/index.mjs"

const gpu = { path: "/sys/class/drm/card1/device", vendor: "amd", deviceId: "0000:03:00.0" }

test("control keeps independent device demand and invalidates changed roles/identities", () => {
  assert.equal(gpuControlText(2, 12345, gpu, null, true, false),
    "1\t2\t12345\t1\t/sys/class/drm/card1/device\tamd\t0\t-\t-\n")
  assert.notEqual(gpuControlSignature(gpu, null, true, false), gpuControlSignature(gpu, null, false, false))
  assert.notEqual(gpuControlSignature(gpu, null, true, false),
    gpuControlSignature({ ...gpu, deviceId: "0000:04:00.0" }, null, true, false))
  assert.notEqual(gpuControlSignature(gpu, null, true, false), gpuControlSignature({ ...gpu, pciId: "1002:9999" }, null, true, false))
  assert.match(gpuControlText(1, 50, { ...gpu, path: "/tmp/a\nb" }, null, true, false), /\t0\t-\t-/)
})

test("freshness uses acquisition age, keeps zero age, and describes PM fallback", () => {
  assert.equal(gpuReadingLabel("sleeping", "suspended", 1000, 6500, 6000), "Sleeping · last read 5s ago")
  assert.equal(gpuReadingLabel("fresh", "disabled", 1000, 1000, 6000), "Live · runtime PM disabled · last read 0s ago")
  assert.equal(gpuReadingLabel("fresh", "active", 1000, 9000, 6000), "Stale · last read 8s ago")
  assert.equal(gpuReadingLabel("failed", "unreadable", 0, 9000, 6000), "Collection failed")
})

test("short suppression breaks minute and persisted hour graphs without counting cached values", () => {
  let minute = pushTimedWindow([], { b: 0, v: 20 }, 101, 60, 242)
  minute = pushHistoryGap(minute, 102, 60, 242)
  minute = pushHistoryGap(minute, 103, 60, 242)
  minute = pushTimedWindow(minute, { b: 40, v: 30 }, 104, 60, 242)
  assert.equal(minute.length, 4)
  assert.equal(graphRuns(minute, ["b"], 8).length, 2)
  assert.equal(graphStats(minute, ["b"]).avg, 20)
  let hour = pushBucket([], { b: 0 }, 101, 10, 3600)
  hour = pushHistoryGap(hour, 102, 3600, 1080)
  hour = pushBucket(hour, { b: 40 }, 104, 10, 3600)
  hour = pushBucket(hour, { b: 60 }, 105, 10, 3600)
  hour = sanitizeBuckets(hour, 110, 3600, 10)
  assert.deepEqual(hour.map(p => p.n), [1, 0, 2])
  assert.equal(hour[2].b, 50)
  assert.equal(graphRuns(hour, ["b"], 45).length, 2)
  assert.deepEqual(pushHistoryGap(minute, 200, 60, 242), [])
})

test("suppressed plots advance their clock while retaining one boundary and no new measurements", () => {
  let points = pushTimedWindow([], { b: 15 }, 100, 60, 242)
  for (let t = 101; t <= 120; t++) points = pushHistoryGap(points, t, 60, 242)
  assert.deepEqual(points, [{ b: 15, t: 100 }, { t: 101, gap: 1, n: 0 }, { t: 120, gap: 1, n: 0 }])
  assert.deepEqual(graphStats(points, ["b"]), { avg: 15, peak: 15 })
  assert.deepEqual(pushHistoryGap(points, 50, 60, 242), [])
})
