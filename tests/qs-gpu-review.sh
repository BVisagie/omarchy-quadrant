#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
if ! command -v quickshell >/dev/null 2>&1; then
  echo "qs-gpu-review: skipped (needs quickshell)"
  exit 0
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/tree" "$work/bin" "$work/sys/class/drm/card0/device/power"
cp -r components scripts lib "$work/tree/"
cp tests/qs/gpu-review.qml "$work/tree/shell.qml"
dev="$work/sys/class/drm/card0/device"
printf '37\n' > "$dev/gpu_busy_percent"
printf 'auto\n' > "$dev/power/control"
printf '5000\n' > "$dev/power/autosuspend_delay_ms"
for helper in system-info disk-info; do
  printf '#!/usr/bin/env bash\nprintf '\''{"ok":true}\\n'\''\n' > "$work/tree/scripts/$helper"
done
mv "$work/tree/scripts/gpu-stats" "$work/tree/scripts/gpu-stats.real"
cat > "$work/tree/scripts/gpu-stats" <<'SH'
#!/usr/bin/env bash
if [[ $1 == list ]]; then printf '{"ok":true,"gpus":[]}\n'; exit; fi
printf '%s %s\n' "$2" "$3" >> "$QUADRANT_TEST_REQUESTS"
if [[ $2 == intel ]]; then
  if [[ ! -e $QUADRANT_INTEL_READY ]]; then exec sleep 5; fi
  printf '{"ok":true,"vendor":"intel","payload":"gt_cur_freq_mhz=400\\ngt_max_freq_mhz=1000"}\n'
else exec "${BASH_SOURCE[0]%/*}/gpu-stats.real" "$@"
fi
SH
cat > "$work/bin/mkdir" <<'SH'
#!/usr/bin/env bash
if [[ ${!#} == "$XDG_RUNTIME_DIR"/quadrant-control.* ]]; then
  printf 'attempt\n' >> "$QUADRANT_SETUP_ATTEMPTS"
  case $QUADRANT_REVIEW_CASE in
    delayed) sleep 2 ;;
    failed) exit 17 ;;
    recovery) [[ $(wc -l < "$QUADRANT_SETUP_ATTEMPTS") == 1 ]] && exit 17 ;;
  esac
fi
exec /usr/bin/mkdir "$@"
SH
chmod +x "$work/tree/scripts/"{system-info,disk-info,gpu-stats} "$work/bin/mkdir"
for scenario in delayed failed recovery nvidia intel-cancel review; do
  mkdir -p "$work/$scenario/runtime" "$work/$scenario/state"
  printf 'active\n' > "$dev/power/runtime_status"
  : > "$work/$scenario/requests"
  if ! QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME="" PATH="$work/bin:$PATH" \
    XDG_STATE_HOME="$work/$scenario/state" XDG_RUNTIME_DIR="$work/$scenario/runtime" \
    QUADRANT_SYS_PATH="$work/sys" QUADRANT_PROC_PATH="$work/proc" QUADRANT_REVIEW_CASE="$scenario" \
    QUADRANT_TEST_REQUESTS="$work/$scenario/requests" QUADRANT_INTEL_READY="$work/$scenario/intel-ready" \
    QUADRANT_SETUP_ATTEMPTS="$work/$scenario/attempts" \
    timeout --kill-after=2s 20 quickshell -p "$work/tree/shell.qml" > "$work/$scenario/log" 2>&1; then
    cat "$work/$scenario/log"
    exit 1
  fi
  if ! rg -q "QGPUREVIEW ok $scenario" "$work/$scenario/log" || rg -i 'error|binding loop' "$work/$scenario/log"; then
    cat "$work/$scenario/log"
    exit 1
  fi
  if [[ $scenario == nvidia && -e $work/$scenario/attempts ]]; then
    echo "NVIDIA-only store created GPU control state"
    exit 1
  fi
  rg 'QGPUREVIEW' "$work/$scenario/log"
done
echo "qs-gpu-review: ok"
