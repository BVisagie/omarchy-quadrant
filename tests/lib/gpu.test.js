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

test("parseNvidiaCsv parses multiple GPUs", () => {
  const rows = Model.parseNvidiaCsv(fixture("nvidia.csv"));
  assert.equal(rows.length, 2);
  assert.deepEqual(rows[0], {
    index: 0, name: "NVIDIA GeForce RTX 4070", utilPct: 12,
    memUsedM: 1024, memTotalM: 12282, tempC: 52, powerW: 35.5, clockMhz: 1800
  });
  assert.equal(rows[1].utilPct, 0);
});

test("parseNvidiaCsv maps N/A and [Not Supported] to null", () => {
  const rows = Model.parseNvidiaCsv(fixture("nvidia-na.csv"));
  assert.equal(rows.length, 1);
  assert.equal(rows[0].utilPct, null);
  assert.equal(rows[0].powerW, null);
  assert.equal(rows[0].clockMhz, null);
  assert.equal(rows[0].memUsedM, 1024);
  assert.equal(Model.parseNvidiaCsv("").length, 0);
  assert.equal(Model.parseNvidiaCsv("garbage line").length, 0);
});

test("parseNvidiaCsv rejoins comma-containing GPU names", () => {
  const rows = Model.parseNvidiaCsv(fixture("nvidia-comma.csv"));
  assert.equal(rows.length, 2);
  assert.equal(rows[0].name, "NVIDIA RTX 4070, Laptop GPU");
  assert.equal(rows[0].utilPct, 12);
  assert.equal(rows[0].clockMhz, 1800);
  assert.equal(rows[1].name, "NVIDIA GeForce GT 1030");
  assert.equal(rows[1].utilPct, 0);
});

test("parseKeyValues reads key=value payloads", () => {
  const kv = Model.parseKeyValues("a=1\nb=two words\nBAD-KEY=3\n=4\n");
  assert.equal(kv.a, "1");
  assert.equal(kv.b, "two words");
  assert.equal(kv["BAD-KEY"], undefined);
});

test("normalizeAmdGpu converts sysfs units", () => {
  const g = Model.normalizeAmdGpu(Model.parseKeyValues(fixture("amd-sysfs.txt")));
  assert.equal(g.busy, 34);
  assert.equal(g.vramUsed, 4294967296);
  assert.equal(g.vramTotal, 12884901888);
  assert.equal(g.tempC, 52);
  assert.equal(g.tempJunctionC, 61);
  assert.equal(g.powerW, 85);
  assert.equal(g.clockMhz, 1800);
  assert.equal(g.memBusy, 22);
  assert.deepEqual(g.engines, [
    { id: "comp_1_0_0", busy: 5 },
    { id: "gfx", busy: 40 }
  ]);
});

test("normalizeAmdGpu tolerates missing files", () => {
  const g = Model.normalizeAmdGpu(Model.parseKeyValues("gpu_busy_percent=7\n"));
  assert.equal(g.busy, 7);
  assert.equal(g.vramUsed, null);
  assert.equal(g.tempC, null);
  assert.equal(g.memBusy, null);
  assert.deepEqual(g.engines, []);
});

test("normalizeIntelGpu reports a labeled frequency estimate, never busy", () => {
  const g = Model.normalizeIntelGpu(Model.parseKeyValues(fixture("intel-sysfs.txt")));
  assert.equal(g.busy, null);
  assert.equal(g.freqEstimate, 50);
  assert.equal(g.tempC, 48);
  assert.equal(Model.normalizeIntelGpu(Model.parseKeyValues("")).freqEstimate, null);
});

test("normalizeGpuList validates entries", () => {
  const list = Model.normalizeGpuList({
    gpus: [
      { card: "card0", vendor: "amd", path: "/sys/class/drm/card0/device", boot: true },
      { card: "card1", vendor: "nvidia", path: "/sys/class/drm/card1/device", boot: false },
      { card: "evil", vendor: "amd", path: "/sys/x", boot: false },
      { card: "card2", vendor: "mali", path: "/sys/class/drm/card2/device", boot: false }
    ]
  });
  assert.equal(list.length, 2);
});

test("pickGpu auto prefers the boot card, then card0", () => {
  const gpus = [
    { card: "card1", vendor: "nvidia", path: "/sys/1", boot: false },
    { card: "card0", vendor: "amd", path: "/sys/0", boot: true }
  ];
  assert.equal(Model.pickGpu(gpus, "auto").card, "card0");
  assert.equal(Model.pickGpu(gpus, "card1").card, "card1");
  assert.equal(Model.pickGpu(gpus, "card9"), null);
  assert.equal(Model.pickGpu([], "auto"), null);
  const noBoot = [
    { card: "card1", vendor: "amd", path: "/sys/1", boot: false },
    { card: "card0", vendor: "intel", path: "/sys/0", boot: false }
  ];
  assert.equal(Model.pickGpu(noBoot, "auto").card, "card0");
});

test("classifyGpuRole uses positive evidence and conservative defaults", () => {
  assert.equal(Model.classifyGpuRole({ card: "card1", vendor: "intel", slot: "0000:00:02.0" }, "auto"), "integrated");
  assert.equal(Model.classifyGpuRole({ card: "card0", vendor: "intel", slot: "0000:01:00.0" }, "auto"), "discrete");
  assert.equal(Model.classifyGpuRole({ card: "card0", vendor: "nvidia", slot: "0000:01:00.0" }, "auto"), "discrete");
  assert.equal(Model.classifyGpuRole({ card: "card0", vendor: "amd" }, "auto", "Navi 31 [Radeon RX 7900 XTX]"), "discrete");
  assert.equal(Model.classifyGpuRole({ card: "card0", vendor: "amd" }, "auto", "Phoenix3 [Radeon 780M]"), "integrated");
  assert.equal(Model.classifyGpuRole({ card: "card0", vendor: "amd" }, "auto", ""), "discrete");
  assert.equal(Model.classifyGpuRole({ card: "card1", vendor: "intel", slot: "0000:00:02.0" }, "none"), "discrete");
  assert.equal(Model.classifyGpuRole({ card: "card0", vendor: "amd" }, "card0", "Navi 31"), "integrated");
  assert.equal(Model.classifyGpuRole({ card: "card1", vendor: "amd" }, "card0", "Phoenix"), "discrete");
});

test("reconcileGpuTopology waits for names and never infers siblings as iGPU", () => {
  const intelIgpu = {
    card: "card1", vendor: "intel", path: "/sys/class/drm/card1/device",
    boot: true, slot: "0000:00:02.0"
  };
  const nvidia = {
    card: "card0", vendor: "nvidia", path: "/sys/class/drm/card0/device",
    boot: false, slot: "0000:01:00.0"
  };
  const hybrid = Model.reconcileGpuTopology([intelIgpu, nvidia], null, "auto");
  assert.equal(hybrid.integratedGpu.card, "card1");
  assert.equal(hybrid.discreteGpus.length, 1);
  assert.equal(hybrid.discreteGpus[0].card, "card0");
  assert.equal(Model.pickGpu(hybrid.discreteGpus, "auto").card, "card0");
  assert.match(Model.gpuDevicePinMessage(hybrid.gpus, "card1"), /integrated/);
  assert.equal(Model.gpuDevicePinMessage(hybrid.gpus, "auto"), "");

  const twoDgpu = Model.reconcileGpuTopology([
    { card: "card0", vendor: "amd", path: "/sys/a", boot: true, slot: "0000:03:00.0" },
    { card: "card1", vendor: "nvidia", path: "/sys/n", boot: false, slot: "0000:01:00.0" }
  ], {
    gpusByCard: {
      card0: { name: "Navi 31 [Radeon RX 7900 XTX]" },
      card1: { name: "GeForce RTX 4090" }
    }
  }, "auto");
  assert.equal(twoDgpu.integratedGpu, null);
  assert.equal(twoDgpu.discreteGpus.length, 2);

  const amdFirst = Model.reconcileGpuTopology([
    { card: "card0", vendor: "amd", path: "/sys/a", boot: true }
  ], null, "auto");
  assert.equal(amdFirst.integratedGpu, null);
  const amdNamed = Model.reconcileGpuTopology([
    { card: "card0", vendor: "amd", path: "/sys/a", boot: true }
  ], { gpusByCard: { card0: { name: "Phoenix [Radeon Graphics]" } } }, "auto");
  assert.equal(amdNamed.integratedGpu.card, "card0");

  const empty = Model.reconcileGpuTopology([], null, "auto");
  assert.equal(empty.integratedGpu, null);
  assert.equal(empty.discreteGpus.length, 0);
});

test("gpuIdentityEqual ignores object identity and extra fields", () => {
  const a = { card: "card1", vendor: "intel", path: "/sys/class/drm/card1/device", boot: true };
  const b = { card: "card1", vendor: "intel", path: "/sys/class/drm/card1/device", name: "UHD Graphics" };
  assert.equal(Model.gpuIdentityEqual(a, b), true);
  assert.equal(Model.gpuIdentityEqual(a, a), true);
  assert.equal(Model.gpuIdentityEqual(null, null), true);
  assert.equal(Model.gpuIdentityEqual(a, null), false);
  assert.equal(Model.gpuIdentityEqual(null, a), false);
  assert.equal(Model.gpuIdentityEqual(a, { card: "card0", vendor: "intel", path: a.path }), false);
  assert.equal(Model.gpuIdentityEqual(a, { card: a.card, vendor: "amd", path: a.path }), false);
  assert.equal(Model.gpuIdentityEqual(a, { card: a.card, vendor: a.vendor, path: "/sys/other" }), false);
  const rebuilt = Model.reconcileGpuTopology([a], {
    gpusByCard: { card1: { name: "Intel UHD Graphics", slot: "0000:00:02.0" } }
  }, "auto").integratedGpu;
  assert.equal(Model.gpuIdentityEqual(a, rebuilt), true);
});

test("gpuStreamSignature is stable across same-card topology rebuilds", () => {
  const raw = { card: "card1", vendor: "amd", path: "/sys/class/drm/card1/device", boot: true };
  const first = Model.pickGpu(
    Model.reconcileGpuTopology([raw], null, "auto").discreteGpus, "auto");
  const rebuilt = Model.pickGpu(
    Model.reconcileGpuTopology([raw], {
      gpusByCard: { card1: { name: "Radeon RX 7900 XT" } }
    }, "auto").discreteGpus, "auto");
  assert.ok(first);
  assert.ok(rebuilt);
  assert.notEqual(first, rebuilt);
  assert.equal(Model.gpuStreamSignature(first), "amd:/sys/class/drm/card1/device");
  assert.equal(Model.gpuStreamSignature(rebuilt), Model.gpuStreamSignature(first));
  assert.equal(Model.gpuStreamPath(rebuilt), Model.gpuStreamPath(first));
  assert.equal(Model.gpuStreamVendor(rebuilt), "amd");
});

test("gpuStreamSignature changes when path or vendor changes", () => {
  const amd = { vendor: "amd", path: "/sys/a" };
  const amdOther = { vendor: "amd", path: "/sys/b" };
  const intel = { vendor: "intel", path: "/sys/a" };
  const nvidia = { vendor: "nvidia", path: "/sys/a" };
  assert.equal(Model.gpuStreamSignature(amd), "amd:/sys/a");
  assert.notEqual(Model.gpuStreamSignature(amd), Model.gpuStreamSignature(amdOther));
  assert.notEqual(Model.gpuStreamSignature(amd), Model.gpuStreamSignature(intel));
  assert.equal(Model.gpuStreamSignature(nvidia), "");
  assert.equal(Model.gpuStreamSignature(null), "");
  assert.equal(Model.gpuStreamSignature({ vendor: "amd", path: "" }), "");
  assert.equal(Model.gpuStreamPath(nvidia), "");
  assert.equal(Model.gpuStreamVendor(intel), "intel");
});

test("normalizeGpuList keeps slot and pci identity", () => {
  const list = Model.normalizeGpuList({
    gpus: [{
      card: "card1", vendor: "intel", path: "/sys/class/drm/card1/device",
      boot: true, slot: "0000:00:02.0", pciClass: "0x030000",
      pciId: "8086:7d55", driver: "i915"
    }]
  });
  assert.equal(list.length, 1);
  assert.equal(list[0].slot, "0000:00:02.0");
  assert.equal(list[0].pciId, "8086:7d55");
  assert.equal(list[0].driver, "i915");
  assert.equal(list[0].pciClass, "0x030000");
});

test("cleanGpuName prefers the marketing name inside brackets", () => {
  assert.equal(Model.cleanGpuName("Navi 31 [Radeon RX 7900 XT/7900 XTX/7900 GRE/7900M]"), "Radeon RX 7900 XT");
  assert.equal(Model.cleanGpuName("Navi 31 [Radeon RX 7900 XTX]"), "Radeon RX 7900 XTX");
  assert.equal(Model.cleanGpuName("AD102 [GeForce RTX 4090]"), "GeForce RTX 4090");
  assert.equal(Model.cleanGpuName("Raptor Lake-P [Iris Xe Graphics]"), "Iris Xe Graphics");
  assert.equal(Model.cleanGpuName("Meteor Lake-P [Intel Arc Graphics]"), "Intel Arc Graphics");
  assert.equal(Model.cleanGpuName("NVIDIA GeForce RTX 4070"), "NVIDIA GeForce RTX 4070");
  assert.equal(Model.cleanGpuName("Intel Corporation Ice Lake-LP GT2 [Iris Plus Graphics G1]"), "Iris Plus Graphics G1");
  assert.equal(Model.cleanGpuName(""), "");
});

test("gpuVramPct understands stream, DRM and nvidia shapes", () => {
  assert.equal(Model.gpuVramPct({ vramUsed: 2, vramTotal: 8 }), 25);
  assert.equal(Model.gpuVramPct({ memUsedM: 512, memTotalM: 2048 }), 25);
  assert.equal(Model.gpuVramPct({ vramUsed: 2, vramTotal: 0 }), null);
  assert.equal(Model.gpuVramPct({ busy: 3 }), null);
  assert.equal(Model.gpuVramPct(null), null);
});

test("parseNvidiaApps reads pid, memory and comm rows", () => {
  const rows = Model.parseNvidiaApps("1234\t512\tblender\n77\tx\tbad\n\n9\t0\t\n");
  assert.deepEqual(rows, [{ pid: 1234, memUsedM: 512, comm: "blender" }, { pid: 9, memUsedM: 0, comm: "" }]);
  assert.deepEqual(Model.parseNvidiaApps(""), []);
  assert.deepEqual(Model.parseNvidiaApps(null), []);
});
