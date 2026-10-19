#!/usr/bin/env bash
# Real panel controls and keyboard dispatch under Qt Quick Test, offscreen.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
shell_dir=${OMARCHY_PATH:-/usr/share/omarchy}/shell
if ! command -v quickshell >/dev/null || [[ ! -d $shell_dir/Ui || ! -d /usr/lib/qt6/qml/QtTest ]]; then
  echo "qs-panel-ui: skipped (needs quickshell, Qt Quick Test and the Omarchy shell)"
  exit 0
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/tree" "$work/runtime" "$work/state"
chmod 700 "$work/runtime"
cp -r components tabs lib scripts "$work/tree/"
cp tests/qs/panel-ui.qml "$work/tree/shell.qml"
ln -s "$shell_dir/Commons" "$work/tree/Commons"
ln -s "$shell_dir/Ui" "$work/tree/Ui"
for mode in patched unpatched; do
  if [[ $mode == unpatched ]]; then sed -i '1{/OmarchyLoadPatch/d;}' "$work/tree/shell.qml"; fi
  if ! QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' XDG_RUNTIME_DIR="$work/runtime" XDG_STATE_HOME="$work/state" \
    timeout 30 quickshell -p "$work/tree/shell.qml" >"$work/test.log" 2>&1; then
    cat "$work/test.log"
    exit 1
  fi
  cat "$work/test.log"
  python3 - "$work/test.log" <<'PYTEST'
import json, pathlib, sys
lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
results = [json.loads(line.split("QPANELUI ", 1)[1]) for line in lines if "QPANELUI {" in line]
assert len(results) == 1 and results[0]["passed"] >= 58 and results[0]["failed"] == 0, results
assert not any(word in line for line in lines for word in ("TypeError", "ReferenceError", "Binding loop", "Failed to load", "Unable to assign"))
print("qs-panel-ui: ok")
PYTEST
  echo "qs-panel-ui: $mode checked"
done
