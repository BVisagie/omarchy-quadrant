#!/usr/bin/env bash
# Run the real Store/watchdog with a sampler that deliberately stops responding.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if ! command -v quickshell >/dev/null 2>&1; then
  echo "qs-stream-recovery: skipped (needs quickshell)"
  exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/tree" "$work/state" "$work/runtime"
cp -r components scripts lib "$work/tree/"
cp tests/qs/stream-recovery.qml "$work/tree/shell.qml"
mv "$work/tree/scripts/quadrant-stream" "$work/tree/scripts/quadrant-stream.real"
cat > "$work/tree/scripts/quadrant-stream" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
count=0
if [[ -f $QUADRANT_TEST_LAUNCHES ]]; then
  read -r count < "$QUADRANT_TEST_LAUNCHES"
fi
count=$((count + 1))
printf '%s\n' "$count" > "$QUADRANT_TEST_LAUNCHES"
script_dir=${BASH_SOURCE[0]%/*}
if (( count == 1 || count == 3 )); then
  QUADRANT_STREAM_TICKS=3 "$script_dir/quadrant-stream.real" "$@"
  # SIGTERM cannot be handled until continued; the watchdog must escalate.
  kill -STOP "$$"
fi
exec "$script_dir/quadrant-stream.real" "$@"
SH
chmod +x "$work/tree/scripts/quadrant-stream"

if ! QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= XDG_STATE_HOME="$work/state" XDG_RUNTIME_DIR="$work/runtime" \
  QUADRANT_TEST_LAUNCHES="$work/launches" \
  timeout --kill-after=2s 35 quickshell -p "$work/tree/shell.qml" > "$work/log" 2>&1; then
  cat "$work/log"
  exit 1
fi
rg 'QRECOVERY' "$work/log" || true
if ! rg -q 'QRECOVERY ok$' "$work/log" || [[ $(cat "$work/launches") != 4 ]]; then
  cat "$work/log"
  exit 1
fi
if rg -i 'error|referenceerror|typeerror' "$work/log"; then
  exit 1
fi
echo "qs-stream-recovery: ok (startup stall, forced kill, settings restart, second stall)"
