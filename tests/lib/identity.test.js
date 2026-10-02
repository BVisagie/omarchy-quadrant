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

test("hostLine joins DMI without repeating the vendor", () => {
  assert.equal(Model.hostLine({ sysVendor: "Framework", productName: "Laptop 16 (AMD Ryzen 7040 Series)" }),
    "Framework Laptop 16 (AMD Ryzen 7040 Series)");
  assert.equal(Model.hostLine({ sysVendor: "Framework", productName: "Framework Laptop 13" }),
    "Framework Laptop 13");
  assert.equal(Model.hostLine({ sysVendor: "Dell Inc.", productName: "" }), "Dell Inc.");
  assert.equal(Model.hostLine({ sysVendor: "ASUS", productName: "System Product Name" }), "ASUS");
  assert.equal(Model.hostLine({ sysVendor: "To Be Filled By O.E.M.", productName: "To Be Filled By O.E.M." }), "");
  assert.equal(Model.hostLine({ sysVendor: "", productName: "" }), "");
  assert.equal(Model.hostLine(null), "");
});

test("parseLspciMm reads quoted machine-format lines", () => {
  const rows = Model.parseLspciMm(fixture("lspci-mm.txt"));
  assert.equal(rows.length, 5);
  assert.equal(rows[0].slot, "0000:03:00.0");
  assert.equal(rows[0].device, "Navi 31 [Radeon RX 7900 XTX]");
  assert.equal(rows[1].vendor, "Intel Corporation");
  assert.equal(rows[2].device, "AD102 [GeForce RTX 4090]");
  // escaped quotes survive; a hostile <img> stays inert text
  assert.equal(rows[3].device, 'Quote "inside" name <img src=x>');
  assert.equal(rows[4].slot, "0000:0b:00.0");
  assert.equal(Model.parseLspciMm("").length, 0);
  assert.equal(Model.parseLspciMm(null).length, 0);
});

test("parseSystemInfo joins lspci names onto cards by slot", () => {
  const info = Model.parseSystemInfo(JSON.parse(fixture("system-info-basic.json")));
  assert.ok(info);
  assert.equal(info.cpu.modelName, "AMD Ryzen 9 7950X 16-Core Processor");
  assert.equal(info.cpu.vendorId, "AuthenticAMD");
  assert.equal(info.cpu.physCores, 16);
  assert.equal(info.cpu.threads, 32);
  assert.equal(info.cpu.cacheKb, 16384);
  assert.equal(info.cpu.governor, "schedutil");
  assert.equal(info.cpu.maxMhz, 5755);
  assert.equal(info.gpus.length, 2);
  assert.equal(info.gpus[0].name, "Navi 31 [Radeon RX 7900 XTX]");
  assert.equal(info.gpus[1].name, "AD102 [GeForce RTX 4090]");
  assert.equal(info.gpusByCard.card0.driver, "amdgpu");
  assert.equal(info.gpusByCard.card0.pciId, "1002:744c");
  assert.equal(info.mem.zram[0].alg, "zstd");
  assert.equal(info.mem.swaps[1].kind, "partition");
  assert.equal(info.host.sysVendor, "Framework");
  assert.equal(Model.gpuVendorLabel("amd"), "AMD");
  assert.equal(Model.formatCache(16384), "16 MB");
});

test("parseSystemInfo tolerates a VM-like all-null envelope", () => {
  const info = Model.parseSystemInfo(JSON.parse(fixture("system-info-minimal.json")));
  assert.ok(info);
  assert.equal(info.cpu.modelName, "Intel(R) Xeon(R) Processor");
  assert.equal(info.cpu.governor, "");
  assert.equal(info.cpu.maxMhz, null);
  assert.equal(info.gpus.length, 0);
  assert.deepEqual(info.gpusByCard, {});
  assert.equal(info.mem.swaps.length, 0);
  assert.equal(info.mem.zram.length, 0);
  assert.equal(info.host.sysVendor, "");
  assert.equal(info.host.kernel, "6.12.94+");
  assert.equal(Model.parseSystemInfo(null), null);
  assert.equal(Model.parseSystemInfo({ ok: false }), null);
  assert.equal(Model.parseSystemInfo({}), null);
});

test("parseSystemInfo drops hostile and malformed GPU entries", () => {
  const info = Model.parseSystemInfo({
    ok: true,
    cpu: { modelName: "<img src=x>", vendorId: "GenuineIntel\n", governor: "schedutil;rm -rf /" },
    gpus: [
      { card: "card0", vendor: "amd", slot: "0000:03:00.0", driver: "amdgpu", pciId: "1002:744C" },
      { card: "evil", vendor: "amd", slot: "0000:03:00.0", driver: "amdgpu", pciId: "1002:744c" },
      { card: "card1", vendor: "mali", slot: "0000:04:00.0", driver: "x", pciId: "0000:0000" }
    ],
    lspciPayload: "\"0000:03:00.0\" \"VGA\" \"AMD\" \"Good name\"\n",
    mem: { swaps: [{ file: "/tmp/x", kind: "worm", sizeKb: -3 }], zram: [{ dev: "sda", alg: "zstd", diskBytes: 1 }] },
    host: { kernel: "6.1", sysVendor: "A", productName: "B" }
  });
  assert.equal(info.cpu.modelName, "<img src=x>");   // inert; rendered PlainText
  assert.equal(info.cpu.governor, "");               // rejected: not a governor token
  assert.equal(info.gpus.length, 1);
  assert.equal(info.gpus[0].pciId, "1002:744c");     // lowercased
  assert.equal(info.gpus[0].name, "Good name");
  assert.equal(info.mem.swaps[0].kind, "file");      // unknown kind coerced
  assert.equal(info.mem.zram.length, 0);             // sda is not zramN
});
