"use strict";

// Quadrant Model.js test suite — run with `node --test`.
// Fixtures are captured real tool outputs plus hostile variants.

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const Model = require("../../lib/index.mjs");

function fixture(name) {
  return fs.readFileSync(path.join(__dirname, "..", "fixtures", name), "utf8");
}

// ---------------------------------------------------------- stream parsing

test("swapRates converts pages to KiB/s", () => {
  const r = Model.swapRates({ swpin: 100, swpout: 200 }, { swpin: 150, swpout: 200 }, 2);
  assert.equal(r.inKBs, 100);   // 50 pages * 4 KiB / 2 s
  assert.equal(r.outKBs, 0);
});

test("memComposition buckets RAM with buffers in cache", () => {
  const mem = { tot: 1000, fre: 200, avl: 600, buf: 50, cac: 300, srec: 50, slab: 100, swtot: 0, swfre: 0 };
  const c = Model.memComposition(mem);
  assert.equal(c.cacheK, 400);          // buffers + cached + sreclaimable
  assert.equal(c.kernelK, 50);          // slab - sreclaimable
  assert.equal(c.freeK, 200);
  assert.equal(c.appsK, 350);           // 1000 - 200 - 400 - 50
  assert.equal(c.usedPct, 40);          // (tot - avl) / tot
});

test("memComposition never yields a negative applications slice", () => {
  const mem = { tot: 100, fre: 10, avl: 90, buf: 60, cac: 60, srec: 10, slab: 10, swtot: 0, swfre: 0 };
  const c = Model.memComposition(mem);
  assert.equal(c.appsK, 0);
});

test("swapUsage handles swapless machines", () => {
  assert.deepEqual(Model.swapUsage({ swtot: 0, swfre: 0 }), { totalK: 0, usedK: 0, pct: 0 });
  const s = Model.swapUsage({ swtot: 1000, swfre: 250 });
  assert.equal(s.usedK, 750);
  assert.equal(s.pct, 75);
});

test("parseUdevRam reads configured DIMM type and speed, skipping empty slots", () => {
  const ram = Model.parseUdevRam(fixture("udev-dmi.txt"));
  assert.equal(ram.type, "DDR4");
  assert.equal(ram.speedMTs, 3200);
  assert.equal(ram.maker, "Kingston");
  assert.equal(ram.kit, "2\u00d716 GiB");
  assert.equal(ram.modules.length, 2);
  assert.equal(ram.label, "Kingston 2\u00d716 GiB \u00b7 DDR4 3200 MT/s");
  assert.equal(Model.parseUdevRam("").label, "");
  assert.equal(Model.formatRamLabel("LPDDR5", 9600), "LPDDR5 9600 MT/s");
  assert.equal(Model.formatRamKit([
    { bytes: 8 * 1024 * 1024 * 1024 },
    { bytes: 16 * 1024 * 1024 * 1024 }
  ]), "1\u00d716 GiB + 1\u00d78 GiB");
});
