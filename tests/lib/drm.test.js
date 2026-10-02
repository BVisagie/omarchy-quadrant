"use strict";

// Quadrant Model.js test suite — run with `node --test`.
// Fixtures are captured real tool outputs plus hostile variants.

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const Model = require("../../lib/index.mjs");
const Theme = require("../../Theme.js");

function fixture(name) {
  return fs.readFileSync(path.join(__dirname, "..", "fixtures", name), "utf8");
}

// ---------------------------------------------------------- stream parsing

test("drmBusyPercent prefers render/gfx/compute engine time", () => {
  const prev = Model.parseDrmSnapshot({
    ok: true, tsNs: 1e9, slot: "0000:00:02.0",
    engines: [
      { client: "1", name: "render", ns: 0 },
      { client: "1", name: "video", ns: 0 }
    ],
    rc6: [], memDedicated: 0, memShared: 0
  });
  const curr = Model.parseDrmSnapshot({
    ok: true, tsNs: 2e9, slot: "0000:00:02.0",
    engines: [
      { client: "1", name: "render", ns: 4e8 },
      { client: "1", name: "video", ns: 9e8 }
    ],
    rc6: [], memDedicated: 0, memShared: 1
  });
  // 0.4s of render in a 1s window = 40%, video ignored
  assert.equal(Math.round(Model.drmBusyPercent(prev, curr)), 40);
  assert.equal(Model.drmMemoryKind(curr), "shared");
});

test("drmBusyPercent divides engine time by capacity", () => {
  const prev = Model.parseDrmSnapshot({
    ok: true, tsNs: 1e9, engines: [{ client: "1", pid: 7, name: "video", ns: 0, capacity: 2 }],
    rc6: [], memDedicated: 0, memShared: 0
  });
  const curr = Model.parseDrmSnapshot({
    ok: true, tsNs: 2e9, engines: [{ client: "1", pid: 7, name: "video", ns: 1e9, capacity: 2 }],
    rc6: [], memDedicated: 0, memShared: 0
  });
  // Two decoders, one second of summed time → 50%, not a clamped 100%.
  assert.equal(Math.round(Model.drmBusyPercent(prev, curr)), 50);
});

test("drmProcessRows attributes engine time and memory per pid", () => {
  const prev = Model.parseDrmSnapshot({
    ok: true, tsNs: 1e9,
    engines: [
      { client: "s/1", pid: 10, name: "render", ns: 0 },
      { client: "s/2", pid: 20, name: "render", ns: 0 },
      { client: "s/2", pid: 20, name: "video", ns: 0 },
      { client: "s/3", pid: 30, name: "render", ns: 0 }
    ],
    clients: [
      { pid: 10, client: "s/1", dedicated: 100, shared: 0 },
      { pid: 20, client: "s/2", dedicated: 50, shared: 5 },
      { pid: 30, client: "s/3", dedicated: 0, shared: 0 },
      { pid: 40, client: "s/4", dedicated: 7, shared: 0 }
    ],
    rc6: [], memDedicated: 150, memShared: 5
  });
  const curr = Model.parseDrmSnapshot({
    ok: true, tsNs: 2e9,
    engines: [
      { client: "s/1", pid: 10, name: "render", ns: 2e8 },
      { client: "s/2", pid: 20, name: "render", ns: 6e8 },
      { client: "s/2", pid: 20, name: "video", ns: 9e8 },
      { client: "s/3", pid: 30, name: "render", ns: 0 }
    ],
    clients: [
      { pid: 10, client: "s/1", dedicated: 100, shared: 0 },
      { pid: 20, client: "s/2", dedicated: 50, shared: 5 },
      { pid: 30, client: "s/3", dedicated: 0, shared: 0 },
      { pid: 40, client: "s/4", dedicated: 7, shared: 0 }
    ],
    rc6: [], memDedicated: 157, memShared: 5
  });
  const rows = Model.drmProcessRows(prev, curr);
  // pid 30 did nothing and holds nothing; it is dropped.
  assert.deepEqual(rows.map((r) => r.pid), [20, 10, 40]);
  assert.equal(Math.round(rows[0].busy), 60);   // render wins over video
  assert.equal(rows[0].dedicated, 50);
  assert.equal(Math.round(rows[1].busy), 20);
  assert.equal(rows[2].busy, 0);
  assert.equal(rows[2].dedicated, 7);
  assert.deepEqual(Model.drmProcessRows(prev, null), []);
  // Card-level busy is the summed render time: 80%.
  assert.equal(Math.round(Model.drmBusyPercent(prev, curr)), 80);
});

test("drmBusyPercent falls back to RC6 when engines are missing", () => {
  const prev = Model.parseDrmSnapshot({
    ok: true, tsNs: 1e9, engines: [],
    rc6: [{ id: "gt0", ms: 0 }], memDedicated: 0, memShared: 0
  });
  const curr = Model.parseDrmSnapshot({
    ok: true, tsNs: 2e9, engines: [],
    rc6: [{ id: "gt0", ms: 250 }], memDedicated: 0, memShared: 0
  });
  // 250ms idle in 1000ms → 75% busy
  assert.equal(Math.round(Model.drmBusyPercent(prev, curr)), 75);
  assert.equal(Model.drmBusyPercent(prev, null), null);
});

test("mergeGpuLive overlays DRM busy without clobbering AMD sysfs busy", () => {
  const amd = Model.mergeGpuLive({ kind: "amd", busy: 12, vramTotal: 8 }, 40, {
    memDedicated: 1, memShared: 2
  });
  assert.equal(amd.busy, 12);
  assert.equal(amd.busySource, "sysfs");
  const intel = Model.mergeGpuLive({ kind: "intel", busy: null, freqEstimate: 50 }, 22, {
    memDedicated: 0, memShared: 4096
  });
  assert.equal(intel.busy, 22);
  assert.equal(intel.busySource, "drm");
  assert.equal(intel.memKind, "shared");
});
