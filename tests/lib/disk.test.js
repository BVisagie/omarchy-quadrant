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

test("isPartitionName and parentDiskName cover common layouts", () => {
  assert.equal(Model.isPartitionName("sda1"), true);
  assert.equal(Model.isPartitionName("sda"), false);
  assert.equal(Model.isPartitionName("nvme0n1"), false);
  assert.equal(Model.isPartitionName("nvme0n1p2"), true);
  assert.equal(Model.isPartitionName("mmcblk0"), false);
  assert.equal(Model.isPartitionName("mmcblk0p1"), true);
  assert.equal(Model.isPartitionName("vda"), false);
  assert.equal(Model.isPartitionName("vda1"), true);
  assert.equal(Model.isPartitionName("dm-0"), false);
  assert.equal(Model.parentDiskName("sda1"), "sda");
  assert.equal(Model.parentDiskName("nvme0n1p2"), "nvme0n1");
  assert.equal(Model.parentDiskName("mmcblk0p1"), "mmcblk0");
  assert.equal(Model.parentDiskName("vda3"), "vda");
  assert.equal(Model.parentDiskName("nvme0n1"), "nvme0n1");
  assert.equal(Model.isExcludedDiskName("loop0"), true);
  assert.equal(Model.isExcludedDiskName("zram0"), true);
  assert.equal(Model.isExcludedDiskName("sda"), false);
  assert.equal(Model.isVirtualDiskName("dm-0"), true);
  assert.equal(Model.isVirtualDiskName("md0"), true);
  assert.equal(Model.isVirtualDiskName("nvme0n1"), false);
});

test("parseDiskstats keeps whole devices and drops partitions and virtuals", () => {
  const rows = Model.parseDiskstats(fixture("diskstats-basic.txt"));
  const names = rows.map((r) => r.n);
  assert.deepEqual(names, ["sda", "nvme0n1", "mmcblk0", "vda"]);
  const nvme = rows.find((r) => r.n === "nvme0n1");
  assert.equal(nvme.rd, 5000);
  assert.equal(nvme.rs, 40000);
  assert.equal(nvme.wr, 3000);
  assert.equal(nvme.ws, 24000);
  assert.equal(nvme.io, 200);
  assert.equal(Model.parseDiskstats("").length, 0);
  assert.equal(Model.parseDiskstats(fixture("diskstats-hostile.txt")).length, 1);
  assert.equal(Model.parseDiskstats(fixture("diskstats-hostile.txt"))[0].n, "sda");
});

test("diskRates computes bytes, IOPS, and utilPct from io_ticks", () => {
  const prev = [{ n: "sda", rd: 10, rs: 20, wr: 5, ws: 8, io: 100 }];
  const curr = [{ n: "sda", rd: 30, rs: 20 + 200, wr: 15, ws: 8 + 50, io: 300 }];
  const rates = Model.diskRates(prev, curr, 2);
  assert.equal(rates.length, 1);
  assert.equal(rates[0].name, "sda");
  assert.equal(rates[0].readBps, 200 * 512 / 2);
  assert.equal(rates[0].writeBps, 50 * 512 / 2);
  assert.equal(rates[0].readIops, 10);
  assert.equal(rates[0].writeIops, 5);
  assert.equal(rates[0].utilPct, 10); // 200 ms / 2000 ms * 100
  const reset = Model.diskRates(curr, prev, 1);
  assert.equal(reset[0].readBps, 0);
  assert.equal(Model.diskRates(null, curr, 1)[0].readBps, 0);
  assert.deepEqual(Model.diskRates(prev, curr, 0), []);
});

test("parseDf keeps real filesystems and drops virtual ones", () => {
  const mounts = Model.parseDf(fixture("df-basic.txt"));
  const targets = mounts.map((m) => m.target);
  assert.deepEqual(targets, ["/", "/boot", "/home", "/mnt/nas"]);
  assert.equal(mounts[0].fstype, "ext4");
  assert.equal(mounts[0].source, "/dev/nvme0n1p2");
  assert.equal(mounts[0].pct, 24);
  const nas = mounts.find((m) => m.target === "/mnt/nas");
  assert.equal(nas.fstype, "nfs4");
  const hostile = Model.parseDf(fixture("df-hostile.txt"));
  assert.equal(hostile.length, 1);
  assert.equal(hostile[0].target, "/<img src=x>");
  assert.equal(Model.parseDf("").length, 0);
});

test("collapseMounts keeps the shortest path of a bind-mount set", () => {
  const mounts = [
    { source: "/dev/nvme0n1p2", fstype: "ext4", size: 100, used: 40, avail: 60, pct: 40, target: "/var/log" },
    { source: "/dev/nvme0n1p2", fstype: "ext4", size: 100, used: 40, avail: 60, pct: 40, target: "/" },
    { source: "/dev/nvme0n1p2", fstype: "ext4", size: 100, used: 40, avail: 60, pct: 40, target: "/home" },
    { source: "/dev/nvme0n1p1", fstype: "vfat", size: 2, used: 1, avail: 1, pct: 8, target: "/boot" }
  ];
  const collapsed = Model.collapseMounts(mounts);
  const targets = collapsed.map((m) => m.target).sort();
  assert.deepEqual(targets, ["/", "/boot"]);
});

test("parseDiskInfo validates disks and parses the df payload", () => {
  const info = Model.parseDiskInfo(JSON.parse(fixture("disk-info-basic.json")));
  assert.ok(info);
  const names = info.disks.map((d) => d.name);
  assert.deepEqual(names, ["nvme0n1", "sda", "evil"]);
  assert.equal(info.disks[0].model, "Samsung SSD 990 PRO 2TB");
  assert.equal(info.disks[0].rotational, false);
  assert.equal(info.disks[0].tempC, 38);
  assert.equal(info.disks[1].rotational, true);
  const evil = info.disks.find((d) => d.name === "evil");
  assert.equal(evil.model, "<img src=x>");
  assert.equal(evil.rotational, null);
  assert.equal(evil.sizeBytes, null);
  assert.equal(info.mounts.length, 1);
  assert.equal(info.mounts[0].target, "/");
  assert.deepEqual(info.backing, {});
  assert.equal(Model.parseDiskInfo(null), null);
  assert.equal(Model.parseDiskInfo({ ok: false }), null);
});

test("pickDisk prefers the root disk, then the largest, then a pin", () => {
  const disks = [
    { name: "sda", sizeBytes: 2000 },
    { name: "nvme0n1", sizeBytes: 500 }
  ];
  const mounts = [{ source: "/dev/nvme0n1p2", target: "/" }];
  const rates = [{ name: "sda" }, { name: "nvme0n1" }];
  assert.equal(Model.pickDisk(disks, mounts, rates, "auto"), "nvme0n1");
  assert.equal(Model.pickDisk(disks, [], rates, "auto"), "sda");
  assert.equal(Model.pickDisk(disks, mounts, rates, "sda"), "sda");
  assert.equal(Model.pickDisk(disks, mounts, rates, "nope"), null);
  assert.equal(Model.pickDisk([], [], [{ name: "vda" }], "auto"), "vda");
});

test("resolveBackingDisk maps mapper and partition sources", () => {
  const backing = { "dm-0": "nvme0n1", cryptroot: "nvme0n1" };
  assert.equal(Model.resolveBackingDisk("/dev/dm-0", backing), "nvme0n1");
  assert.equal(Model.resolveBackingDisk("/dev/mapper/cryptroot", backing), "nvme0n1");
  assert.equal(Model.resolveBackingDisk("/dev/nvme0n1p2", backing), "nvme0n1");
  assert.equal(Model.resolveBackingDisk("/dev/nvme1n1p1", backing), "nvme1n1");
  assert.equal(Model.resolveBackingDisk("nvme0n1", backing), "nvme0n1");
});

test("parseDiskInfo folds mapper disks onto the backing NVMe", () => {
  const info = Model.parseDiskInfo(JSON.parse(fixture("disk-info-luks.json")));
  assert.ok(info);
  assert.deepEqual(info.disks.map((d) => d.name), ["nvme0n1", "nvme1n1"]);
  assert.equal(info.backing["dm-0"], "nvme0n1");
  assert.equal(info.backing.cryptroot, "nvme0n1");
  const targets = info.mounts.map((m) => m.target);
  assert.deepEqual(targets, ["/", "/boot"]);
});

test("pickDisk remaps mapper pins and quoted names through backing", () => {
  const info = Model.parseDiskInfo(JSON.parse(fixture("disk-info-luks.json")));
  const rates = [{ name: "nvme0n1" }, { name: "nvme1n1" }, { name: "dm-0" }];
  assert.equal(Model.pickDisk(info.disks, info.mounts, rates, "auto", info.backing), "nvme0n1");
  assert.equal(Model.pickDisk(info.disks, info.mounts, rates, "dm-0", info.backing), "nvme0n1");
  assert.equal(Model.pickDisk(info.disks, info.mounts, rates, '"dm-0"', info.backing), "nvme0n1");
  assert.equal(Model.pickDisk(info.disks, info.mounts, rates, '"nvme1n1"', info.backing), "nvme1n1");
  assert.equal(Model.diskNamePresent("nvme0n1", info.disks, rates), true);
  assert.equal(Model.diskNamePresent("dm-0", info.disks, rates), true);
});

test("pickDisk keeps a multi-parent RAID device selectable", () => {
  const info = Model.parseDiskInfo(JSON.parse(fixture("disk-info-raid.json")));
  const rates = [{ name: "nvme0n1" }, { name: "nvme1n1" }, { name: "md0" }];
  assert.deepEqual(info.disks.map((d) => d.name), ["nvme0n1", "nvme1n1", "md0"]);
  assert.equal(Model.pickDisk(info.disks, info.mounts, rates, "auto", info.backing), "md0");
  assert.equal(Model.pickDisk(info.disks, info.mounts, rates, "md0", info.backing), "md0");
  assert.equal(Model.pickDisk(info.disks, [], rates, "auto", info.backing), "nvme0n1");
});

test("parseDiskUsage and mergeDiskUsage refresh mounts and temperatures only", () => {
  const info = Model.parseDiskInfo(JSON.parse(fixture("disk-info-basic.json")));
  const usage = Model.parseDiskUsage({ ok: true, usage: true, temps: { nvme0n1: 51, "bad name": 1, nvme1n1: "x" }, dfPayload: fixture("df-basic.txt") });
  assert.deepEqual(usage.temps, { nvme0n1: 51 });
  assert.ok(usage.mounts.length > 0);
  const merged = Model.mergeDiskUsage(info, usage);
  assert.equal(merged.disks.length, info.disks.length);
  const d = merged.disks.find((x) => x.name === "nvme0n1");
  if (d) assert.equal(d.tempC, 51);
  assert.deepEqual(merged.backing, info.backing);
  assert.equal(Model.parseDiskUsage({ ok: false }), null);
  assert.equal(Model.mergeDiskUsage(null, usage), null);
  assert.equal(Model.mergeDiskUsage(info, null), info);
});
