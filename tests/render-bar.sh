#!/usr/bin/env bash
# Render the real widget with a shared synthetic service and panel stand-in.
# Usage: tests/render-bar.sh [out.png]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
out=${1:-/tmp/quadrant-bar.png}
shell_dir=${OMARCHY_PATH:-/usr/share/omarchy}/shell
[[ -d $shell_dir/Ui ]] || { echo "render-bar: needs the Omarchy shell at $shell_dir"; exit 1; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/tree" "$work/runtime" "$work/state"
chmod 700 "$work/runtime"
cp -r components lib scripts "$work/tree/"
cp BarWidget.qml tests/qs/BarFixture.qml tests/qs/BarHost.qml "$work/tree/"
if [[ -n ${QUADRANT_RENDER_BAR_REF:-} ]]; then
  git show "${QUADRANT_RENDER_BAR_REF}:BarWidget.qml" >"$work/tree/BarWidget.qml"
fi
cp tests/qs/bar-panel.qml "$work/tree/Panel.qml"
cp tests/qs/bar-render.qml "$work/tree/shell.qml"
ln -s "$shell_dir/Commons" "$work/tree/Commons"
ln -s "$shell_dir/Ui" "$work/tree/Ui"
if ! QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QUADRANT_RENDER_OUT="$work/render.png" \
  XDG_RUNTIME_DIR="$work/runtime" XDG_STATE_HOME="$work/state" \
  timeout 30 quickshell -p "$work/tree/shell.qml" >"$work/render.log" 2>&1; then
  cat "$work/render.log" >&2
  exit 1
fi
cat "$work/render.log"
[[ -s $work/render.png ]] || exit 1
if grep -E 'TypeError|ReferenceError|Binding loop|Failed to load|Unable to assign' "$work/render.log"; then exit 1; fi
cp "$work/render.png" "$out"
echo "render-bar: $out"
