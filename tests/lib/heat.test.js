const test = require("node:test");
const assert = require("node:assert/strict");

const Model = require("../../lib/index.mjs");

test("heatColor ramps muted → accent → urgent and parses Qt colour forms", () => {
  const muted = "#404040", accent = "#00ff00", urgent = "#ff0000";
  assert.equal(Model.heatColor(0, muted, accent, urgent), muted);
  assert.equal(Model.heatColor(5, muted, accent, urgent), muted);       // at the floor: still quiet
  assert.equal(Model.heatColor(52.5, muted, accent, urgent), accent);   // midpoint of the ramp
  assert.equal(Model.heatColor(100, muted, accent, urgent), urgent);
  assert.equal(Model.heatColor(250, muted, accent, urgent), urgent);
  const quarter = Model.heatColor(28.75, muted, accent, urgent);        // halfway muted→accent
  assert.equal(quarter, "#20a020");
  assert.deepEqual(Model.parseHex("#ff00ff80"), { r: 0, g: 255, b: 128 }); // Qt #aarrggbb
  assert.deepEqual(Model.parseHex("#abc"), { r: 170, g: 187, b: 204 });
  assert.equal(Model.parseHex("red"), null);
  assert.equal(Model.mixHex("nope", "#000000", 0.5), "#000000");
  assert.equal(Model.mixHex("#000000", "nope", 0.5), "#000000");
});

test("band applies hysteresis around the threshold", () => {
  assert.equal(Model.band(false, 89.9, 90, 80), false);
  assert.equal(Model.band(false, 90, 90, 80), true);
  assert.equal(Model.band(true, 85, 90, 80), true);    // still hot above exit
  assert.equal(Model.band(true, 80, 90, 80), false);   // leaves at or below exit
  assert.equal(Model.band(true, null, 90, 80), false);
  assert.equal(Model.band(false, 95, 90, 99), true);   // exit above enter is clamped
});
