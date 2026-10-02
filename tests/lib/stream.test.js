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

test("parseStreamLine parses a full sample", () => {
  const s = Model.parseStreamLine(fixture("stream-basic.json"));
  assert.ok(s);
  assert.equal(s.ts, 1788067655.087906);
  assert.deepEqual(s.cpu, { user: 7132, nice: 0, system: 4217, idle: 301512, iowait: 295, irq: 0, softirq: 1203, steal: 8 });
  assert.equal(s.mem.tot, 16398384);
  assert.equal(s.psi.cs300, 0.04);
  assert.deepEqual(s.net, [
    { n: "eth0", rx: 2268161762, tx: 7069677 },
    { n: "docker0", rx: 0, tx: 0 }
  ]);
  assert.deepEqual(s.r4, [{ n: "eth0", m: 0 }]);
  assert.equal(s.gpu, null);
  assert.equal(s.tempC, null);
  assert.equal(s.cores, 4);
  assert.equal(s.uptimeS, 784.2);
});

test("parseStreamLine accepts missing PSI and Intel gpu shape", () => {
  const s = Model.parseStreamLine(fixture("stream-no-psi.json"));
  assert.ok(s);
  assert.equal(s.psi, null);
  assert.equal(s.gpu.kind, "intel");
  assert.equal(s.gpu.busy, null);
  assert.equal(s.gpu.freqCurMhz, 400);
  assert.equal(s.gpu.freqMaxMhz, 1300);
  assert.deepEqual(s.r6, [{ n: "wlan0", m: 600 }]);
});

test("parseStreamLine keeps unread PSI half as null, not zero", () => {
  const s = Model.parseStreamLine(fixture("stream-partial-psi.json"));
  assert.ok(s);
  assert.equal(s.psi.cs10, 1.5);
  assert.equal(s.psi.ms10, null);
  assert.equal(s.psi.ms60, null);
  assert.equal(s.gpu.kind, "amd");
  assert.equal(s.gpu.memBusy, 22);
  assert.deepEqual(s.gpu.engines, [
    { id: "comp_1_0_0", busy: 5 },
    { id: "gfx", busy: 40 }
  ]);
});

test("parseStreamLine rejects garbage", () => {
  assert.equal(Model.parseStreamLine(""), null);
  assert.equal(Model.parseStreamLine("not json"), null);
  assert.equal(Model.parseStreamLine('{"v":2,"ts":1}'), null);
  assert.equal(Model.parseStreamLine('{"v":1,"ts":-3,"cpu":[1,2,3,4,5,6,7,8],"mem":{"tot":1,"fre":1,"avl":1,"buf":1,"cac":1,"srec":1,"slab":1,"swtot":1,"swfre":1}}'), null);
  assert.equal(Model.parseStreamLine('{"v":1,"ts":5,"cpu":[1,2,3],"mem":{}}'), null);
  assert.equal(Model.parseStreamLine('{"v":1,"ts":5,"cpu":["x",0,0,0,0,0,0,0],"mem":{"tot":1,"fre":1,"avl":1,"buf":1,"cac":1,"srec":1,"slab":1,"swtot":1,"swfre":1}}'), null);
});

test("parseStreamLine carries sparse core ids through to the delta", () => {
  const line = JSON.stringify({
    v: 1, ts: 10, cpu: [1, 0, 1, 1, 0, 0, 0, 0],
    mem: { tot: 1, fre: 1, avl: 1, buf: 0, cac: 0, srec: 0, slab: 0, swtot: 0, swfre: 0 },
    cc: [[1, 0, 0, 1, 0, 0, 0, 0], [1, 0, 0, 1, 0, 0, 0, 0]], ci: [0, 2]
  });
  const s = Model.parseStreamLine(line);
  assert.deepEqual(s.cpuCoreIds, [0, 2]);
  const s2 = Model.parseStreamLine(JSON.stringify({
    v: 1, ts: 11, cpu: [2, 0, 1, 1, 0, 0, 0, 0],
    mem: { tot: 1, fre: 1, avl: 1, buf: 0, cac: 0, srec: 0, slab: 0, swtot: 0, swfre: 0 },
    cc: [[1, 0, 0, 2, 0, 0, 0, 0], [2, 0, 0, 1, 0, 0, 0, 0]], ci: [0, 2]
  }));
  const rows = Model.cpuCoreDeltas(s.cpuCores, s2.cpuCores, s.cpuCoreIds, s2.cpuCoreIds);
  assert.deepEqual(rows.map((r) => [r.id, Math.round(r.busy)]), [[0, 0], [2, 100]]);
});

test("parseStreamLine treats a missing disk array as empty", () => {
  const s = Model.parseStreamLine(fixture("stream-basic.json"));
  assert.deepEqual(s.disk, []);
  const withDisk = Model.parseStreamLine('{"v":1,"ts":1,"cpu":[1,0,1,1,0,0,0,0],"mem":{"tot":1,"fre":1,"avl":1,"buf":1,"cac":1,"srec":1,"slab":1,"swtot":1,"swfre":1},"disk":[{"n":"sda","rd":1,"rs":2,"wr":3,"ws":4,"io":5},{"n":"sda1","rd":1,"rs":2,"wr":3,"ws":4,"io":5}]}');
  assert.equal(withDisk.disk.length, 1);
  assert.equal(withDisk.disk[0].n, "sda");
});

test("parseStreamLine accepts optional cf and treats it as missing when absent", () => {
  const noCf = Model.parseStreamLine(fixture("stream-basic.json"));
  assert.equal(noCf.cpuFreqMhz, null);
  const withCf = Model.parseStreamLine('{"v":1,"ts":1,"cpu":[1,0,1,1,0,0,0,0],"mem":{"tot":1,"fre":1,"avl":1,"buf":1,"cac":1,"srec":1,"slab":1,"swtot":1,"swfre":1},"cf":4200}');
  assert.equal(withCf.cpuFreqMhz, 4200);
  const badCf = Model.parseStreamLine('{"v":1,"ts":1,"cpu":[1,0,1,1,0,0,0,0],"mem":{"tot":1,"fre":1,"avl":1,"buf":1,"cac":1,"srec":1,"slab":1,"swtot":1,"swfre":1},"cf":"nope"}');
  assert.equal(badCf.cpuFreqMhz, null);
});
