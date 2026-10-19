#!/usr/bin/env bash
# Render one panel tab offscreen to a PNG, driven by the real store.
# Usage: tests/render.sh <cpu|gpu|mem|disk|net|settings|bar> [out.png]
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
cp -r components tabs lib scripts BarWidget.qml Panel.qml "$work/tree/"
ln -s "$shell_dir/Commons" "$work/tree/Commons"
ln -s "$shell_dir/Ui" "$work/tree/Ui"
cp tests/qs/render-tab.qml "$work/tree/shell.qml"
if ! QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME="" QUADRANT_RENDER_OUT="$work/render.png" QUADRANT_RENDER_TAB="$tab" XDG_STATE_HOME="$work/state" XDG_RUNTIME_DIR="$work/runtime" \
  timeout 30 quickshell -p "$work/tree/shell.qml" >"$work/render.log" 2>&1; then
  cat "$work/render.log" >&2
  exit 1
fi
grep -E "rror|RENDER|BAR |TOOLTIP|loop" "$work/render.log" | grep -vE "qt\.qpa|qmlscanner" || true
[[ -s $work/render.png ]] || { cat "$work/render.log" >&2; exit 1; }
cp "$work/render.png" "$out"
echo "render: $out"
