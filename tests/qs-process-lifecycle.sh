#!/usr/bin/env bash
# Shared Store + real process helper against a deterministic 80-process /proc.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
if ! command -v quickshell >/dev/null; then
  echo "qs-process-lifecycle: skipped (needs quickshell)"
  exit 0
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/tree" "$work/proc" "$work/state"
cp -r components lib scripts "$work/tree/"
cp tests/qs/process-lifecycle.qml "$work/tree/shell.qml"
python3 - "$work" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
sys.path.insert(0, str(pathlib.Path.cwd() / 'tests' / 'py'))
from test_process_sample import stat_line
for pid in range(1, 81):
    proc = root / 'proc' / str(pid)
    proc.mkdir()
    (proc / 'stat').write_text(stat_line(pid, f'worker-{pid}', 100, 0, 1, pid, 100))
    (proc / 'comm').write_text(f'worker-{pid}\n')
    if pid <= 60:
        (proc / 'io').write_text('read_bytes: 100\nwrite_bytes: 100\n')
(root / 'proc' / 'stat').write_text('procs_running 1\n')
helper = root / 'tree' / 'scripts' / 'process-sample'
s = helper.read_text().replace('count=5\n', 'printf \'%s %s\\n\' "$EPOCHREALTIME" "$*" >> "$QUADRANT_TEST_REQUESTS"\ncount=5\n', 1)
s = s.replace('count=5\n', 'if [[ $QUADRANT_TEST_MODE == failed && " $* " == *" --expanded "* ]]; then fail "fixture process failure"; fi\ncount=5\n', 1)
helper.write_text(s)
for name in ('gpu-stats', 'system-info', 'disk-info'):
    (root / 'tree' / 'scripts' / name).write_text('#!/usr/bin/env bash\nprintf \'%s\\n\' \'{"ok":true}\'\n')
(root / 'tree' / 'scripts' / 'quadrant-stream').write_text('#!/usr/bin/env bash\nexec sleep 30\n')
PY
for mode in normal cancel early-valid failed inflight; do
  mkdir -m 700 "$work/runtime-$mode"
  requests="$work/requests-$mode"
  : > "$requests"
  if ! QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QUADRANT_PROC_PATH="$work/proc" \
    QUADRANT_TEST_MODE="$mode" QUADRANT_TEST_REQUESTS="$requests" \
    XDG_RUNTIME_DIR="$work/runtime-$mode" XDG_STATE_HOME="$work/state" \
    timeout 15 quickshell -p "$work/tree/shell.qml" >"$work/$mode.log" 2>&1; then
    cat "$work/$mode.log"
    exit 1
  fi
  python3 - "$work/$mode.log" "$requests" "$mode" <<'PY'
import json, pathlib, sys
log, requests, mode = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
lines = log.read_text().splitlines()
events = [json.loads(line.split('QPROCESS ', 1)[1]) for line in lines if 'QPROCESS {' in line]
assert events and events[-1]['phase'] == 'done', log.read_text()
assert not any(word in line for line in lines for word in ('TypeError', 'ReferenceError', 'Binding loop', 'Failed to load')), log.read_text()
calls = [line.split(' ', 1) for line in requests.read_text().splitlines()]
starts = [float(call[0]) for call in calls]
assert all(b - a >= .39 for a, b in zip(starts, starts[1:])), calls
if mode == 'normal':
    assert len(calls) == 4, (calls, log.read_text())  # cold, one warm-up, expanded, compact
    assert .4 <= starts[1] - starts[0] <= 1.5, calls
    assert [('--expanded' in call[1]) for call in calls] == [False, False, True, False], calls
    assert [e['phase'] for e in events] == ['cold', 'warm', 'expanded', 'one-viewer', 'compact', 'done'], events
elif mode == 'failed':
    assert len(calls) == 3 and '--expanded' in calls[-1][1], (mode, calls, log.read_text())
    assert [e['phase'] for e in events] == ['cold', 'warm', 'failed', 'done'], events
elif mode == 'inflight':
    assert len(calls) == 2 and '--expanded' in calls[-1][1], (mode, calls, log.read_text())
    assert [e['phase'] for e in events] == ['cold', 'expanded', 'done'], events
else:
    assert len(calls) == 1, (mode, calls)
print(f'qs-process-lifecycle: {mode} ok ({len(calls)} shared runs)')
PY
done
