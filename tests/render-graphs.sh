#!/usr/bin/env bash
# Matched synthetic histories in the overlay and alternative layouts.
# Usage: tests/render-graphs.sh [out.png]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
out=${1:-/tmp/quadrant-graphs.png}
shell_dir=${OMARCHY_PATH:-/usr/share/omarchy}/shell
[[ -d $shell_dir/Ui ]] || { echo "render-graphs: needs the Omarchy shell at $shell_dir"; exit 1; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/tree" "$work/runtime" "$work/state"
chmod 700 "$work/runtime"
cp -r components lib "$work/tree/"
cp tests/qs/graph-data.mjs "$work/tree/"
cp tests/qs/graph-render.qml "$work/tree/shell.qml"
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
echo "render-graphs: $out"
