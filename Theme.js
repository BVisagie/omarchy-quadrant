// Quadrant visual constants — declared once, shared by the bar widget, the
// panel chrome, and the graphs so everything follows the same language.
//
// Series colors are fixed hex values chosen to read well on both dark and
// light Omarchy themes. The muted grid/track variant is not a fixed color:
// it is derived from the live barForeground via alphaHex() so graphs always
// sit on the active theme's text color. Pure functions, node-testable.

var series = {
  cpuUser: "#7aa2f7",    // blue
  cpuSystem: "#bb9af7",  // violet
  cpuIowait: "#e0af68",  // amber
  cpuSteal: "#f7768e",   // red
  memApps: "#9ece6a",    // green
  memCache: "#7aa2f7",   // blue
  memKernel: "#bb9af7",  // violet
  gpu: "#7dcfff",        // cyan
  netRx: "#73daca",      // teal
  netTx: "#e0af68",      // amber
  swap: "#f7768e"        // red
}

// Sizes are px at the shell's base scale; QML wraps them in Style.space().
var metrics = {
  barMeterWidth: 18,
  barMeterHeight: 10,
  barSegmentGap: 8,
  barNetWidth: 86,
  graphHeight: 96,
  ringSize: 92,
  ringThickness: 9,
  processIcon: 16
}

// "#RRGGBB" + alpha 0..1 -> "#RRGGBBAA". Returns null for bad input so the
// caller can fall back to a theme color.
function alphaHex(hex, alpha) {
  var s = String(hex || "")
  var m = s.match(/^#([0-9A-Fa-f]{6})$/)
  if (!m) return null
  var a = Number(alpha)
  if (!isFinite(a)) return null
  a = a < 0 ? 0 : (a > 1 ? 1 : a)
  var byte = Math.round(a * 255)
  var hexA = (byte < 16 ? "0" : "") + byte.toString(16)
  return "#" + m[1] + hexA
}

// Muted grid/track color derived from the bar foreground.
function gridFor(barForeground) {
  return alphaHex(barForeground, 0.14)
}

function trackFor(barForeground) {
  return alphaHex(barForeground, 0.10)
}

// Strip Qt's #AARRGGBB (alpha prefix) and accept plain #RRGGBB. Returns
// null for anything else so callers can fall back to a vivid constant.
function normalizeHex(hex) {
  var s = String(hex || "")
  var m8 = s.match(/^#([0-9A-Fa-f]{8})$/)
  if (m8) return "#" + m8[1].slice(2)
  var m6 = s.match(/^#([0-9A-Fa-f]{6})$/)
  if (m6) return "#" + m6[1]
  return null
}

// Theme-native bar meter palette. Accent is the fill; a 0.45-alpha accent
// is the stacked CPU "system" layer; the track is foreground at 0.14 (the
// first-party Util.alpha(fg, 0.18) idiom, slightly quieter for an 18px
// meter). Urgent is the high-load fill. Malformed input falls back
// field-by-field to the vivid constants so a bad color can never blank
// the bars.
function barPaletteFor(fgHex, accentHex, urgentHex) {
  var fill = normalizeHex(accentHex) || series.gpu
  var fillStack = alphaHex(fill, 0.45) || fill
  var track = alphaHex(normalizeHex(fgHex) || "#cacccc", 0.14) || "#cacccc24"
  var urgent = normalizeHex(urgentHex) || series.cpuSteal
  return { fill: fill, fillStack: fillStack, track: track, urgent: urgent }
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    series: series,
    metrics: metrics,
    alphaHex: alphaHex,
    gridFor: gridFor,
    trackFor: trackFor,
    normalizeHex: normalizeHex,
    barPaletteFor: barPaletteFor
  }
}
