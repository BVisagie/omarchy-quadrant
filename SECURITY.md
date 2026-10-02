# Security and data handling

[← README](README.md)

Quadrant runs **unsandboxed inside `omarchy-shell` with your user
permissions**, using Quattro's plugin model. Review the repository before
enabling it. It does not require root, sudo, pkexec, setcap, or setuid,
and installs no daemon or systemd unit.

## System access

Monitoring reads `/proc`, `/sys`, unprivileged udev DMI data, and output
from local tools. Quadrant does not change hardware settings or send
signals to the processes listed in the panel. The stream watchdog can
terminate and restart **its own sampler**; startup cleanup also probes
sampler PIDs to remove abandoned FIFO directories.

Settings are written through Omarchy's `shell.json` writer. A compatibility
path can call `omarchy bar set --json` when the in-process writer is not
available. Right-click launches `btop` through
`omarchy-launch-or-focus-tui` with a fixed argument list.

## Stored data

| Data | Location and contents | Lifetime |
| --- | --- | --- |
| Graph history | `$XDG_STATE_HOME/dev.bvisagie.quadrant/history.json`, defaulting to `~/.local/state/dev.bvisagie.quadrant/history.json`; numeric time buckets and GPU/interface/disk tags | Saved every 30 s and on store destruction; remains after uninstall |
| Process counter cache | `$XDG_RUNTIME_DIR/quadrant-procs.json`; timestamps and CPU/I/O counters keyed by PID and start time, without names or command lines | Used for interval rates; not removed on plugin exit |
| Process cache fallback | `~/.cache/quadrant-procs.json` if the process helper runs without `$XDG_RUNTIME_DIR` | Remains until deleted; the streaming sampler itself requires `$XDG_RUNTIME_DIR` |
| Tick FIFO | `$XDG_RUNTIME_DIR/quadrant-stream.<pid>.<random>/tick.fifo` | Removed on normal exit; abandoned directories are swept on next sampler start |
| Settings | Quadrant's inline widget entry in `~/.config/omarchy/shell.json` | Managed by the shell |

History uses atomic writes and is validated on load. Process-cache writes
use an atomic rename and a temporary file named `quadrant-procs.json.tmp`;
a crash during the write can leave it behind. If history cannot be saved,
live graphs still work and history may start empty after restarting.

After disabling or removing Quadrant, delete its history directory if you
want to remove saved graphs. Remove `quadrant-procs.json` and any `.tmp`
file from the runtime directory (and `~/.cache` if that fallback was used)
to clear process counters. Abandoned `quadrant-stream.*` directories can
also be removed once their sampler has stopped.

## Process data

CPU, memory, and disk process lists read `comm`, `stat`, `io`, and, for
memory candidates, `smaps_rollup`. The helper reads up to 4096 bytes of
`cmdline` and the `exe` link only for top candidates, to identify scripts
and recognize applications such as Electron wrappers. A clipped command
hint travels in the JSON sample to the naming logic; raw argument lists
are not displayed or saved in the counter cache. Script basenames and
recognized app labels may appear in the panel. `environ` is never read.

GPU attribution reads DRM `fdinfo` and process names, or NVIDIA compute-app
memory data. TCP attribution reads socket counters, owners, and local
addresses from `ss` and `ip`. Access is limited to what your user can read.
These are local observations; Quadrant does not upload metrics or process
data. Attribution limits are documented in [Measurements](docs/METRICS.md).

## Rendering and helpers

- All plugin `Text` elements explicitly use `Text.PlainText`; CI checks
  every QML file. Process and firmware names cannot become rich-text markup.
- Untrusted strings travel as JSON data. Bash helpers use `jq --arg` for
  string payloads; Python uses its JSON encoder; the stream uses its own
  JSON escaping with Bash builtins. Strings are not executed as commands.
- Desktop-entry matching for process icons and names uses exact normalized
  matches and a bounded cache. Wrapper labels use a fixed application map.
- The `ss` parser anchors process ownership on the trailing `pid=` field
  rather than accepting a PID-looking token inside a process name.
- Settings are normalized on read. Device names and helper arguments are
  checked before use. Bash helpers use `set -euo pipefail` and prefer
  `/usr/bin/<name>` for resolved tools, falling back to `PATH` where needed.
- `ss` and `nvidia-smi` calls are timeout-bounded; the QML sampler also
  bounds helper execution. Stream and process-sampler failures, GPU
  detection, disk identity, NVIDIA, and integrated-GPU errors have panel
  messages. Some optional failures retain previous data or omit metrics:
  discrete AMD/Intel polls, DRM details, system identity, mount refresh,
  and history-save failures do not all expose an error message.

Runtime tools include `bash`, `jq`, `python3`, `ss`, `ip`, `df`, `awk`,
`timeout`, `dirname`, `readlink`, `mkdir`, `mktemp`, `mkfifo`, and `rm`;
`nvidia-smi` for NVIDIA; optional `lspci` for identity; and
`omarchy-launch-or-focus-tui` for the right-click action. They operate
locally, without downloading monitoring code or data.
