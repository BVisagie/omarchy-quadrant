"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const Model = require("../../lib/index.mjs");

test("graph measurements distinguish unknown and unavailable from a real zero", () => {
  for (const point of [null, undefined, 0, { v: null }, {}, { v: NaN }, { v: Infinity }, { v: -1 }, { v: "" }])
    assert.equal(Model.graphValue(point, "v"), null);
  assert.equal(Model.graphValue({ v: 0 }, "v"), 0);
  assert.equal(Model.graphValue({ v: "12.5" }, "v"), 12.5);
});

test("visible summaries and scales exclude offscreen and invalid timestamps", () => {
  const points = [{ t: 1, v: 99999 }, { t: 40, v: 0 }, { t: 80, v: 20 }, { t: 100, v: null }, { t: "invalid", v: 9999 }];
  const visible = Model.graphWindow(points, 60);
  assert.deepEqual(visible, points.slice(1, 4));
  assert.equal(visible[0], points[1], "windowing does not rewrite measurements");
  assert.deepEqual(Model.graphStats(visible, ["v"]), { avg: 10, peak: 20 });
  assert.equal(Model.graphAxis(visible, ["v"]).max, 20);
  assert.deepEqual(Model.graphWindow(null, 60), []);
  assert.deepEqual(Model.graphWindow([{ v: 5 }], 60), []);
  assert.deepEqual(Model.graphWindow(points, 3600), points.slice(0, 4));
});

test("each series keeps its own positive summary; stacks require a complete measurement", () => {
  const points = [{ a: null, b: 40 }, { a: 0, b: 20 }, { a: 10, b: 30 }, { a: -1, b: null }];
  assert.deepEqual(Model.graphStats(points, ["a"]), { avg: 5, peak: 10 });
  assert.deepEqual(Model.graphStats(points, ["b"]), { avg: 30, peak: 40 });
  assert.deepEqual(Model.graphStats(points, ["a", "b"]), { avg: 30, peak: 40 });
  assert.equal(Model.graphStats([{ a: null }, {}], ["a"]), null);
  assert.equal(Model.graphStats(points, []), null);
});

test("rate axes share both series' peak with a 1 KiB/s floor and retain real zero", () => {
  for (const points of [[], [{ rx: null, tx: null }], [{ rx: 0, tx: 0 }], [{ rx: 1, tx: 2 }]]) {
    const axis = Model.graphAxis(points, ["rx", "tx"], { minimumMax: 1024 });
    assert.equal(axis.min, 0);
    assert.equal(axis.max, 1024);
  }
  const busy = Model.graphAxis([{ rx: 2000, tx: 4000 }], ["rx", "tx"], { minimumMax: 1024 });
  assert.equal(busy.max, 5000);
  assert.equal(busy.hi, 4000);
  const gpu = Model.graphAxis([{ b: 3, v: 80 }], ["b", "v"], { fixedMax: 100 });
  assert.equal(gpu.max, 100);
  assert.equal(Model.graphAxis([{ b: 3 }], ["b"], { fixedMax: 100 }).max, gpu.max);
});

test("stack and memory-band axes preserve existing measurement semantics", () => {
  assert.equal(Model.graphAxis([{ a: 10, b: null }, { a: 20, b: 30 }], ["a", "b"], { stacked: true }).hi, 50);
  const band = Model.graphAxis([{ u: 40 }, { u: 45 }], ["u"], { band: true, fixedMax: 100 });
  assert.equal(band.min, 38.75);
  assert.equal(band.max, 46.25);
  assert.equal(Model.graphAxis([{ u: 99 }, { u: 100 }], ["u"], { band: true, fixedMax: 100 }).max, 100);
});

test("runs leave real gaps for null, missing, unavailable, bad time, and suspended streams", () => {
  const points = [{ t: 1, v: 0 }, { t: 2, v: 20 }, { t: 3, v: null }, { t: 4, v: 10 }, { t: 5 },
    { t: 6, v: -1 }, { t: 7, v: 2 }, { t: 50, v: 10 }, { t: 51, v: 20 }, { t: "bad", v: 10 }, { t: 52, v: 1 }];
  assert.deepEqual(Model.graphRuns(points, ["v"], 3), [{ start: 0, end: 1 }, { start: 3, end: 3 },
    { start: 6, end: 6 }, { start: 7, end: 8 }, { start: 10, end: 10 }]);
  assert.deepEqual(Model.graphRuns([{ t: 3, a: 10, b: 1 }, { t: 2, a: 1, b: 1 }], ["a", "b"], 3),
    [{ start: 0, end: 0 }, { start: 1, end: 1 }]);
  assert.deepEqual(Model.graphRuns([{ t: 1, a: 20, b: 10 }, { t: 2, a: 10, b: null }, { t: 3, a: 20, b: 10 }], ["a", "b"], 3),
    [{ start: 0, end: 0 }, { start: 2, end: 2 }]);
});

test("hover follows connected time, snaps to isolated points and leaves long gaps blank", () => {
  const points = [{ t: 100 }, { t: 101 }, { t: 110 }, { t: 111 }, { t: 160 }];
  assert.equal(Model.graphHoverIndex(points, 100.6, 3, 0.5), 1);
  assert.equal(Model.graphHoverIndex(points, 105, 3, 0.5), -1);
  assert.equal(Model.graphHoverIndex(points, 159.7, 3, 0.5), 4);
  assert.equal(Model.graphHoverIndex(points, 130, 3, 0.5), -1);
  assert.equal(Model.graphHoverIndex(points, 99, 3, 0.5), -1);
  assert.equal(Model.graphHoverIndex([], 100, 3, 0.5), -1);
  assert.equal(Model.graphHoverIndex(points, null, 3, 0.5), -1);
});

test("hour summaries report the peak of 10 s means, independent of layout", () => {
  let buckets = [];
  for (const [t, a, b] of [[100, 0, 100], [101, 100, 0], [110, 10, 20]])
    buckets = Model.pushBucket(buckets, { a, b }, t, 10, 3600);
  assert.deepEqual(Model.graphStats(Model.graphWindow(buckets, 3600), ["a"]), { avg: 30, peak: 50 });
  assert.deepEqual(Model.graphStats(Model.graphWindow(buckets, 3600), ["b"]), { avg: 35, peak: 50 });
});
