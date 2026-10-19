// Deterministic synthetic histories for matched layout comparisons. Values
// in the long view represent 10 s means, not individual peak samples.
export function history(longer, pattern) {
  var points = [], span = longer ? 3600 : 60, step = longer ? 10 : 1
  var end = 1700000000
  for (var age = span; age >= 0; age -= step) {
    var phase = (span - age) / span
    if (pattern === "gaps" && phase > 0.35 && phase < 0.65) continue
    var a = 38 + 28 * Math.sin(phase * Math.PI * 5), b = 46 + 20 * Math.cos(phase * Math.PI * 4)
    if (pattern === "low") { a /= 1000; b /= 1000 }
    var missing = pattern === "unknown" || (pattern === "gaps" && phase > 0.78 && phase < 0.86)
    points.push({ t: end - age, b: missing ? null : a, v: pattern === "unknown" ? null : b,
      rx: missing ? null : a * 4096, tx: pattern === "unknown" ? null : b * 4096,
      r: missing ? null : a * 8192, w: pattern === "unknown" ? null : b * 8192 })
  }
  return points
}
