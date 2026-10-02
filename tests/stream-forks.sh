#!/usr/bin/env bash
# stream-forks.sh — proves quadrant-stream forks nothing on the tick path.
#
# A command substitution or external tool inside the loop would create a
# child that bash waits for, and the kernel folds every waited-for child's
# page faults and CPU time into the parent's cminflt/cutime/cstime fields
# in /proc/<pid>/stat. Those fields must therefore stay flat between two
# points inside the loop. Startup forks (mktemp, mkfifo, mapfile fills)
# happen before the first tick and are excluded by sampling after it.
#
# Also checks that a SIGTERM runs the EXIT trap: the FIFO directory must be
# gone once the sampler exits.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

XDG_RUNTIME_DIR=$(mktemp -d)
export XDG_RUNTIME_DIR
trap 'rm -rf "$XDG_RUNTIME_DIR"' EXIT

child_counters() {
  # cminflt cmajflt cutime cstime from /proc/<pid>/stat (fields 11,12,16,17
  # counted after the parenthesised comm).
  local stat rest
  stat=$(cat "/proc/$1/stat")
  rest=${stat##*) }
  # shellcheck disable=SC2206
  local f=($rest)
  printf '%s %s %s %s\n' "${f[8]}" "${f[9]}" "${f[13]}" "${f[14]}"
}

# Twelve ticks at 250 ms; we read the counters after tick 3 and after the
# stream has emitted all twelve.
QUADRANT_STREAM_TICKS=12 ./scripts/quadrant-stream 250 > "$XDG_RUNTIME_DIR/out.jsonl" &
pid=$!

lines=0
for _ in $(seq 1 80); do
  lines=$(wc -l < "$XDG_RUNTIME_DIR/out.jsonl")
  (( lines >= 3 )) && break
  sleep 0.1
done
(( lines >= 3 )) || { echo "stream produced no output"; kill "$pid" 2>/dev/null; exit 1; }
before=$(child_counters "$pid")

for _ in $(seq 1 80); do
  lines=$(wc -l < "$XDG_RUNTIME_DIR/out.jsonl")
  (( lines >= 11 )) && break
  sleep 0.1
done
(( lines >= 11 )) || { echo "stream stalled at $lines lines"; kill "$pid" 2>/dev/null; exit 1; }
after=$(child_counters "$pid")
wait "$pid" || true

if [[ $before != "$after" ]]; then
  echo "quadrant-stream forked on the tick path: child counters moved $before -> $after"
  exit 1
fi
echo "stream-forks: no child process between tick 3 and tick 11 (counters $after)"

# Every line must be a complete JSON object.
while IFS= read -r line; do
  printf '%s\n' "$line" | jq -e '.v == 1 and .cpu and .mem' > /dev/null
done < "$XDG_RUNTIME_DIR/out.jsonl"

# SIGTERM must run the EXIT trap and remove the FIFO directory.
./scripts/quadrant-stream 250 > /dev/null &
pid=$!
sleep 0.5
dirs_before=$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -name 'quadrant-stream.*' | wc -l)
(( dirs_before == 1 )) || { echo "expected one FIFO directory while running, saw $dirs_before"; kill "$pid"; exit 1; }
kill -TERM "$pid"
wait "$pid" || true
dirs_after=$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -name 'quadrant-stream.*' | wc -l)
(( dirs_after == 0 )) || { echo "FIFO directory survived SIGTERM"; exit 1; }
echo "stream-forks: SIGTERM cleaned up the FIFO directory"

# A directory left by a dead sampler is swept at the next start.
mkdir "$XDG_RUNTIME_DIR/quadrant-stream.999999.stale"
QUADRANT_STREAM_TICKS=1 ./scripts/quadrant-stream 250 > /dev/null
[[ ! -d "$XDG_RUNTIME_DIR/quadrant-stream.999999.stale" ]] || { echo "stale FIFO directory was not swept"; exit 1; }
echo "stream-forks: stale directory swept"
