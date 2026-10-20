# Security and data handling

[← README](README.md)

Quadrant runs **unsandboxed inside `omarchy-shell` with your user
permissions**, using Quattro's plugin model. Review the repository before
enabling it. It does not require root, sudo, pkexec, setcap, or setuid,
and installs no daemon or systemd unit.

## System access

Monitoring reads `/proc`, `/sys`, unprivileged udev DMI data, libdrm's
`amdgpu.ids` product table, and output from local tools. Quadrant does not
change hardware settings or send signals to the processes listed in the
panel. The stream watchdog can terminate and restart **its own sampler**;
startup cleanup also probes sampler PIDs to remove abandoned FIFO
directories.

Hardware diagnostics read bounded hwmon, powercap energy, and power-supply
attributes. Permission-denied counters remain unavailable; the helper never
changes access, enables capping, writes fan controls, or manages GPU runtime
power. GPU-owned hwmon input files are left to the existing GPU collectors.
Metadata inventory includes detected cards without making them live targets.

Settings are written through Omarchy's `shell.json` writer. A compatibility
path can call `omarchy bar set --json` when the in-process writer is not
available. Right-click launches `btop` through
`omarchy-launch-or-focus-tui` with a fixed argument list.

Explicit **Copy** actions send the displayed address/MAC as UTF-8 on `wl-copy`'s
stdin, without reading the clipboard. The shell's clipboard history may retain
copied values according to its own settings. **Open** checks the exact directory
against `/proc/self/mountinfo` and user access, then passes an encoded local-file
URI as one argument to `gio open`, falling back to `xdg-open` when GIO is absent.
When available, `uwsm-app --` starts the launcher outside the compositor's unit.
Quadrant passes argument lists without building shell commands from values or
paths. These actions have desktop side effects only after activation and report
tool failures and timeouts in the panel.
They do not mount volumes or request additional permissions.

## Stored data

| Data | Location and contents | Lifetime |
| --- | --- | --- |
| Graph history | `$XDG_STATE_HOME/dev.bvisagie.quadrant/history.json`, defaulting to `~/.local/state/dev.bvisagie.quadrant/history.json`; numeric time buckets and GPU/interface/disk tags (PCI hardware fingerprint or disk by-id name, which can contain a serial number) | Saved every 30 s and on store destruction; remains after uninstall |
| Process counter cache | `$XDG_RUNTIME_DIR/quadrant-procs.json`; timestamps and CPU/I/O counters keyed by PID and start time, without names or command lines | Used for interval rates; not removed on plugin exit |
| Process cache fallback | `~/.cache/quadrant-procs.json` if the process helper runs without `$XDG_RUNTIME_DIR` | Remains until deleted; the streaming sampler itself requires `$XDG_RUNTIME_DIR` |
| Tick FIFO | `$XDG_RUNTIME_DIR/quadrant-stream.<pid>.<random>/tick.fifo` | Removed on normal exit; abandoned directories are swept on next sampler start |
| GPU collection control | `$XDG_RUNTIME_DIR/quadrant-control.<shell-pid>.<random>/control`; device paths, visibility demand, generation and boot-time lease, in a private directory | Removed on Store destruction; directories of dead controllers are swept on stream startup; expired/malformed control suppresses AMD telemetry |
| Settings | Quadrant's inline widget entry in `~/.config/omarchy/shell.json`, including selected GPU PCI addresses, disk by-id pins, and hashed sensor pins when set | Managed by the shell |

History uses atomic writes and is validated on load. Process-cache writes
share a private `quadrant-procs.json.lock` file across compact/expanded runs
and use an atomic rename and a temporary file named `quadrant-procs.json.tmp`;
a crash during the write can leave it behind. If history cannot be saved,
live graphs still work and history may start empty after restarting. If the
process-state lock cannot be opened or acquired, memory and process counts
still work with unavailable CPU/I/O rates; the helper does not read or
write shared counters without the lock.

Sensor IDs hash device path, driver, channel, and available NVMe serial;
the raw serial is not stored in that setting. Battery identities also hash
available serials. Diagnostic snapshots and package baselines stay in memory,
with no hardware history file. This does not alter existing disk history tags,
which may contain a disk serial as documented above.

After disabling or removing Quadrant, delete its history directory if you
want to remove saved graphs. Remove `quadrant-procs.json`, its `.lock` file,
and any `.tmp` file from the runtime directory (and `~/.cache` if that fallback was used)
to clear process counters. Abandoned `quadrant-stream.*` directories can
also be removed once their sampler has stopped.
Abandoned `quadrant-control.*` directories can be removed after their
controller has stopped. This file schedules reads; it is never sourced as
shell code and does not write GPU power controls or driver configuration.

## Process data

CPU, memory, and disk process lists read `comm`, `stat`, `io`, and, for
memory candidates, `smaps_rollup`. The helper reads up to 4096 bytes of
`cmdline` and the `exe` link for top candidates in compact mode and for all
eligible rows while expanded CPU/Memory/Drives data is requested, to identify
scripts and recognize applications such as Electron wrappers. A clipped command
hint travels in the JSON sample to the naming logic; raw argument lists
are not displayed or saved in the counter cache. Script basenames and
recognized app labels may appear in the panel. Expanded memory uses RSS and
does not read every `smaps_rollup`. Search and icons use the collected roster
and local desktop-entry inventory. The search component requests no clipboard
data on creation, focus, or hiding; paste requires an explicit user action.
`environ` is never read.

GPU attribution reads DRM `fdinfo` and process names, or NVIDIA compute-app
memory data. TCP attribution reads socket counters, owners, and local
addresses from `ss` and `ip`. Access is limited to what your user can read.
These are local observations; Quadrant does not upload metrics or process
data. Attribution limits are documented in [Measurements](docs/METRICS.md).

## Rendering and helpers

- All plugin `Text` elements explicitly use `Text.PlainText`; CI checks
  every QML file. Process and firmware names cannot become rich-text markup.
- Untrusted strings travel as JSON data. Small Bash helper fields use
  `jq --arg`; process and socket payloads stream through a bounded Python
  JSON encoder with a 1 MiB envelope limit. The stream uses its own
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
  discrete Intel polls, DRM details, system identity, mount refresh,
  and history-save failures do not all expose an error message.

Runtime tools include `bash`, `jq`, `python3`, `ss`, `ip`, `df`, `base64`, `awk`,
`timeout`, `dirname`, `readlink`, `mkdir`, `mktemp`, `mkfifo`, and `rm`;
`nvidia-smi` for NVIDIA; optional `lspci` for identity; and
`omarchy-launch-or-focus-tui` for the right-click action. They operate
locally, without downloading monitoring code or data.

Optional panel actions also use `wl-copy`, `gio` or `xdg-open`, and `uwsm-app`
when available. Each desktop tool request is bounded to five seconds, with an
eight-second QML watchdog for the helper. File-manager success confirms the
launch request was accepted.
