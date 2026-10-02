#!/usr/bin/env bash
# Render one panel tab offscreen to a PNG, driven by the real store.
# Usage: tests/render.sh <cpu|gpu|mem|disk|net> [out.png]
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
mkdir -p "$work/tree" "$work/state"
cp -r components tabs lib scripts "$work/tree/"
ln -s "$shell_dir/Commons" "$work/tree/Commons"
ln -s "$shell_dir/Ui" "$work/tree/Ui"
cp tests/qs/render-tab.qml "$work/tree/shell.qml"
QT_QPA_PLATFORM=offscreen QUADRANT_RENDER_OUT="$out" QUADRANT_RENDER_TAB="$tab" XDG_STATE_HOME="$work/state" \
  timeout 30 quickshell -p "$work/tree/shell.qml" 2>&1 | grep -E "rror|RENDER" | grep -vE "qt\.qpa|qmlscanner" || true
[[ -f $out ]] && echo "render: $out"
