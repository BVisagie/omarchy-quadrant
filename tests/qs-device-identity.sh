#!/usr/bin/env bash
# Real Store wiring with deterministic inventories and delayed GPU results.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
if ! command -v quickshell >/dev/null 2>&1; then
  echo "qs-device-identity: skipped (needs quickshell)"
  exit 0
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/tree" "$work/state" "$work/runtime" "$work/fixtures"
cp -r components scripts lib "$work/tree/"
cp tests/qs/device-identity.qml "$work/tree/shell.qml"
printf 'initial\n' > "$work/stage"

python3 - "$work/fixtures" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
for stage in ('initial', 'swapped', 'missing'):
    gpu = lambda card, slot: dict(card=card, slot=slot, vendor='amd', pciId='1002:744c', path=f'/sys/class/drm/{card}/device')
    disk = lambda name, identity: dict(name=name, deviceIds=[identity], sizeBytes=1000)
    if stage == 'initial':
        gpus = [gpu('card0', '0000:03:00.0'), gpu('card1', '0000:08:00.0')]
        disks = [disk('sda', 'wwn-A'), disk('sdb', 'wwn-B')]
    else:
        gpus = [gpu('card0', '0000:08:00.0')]
        disks = [disk('sda', 'wwn-B')]
        if stage == 'swapped':
            gpus.append(gpu('card1', '0000:03:00.0'))
            disks.append(disk('sdb', 'wwn-A'))
    (root / f'{stage}-gpu.json').write_text(json.dumps(dict(ok=True, gpus=gpus)))
    (root / f'{stage}-disk.json').write_text(json.dumps(dict(ok=True, disks=disks, dfPayload='')))
PY
cat > "$work/tree/scripts/gpu-stats" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ $1 == list ]]; then
  read -r stage < "$QUADRANT_TEST_STAGE"
  cat "$QUADRANT_TEST_FIXTURES/$stage-gpu.json"
else
  printf '%s %s\n' "$2" "$3" >> "$QUADRANT_TEST_REQUESTS"
  while [[ ! -e $QUADRANT_TEST_GPU_GATE ]]; do sleep 0.05; done
  sleep 0.5
  if [[ $2 == nvidia ]]; then
    printf '%s\n' '{"ok":true,"vendor":"nvidia","payload":"0,Test GPU,42,1,2,30,10,500"}'
  else
    printf '%s\n' '{"ok":true,"vendor":"amd","payload":"gpu_busy_percent=55"}'
  fi
fi
SH
cat > "$work/tree/scripts/disk-info" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
read -r stage < "$QUADRANT_TEST_STAGE"
if [[ $stage == initial ]]; then
  while [[ ! -e $QUADRANT_TEST_DISK_GATE ]]; do sleep 0.05; done
fi
cat "$QUADRANT_TEST_FIXTURES/$stage-disk.json"
SH
cat > "$work/tree/scripts/system-info" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '{"ok":true}'
SH
cat > "$work/tree/scripts/quadrant-stream" <<'SH'
#!/usr/bin/env bash
# The harness injects counter samples itself.
exec sleep 25
SH
chmod +x "$work/tree/scripts/"{gpu-stats,disk-info,system-info,quadrant-stream}
if ! QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME="" XDG_STATE_HOME="$work/state" XDG_RUNTIME_DIR="$work/runtime" \
  QUADRANT_TEST_STAGE="$work/stage" QUADRANT_TEST_FIXTURES="$work/fixtures" QUADRANT_TEST_REQUESTS="$work/requests" \
  QUADRANT_TEST_DISK_GATE="$work/disk-ready" QUADRANT_TEST_GPU_GATE="$work/gpu-ready" \
  timeout --kill-after=2s 25 quickshell -p "$work/tree/shell.qml" > "$work/log" 2>&1; then
  cat "$work/log"
  exit 1
fi
if ! rg -q 'QIDENTITY ok' "$work/log" || rg -i 'error|referenceerror|typeerror|binding loop' "$work/log"; then
  cat "$work/log"
  exit 1
fi
if ! rg -q '^nvidia 0000:03:00.0$' "$work/requests"; then
  cat "$work/requests"
  exit 1
fi
rg 'QIDENTITY' "$work/log"
echo "qs-device-identity: ok"
