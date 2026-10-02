const test = require("node:test");
const assert = require("node:assert/strict");

const Model = require("../../lib/index.mjs");

test("hue rotation round-trips and keeps lightness", () => {
  assert.equal(Model.hslToHex(0, 1, 0.5), "#ff0000");
  assert.equal(Model.rotateHue("#ff0000", 120), "#00ff00");
  assert.equal(Model.rotateHue("#ff0000", -120), "#0000ff");
  assert.equal(Model.rotateHue("#7aa2f7", 360), "#7aa2f7");
  assert.equal(Model.rotateHue("nope", 90), "nope");
  const hsl = Model.rgbToHsl({ r: 122, g: 162, b: 247 });
  assert.ok(Math.abs(hsl.l - 0.7235) < 0.01);
});

test("seriesPalette follows a coloured accent and tints a grey one", () => {
  const p = Model.seriesPalette("#ff7aa2f7", "#ffa55555", "#ffcacccc", "#ff101315");
  assert.equal(p.primary, "#7aa2f7");                 // Qt alpha prefix stripped
  assert.notEqual(p.secondary, p.primary);
  assert.notEqual(p.tertiary, p.secondary);
  assert.equal(p.hot, "#ffa55555");
  assert.equal(p.track, "#1acacccc");                 // fg at 10 %
  assert.equal(p.grid, "#24cacccc");
  assert.equal(p.dim, Model.mixHex("#cacccc", "#101315", 0.42));
  const grey = Model.seriesPalette("#cacccc", "#a55555", "#cacccc", "#101315");
  assert.equal(grey.primary, "#cacccc");
  assert.equal(grey.secondary, Model.dimColor("#cacccc", "#101315", 0.3));
  // Light theme: dim is darker than the foreground, not lighter.
  const light = Model.seriesPalette("#2a6fdb", "#c0392b", "#202020", "#fafafa");
  const dimL = Model.parseHex(light.dim), fgL = Model.parseHex("#202020");
  assert.ok(dimL.r > fgL.r);
  assert.equal(Model.withAlpha("#ffffff", 0.5), "#80ffffff");
  assert.equal(Model.withAlpha("bad", 0.5), "bad");
});

test("bar labels resolve glyphs, letters and none", () => {
  assert.equal(Model.barLabelFor("glyph", "cpu"), Model.BAR_GLYPHS.cpu);
  assert.equal(Model.barLabelFor("letter", "mem"), "M");
  assert.equal(Model.barLabelFor("none", "net"), "");
  assert.equal(Model.barLabelFor("typo", "disk"), Model.BAR_GLYPHS.disk);
  assert.equal(Model.barLabelFor("letter", "nope"), "");
  assert.equal(Object.keys(Model.VIVID).length, 5);
});

test("bar glyphs are the Nerd Font code points", () => {
  const cp = (s) => s.codePointAt(0);
  assert.equal(cp(Model.BAR_GLYPHS.cpu), 0xF061A);
  assert.equal(cp(Model.BAR_GLYPHS.gpu), 0xF08AE);
  assert.equal(cp(Model.BAR_GLYPHS.mem), 0xEFC5);
  assert.equal(cp(Model.BAR_GLYPHS.disk), 0xF02CA);
  assert.equal(cp(Model.BAR_GLYPHS.net), 0xF0317);
  assert.equal(cp(Model.BAR_GLYPHS.monitor), 0xF0A07);
  for (const k of Object.keys(Model.BAR_GLYPHS)) assert.equal([...Model.BAR_GLYPHS[k]].length, 1, k);
});
