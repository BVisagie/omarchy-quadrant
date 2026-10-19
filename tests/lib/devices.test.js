"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const Model = require("../../lib/index.mjs");
const ReleasedSettings = require("../fixtures/settings-v1.mjs");

function gpu(card, slot, extra = {}) {
  return { card, slot, vendor: "amd", path: `/sys/class/drm/${card}/device`, pciId: "1002:744c", ...extra };
}
function inventory(rows) {
  return Model.reconcileGpuTopology(Model.normalizeGpuList({ gpus: rows }), null, "none");
}
function disks(rows) {
  return Model.parseDiskInfo({ ok: true, disks: rows, backing: { cryptroot: "sda" }, dfPayload: "" });
}

test("persistent settings accept typed and quoted IDs, reject paths and malformed addresses", () => {
  const cfg = Model.readSettings({
    gpuDeviceId: '"0000:AF:1F.7"', integratedGpuDeviceId: "0000:00:02.0", diskDeviceId: '"wwn-0x1234"'
  });
  assert.equal(cfg.gpuDeviceId, "0000:af:1f.7");
  assert.equal(cfg.integratedGpuDeviceId, "0000:00:02.0");
  assert.equal(cfg.diskDeviceId, "wwn-0x1234");
  for (const id of ["../card0", "/sys/bus/pci/0000:03:00.0", "0000:03:20.0", "0000:03:00.8", "0:03:00.0", "03:00.0", "auto"])
    assert.equal(Model.normalizeGpuDeviceId(id), "", id);
  for (const id of ["../sda", "/dev/disk/by-id/ata-123", "ata-123-part1", "a".repeat(256), "a\nb", "-i", "a..b"])
    assert.equal(Model.normalizeDiskDeviceId(id), "", id);
  assert.equal(Model.normalizeDiskDeviceId("nvme-eui.0123456789"), "nvme-eui.0123456789");
});

test("PCI pins survive a card enumeration swap, and never fall back to a reused name", () => {
  const before = inventory([gpu("card0", "0000:03:00.0"), gpu("card1", "0000:08:00.0")]);
  const after = inventory([gpu("card1", "0000:03:00.0"), gpu("card0", "0000:08:00.0")]);
  const first = Model.pickGpu(before.discreteGpus, "card0", "0000:03:00.0");
  const next = Model.pickGpu(after.discreteGpus, "card0", "0000:03:00.0");
  assert.equal(next.card, "card1");
  assert.equal(Model.gpuHistoryTag(first), Model.gpuHistoryTag(next));
  assert.equal(Model.gpuIdentityEqual(first, next), false); // reset in-flight polls and rate baselines
  const absent = after.gpus.filter(g => g.card === "card0");
  assert.equal(Model.pickGpu(absent, "card0", "0000:03:00.0"), null);
  assert.match(Model.gpuDevicePinMessage(absent, "card0", "0000:03:00.0"), /0000:03:00.0.*not available/);
  assert.equal(Model.pickGpu(after.discreteGpus, "auto").card, "card0");
});

test("an integrated pin follows its PCI address, including none/auto legacy values", () => {
  const rows = Model.normalizeGpuList({ gpus: [gpu("card0", "0000:08:00.0"), gpu("card1", "0000:00:02.0", { vendor: "intel" })] });
  for (const policy of ["card0", "auto", "none"]) {
    const topo = Model.reconcileGpuTopology(rows, null, policy, "0000:00:02.0");
    assert.equal(topo.integratedGpu.card, "card1");
    assert.deepEqual(topo.discreteGpus.map(g => g.card), ["card0"]);
  }
  const missing = Model.reconcileGpuTopology(rows, null, "auto", "0000:03:00.0");
  assert.equal(missing.integratedGpu, null);
  assert.equal(missing.discreteGpus.length, 2);
});

test("duplicate PCI addresses are unusable as persistent pins", () => {
  const topo = inventory([gpu("card0", "0000:03:00.0"), gpu("card1", "0000:03:00.0")]);
  assert.ok(topo.gpus.every(g => g.deviceId === ""));
  assert.equal(Model.pickGpu(topo.gpus, "card0", "0000:03:00.0"), null);
  assert.equal(Model.pickGpu(topo.gpus, "card0").card, "card0");
});

test("missing GPU identity cannot be inferred from a cached card name", () => {
  const topo = Model.reconcileGpuTopology(Model.normalizeGpuList({ gpus: [gpu("card1", "", { revision: 12 })] }),
    { gpusByCard: { card1: { slot: "0000:03:00.0", name: "Old card" } } }, "auto");
  assert.equal(topo.gpus[0].deviceId, "");
  assert.equal(topo.gpus[0].revision, "");
  assert.equal(Model.gpuHistoryTag(topo.gpus[0]), "name:card1");
  const withoutFingerprint = inventory([gpu("card0", "0000:03:00.0", { pciId: "" })]).gpus[0];
  const moved = inventory([gpu("card0", "0000:08:00.0", { pciId: "" })]).gpus[0];
  assert.notEqual(Model.gpuHistoryTag(withoutFingerprint), Model.gpuHistoryTag(moved));
  assert.equal(Model.gpuIdentityEqual(withoutFingerprint, moved), false);
  const tag = Model.gpuHistoryTag(withoutFingerprint);
  const loaded = Model.loadHistoryFile({ v: 2, saved: 990, tags: { gpu: tag } }, 1000, 3600, 10);
  assert.equal(Model.historySeriesMatches(loaded, "gpu", tag, "card0", 950), true);
  assert.equal(Model.historySeriesMatches(loaded, "gpu", tag, "card0", 995), false);
});

test("replacement in the same PCI slot changes the GPU fingerprint and live identity", () => {
  const old = inventory([gpu("card0", "0000:03:00.0", { subsystemId: "1002:0001", revision: "c8" })]).gpus[0];
  for (const changes of [{ pciId: "1002:7550" }, { subsystemId: "1002:0002" }, { revision: "c9" }]) {
    const next = { ...old, ...changes };
    assert.notEqual(Model.gpuHistoryTag(old), Model.gpuHistoryTag(next));
    assert.equal(Model.gpuIdentityEqual(old, next), false);
  }
  assert.equal(Model.gpuIdentityEqual(old, { ...old, name: "new descriptive name" }), true);
});

test("topology refresh joins names by physical slot when system-info still has old card numbers", () => {
  const sys = { gpusByCard: {
    card0: { slot: "0000:03:00.0", pciId: "1002:744c", name: "Radeon RX 7900 XT" },
    card1: { slot: "0000:08:00.0", pciId: "1002:744c", name: "Radeon Graphics" }
  } };
  const topo = Model.reconcileGpuTopology(Model.normalizeGpuList({ gpus: [gpu("card1", "0000:03:00.0"), gpu("card0", "0000:08:00.0")] }), sys, "auto");
  assert.equal(topo.integratedGpu.card, "card0");
  assert.equal(topo.discreteGpus[0].name, "Radeon RX 7900 XT");
});

test("whole-disk IDs and aliases survive enumeration swaps and usage refresh", () => {
  const info = disks([
    { name: "sdb", deviceIds: ["ata-ABC", "wwn-0x1234", "ata-ABC-part1", "../bad"], sizeBytes: 1 },
    { name: "sda", deviceIds: ["ata-DEF"], sizeBytes: 2 }
  ]);
  assert.equal(info.disks[0].deviceId, "wwn-0x1234");
  assert.deepEqual(info.disks[0].deviceIds, ["wwn-0x1234", "ata-ABC"]);
  for (const id of ["wwn-0x1234", "ata-ABC"])
    assert.equal(Model.pickDisk(info.disks, [], [{ name: "sda" }], "sda", {}, id), "sdb");
  assert.equal(Model.pickDisk(info.disks, [], [], "sda", {}, "wwn-missing"), null);
  assert.equal(Model.pickDisk(info.disks, [], [], "auto", {}), "sda");
  const refreshed = Model.mergeDiskUsage(info, { mounts: [], temps: { sdb: 33 } });
  assert.equal(refreshed.disks[0].tempC, 33);
  assert.deepEqual(refreshed.disks[0].deviceIds, info.disks[0].deviceIds);
  assert.equal(Model.diskHistoryTag(refreshed.disks[0], "sdb"), "by-id:wwn-0x1234");
});

test("disk identity prefers namespace-specific NVMe aliases, drops duplicates, and permits name fallback", () => {
  const info = disks([
    { name: "nvme0n1", deviceIds: ["nvme-model_serial", "nvme-model_serial_1", "wwn-duplicate"] },
    { name: "nvme1n1", deviceIds: ["wwn-duplicate"] },
    { name: "vda" }
  ]);
  assert.equal(info.disks[0].deviceId, "nvme-model_serial_1");
  assert.equal(info.disks[1].deviceId, "");
  assert.equal(Model.diskDeviceById(info.disks, "wwn-duplicate"), null);
  assert.equal(Model.pickDisk(info.disks, [], [], "nvme1n1", {}), "nvme1n1");
  assert.equal(Model.diskHistoryTag(info.disks[1], "nvme1n1"), "name:nvme1n1");
});

test("legacy pins migrate only when resolved; existing IDs update only the compatibility name", () => {
  const gpus = inventory([gpu("card1", "0000:03:00.0"), gpu("card0", "0000:00:02.0")]).gpus;
  const diskInfo = disks([{ name: "sda", deviceIds: ["ata-ABC"] }]);
  const legacy = Model.readSettings({ gpuDevice: '"card1"', integratedGpuDevice: "card0", diskDevice: '"cryptroot"' });
  assert.deepEqual(Model.devicePinMigration(legacy, gpus, diskInfo), {
    gpuDeviceId: "0000:03:00.0", integratedGpuDeviceId: "0000:00:02.0", diskDevice: "sda", diskDeviceId: "ata-ABC"
  });
  const pinned = Model.readSettings({ gpuDevice: "card0", gpuDeviceId: "0000:03:00.0", diskDevice: "sdb", diskDeviceId: "ata-ABC" });
  assert.deepEqual(Model.devicePinMigration(pinned, gpus, diskInfo), { gpuDevice: "card1", diskDevice: "sda" });
  const unresolved = Model.readSettings({ gpuDevice: "card9", diskDevice: "sdc", integratedGpuDevice: "card8" });
  assert.deepEqual(Model.devicePinMigration(unresolved, gpus, diskInfo), {});
  assert.deepEqual(Model.devicePinMigration(Model.readSettings({}), gpus, diskInfo), {});
  assert.deepEqual(Model.devicePinMigration(legacy, null, null), {});
});

test("a live auto/none change clears the unchanged device ID", () => {
  for (const [key, name, id, policies] of [
    ["gpuDevice", "card1", "0000:03:00.0", ["auto"]],
    ["integratedGpuDevice", "card0", "0000:00:02.0", ["auto", "none"]],
    ["diskDevice", "sda", "ata-ABC", ["auto"]]
  ]) {
    const idKey = key + "Id";
    for (const policy of policies) {
      const previous = Model.readSettings({ [key]: name, [idKey]: id });
      const next = Model.readSettings({ [key]: JSON.stringify(policy), [idKey]: JSON.stringify(id) });
      assert.deepEqual(Model.devicePolicyResetPatch(previous, next), { [idKey]: "" });
      const persisted = Model.settingsPatch(next, Model.devicePolicyResetPatch(previous, next));
      assert.equal(Model.readSettings(persisted)[key], policy);
      assert.equal(Model.readSettings(persisted)[idKey], "");
      assert.deepEqual(Model.devicePinMigration(Model.readSettings(persisted), inventory([gpu("card1", "0000:03:00.0")]).gpus,
        disks([{ name: "sda", deviceIds: ["ata-ABC"] }])), {});
    }
  }
});

test("initial settings, ID-only edits, and unchanged policies keep ID precedence", () => {
  const pinned = Model.readSettings({ gpuDevice: "card1", gpuDeviceId: "0000:03:00.0", diskDevice: "sda", diskDeviceId: "ata-ABC" });
  assert.deepEqual(Model.devicePolicyResetPatch(null, pinned), {});
  assert.deepEqual(Model.devicePolicyResetPatch(Model.readSettings({}), Model.readSettings({ gpuDeviceId: "0000:03:00.0" })), {});
  assert.deepEqual(Model.devicePolicyResetPatch(pinned, Model.readSettings({ ...pinned, processCount: 8 })), {});
  assert.deepEqual(Model.devicePolicyResetPatch(pinned, Model.readSettings({ ...pinned, gpuDevice: "auto", gpuDeviceId: "0000:08:00.0" })), {});
  assert.deepEqual(Model.devicePolicyResetPatch(pinned, Model.readSettings({ ...pinned, gpuDevice: "auto", gpuDeviceId: "" })), {});
  const initial = Model.readSettings({ gpuDeviceId: "0000:03:00.0", integratedGpuDevice: "none", integratedGpuDeviceId: "0000:08:00.0" });
  assert.deepEqual(Model.devicePolicyResetPatch(initial, { ...initial }), {});
  const gpus = inventory([gpu("card1", "0000:03:00.0"), gpu("card0", "0000:08:00.0")]).gpus;
  assert.deepEqual(Model.devicePinMigration(initial, gpus, null), { gpuDevice: "card1", integratedGpuDevice: "card0" });
});

test("the released settings writer preserves identity keys and usable best-effort pins on downgrade", () => {
  const current = Model.settingsPatch({ userNote: { keep: true } }, {
    gpuDevice: "card1", gpuDeviceId: "0000:03:00.0", integratedGpuDevice: "card0",
    integratedGpuDeviceId: "0000:00:02.0", diskDevice: "sdb", diskDeviceId: "ata-ABC"
  });
  const oldCfg = ReleasedSettings.readSettings(current);
  assert.equal(oldCfg.gpuDevice, "card1");
  assert.equal(oldCfg.integratedGpuDevice, "card0");
  assert.equal(oldCfg.diskDevice, "sdb");
  const oldWrite = ReleasedSettings.settingsPatch(current, { processCount: 7 });
  const upgraded = Model.readSettings(oldWrite);
  assert.equal(upgraded.gpuDeviceId, "0000:03:00.0");
  assert.equal(upgraded.integratedGpuDeviceId, "0000:00:02.0");
  assert.equal(upgraded.diskDeviceId, "ata-ABC");
  assert.deepEqual(oldWrite.userNote, { keep: true });
  assert.equal(upgraded.processCount, 7);
});

test("history accepts stable identity across boots and legacy names only within the current boot", () => {
  const tag = Model.gpuHistoryTag(inventory([gpu("card1", "0000:03:00.0")]).gpus[0]);
  const load = (v, saved, gpuTag) => Model.loadHistoryFile({ v, saved, tags: { gpu: gpuTag, disk: "sda", iface: "enp1s0" }, gpu: [{ t: 990, b: 20 }] }, 1000, 3600, 10);
  const matches = (data, target = tag, boot = 950) => Model.historySeriesMatches(data, "gpu", target, "card1", boot);
  assert.equal(matches(load(2, 900, tag)), true);
  assert.equal(matches(load(2, 990, tag), tag.replace("744c", "7550")), false);
  assert.equal(matches(load(1, 990, "card1")), true);
  assert.equal(matches(load(1, 900, "card1")), false);
  assert.equal(matches(load(1, undefined, "card1")), false);
  assert.equal(matches(load(1, 990, "card1"), tag, 0), false);
  assert.equal(matches(load(1, 990, "card0")), false);
  assert.equal(matches(load(2, 990, "name:card1")), true);
  assert.equal(matches(load(2, 900, "name:card1")), false);
  assert.equal(matches(load(1, 99999, "card1")), false); // untrustworthy future save time
  const legacy = load(1, 900, "card1");
  assert.equal(Model.historySeriesMatches(legacy, "cpu", "", "", 950), true);
  assert.equal(Model.historySeriesMatches(legacy, "mem", "", "", 950), true);
  assert.equal(Model.historySeriesMatches(legacy, "net", "enp1s0", "", 950), true);
  assert.equal(Model.historySeriesMatches(legacy, "disk", "by-id:ata-ABC", "sda", 950), false);
  legacy.saved = 990;
  assert.equal(Model.historySeriesMatches(legacy, "disk", "by-id:ata-ABC", "sda", 950), true);
  const stableDisk = Model.loadHistoryFile({ v: 2, saved: 900, tags: { disk: "by-id:ata-ABC" } }, 1000, 3600, 10);
  assert.equal(Model.historySeriesMatches(stableDisk, "disk", "by-id:ata-ABC", "sdb", 950), true);
});

test("kernel boot time parser tolerates /proc/stat fields and fails closed on missing metadata", () => {
  assert.equal(Model.parseBootTime("cpu 1 2 3\nintr 1 2\nbtime 1770000000\nprocesses 42\n"), 1770000000);
  for (const text of [null, "", "btime nope\n", "other_btime 100\n"])
    assert.equal(Model.parseBootTime(text), 0);
});
