"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const Model = require("../../lib/index.mjs");
const Released = require("../fixtures/settings-v1.mjs");
const canonical = ["cpu", "gpu", "memory", "disk", "network"];

test("bar order normalizes typed, legacy and partial lists without losing hidden positions", () => {
  for (const input of [["network", "gpu", "network", "unknown"], '["network","gpu","network","unknown"]', '"network, gpu, network, unknown"'])
    assert.deepEqual(Model.barOrderFromSetting(input), ["network", "gpu", "cpu", "memory", "disk"]);
  for (const invalid of [null, undefined, 12, true, {}, { 0: "network", length: 1 }, "[oops", [], ["unknown"]])
    assert.deepEqual(Model.barOrderFromSetting(invalid), canonical);
  const order = ["network", "disk", "memory", "gpu", "cpu"];
  const moved = Model.moveBarSegment(order, "gpu", -1);
  assert.deepEqual(moved, ["network", "disk", "gpu", "memory", "cpu"]);
  assert.deepEqual(order, ["network", "disk", "memory", "gpu", "cpu"], "movement is pure");
  assert.deepEqual(Model.moveBarSegment(order, "network", -1), order);
  assert.deepEqual(Model.moveBarSegment(order, "cpu", 1), order);
  assert.deepEqual(Model.moveBarSegment(order, "unknown", 1), order);
  assert.deepEqual(Model.moveBarSegment(order, "cpu", 2), order);
});

test("style, width and order survive save, toggles, reload, downgrade and reset", () => {
  assert.equal(Model.readSettings({}).barStyle, "text");
  assert.equal(Model.readSettings({}).barGraphWidth, 32);
  assert.deepEqual(Model.readSettings({}).barOrder, canonical);
  const order = ["network", "disk", "cpu", "memory", "gpu"];
  let raw = Model.settingsPatch({ userNote: "keep" }, { barStyle: '"GRAPH-TEXT"', barGraphWidth: "999", barOrder: order });
  assert.equal(raw.barStyle, "graph-text"); assert.equal(raw.barGraphWidth, 64);
  raw = Model.settingsPatch(raw, { segments: Model.toggleSegment(Model.readSettings(raw).segments, "gpu", false) });
  raw = Model.settingsPatch(raw, { segments: Model.toggleSegment(Model.readSettings(raw).segments, "gpu", true) });
  const oldWrite = Released.settingsPatch(JSON.parse(JSON.stringify(raw)), { processCount: 7 });
  const cfg = Model.readSettings(oldWrite);
  assert.deepEqual(cfg.barOrder, order); assert.equal(cfg.barStyle, "graph-text"); assert.equal(cfg.barGraphWidth, 64);
  assert.equal(cfg.processCount, 7);
  assert.deepEqual(Model.settingsPatch(raw, { barOrder: canonical, barStyle: "text", barGraphWidth: 32 }), { userNote: "keep" });
  assert.equal(Model.readSettings({ barStyle: "ring" }).barStyle, "text");
  assert.equal(Model.readSettings({ barGraphWidth: -1 }).barGraphWidth, 16);
});

function permutations(values) {
  return values.length ? values.flatMap((value, i) => permutations(values.filter((_, j) => j !== i)).map(tail => [value, ...tail])) : [[]];
}
test("every saved order keeps Drives' position through GPU fallback without duplicates or mutation", () => {
  for (const order of permutations(canonical)) {
    for (const explicitDisk of [false, true]) {
      const configured = explicitDisk ? canonical : canonical.filter(key => key !== "disk");
      const absent = Model.effectiveSegments(configured, true, false, true, true, order);
      assert.deepEqual(absent, order.filter(key => key !== "gpu"));
      assert.equal(absent.filter(key => key === "disk").length, 1);
      assert.deepEqual(Model.visibleBarCells(absent, false, false), absent.filter(key => key !== "disk").map(key => key === "memory" ? "mem" : key === "network" ? "net" : key));
      const recovered = Model.effectiveSegments(configured, true, true, true, true, order);
      assert.deepEqual(recovered, order.filter(key => explicitDisk || key !== "disk"));
      for (const state of [[false, false, true, true], [true, false, true, false], [true, false, false, true]])
        assert.deepEqual(Model.effectiveSegments(configured, ...state, order), order.filter(key => configured.includes(key)));
      assert.deepEqual(configured, explicitDisk ? canonical : canonical.filter(key => key !== "disk"));
    }
  }
});

test("effective Drives switches handle fallback and explicit membership even with GPU disabled", () => {
  let cfg = Model.readSettings({ barOrder: ["network", "disk", "cpu"], diskFallbackWithoutGpu: false });
  let patch = Model.barSegmentPatch(cfg, "disk", true, true);
  assert.deepEqual(patch, { diskFallbackWithoutGpu: true });
  cfg = Model.readSettings({ ...cfg, ...patch });
  patch = Model.barSegmentPatch(cfg, "disk", false, true);
  assert.equal(patch.diskFallbackWithoutGpu, false); assert.ok(!patch.segments.includes("disk"));
  cfg = Model.readSettings({ ...cfg, segments: ["cpu"], diskFallbackWithoutGpu: false });
  patch = Model.barSegmentPatch(cfg, "disk", true, true);
  assert.deepEqual(patch.segments, ["cpu", "disk"]);
  const enabled = Model.readSettings({ ...cfg, ...patch });
  assert.ok(Model.effectiveSegments(enabled.segments, true, false, enabled.diskFallbackWithoutGpu, true, enabled.barOrder).includes("disk"));
  assert.deepEqual(enabled.barOrder, cfg.barOrder);
  assert.deepEqual(Model.barSegmentPatch(cfg, "unknown", true, true), {});
});

test("bar trend values match each text measurement, preserving zeros, missing fields and collection gaps", () => {
  const cpu = [{ t: 1, u: 20, s: 10, io: 5, st: 5 }, { t: 2, u: 0, s: 0, io: 0, st: 0 },
    { t: 3, u: 20, s: null, io: 0, st: 0 }, { t: 60, u: 30, s: 10, io: 1, st: 0 }];
  assert.deepEqual(Model.barTrendPoints(cpu, "cpu").map(point => point.v), [40, 0, null, 41]);
  const points = [{ t: 1, u: 0, b: 0, rx: 0, tx: 0 }, { t: 2, u: 65, b: 80, rx: 3000, tx: 1000 }, { t: 60, u: null, b: -1, rx: null, tx: 0 }];
  for (const [metric, values] of [["mem", [0, 65, null]], ["gpu", [0, 80, null]], ["disk", [0, 80, null]]])
    assert.deepEqual(Model.barTrendPoints(points, metric).map(point => point.v), values);
  const projected = Model.barTrendPoints(cpu, "cpu");
  assert.deepEqual(Model.graphRuns(projected, ["v"], 8), [{ start: 0, end: 1 }, { start: 3, end: 3 }]);
  assert.deepEqual(Model.barTrendPoints([...points, { t: 70, rx: 4, tx: 5 }], "net"), [points[2], { t: 70, rx: 4, tx: 5 }]);
  assert.deepEqual(Model.barTrendPoints(points, "unknown"), []);
  assert.equal(cpu[0].v, undefined);
});

test("compact rates stay bounded at rounding boundaries and extreme finite inputs", () => {
  for (let exponent = 0; exponent <= 6; exponent++) {
    for (const value of [0, 9.99, 10, 99.9, 999, 999.49, 999.5, 1000, 1023, 1023.99, 1024])
      assert.ok(Model.formatRateCompact(value * 1024 ** exponent).length <= 4, `${value} × 1024^${exponent}`);
  }
  assert.equal(Model.formatRateCompact(999.5 * 1024), "1.0M");
  assert.equal(Model.formatRateCompact(1023 * 1024 ** 4), "1.0P");
  assert.equal(Model.formatRateCompact(Number.MAX_VALUE), ">99E");
  assert.equal(Model.formatRateCompact(Infinity), "--");
});
