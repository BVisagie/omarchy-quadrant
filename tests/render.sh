#!/usr/bin/env bash
# Render one panel tab offscreen with live readings or documentation fixtures.
# Usage: tests/render.sh <cpu|gpu|mem|disk|net|hardware|settings|bar> [out.png]
# Needs quickshell and an installed Omarchy shell (for qs.Commons / qs.Ui);
# runs under QT_QPA_PLATFORM=offscreen so it works on a locked session.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
tab=${1:-cpu}
out=${2:-/tmp/quadrant-$tab.png}
shell_dir=${OMARCHY_PATH:-/usr/share/omarchy}/shell
[[ -d $shell_dir/Ui ]] || { echo "render: needs the Omarchy shell at $shell_dir"; exit 1; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/tree" "$work/state" "$work/runtime"
chmod 700 "$work/runtime"
# GTK's platform theme needs the session socket for the same icon lookup as
# the live shell. Share only that socket; sampler state stays in our runtime.
theme=""
display=""
socket=${WAYLAND_DISPLAY:-}
if [[ -n $socket ]]; then
  [[ $socket == /* ]] || socket=${XDG_RUNTIME_DIR:-}/$socket
  if [[ -S $socket ]]; then
    ln -s "$socket" "$work/runtime/wayland-render"
    display=wayland-render
    theme=${QT_QPA_PLATFORMTHEME:-}
  fi
fi
cp -r components tabs lib scripts BarWidget.qml Panel.qml "$work/tree/"
ln -s "$shell_dir/Commons" "$work/tree/Commons"
ln -s "$shell_dir/Ui" "$work/tree/Ui"
cp tests/qs/graph-data.mjs "$work/tree/"
cp tests/qs/ActionFixture.qml "$work/tree/"
cp tests/qs/HardwareFixture.qml "$work/tree/"
cp tests/qs/DocumentationFixture.qml "$work/tree/"
cp tests/qs/render-tab.qml "$work/tree/shell.qml"
if ! QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME="$theme" WAYLAND_DISPLAY="$display" QUADRANT_RENDER_OUT="$work/render.png" QUADRANT_RENDER_TAB="$tab" XDG_STATE_HOME="$work/state" XDG_RUNTIME_DIR="$work/runtime" \
  timeout 30 quickshell -p "$work/tree/shell.qml" >"$work/render.log" 2>&1; then
  cat "$work/render.log" >&2
  exit 1
fi
grep -E "rror|RENDER|BAR |TOOLTIP|loop" "$work/render.log" | grep -vE "qt\.qpa|qmlscanner" || true
[[ -s $work/render.png ]] || { cat "$work/render.log" >&2; exit 1; }
if grep -E 'TypeError|ReferenceError|Binding loop|Failed to load|Unable to assign' "$work/render.log"; then exit 1; fi
cp "$work/render.png" "$out"
echo "render: $out"
