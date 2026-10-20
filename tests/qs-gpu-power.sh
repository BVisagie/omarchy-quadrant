#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
if ! command -v quickshell >/dev/null 2>&1; then
  echo "qs-gpu-power: skipped (needs quickshell)"
  exit 0
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/tree" "$work/runtime" "$work/state"
cp -r components scripts lib "$work/tree/"
cp tests/qs/gpu-power.qml "$work/tree/shell.qml"
for card in card0 card1; do
  dev="$work/sys/class/drm/$card/device"
  mkdir -p "$dev/power"
  printf 'active\n' > "$dev/power/runtime_status"
  printf 'auto\n' > "$dev/power/control"
  printf '5000\n' > "$dev/power/autosuspend_delay_ms"
  printf '37\n' > "$dev/gpu_busy_percent"
done
printf '65\n' > "$work/sys/class/drm/card1/device/gpu_busy_percent"
# Inventory is injected by the harness; no discovery touches host GPU inputs.
for helper in system-info disk-info; do
  printf '#!/usr/bin/env bash\nprintf '\''{"ok":true}\\n'\''\n' > "$work/tree/scripts/$helper"
done
mv "$work/tree/scripts/gpu-stats" "$work/tree/scripts/gpu-stats.real"
cat > "$work/tree/scripts/gpu-stats" <<'SH'
#!/usr/bin/env bash
if [[ $1 == list ]]; then printf '{"ok":true,"gpus":[]}\n'
else exec "${BASH_SOURCE[0]%/*}/gpu-stats.real" "$@"
fi
SH
chmod +x "$work/tree/scripts/"{system-info,disk-info,gpu-stats}
if ! QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME="" XDG_STATE_HOME="$work/state" XDG_RUNTIME_DIR="$work/runtime" \
  QUADRANT_SYS_PATH="$work/sys" QUADRANT_PROC_PATH="$work/proc" \
  timeout --kill-after=2s 20 quickshell -p "$work/tree/shell.qml" > "$work/log" 2>&1; then
  cat "$work/log"
  exit 1
fi
if ! rg -q 'QGPUPOWER ok' "$work/log" || rg -i 'error|referenceerror|typeerror|binding loop' "$work/log"; then
  cat "$work/log"
  exit 1
fi
rg 'QGPUPOWER' "$work/log"
echo "qs-gpu-power: ok"
