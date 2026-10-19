// Action rows carry exactly the value that the user sees. Order and keys
// preserve keyboard selection when inventory refreshes without changing it.
export function addressActions(iface) {
  if (!iface) return []
  var out = [], seen = {}
  if (typeof iface.mac === "string" && iface.mac !== "")
    out.push({ key: "mac:" + iface.mac, kind: "copy", label: "MAC", value: iface.mac })
  var addrs = Array.isArray(iface.addrs) ? iface.addrs : []
  for (var i = 0; i < addrs.length; i++) {
    var value = typeof addrs[i] === "string" ? addrs[i].replace(/\/\d+$/, "") : ""
    if (!value || seen[value]) continue
    seen[value] = true
    out.push({ key: "ip:" + value, kind: "copy", label: value.indexOf(":") >= 0 ? "IPv6" : "IPv4", value: value })
  }
  return out
}

export function mountActions(mounts) {
  if (!Array.isArray(mounts)) return []
  return mounts.filter(function (mount) { return mount && typeof mount.target === "string" && mount.target !== "" })
    .map(function (mount) {
      return { key: "mount:" + mount.target, kind: "open-mount", label: "Mounted volume", value: mount.target,
        used: mount.used, size: mount.size, pct: mount.pct, available: mount.targetComplete !== false }
    })
}
