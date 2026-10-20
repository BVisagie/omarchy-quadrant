#!/usr/bin/env bash
# Hardware UI and shared collector lifecycle under Qt Quick Test.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
shell_dir=${OMARCHY_PATH:-/usr/share/omarchy}/shell
if ! command -v quickshell >/dev/null || [[ ! -d $shell_dir/Ui || ! -d /usr/lib/qt6/qml/QtTest ]]; then
  echo "qs-hardware-ui: skipped (needs quickshell, Qt Quick Test and the Omarchy shell)"
  exit 0
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/tree" "$work/runtime" "$work/state" "$work/sys"
chmod 700 "$work/runtime"
cp -r components tabs lib scripts "$work/tree/"
cp tests/qs/HardwareFixture.qml "$work/tree/"
cp tests/qs/hardware-ui.qml "$work/tree/shell.qml"
cp "$work/tree/scripts/hardware-info.py" "$work/tree/scripts/hardware-real.py"
cp tests/qs/hardware-helper.py "$work/tree/scripts/hardware-info.py"
ln -s "$shell_dir/Commons" "$work/tree/Commons"
ln -s "$shell_dir/Ui" "$work/tree/Ui"
python3 - "$work/sys" <<'PY'
import os
from pathlib import Path
import sys
root = Path(sys.argv[1])
def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(str(value) + "\n")
def alias(path, target):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.symlink_to(target)
for index, driver, owner in [(0, 'coretemp', 'platform/coretemp.0'), (1, 'board', 'platform/board.0'), (2, 'amdgpu', 'pci0000:00/0000:03:00.0')]:
    device = root/'devices'/owner
    hw = device/'hwmon'/('hwmon'+str(index))
    write(hw/'name', driver)
    alias(hw/'device', device)
    alias(root/'class/hwmon'/hw.name, hw)
    if driver == 'amdgpu':
        os.mkfifo(hw/'temp1_input')  # must never be opened by Hardware
    else:
        write(hw/('fan1_input' if driver == 'board' else 'temp1_input'), 0 if driver == 'board' else 42000)
package = root/'devices/virtual/powercap/intel-rapl:0'
for name, value in [('name','package-0'), ('energy_uj',1000000000), ('max_energy_range_uj',100000000000)]:
    write(package/name,value)
alias(root/'class/powercap/intel-rapl:0', package)
battery = root/'devices/platform/power_supply/BAT0'
for name, value in [('type','Battery'), ('capacity',80), ('energy_full',50000000), ('energy_full_design',60000000), ('power_now',0)]:
    write(battery/name,value)
alias(root/'class/power_supply/BAT0',battery)
PY
cat > "$work/tree/scripts/gpu-stats" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '{"ok":true,"gpus":[],"inventory":[]}'
SH
cat > "$work/tree/scripts/system-info" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '{"ok":true}'
SH
cat > "$work/tree/scripts/disk-info" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '{"ok":true,"disks":[],"backing":{},"dfPayload":""}'
SH
cat > "$work/tree/scripts/process-sample" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '{"ok":false,"error":"fixture process collection"}'
SH
cat > "$work/tree/scripts/quadrant-stream" <<'SH'
#!/usr/bin/env bash
exec sleep 25
SH
chmod +x "$work/tree/scripts/"{gpu-stats,system-info,disk-info,process-sample,quadrant-stream}
for mode in patched unpatched; do
  printf '{}\n' > "$work/hardware-state"
  : > "$work/requests"
  if [[ $mode == unpatched ]]; then sed -i '1{/OmarchyLoadPatch/d;}' "$work/tree/shell.qml"; fi
  if ! QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' XDG_RUNTIME_DIR="$work/runtime" XDG_STATE_HOME="$work/state" \
    QUADRANT_SYS_PATH="$work/sys" QUADRANT_TEST_HARDWARE_STATE="$work/hardware-state" QUADRANT_TEST_HARDWARE_REQUESTS="$work/requests" \
    timeout --kill-after=2s 30 quickshell -p "$work/tree/shell.qml" >"$work/test.log" 2>&1; then
    cat "$work/test.log"
    exit 1
  fi
  cat "$work/test.log"
  python3 - "$work/test.log" <<'PY'
import json, pathlib, sys
lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
results = [json.loads(line.split("QHARDWAREUI ", 1)[1]) for line in lines if "QHARDWAREUI {" in line]
assert len(results) == 1 and results[0]["passed"] >= 22 and results[0]["failed"] == 0, results
assert not any(word in line for line in lines for word in ("TypeError", "ReferenceError", "Binding loop", "Failed to load", "Unable to assign"))
print("qs-hardware-ui: ok")
PY
  echo "qs-hardware-ui: $mode checked"
done
