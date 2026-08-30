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
  diskRead: "#7aa2f7",   // blue
  diskWrite: "#e0af68",  // amber
  swap: "#f7768e"        // red
}

// Sizes are px at the shell's base scale; QML wraps them in Style.space().
// barLabelGap hugs icon to value; barSegmentGap is the gap between cells;
// barOuterPad is the slot inset.
var metrics = {
  barLabelGap: 3,
  barSegmentGap: 6,
  barOuterPad: 6,
  graphHeight: 96,
  ringSize: 92,
  largeRingSize: 108,
  ringThickness: 9,
  largeRingThickness: 10,
  processIcon: 16
}

// Nerd Fonts v3 private-use glyphs for bar metric cells. Literal UTF-8,
// matching the existing ↑ / °C style. Verified against glyphnames.json:
//   cpu     md-chip                 U+F061A  (simple die; not md-cpu_64_bit,
//                                            which paints a tiny "64" at caption size)
//   gpu     md-expansion_card       U+F08AE
//   mem     fa-memory               U+EFC5   (DIMM silhouette; not md-memory,
//                                            which collides with the CPU die)
//   disk    md-harddisk             U+F02CA
//   net     md-lan                  U+F0317  (neutral; not wifi/ethernet)
//   monitor md-monitor-dashboard    U+F0A07  (icon-only bar fallback)
var barGlyphs = {
  cpu: "󰘚",
  gpu: "󰢮",
  mem: "",
  disk: "󰋊",
  net: "󰌗",
  monitor: "󰨇"
}

var barLetters = {
  cpu: "C",
  gpu: "G",
  mem: "M",
  disk: "D",
  net: "N"
}

// Resolve a bar-cell label. Unknown modes fall back to glyphs so a typo
// in barLabels never blanks the cells.
function barLabelFor(mode, metric) {
  var m = String(mode || "").toLowerCase()
  var key = String(metric || "")
  if (m === "letter") return barLetters[key] || ""
  if (m === "none") return ""
  return barGlyphs[key] || ""
}

// "#RRGGBB" + alpha 0..1 -> Qt's "#AARRGGBB". QML uses the alpha-first
// QColor notation, not CSS's alpha-last "#RRGGBBAA". Getting this order
// wrong makes a muted gray track become an opaque yellow/green color.
// Returns null for bad input so the caller can fall back to a theme color.
function alphaHex(hex, alpha) {
  var s = String(hex || "")
  var m = s.match(/^#([0-9A-Fa-f]{6})$/)
  if (!m) return null
  var a = Number(alpha)
  if (!isFinite(a)) return null
  a = a < 0 ? 0 : (a > 1 ? 1 : a)
  var byte = Math.round(a * 255)
  var hexA = (byte < 16 ? "0" : "") + byte.toString(16)
  return "#" + hexA + m[1]
}

// Muted grid/track color derived from the bar foreground.
function gridFor(barForeground) {
  return alphaHex(normalizeHex(barForeground) || barForeground, 0.14) || "#24cacccc"
}

function trackFor(barForeground) {
  return alphaHex(normalizeHex(barForeground) || barForeground, 0.10) || "#1acacccc"
}

// Secondary bar labels (glyphs/letters). Quiet enough to sit behind the
// value, opaque enough to stay readable at caption-adjacent size.
function mutedFor(barForeground) {
  return alphaHex(normalizeHex(barForeground) || "#cacccc", 0.62) || "#9ecacccc"
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

// Theme-native high-load palette. Urgent is the ≥90% text color. Fill
// and track remain for tests and any caller that still wants the old
// meter colors. Malformed input falls back field-by-field to the vivid
// constants so a bad color can never blank the values.
function barPaletteFor(fgHex, accentHex, urgentHex) {
  var fill = normalizeHex(accentHex) || series.gpu
  var fillStack = alphaHex(fill, 0.45) || fill
  var track = alphaHex(normalizeHex(fgHex) || "#cacccc", 0.14) || "#24cacccc"
  var urgent = normalizeHex(urgentHex) || series.cpuSteal
  return { fill: fill, fillStack: fillStack, track: track, urgent: urgent }
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    series: series,
    metrics: metrics,
    barGlyphs: barGlyphs,
    barLetters: barLetters,
    barLabelFor: barLabelFor,
    alphaHex: alphaHex,
    gridFor: gridFor,
    trackFor: trackFor,
    mutedFor: mutedFor,
    normalizeHex: normalizeHex,
    barPaletteFor: barPaletteFor
  }
}
