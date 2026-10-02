// Colours derived from the active theme, never named. Graph series are
// the accent plus two hue-rotated companions (or, for a grey accent, two
// foreground tints), hot is the theme's urgent colour, and every muted
// tone is a foreground/background mix so it reads on light and dark
// themes alike. Qt colour strings arrive as #aarrggbb; everything here
// returns #rrggbb or #aarrggbb that QML accepts.

import { clamp, num } from "./core.mjs"
import { parseHex, mixHex } from "./heat.mjs"

function hexByte(n) {
  var v = Math.round(clamp(n, 0, 255))
  return (v < 16 ? "0" : "") + v.toString(16)
}

export function rgbToHsl(c) {
  var r = c.r / 255, g = c.g / 255, b = c.b / 255
  var max = Math.max(r, g, b), min = Math.min(r, g, b)
  var l = (max + min) / 2
  var h = 0, s = 0
  if (max !== min) {
    var d = max - min
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
    if (max === r) h = (g - b) / d + (g < b ? 6 : 0)
    else if (max === g) h = (b - r) / d + 2
    else h = (r - g) / d + 4
    h /= 6
  }
  return { h: h, s: s, l: l }
}

export function hslToHex(h, s, l) {
  var hh = ((h % 1) + 1) % 1
  var ss = clamp(s, 0, 1), ll = clamp(l, 0, 1)
  function f(p, q, t) {
    if (t < 0) t += 1
    if (t > 1) t -= 1
    if (t < 1 / 6) return p + (q - p) * 6 * t
    if (t < 1 / 2) return q
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6
    return p
  }
  var r, g, b
  if (ss === 0) { r = g = b = ll }
  else {
    var q = ll < 0.5 ? ll * (1 + ss) : ll + ss - ll * ss
    var p = 2 * ll - q
    r = f(p, q, hh + 1 / 3); g = f(p, q, hh); b = f(p, q, hh - 1 / 3)
  }
  return "#" + hexByte(r * 255) + hexByte(g * 255) + hexByte(b * 255)
}

export function rotateHue(hex, degrees) {
  var c = parseHex(hex)
  if (!c) return String(hex)
  var hsl = rgbToHsl(c)
  return hslToHex(hsl.h + num(degrees, 0) / 360, hsl.s, hsl.l)
}

// "#rrggbb" + alpha → Qt "#aarrggbb".
export function withAlpha(hex, alpha) {
  var c = parseHex(hex)
  if (!c) return String(hex)
  return "#" + hexByte(clamp(num(alpha, 1), 0, 1) * 255) + hexByte(c.r) + hexByte(c.g) + hexByte(c.b)
}

// Muted text: most of the foreground, some background. 0.42 keeps a
// caption readable on both a light and a dark theme.
export function dimColor(fg, bg, amount) {
  return mixHex(fg, bg, amount === undefined ? 0.42 : amount)
}

export function seriesPalette(accent, urgent, fg, bg) {
  var a = parseHex(accent)
  var hsl = a ? rgbToHsl(a) : { h: 0, s: 0, l: 0.5 }
  var grey = !a || hsl.s < 0.15
  var primary = a ? String(accent).length === 9 ? "#" + String(accent).slice(3) : String(accent) : "#7aa2f7"
  var secondary = grey ? dimColor(fg, bg, 0.3) : rotateHue(primary, 50)
  var tertiary = grey ? dimColor(fg, bg, 0.55) : rotateHue(primary, -50)
  var fgHex = parseHex(fg) ? hslToHex(rgbToHsl(parseHex(fg)).h, rgbToHsl(parseHex(fg)).s, rgbToHsl(parseHex(fg)).l) : "#cacccc"
  return {
    primary: primary,
    secondary: secondary,
    tertiary: tertiary,
    hot: parseHex(urgent) ? String(urgent) : "#f7768e",
    dim: dimColor(fg, bg, 0.42),
    faint: dimColor(fg, bg, 0.65),
    track: withAlpha(fgHex, 0.10),
    grid: withAlpha(fgHex, 0.14),
    hairline: withAlpha(fgHex, 0.22)
  }
}

// Fixed per-resource hues for `barPalette: vivid` (the original Tokyo
// Night set). Bar values only; panels always follow the theme.
export var VIVID = { cpu: "#7aa2f7", gpu: "#7dcfff", mem: "#9ece6a", disk: "#e0af68", net: "#73daca" }

// Nerd Fonts v3 private-use glyphs for bar metric cells, as code-point
// escapes so an editor or a copy can never drop them:
//   cpu md-chip · gpu md-expansion_card · mem fa-memory · disk md-harddisk
//   · net md-lan · monitor md-monitor-dashboard (icon-only bar fallback)
export var BAR_GLYPHS = {
  cpu: "\u{F061A}",
  gpu: "\u{F08AE}",
  mem: "\u{EFC5}",
  disk: "\u{F02CA}",
  net: "\u{F0317}",
  monitor: "\u{F0A07}"
}
export var BAR_LETTERS = { cpu: "C", gpu: "G", mem: "M", disk: "D", net: "N" }

// Resolve a bar-cell label. Unknown modes fall back to glyphs so a typo
// in barLabels never blanks the cells.
export function barLabelFor(mode, metric) {
  var m = String(mode || "").toLowerCase()
  var key = String(metric || "")
  if (m === "letter") return BAR_LETTERS[key] || ""
  if (m === "none") return ""
  return BAR_GLYPHS[key] || ""
}
