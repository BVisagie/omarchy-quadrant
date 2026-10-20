#!/usr/bin/env bash
# Process identities and live icon refresh using a private icon installation.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
shell_dir=${OMARCHY_PATH:-/usr/share/omarchy}/shell
if ! command -v quickshell >/dev/null || [[ ! -d $shell_dir/Ui || ! -d /usr/lib/qt6/qml/QtTest ]]; then
  echo "qs-process-icons: skipped (needs quickshell, Qt Quick Test and the Omarchy shell)"
  exit 0
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/tree" "$work/runtime" "$work/data/icons/hicolor/scalable/apps"
chmod 700 "$work/runtime"
cp -r components lib scripts "$work/tree/"
cp tests/qs/process-icons.qml "$work/tree/shell.qml"
ln -s "$shell_dir/Commons" "$work/tree/Commons"
ln -s "$shell_dir/Ui" "$work/tree/Ui"
mv "$work/tree/scripts/process-icons.py" "$work/tree/scripts/process-icons-real.py"
cat > "$work/tree/scripts/process-icons.py" <<'PY'
import os
import runpy
from pathlib import Path
with open(os.environ['QUADRANT_ICON_REQUESTS'], 'a') as log:
    log.write('scan\n')
runpy.run_path(str(Path(__file__).with_name('process-icons-real.py')), run_name='__main__')
PY
printf '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><rect width="24" height="24" fill="#66aaff"/></svg>\n' > "$work/icon.svg"
cp "$work/icon.svg" "$work/data/icons/hicolor/scalable/apps/quadrant-test-brave.svg"
for mode in patched unpatched; do
  # Each mode gets a fresh absent name, ensuring Qt sees a miss before install.
  late="$work/data/icons/hicolor/scalable/apps/quadrant-test-t3.svg"
  absolute="$work/absolute-icon.svg"
  python3 - "$late" "$absolute" <<'PY'
from pathlib import Path
import sys
for value in sys.argv[1:]:
    Path(value).unlink(missing_ok=True)
PY
  : > "$work/requests"
  if [[ $mode == unpatched ]]; then sed -i '1{/OmarchyLoadPatch/d;}' "$work/tree/shell.qml"; fi
  if ! QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' XDG_RUNTIME_DIR="$work/runtime" \
    XDG_DATA_HOME="$work/data" XDG_DATA_DIRS="$work/data" \
    QUADRANT_ICON_REQUESTS="$work/requests" QUADRANT_ICON_TEMPLATE="$work/icon.svg" QUADRANT_LATE_ICON="$late" \
    QUADRANT_ABSOLUTE_ICON="$absolute" \
    timeout --kill-after=2s 20 quickshell -p "$work/tree/shell.qml" > "$work/log" 2>&1; then
    cat "$work/log"
    exit 1
  fi
  cat "$work/log"
  python3 - "$work/log" <<'PY'
import json
from pathlib import Path
import sys
lines = Path(sys.argv[1]).read_text().splitlines()
results = [json.loads(line.split('QPROCESSICONS ', 1)[1]) for line in lines if 'QPROCESSICONS {' in line]
assert len(results) == 1 and results[0]['passed'] >= 2 and results[0]['failed'] == 0, results
assert not any(word in line for line in lines for word in ('TypeError', 'ReferenceError', 'Binding loop', 'Failed to load', 'Unable to assign'))
print('qs-process-icons: ok')
PY
  echo "qs-process-icons: $mode checked"
done
