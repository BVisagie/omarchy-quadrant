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

test("Theme.alphaHex derives muted variants", () => {
  // QColor/QML uses alpha-first #AARRGGBB, unlike CSS #RRGGBBAA.
  assert.equal(Theme.alphaHex("#cacccc", 0.5), "#80cacccc");
  assert.equal(Theme.alphaHex("#cacccc", 0), "#00cacccc");
  assert.equal(Theme.alphaHex("#cacccc", 1), "#ffcacccc");
  assert.equal(Theme.alphaHex("red", 0.5), null);
  assert.equal(Theme.gridFor("#101315"), "#24101315");   // 0.14 * 255 ≈ 36 = 0x24
  assert.equal(Theme.mutedFor("#cacccc"), "#9ecacccc"); // 0.62 * 255 ≈ 158 = 0x9e
  assert.equal(Theme.mutedFor("#101315"), "#9e101315");
  assert.equal(Theme.mutedFor("#ffcacccc"), "#9ecacccc");
  assert.equal(Theme.mutedFor("red"), "#9ecacccc");
});

test("Theme.barPaletteFor uses accent fill and falls back on bad input", () => {
  const pal = Theme.barPaletteFor("#cacccc", "#7aa2f7", "#f7768e");
  assert.equal(pal.fill, "#7aa2f7");
  assert.equal(pal.fillStack, "#737aa2f7");             // 0.45 * 255 ≈ 115 = 0x73
  assert.equal(pal.track, "#24cacccc");
  assert.equal(pal.urgent, "#f7768e");
  // Qt color strings are often #AARRGGBB
  const fromQt = Theme.barPaletteFor("#ffcacccc", "#ff9ece6a", "#ffa55555");
  assert.equal(fromQt.fill, "#9ece6a");
  assert.equal(fromQt.urgent, "#a55555");
  const bad = Theme.barPaletteFor("red", "nope", "");
  assert.equal(bad.fill, Theme.series.gpu);
  assert.equal(bad.urgent, Theme.series.cpuSteal);
  assert.match(bad.track, /^#[0-9a-fA-F]{8}$/);
});

test("Theme.barLabelFor resolves glyph, letter, and none", () => {
  assert.equal(Theme.barLabelFor("glyph", "cpu"), "\u{F061A}");
  assert.equal(Theme.barLabelFor("glyph", "gpu"), "\u{F08AE}");
  assert.equal(Theme.barLabelFor("glyph", "mem"), "\uEFC5");
  assert.equal(Theme.barLabelFor("glyph", "disk"), "\u{F02CA}");
  assert.equal(Theme.barLabelFor("glyph", "net"), "\u{F0317}");
  assert.equal(Theme.barGlyphs.monitor, "\u{F0A07}");
  assert.equal(Theme.barLabelFor("letter", "cpu"), "C");
  assert.equal(Theme.barLabelFor("letter", "gpu"), "G");
  assert.equal(Theme.barLabelFor("letter", "mem"), "M");
  assert.equal(Theme.barLabelFor("letter", "disk"), "D");
  assert.equal(Theme.barLabelFor("letter", "net"), "N");
  assert.equal(Theme.barLabelFor("none", "cpu"), "");
  assert.equal(Theme.barLabelFor("none", "net"), "");
  assert.equal(Theme.barLabelFor("NONE", "mem"), "");
  // unknown mode falls back to glyphs; unknown metric is empty
  assert.equal(Theme.barLabelFor("typo", "cpu"), Theme.barGlyphs.cpu);
  assert.equal(Theme.barLabelFor("glyph", "nope"), "");
  assert.equal(Theme.barLabelFor(undefined, "cpu"), Theme.barGlyphs.cpu);
  assert.equal(Theme.metrics.barLabelGap, 3);
  assert.equal(Theme.metrics.barSegmentGap, 6);
  assert.equal(Theme.metrics.barOuterPad, 6);
});

test("Theme.normalizeHex accepts 6 and 8 digit forms", () => {
  assert.equal(Theme.normalizeHex("#7aa2f7"), "#7aa2f7");
  assert.equal(Theme.normalizeHex("#ff7aa2f7"), "#7aa2f7");
  assert.equal(Theme.normalizeHex("7aa2f7"), null);
  assert.equal(Theme.normalizeHex(""), null);
});
