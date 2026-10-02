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

test("cpuDelta computes bucketed percentages", () => {
  const prev = { user: 100, nice: 0, system: 50, idle: 800, iowait: 30, irq: 10, softirq: 10, steal: 0 };
  const curr = { user: 160, nice: 10, system: 70, idle: 1500, iowait: 40, irq: 15, softirq: 15, steal: 10 };
  const d = Model.cpuDelta(prev, curr);
  // deltas: user 70 (incl nice), system 30 (incl irq+softirq), iowait 10, steal 10, idle 700 → total 820
  assert.ok(d);
  assert.equal(Math.round(d.user * 100 / 100), Math.round(100 * 70 / 820));
  assert.equal(Math.round(d.system), Math.round(100 * 30 / 820));
  assert.equal(Math.round(d.iowait), Math.round(100 * 10 / 820));
  assert.equal(Math.round(d.steal), Math.round(100 * 10 / 820));
  assert.equal(Math.round(d.busy), Math.round(100 * 100 / 820));
  assert.equal(Math.round(d.nonIdle), Math.round(100 * 120 / 820));
});

test("cpuBarTooltip mentions iowait when it is material", () => {
  const d = Model.cpuDelta(
    { user: 0, nice: 0, system: 0, idle: 0, iowait: 0, irq: 0, softirq: 0, steal: 0 },
    { user: 10, nice: 0, system: 0, idle: 10, iowait: 80, irq: 0, softirq: 0, steal: 0 }
  );
  assert.ok(d);
  assert.equal(Math.round(d.busy), 10);
  assert.equal(Math.round(d.nonIdle), 90);
  assert.match(Model.cpuBarTooltip(d), /iowait/);
  assert.equal(Model.cpuBarTooltip(null), "CPU --");
});

test("cpuCoreDeltas maps per-logical non-idle percent", () => {
  const prev = [
    { user: 0, nice: 0, system: 0, idle: 0, iowait: 0, irq: 0, softirq: 0, steal: 0 },
    { user: 0, nice: 0, system: 0, idle: 0, iowait: 0, irq: 0, softirq: 0, steal: 0 }
  ];
  const curr = [
    { user: 50, nice: 0, system: 0, idle: 50, iowait: 0, irq: 0, softirq: 0, steal: 0 },
    { user: 0, nice: 0, system: 0, idle: 100, iowait: 0, irq: 0, softirq: 0, steal: 0 }
  ];
  const rows = Model.cpuCoreDeltas(prev, curr);
  assert.equal(rows.length, 2);
  assert.equal(rows[0].id, 0);
  assert.equal(Math.round(rows[0].busy), 50);
  assert.equal(Math.round(rows[1].busy), 0);
});

test("cpuCoreDeltas keys cores by id when /proc/stat skips offline cpus", () => {
  const z = { user: 0, nice: 0, system: 0, idle: 0, iowait: 0, irq: 0, softirq: 0, steal: 0 };
  const prev = [z, z, z];
  const curr = [
    { user: 0, nice: 0, system: 0, idle: 100, iowait: 0, irq: 0, softirq: 0, steal: 0 },
    { user: 100, nice: 0, system: 0, idle: 0, iowait: 0, irq: 0, softirq: 0, steal: 0 },
    { user: 0, nice: 0, system: 0, idle: 100, iowait: 0, irq: 0, softirq: 0, steal: 0 }
  ];
  // SMT siblings 1 and 3 are offline: ids are 0, 2, 4.
  const rows = Model.cpuCoreDeltas(prev, curr, [0, 2, 4], [0, 2, 4]);
  assert.deepEqual(rows.map((r) => r.id), [0, 2, 4]);
  assert.equal(Math.round(rows[1].busy), 100);
  // A core that was offline in the previous sample has no delta yet.
  const hot = Model.cpuCoreDeltas(prev.slice(0, 2), curr, [0, 2], [0, 2, 4]);
  assert.deepEqual(hot.map((r) => r.id), [0, 2]);
  // Without ids, positions are ids (older streams and fixtures).
  assert.deepEqual(Model.parseCpuCoreIds(undefined, 3), [0, 1, 2]);
  assert.deepEqual(Model.parseCpuCoreIds([0, "x", 2], 3), [0, 1, 2]);
  assert.deepEqual(Model.parseCpuCoreIds([0, 2], 3), [0, 1, 2]);
});

test("physical cores are counted per package, not by bare core_id", () => {
  const topo = [
    { id: 0, core: 0, pkg: 0, cls: "performance", maxKhz: 3000000, cap: 0 },
    { id: 1, core: 1, pkg: 0, cls: "performance", maxKhz: 3000000, cap: 0 },
    { id: 2, core: 0, pkg: 1, cls: "performance", maxKhz: 3000000, cap: 0 },
    { id: 3, core: 1, pkg: 1, cls: "performance", maxKhz: 3000000, cap: 0 }
  ];
  const info = Model.parseSystemCpu({ modelName: "x", vendorId: "y", topo: topo });
  assert.equal(info.physCores, 4);
  assert.equal(info.classes.performance, 4);
  const layout = Model.coreGridLayout(topo, { 0: 10, 1: 20, 2: 30, 3: 40 });
  assert.equal(layout.rows[0].cells.length, 4);
  assert.equal(layout.rows[0].cells[2].usage, 30);
  // Omitting pkg still works for single-socket topologies.
  const single = topo.slice(0, 2).map((e) => ({ id: e.id, core: e.core, cls: e.cls, maxKhz: e.maxKhz, cap: 0 }));
  assert.equal(Model.parseSystemCpu({ topo: single }).physCores, 2);
});

test("classifyCpuTopology keeps Intel hybrid labels and counts physical cores", () => {
  const topo = [
    { id: 0, core: 0, cls: "performance", maxKhz: 5100000, cap: 0, l3: "0-19" },
    { id: 1, core: 0, cls: "performance", maxKhz: 5100000, cap: 0, l3: "0-19" },
    { id: 8, core: 16, cls: "performance", maxKhz: 5100000, cap: 0, l3: "0-19" },
    { id: 16, core: 36, cls: "efficiency", maxKhz: 3800000, cap: 0, l3: "0-19" },
    { id: 17, core: 37, cls: "lowpower", maxKhz: 2200000, cap: 0, l3: "16-19" }
  ];
  const info = Model.parseSystemCpu({
    modelName: "Intel(R) Core(TM) Ultra 9 185H",
    vendorId: "GenuineIntel",
    physCores: 99,
    threads: 3,
    topo: topo
  });
  assert.equal(info.physCores, 4);
  assert.equal(info.threads, 5);
  assert.equal(info.classes.performance, 2);
  assert.equal(info.classes.efficiency, 1);
  assert.equal(info.classes.lowpower, 1);
  assert.equal(Model.formatCpuClassMix(info.classes), "2P · 1E · 1LP");
});

test("classifyCpuTopology splits unlabeled chips by max frequency", () => {
  const topo = [
    { id: 0, core: 0, cls: "", maxKhz: 5500000, cap: 0 },
    { id: 1, core: 1, cls: "", maxKhz: 5500000, cap: 0 },
    { id: 2, core: 2, cls: "", maxKhz: 3300000, cap: 0 },
    { id: 3, core: 3, cls: "", maxKhz: 3300000, cap: 0 }
  ];
  const classified = Model.classifyCpuTopology(topo);
  assert.equal(classified[0].cls, "performance");
  assert.equal(classified[2].cls, "efficiency");
  const layout = Model.coreGridLayout(topo, { 0: 80, 1: 10, 2: 40, 3: 5 });
  assert.equal(layout.mode, "hybrid");
  assert.equal(layout.rows.length, 2);
  assert.equal(layout.rows[0].kind, "performance");
  assert.equal(layout.rows[0].cells.length, 2);
});

test("coreGridLayout collapses SMT siblings onto one cell", () => {
  const topo = [
    { id: 0, core: 0, cls: "performance", maxKhz: 5000000, cap: 0 },
    { id: 1, core: 0, cls: "performance", maxKhz: 5000000, cap: 0 },
    { id: 2, core: 1, cls: "performance", maxKhz: 5000000, cap: 0 },
    { id: 3, core: 1, cls: "performance", maxKhz: 5000000, cap: 0 }
  ];
  const layout = Model.coreGridLayout(topo, { 0: 10, 1: 70, 2: 5, 3: 5 });
  assert.equal(layout.mode, "uniform");
  assert.equal(layout.rows[0].cells.length, 2);
  assert.equal(layout.rows[0].cells[0].usage, 70);
  assert.deepEqual(layout.rows[0].cells[0].logicals, [0, 1]);
});

test("cpuDelta returns null when counters do not advance", () => {
  const c = { user: 1, nice: 0, system: 1, idle: 1, iowait: 0, irq: 0, softirq: 0, steal: 0 };
  assert.equal(Model.cpuDelta(c, c), null);
  assert.equal(Model.cpuDelta(null, c), null);
});

test("cpuDelta clamps counter resets instead of going negative", () => {
  // user/system reset while idle keeps advancing: reset buckets clamp to 0.
  const prev = { user: 1000, nice: 0, system: 500, idle: 100, iowait: 0, irq: 0, softirq: 0, steal: 0 };
  const curr = { user: 10, nice: 0, system: 5, idle: 150, iowait: 0, irq: 0, softirq: 0, steal: 0 };
  const d = Model.cpuDelta(prev, curr);
  assert.ok(d);
  assert.equal(d.user, 0);
  assert.equal(d.system, 0);
  assert.equal(d.idle, 100);
  // everything reset at once: no usable delta at all
  const gone = Model.cpuDelta(curr, { user: 1, nice: 0, system: 1, idle: 1, iowait: 0, irq: 0, softirq: 0, steal: 0 });
  assert.equal(gone, null);
});

test("cleanCpuName strips trademarks and clock suffixes", () => {
  assert.equal(Model.cleanCpuName("Intel(R) Core(TM) Ultra 9 185H"), "Intel Core Ultra 9 185H");
  assert.equal(Model.cleanCpuName("AMD Ryzen 9 7950X 16-Core Processor"), "AMD Ryzen 9 7950X");
  assert.equal(Model.cleanCpuName("Intel(R) Xeon(R) Processor"), "Intel Xeon");
  assert.equal(Model.cleanCpuName("AMD Ryzen 7 8845HS w/ Radeon 780M Graphics"), "AMD Ryzen 7 8845HS w/ Radeon 780M Graphics");
  assert.equal(Model.cleanCpuName(""), "");
});
