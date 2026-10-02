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

test("normalizeDeviceSetting strips wrapping quotes", () => {
  assert.equal(Model.normalizeDeviceSetting("nvme0n1"), "nvme0n1");
  assert.equal(Model.normalizeDeviceSetting('"nvme0n1"'), "nvme0n1");
  assert.equal(Model.normalizeDeviceSetting("  "), "auto");
  assert.equal(Model.normalizeDeviceSetting(""), "auto");
  assert.equal(Model.normalizeDeviceSetting(null), "auto");
  assert.equal(Model.normalizeDeviceSetting("auto"), "auto");
});

test("readSettings accepts typed values and pre-1.0 string entries alike", () => {
  const typed = Model.readSettings({
    segments: ["network", "cpu"], processCount: 8, barIntervalMs: 500, diskDevice: "nvme0n1",
    diskFallbackWithoutGpu: false, barPalette: "heat", rateUnit: "bits"
  });
  assert.deepEqual(typed.segments, ["cpu", "network"]);
  assert.equal(typed.processCount, 8);
  assert.equal(typed.barIntervalMs, 500);
  assert.equal(typed.diskDevice, "nvme0n1");
  assert.equal(typed.diskFallbackWithoutGpu, false);
  assert.equal(typed.barPalette, "heat");
  assert.equal(typed.rateUnit, "bits");
  // What `omarchy bar set` without --json stored.
  const legacy = Model.readSettings({
    segments: '["cpu","disk"]', processCount: "8", barIntervalMs: "\"500\"", diskDevice: '"nvme0n1"',
    diskFallbackWithoutGpu: "false", barPalette: '"Vivid"', barLabels: "LETTER", networkInterface: '"wg0"'
  });
  assert.deepEqual(legacy.segments, ["cpu", "disk"]);
  assert.equal(legacy.processCount, 8);
  assert.equal(legacy.barIntervalMs, 500);
  assert.equal(legacy.diskDevice, "nvme0n1");
  assert.equal(legacy.diskFallbackWithoutGpu, false);
  assert.equal(legacy.barPalette, "vivid");
  assert.equal(legacy.barLabels, "letter");
  assert.equal(legacy.networkInterface, "wg0");
  // Garbage falls back to defaults and limits clamp.
  const junk = Model.readSettings({ segments: "[oops", processCount: "99", barIntervalMs: -4, barPalette: "neon", rateUnit: 7 });
  assert.deepEqual(junk.segments, Model.SETTING_DEFAULTS.segments);
  assert.equal(junk.processCount, 10);
  assert.equal(junk.barIntervalMs, 250);
  assert.equal(junk.barPalette, "theme");
  assert.equal(junk.rateUnit, "bytes");
  assert.deepEqual(Model.readSettings(null), Model.readSettings({}));
  assert.deepEqual(Model.segmentsFromSetting("cpu, memory"), ["cpu", "memory"]);
});

test("settingsPatch writes a typed entry, keeps unknown keys, drops defaults", () => {
  const raw = { id: "dev.bvisagie.quadrant", processCount: "8", diskDevice: '"nvme0n1"', myNote: "keep me" };
  const next = Model.settingsPatch(raw, { segments: ["cpu", "gpu", "memory", "network", "disk"], processCount: 5 });
  assert.deepEqual(next, { myNote: "keep me", segments: ["cpu", "gpu", "memory", "disk", "network"], diskDevice: "nvme0n1" });
  assert.equal("id" in next, false);
  // Setting a value back to its default removes the key entirely.
  assert.deepEqual(Model.settingsPatch({ diskDevice: "nvme0n1" }, { diskDevice: "auto" }), {});
  assert.deepEqual(Model.settingsPatch(null, { diskFallbackWithoutGpu: false }), { diskFallbackWithoutGpu: false });
});

test("manifest schema uses first-party field types and matches defaults", () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "..", "manifest.json"), "utf8"));
  const allowed = ["integer", "enum", "boolean", "string", "path", "multiselect"];
  const schemaKeys = manifest.barWidget.schema.map((f) => f.key);
  assert.deepEqual(schemaKeys.sort(), Object.keys(manifest.barWidget.defaults).sort());
  assert.deepEqual(schemaKeys.slice().sort(), Object.keys(Model.SETTING_DEFAULTS).sort());
  for (const field of manifest.barWidget.schema) {
    assert.ok(allowed.includes(field.type), `${field.key}: type ${field.type}`);
    assert.deepEqual(field.defaultValue, manifest.barWidget.defaults[field.key], `${field.key} default`);
    assert.deepEqual(field.defaultValue, Model.SETTING_DEFAULTS[field.key], `${field.key} model default`);
    if (field.type === "integer") {
      assert.ok(field.min <= field.defaultValue && field.defaultValue <= field.max, `${field.key} range`);
      assert.equal(Model.readSettings({ [field.key]: field.max + 1 })[field.key], field.max);
    }
    if (field.type === "enum") {
      for (const opt of field.options) assert.equal(Model.readSettings({ [field.key]: opt })[field.key], opt);
    }
  }
});

test("toggleSegment adds, removes, and allows an empty list", () => {
  const def = ["cpu", "gpu", "memory", "network"];
  assert.deepEqual(Model.segmentsFromSetting(null), def);
  assert.deepEqual(Model.segmentsFromSetting(["cpu", "foo", "disk", "cpu"]), ["cpu", "disk"]);
  assert.deepEqual(Model.segmentsFromSetting([]), []);
  assert.equal(Model.segmentKeyForTab("mem"), "memory");
  assert.equal(Model.segmentKeyForTab("net"), "network");
  assert.equal(Model.segmentKeyForTab("disk"), "disk");
  assert.equal(Model.segmentKeyForTab("nope"), "");
  assert.deepEqual(Model.toggleSegment(def, "disk", true), ["cpu", "gpu", "memory", "disk", "network"]);
  assert.deepEqual(Model.toggleSegment(def, "cpu", false), ["gpu", "memory", "network"]);
  assert.deepEqual(Model.toggleSegment(["cpu"], "cpu", false), []);
  assert.deepEqual(Model.toggleSegment([], "cpu", true), ["cpu"]);
  assert.deepEqual(Model.toggleSegment(def, "cpu", true), def);
  assert.deepEqual(Model.toggleSegment(def, "nope", true), def);
  assert.deepEqual(Model.toggleSegment(["cpu", "disk"], "memory", true), ["cpu", "memory", "disk"]);
  assert.deepEqual(Model.toggleSegment(["network", "cpu"], "gpu", true), ["cpu", "gpu", "network"]);
});

test("effectiveSegments substitutes disk for gpu only after confirmed no dGPU", () => {
  const def = ["cpu", "gpu", "memory", "network"];
  assert.deepEqual(Model.effectiveSegments(def, false, false, true, true), def);
  assert.deepEqual(Model.effectiveSegments(def, true, true, true, true), def);
  assert.deepEqual(Model.effectiveSegments(def, true, false, true, false), def);
  assert.deepEqual(
    Model.effectiveSegments(def, true, false, true, true),
    ["cpu", "memory", "disk", "network"]
  );
  assert.deepEqual(Model.effectiveSegments(def, true, false, false, true), def);
  assert.deepEqual(
    Model.effectiveSegments(["cpu", "gpu", "memory", "disk", "network"], true, false, true, true),
    ["cpu", "memory", "disk", "network"]
  );
  assert.deepEqual(Model.effectiveSegments(["cpu", "memory", "network"], true, false, true, true), ["cpu", "memory", "network"]);
  assert.deepEqual(Model.effectiveSegments([], true, false, true, true), []);
});

test("visibleBarCells maps enabled segments to painted cells", () => {
  assert.deepEqual(
    Model.visibleBarCells(["cpu", "gpu", "memory", "network"], true, true),
    ["cpu", "gpu", "mem", "net"]
  );
  assert.deepEqual(
    Model.visibleBarCells(["cpu", "gpu", "memory", "network"], false, true),
    ["cpu", "mem", "net"]
  );
  assert.deepEqual(
    Model.visibleBarCells(["cpu", "memory", "disk", "network"], false, false),
    ["cpu", "mem", "net"]
  );
  assert.deepEqual(
    Model.visibleBarCells(["cpu", "memory", "disk", "network"], false, true),
    ["cpu", "mem", "disk", "net"]
  );
  assert.deepEqual(
    Model.visibleBarCells(["cpu", "gpu", "memory", "disk", "network"], true, true),
    ["cpu", "gpu", "mem", "disk", "net"]
  );
  assert.deepEqual(Model.visibleBarCells([], true, true), []);
  assert.deepEqual(Model.visibleBarCells(null, true, true), []);
});
