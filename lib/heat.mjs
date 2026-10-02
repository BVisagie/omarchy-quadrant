// Severity colour for a 0–100 value that follows the active theme instead
// of naming any colour: muted → accent over the lower half, accent →
// urgent over the upper half. Two segments, so a theme whose accent sits
// close to its foreground still ramps visibly. `band` adds hysteresis to
// threshold colouring: a value crosses into the hot band at `enter` and
// only leaves it below `exit`, so a reading hovering around the line does
// not flicker.

import { clamp, num } from "./core.mjs"

function hexByte(n) {
  var v = Math.round(clamp(n, 0, 255))
  return (v < 16 ? "0" : "") + v.toString(16)
}

// "#rrggbb" / "#rrggbbaa" / "#aarrggbb" (Qt) → { r, g, b } or null.
export function parseHex(color) {
  var s = String(color || "").trim()
  if (s.charAt(0) !== "#") return null
  var hex = s.slice(1)
  if (hex.length === 8) hex = hex.slice(2)          // Qt writes #aarrggbb
  if (hex.length === 3) hex = hex.charAt(0) + hex.charAt(0) + hex.charAt(1) + hex.charAt(1) + hex.charAt(2) + hex.charAt(2)
  if (hex.length !== 6 || !/^[0-9a-fA-F]+$/.test(hex)) return null
  return { r: parseInt(hex.slice(0, 2), 16), g: parseInt(hex.slice(2, 4), 16), b: parseInt(hex.slice(4, 6), 16) }
}

export function mixHex(a, b, t) {
  var ca = parseHex(a)
  var cb = parseHex(b)
  if (!ca || !cb) return ca ? String(a) : String(b)
  var k = clamp(num(t, 0), 0, 1)
  return "#" + hexByte(ca.r + (cb.r - ca.r) * k) + hexByte(ca.g + (cb.g - ca.g) * k) + hexByte(ca.b + (cb.b - ca.b) * k)
}

// value 0..100 → colour string. Below `floor` the colour is `muted` so a
// quiet machine reads quiet; above it the ramp runs to accent at the
// midpoint and urgent at 100.
export function heatColor(value, muted, accent, urgent, floor) {
  var v = clamp(num(value, 0), 0, 100)
  var lo = clamp(num(floor, 5), 0, 99)
  if (v <= lo) return String(muted)
  var span = 100 - lo
  var frac = (v - lo) / span
  if (frac <= 0.5) return mixHex(muted, accent, frac * 2)
  return mixHex(accent, urgent, (frac - 0.5) * 2)
}

// Hysteresis: returns the new hot state given the previous one.
export function band(wasHot, value, enter, exit) {
  var v = num(value, null)
  if (v === null) return false
  var on = num(enter, 90)
  var off = num(exit, on - 10)
  if (off > on) off = on
  return wasHot ? v > off : v >= on
}
