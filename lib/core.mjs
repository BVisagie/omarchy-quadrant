// Generic helpers shared by every module: numeric coercion, safe JSON,
// string clipping. No imports.

export function clamp(value, lo, hi) {
  var n = Number(value)
  if (!isFinite(n)) return lo
  return n < lo ? lo : (n > hi ? hi : n)
}

// Coerce to a finite number or return fallback (null when omitted).
// null/undefined/"" mean "no data", never 0.
export function num(value, fallback) {
  if (value === null || value === undefined || value === "") return fallback === undefined ? null : fallback
  var n = Number(value)
  if (isFinite(n)) return n
  return fallback === undefined ? null : fallback
}

export function nonNeg(value) {
  var n = num(value, 0)
  return n < 0 ? 0 : n
}

export function safeJson(line) {
  if (typeof line !== "string" || line.length === 0) return null
  try {
    var data = JSON.parse(line)
    return (data && typeof data === "object") ? data : null
  } catch (e) {
    return null
  }
}

export function safeJsonValue(text) {
  try { return JSON.parse(text) } catch (e) { return undefined }
}

export function clipStr(value, max) {
  if (value === null || value === undefined) return ""
  var s = String(value)
  var out = ""
  for (var i = 0; i < s.length && out.length < max; i++) {
    var code = s.charCodeAt(i)
    if (code < 32 || code === 127) continue
    out += s.charAt(i)
  }
  return out
}

export function collapseSpaces(value) {
  return String(value || "").replace(/\s+/g, " ").replace(/^\s+|\s+$/g, "")
}

//
// Mean buckets `bucketSeconds` wide, kept for `windowSeconds`. Every
// numeric field of `point` is averaged inside its bucket; `t` is the
// bucket start and `n` the sample count. A null field is skipped, so a
// bucket only carries the keys that had data. Gaps are left as missing
// buckets, never interpolated — graphs read the t spacing.
export function hasOwn(o, k) {
  return Object.prototype.hasOwnProperty.call(o, k)
}
