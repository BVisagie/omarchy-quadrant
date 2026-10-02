#!/usr/bin/env bash
# Headless Store smoke test under a throwaway quickshell instance.
# Skips when quickshell or a display is unavailable (CI).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if ! command -v quickshell >/dev/null 2>&1 || [[ -z ${WAYLAND_DISPLAY:-}${DISPLAY:-} ]]; then
  echo "qs-smoke: skipped (needs quickshell and a display)"
  exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
state=$work/state
mkdir -p "$state" "$work/tree"
export XDG_STATE_HOME=$state
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-$state}

# Quickshell resolves relative imports inside its config folder only, so
# the harness runs from a copy of the plugin tree with the smoke test as
# its shell.qml.
cp -r components scripts Model.js Theme.js "$work/tree/"
cp tests/qs/store-smoke.qml "$work/tree/shell.qml"

run_once() {
  timeout 20 quickshell -p "$work/tree/shell.qml" 2>&1 | grep -E "QSMOKE|rror|arning" | grep -vE "qmlscanner|qt\.qpa" | sed -E 's/^.*QSMOKE /QSMOKE /' || true
}

echo "== first run"
out1=$(run_once)
printf '%s\n' "$out1"
find "$state/dev.bvisagie.quadrant" -maxdepth 1 -type f -printf "%f %s bytes\n" 2>/dev/null || true
# Start the second run in a later 10 s bucket so every bucket the first run
# saved is older than the second run's first live bucket.
sleep 11
echo "== second run (history reload)"
out2=$(run_once)
printf '%s\n' "$out2"

python3 - "$out1" "$out2" "$state/dev.bvisagie.quadrant/history.json" <<'PY'
import json, sys
def phases(text):
    out = {}
    for line in text.splitlines():
        if line.startswith("QSMOKE "):
            d = json.loads(line[7:]); out[d["phase"]] = d["data"]
    return out
a, b = phases(sys.argv[1]), phases(sys.argv[2])
for text in (sys.argv[1], sys.argv[2]):
    bad = [l for l in text.splitlines() if not l.startswith("QSMOKE") and ("rror" in l) and "QSMOKE" not in l]
    assert not bad, "qml errors: %s" % bad
s = a["stream"]
assert s["live"] and s["hasCpu"] and s["cores"] > 0 and s["memUsed"] is not None, s
assert s["gpuReady"], s
assert s["cpuHistory"] >= 2 and s["cpuLong"] >= 1 and s["memLong"] >= 1, s
assert "cpu" in s["cells"] and "mem" in s["cells"], s
assert a["settings-legacy"] == {"processCount": 8, "diskDevice": "nvme0n1"}, a["settings-legacy"]
sp = a["settings-persist"]
assert sp["segments"] == ["cpu", "gpu", "memory"], sp
assert sp["pending"] is None, sp   # fake shell echoed the entry back → pending cleared
w = sp["writes"][0]
assert w["id"] == "dev.bvisagie.quadrant"
assert w["settings"] == {"segments": ["cpu", "gpu", "memory"], "processCount": 8, "diskDevice": "nvme0n1"}, w
v = a["viewers"]
assert v == {"gpuSeg": 2, "gpuTab": 1, "cpuTab": 1, "open": 2, "discretePoll": v["discretePoll"], "procWanted": True, "netWanted": True}, v
p = a["procs"]
assert p["error"] == "" and p["stats"]["procs"] > 0 and p["stats"]["threads"] > 0, p
assert p["cpuRows"] > 0 and p["memRows"] > 0 and p["memKind"] in ("pss", "rss"), p
assert p["netError"] == "" and p["netRows"] >= 1, p
assert a["viewers-after"] == {"gpuSeg": 1, "gpuTab": 0, "open": 1}, a["viewers-after"]
hist = json.load(open(sys.argv[3]))
assert hist["v"] == 1 and len(hist["cpu"]) >= 1 and len(hist["mem"]) >= 1, hist.keys()
assert hist["tags"]["iface"] == s["iface"], hist["tags"]
# Second run starts with the first run's buckets glued in front of its own.
s2 = b["stream"]
assert s2["cpuLong"] > s["cpuLong"], (s["cpuLong"], s2["cpuLong"])
assert s2["memLong"] > s["memLong"], (s["memLong"], s2["memLong"])
print("qs-smoke: ok (history buckets run1=%d run2=%d)" % (s["cpuLong"], s2["cpuLong"]))
PY
