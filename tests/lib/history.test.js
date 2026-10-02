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

test("pushTimedWindow preserves 60 seconds at custom cadences", () => {
  var h = [];
  for (var i = 0; i <= 280; i++) {
    h = Model.pushTimedWindow(h, { value: i }, 1000 + i * 0.25, 60, 242);
  }
  assert.equal(h.length, 241);
  assert.equal(h[0].t, 1010);
  assert.equal(h.at(-1).t, 1070);
  assert.equal(h.at(-1).value, 280);

  const point = { value: 1 };
  const reset = Model.pushTimedWindow(h, point, 5, 60, 242);
  assert.equal(reset.length, 1);
  assert.equal(reset[0].t, 5);
  assert.equal(point.t, undefined); // pure: input point is not mutated
});

test("pushBucket averages samples inside a bucket and keeps gaps", () => {
  let h = [];
  h = Model.pushBucket(h, { u: 10, p: null }, 1000.2, 10, 3600);
  h = Model.pushBucket(h, { u: 30, p: 4 }, 1004.9, 10, 3600);
  assert.equal(h.length, 1);
  assert.equal(h[0].t, 1000);
  assert.equal(h[0].n, 2);
  assert.equal(h[0].u, 20);
  assert.equal(h[0].p, 4);           // null samples do not drag the mean down
  h = Model.pushBucket(h, { u: 50 }, 1035, 10, 3600);
  assert.equal(h.length, 2);         // 1010 and 1020 are simply absent
  assert.deepEqual(h.map((b) => b.t), [1000, 1030]);
  // Window trim: a sample an hour later drops the first bucket.
  h = Model.pushBucket(h, { u: 1 }, 1000 + 3600 + 5, 10, 3600);
  assert.deepEqual(h.map((b) => b.t), [1030, 4600]);
  // Clock going backwards resets rather than corrupting order.
  h = Model.pushBucket(h, { u: 1 }, 500, 10, 3600);
  assert.deepEqual(h.map((b) => b.t), [500]);
  assert.deepEqual(Model.pushBucket([{ t: 1 }], { u: 1 }, "nope", 10, 60), [{ t: 1 }]);
});

test("mergeBuckets keeps only loaded buckets older than live data", () => {
  const older = [{ t: 100, u: 1 }, { t: 110, u: 2 }, { t: 120, u: 3 }];
  const live = [{ t: 110, u: 9 }, { t: 130, u: 8 }];
  assert.deepEqual(Model.mergeBuckets(older, live).map((b) => [b.t, b.u]), [[100, 1], [110, 9], [130, 8]]);
  assert.deepEqual(Model.mergeBuckets(older, []), older);
  assert.deepEqual(Model.mergeBuckets(null, live), live);
});

test("loadHistoryFile validates a persisted file", () => {
  const now = 10000;
  const good = Model.loadHistoryFile({
    v: 1, tags: { gpu: "card1", iface: "wlan0", disk: "nvme0n1" },
    cpu: [
      { t: 9990, n: 3, u: 12.5, s: 1 },
      { t: 9980, n: 1, u: "oops", s: 2 },           // bad field dropped, bucket kept
      { t: 1, n: 1, u: 5 },                          // too old
      { t: 99999, n: 1, u: 5 },                      // from the future
      { t: 9990, n: 1, u: 99 },                      // duplicate t: later wins
      { t: 9970, n: 1, u: 3, "x y": 4, verylongkeynamethatisbad: 1 },
      "junk", null, 7
    ],
    mem: "not a list"
  }, now, 3600, 10);
  assert.deepEqual(good.tags, { gpu: "card1", iface: "wlan0", disk: "nvme0n1" });
  assert.deepEqual(good.series.cpu.map((b) => [b.t, b.u]), [[9970, 3], [9980, undefined], [9990, 99]]);
  assert.equal("x y" in good.series.cpu[0], false);
  assert.deepEqual(good.series.mem, []);
  assert.equal(good.any, true);
  assert.equal(Model.loadHistoryFile({ v: 2 }, now, 3600, 10), null);
  assert.equal(Model.loadHistoryFile("[]", now, 3600, 10), null);
  const payload = Model.historyFilePayload({ cpu: [{ t: 1, u: 2 }] }, { iface: "eth0" }, now);
  assert.equal(payload.v, 1);
  assert.deepEqual(payload.cpu, [{ t: 1, u: 2 }]);
  assert.deepEqual(payload.tags, { gpu: "", iface: "eth0", disk: "" });
  assert.deepEqual(payload.gpu, []);
  // Round trip.
  assert.deepEqual(Model.loadHistoryFile(JSON.parse(JSON.stringify(payload)), 100, 3600, 10).series.cpu, [{ t: 1, n: 1, u: 2 }]);
});
