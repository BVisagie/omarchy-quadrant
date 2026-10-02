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

test("formatRate and formatBytes", () => {
  assert.equal(Model.formatRate(512), "512 B/s");
  assert.equal(Model.formatRate(1126), "1.1 KiB/s");
  assert.equal(Model.formatRate(3686), "3.6 KiB/s");
  assert.equal(Model.formatRate(5 * 1024 * 1024), "5 MiB/s");
  assert.equal(Model.formatRate(null), "--");
  assert.equal(Model.formatBytes(2048), "2 KiB");
  assert.equal(Model.formatKiB(1024), "1 MiB");
  assert.equal(Model.formatKiB(1536), "1.5 MiB");
});

test("formatPct, formatTemp, formatUptime", () => {
  assert.equal(Model.formatPct(37.4), "37%");
  assert.equal(Model.formatPct(12.34, 1), "12.3%");
  assert.equal(Model.formatPct(null), "--");
  assert.equal(Model.formatTemp(52.4), "52°C");
  assert.equal(Model.formatTemp(null), "--");
  assert.equal(Model.formatUptime(90061), "1d 1h");
  assert.equal(Model.formatUptime(3660), "1h 1m");
  assert.equal(Model.formatUptime(300), "5m");
});

test("formatMhz, formatWatts, formatLoad", () => {
  assert.equal(Model.formatMhz(1800), "1800 MHz");
  assert.equal(Model.formatMhz(null), "--");
  assert.equal(Model.formatGpuClock(1800), "1800 MHz");
  assert.equal(Model.formatGpuClock(0), "IDLE");
  assert.equal(Model.formatGpuClock(null), "--");
  assert.equal(Model.formatWatts(85), "85 W");
  assert.equal(Model.formatWatts(8.24), "8.2 W");
  assert.equal(Model.formatLoad(0.5), "0.50");
  assert.equal(Model.nvidiaMiBToBytes(1024), 1024 * 1024 * 1024);
  assert.equal(Model.nvidiaMiBToBytes(null), null);
});

test("formatRateCompact stays within four glyphs plus a unit", () => {
  assert.equal(Model.formatRateCompact(0), "0B");
  assert.equal(Model.formatRateCompact(999), "999B");
  assert.equal(Model.formatRateCompact(1000), "1.0K");
  assert.equal(Model.formatRateCompact(1024), "1.0K");
  assert.equal(Model.formatRateCompact(1024 * 9.9), "9.9K");
  assert.equal(Model.formatRateCompact(1024 * 10), "10K");
  assert.equal(Model.formatRateCompact(1024 * 999), "999K");
  assert.equal(Model.formatRateCompact(1024 * 1024), "1.0M");
  assert.equal(Model.formatRateCompact(5 * 1024 * 1024), "5.0M");
  assert.equal(Model.formatRateCompact(null), "--");
  assert.equal(Model.formatRateCompact(-1), "--");
});

test("formatRateUnit shows bytes with binary units and bits with decimal units", () => {
  assert.equal(Model.formatRateUnit(1536, "bytes"), "1.5 KiB/s");
  assert.equal(Model.formatRateUnit(1250, "bits"), "10 kb/s");
  assert.equal(Model.formatRateUnit(125000000, "bits"), "1 Gb/s");
  assert.equal(Model.formatRateUnit(137500, "bits"), "1.1 Mb/s");
  assert.equal(Model.formatRateUnit(null, "bits"), "--");
  assert.equal(Model.formatRateUnit(5, "nope"), "5 B/s");
});
