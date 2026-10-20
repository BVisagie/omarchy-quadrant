import test from "node:test"
import assert from "node:assert/strict"
import { gpuControlText, gpuControlSignature, gpuReadingLabel, gpuReadingAfterGap, gpuActivityHint, pushTimedWindow,
  pushBucket, pushHistoryGap, pushBucketGap, sanitizeBuckets, graphRuns, graphStats } from "../../lib/index.mjs"

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
  let hour = pushBucket([], { b: 10 }, 91, 10, 3600)
  hour = pushBucket(hour, { b: 0 }, 101, 10, 3600)
  hour = pushBucketGap(hour, 102, 10, 3600)
  hour = pushBucket(hour, { b: 40 }, 104, 10, 3600)
  hour = pushBucket(hour, { b: 60 }, 105, 10, 3600)
  hour = pushBucket(hour, { b: 80 }, 111, 10, 3600)
  hour = sanitizeBuckets(hour, 112, 3600, 10)
  assert.deepEqual(hour.map(p => p.n), [1, 3, 1])
  assert.equal(hour[1].b, 100 / 3)
  assert.equal(hour[1].gap, 1)
  assert.equal(graphRuns(hour, ["b"], 45).length, 2)
  assert.equal(graphStats(hour, ["b"]).avg, 45)
  assert.deepEqual(pushHistoryGap(minute, 200, 60, 242), [])
})

test("suppressed plots advance their clock while retaining one boundary and no new measurements", () => {
  let points = pushTimedWindow([], { b: 15 }, 100, 60, 242)
  for (let t = 101; t <= 120; t++) points = pushHistoryGap(points, t, 60, 242)
  assert.deepEqual(points, [{ b: 15, t: 100 }, { t: 101, gap: 1, n: 0 }, { t: 120, gap: 1, n: 0 }])
  assert.deepEqual(graphStats(points, ["b"]), { avg: 15, peak: 15 })
  assert.deepEqual(pushHistoryGap(points, 50, 60, 242), [])
})


test("unrelated CPU demand without an iGPU does not change GPU control", () => {
  assert.equal(gpuControlSignature(gpu, null, true, false), gpuControlSignature(gpu, null, true, true))
})

test("late acquisitions cannot cross a suppression watermark; real clock changes can", () => {
  assert.equal(gpuReadingAfterGap({ acquiredMs: 1000, acquiredAt: 10 }, 1100, 11), false)
  assert.equal(gpuReadingAfterGap({ acquiredMs: 1100, acquiredAt: 10.99 }, 1100, 11), false)
  assert.equal(gpuReadingAfterGap({ acquiredMs: 1100, acquiredAt: 11.01 }, 1100, 11), true)
  assert.equal(gpuReadingAfterGap({ acquiredMs: 1200, acquiredAt: 1 }, 1100, 11), true)
})

test("rapid runtime transitions preserve a bounded full hour with aligned buckets", () => {
  let hour = []
  let cpu = []
  for (let t = 0; t < 7200; t += 0.5) {
    if (Number.isInteger(t)) hour = pushBucket(hour, { b: t % 100 }, t, 10, 3600)
    else hour = pushBucketGap(hour, t, 10, 3600)
    cpu = pushBucket(cpu, { u: 20 }, t, 10, 3600)
  }
  const reloaded = sanitizeBuckets(hour, 7200, 3600, 10)
  assert.equal(hour.length, 360)
  assert.equal(reloaded.length, 360)
  assert.equal(hour[0].t, 3600)
  assert.equal(hour.at(-1).t, 7190)
  assert.ok(hour.every(p => p.t % 10 === 0 && p.n === 10 && p.gap === 1))
  assert.equal(cpu.length, 360)
  assert.ok(cpu.every(p => p.n === 20 && p.u === 20))
})

test("AMD estimate disclosure remains alongside acquisition age", () => {
  assert.equal(gpuActivityHint({ estimated: true }, "Live · last read 0s ago"),
    "Frequency estimate · not measured busy time · Live · last read 0s ago")
  assert.equal(gpuActivityHint({ estimated: false }, "Held · last read 12s ago"), "Held · last read 12s ago")
})
