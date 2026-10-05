# Development

[← README](../README.md)

## Architecture

`manifest.json` declares a bar widget and a service. `Service.qml` creates
one `components/Store.qml` per shell; each `BarWidget.qml` copy binds to
it through `bar.shell.serviceFor()`. Widgets report which segments and
tabs are visible. The store owns sampling, derived metrics, settings,
and history, so multiple monitors share one stream and one set of pollers.

If service lookup fails after ten attempts, a widget embeds its own
store. That compatibility fallback can run a sampler per widget; the
one-store guarantee depends on successful service resolution in the
supported shell.

`Panel.qml` owns navigation, settings, and IPC. Files under `tabs/` lay out
each metric; reusable controls live in `components/`. Pure functions in
`lib/*.mjs` parse counters, calculate deltas, select devices, normalize
settings, name processes, and manage history. The same ES modules run
under Quickshell and Node tests.

### Samplers

`scripts/quadrant-stream` emits one JSON line per tick: CPU and per-core
ticks, meminfo, PSI, swap counters, interfaces, disks, default routes,
CPU temperature, frequency, and cheap dedicated AMD/Intel sysfs fields.
Its tick path uses Bash builtins with zero fork/exec; `read -t` on a
self-held FIFO provides timing. Setup and cleanup use external tools.
`tests/stream-forks.sh` checks the tick budget and FIFO cleanup.

| Helper | When it runs |
| --- | --- |
| `system-info` | Startup, `R`, and GPU-tab refresh; hardware and interface identity |
| `disk-info` | Startup and `R`; disk identity, backing devices, mounts |
| `gpu-stats list` | Startup; detected GPU inventory |
| `process-sample` → `qproc.py` | CPU, Memory, or Drives tab open; one `/proc` walk for all three |
| `process-net` | Network tab open with a valid interface; TCP attribution |
| `gpu-stats sample nvidia` | NVIDIA segment or GPU tab visible |
| `gpu-stats sample amd/intel` → `gpu-drm` | GPU tab open, or GPU segment visible when DRM polling is needed for busy; integrated GPU while CPU tab is open |
| `disk-info usage` | Drives tab open; mount capacity and NVMe temperatures |

`panelIntervalMs` controls poll timers, including GPU polls needed by a
visible bar segment. `barIntervalMs` controls the stream and graph ticks.
Settings-view visibility does not clear the current metric tab's viewer
flag, so its polls can continue while settings is open. GPU inventory is
not re-enumerated by `R`; newly attached cards need a plugin/shell reload.

See [Measurements](METRICS.md) for calculations and [Security](../SECURITY.md)
for state paths and failure behavior.

## Checks

Run from the repository root. Pure tests need Node and Python; the script
checks need the runtime tools, ShellCheck, Ruff, mawk, and gawk.

```sh
node --test tests/lib/*.test.js
python3 -m unittest discover -s tests/py -t . -v
ruff check --no-cache scripts/gpu-drm scripts/qproc.py tests/py
python3 -m py_compile scripts/gpu-drm scripts/qproc.py
bash tests/intel-freq-paths.sh
bash tests/stream-forks.sh
shellcheck -x scripts/quadrant-stream scripts/system-info scripts/disk-info scripts/gpu-stats scripts/gpu-intel-paths.sh scripts/process-sample scripts/process-net tests/*.sh
mawk -f tests/check-plaintext.awk *.qml components/*.qml tabs/*.qml tests/qs/*.qml
gawk -f tests/check-plaintext.awk *.qml components/*.qml tabs/*.qml tests/qs/*.qml
```

[CI](../.github/workflows/test.yml) also parses the manifest, checks Bash
syntax, and runs helper smoke checks in a mawk/gawk matrix. The
`QUADRANT_AWK` environment variable selects the helper's awk executable.

### Quickshell checks and rendering

```sh
bash tests/qs-smoke.sh
bash tests/qmllint.sh
bash tests/render.sh cpu /tmp/quadrant-cpu.png
```

`qs-smoke.sh` runs the real store under a throwaway Quickshell instance and
checks settings, viewers, process sampling, history reload, and watchdog
recovery before and after a settings restart. It needs
Quickshell and a display (`WAYLAND_DISPLAY` or `DISPLAY`), but does not
need the Omarchy `qs.*` imports. It skips without those prerequisites.
The watchdog regression can also run independently with
`bash tests/qs-stream-recovery.sh`; it uses Qt's offscreen platform and only
needs Quickshell.

`qmllint.sh` needs qmllint and an Omarchy shell at
`${OMARCHY_PATH:-/usr/share/omarchy}/shell`; it skips when either is
missing. The regular CI runner therefore does not establish that the QML
passes this local gate. The harnesses under `tests/qs/` run from copied
trees and are excluded from qmllint.

`render.sh` needs Quickshell and Omarchy's shell imports. It uses Qt's
offscreen platform and temporary state to render `cpu`, `gpu`, `mem`,
`disk`, `net`, `settings`, or `bar`. Missing shell imports are an error,
not a skip. It samples this machine's real hardware; inspect the output
and any reported QML errors before using it. Public screenshot files are
`preview.png` and `docs/screenshots/{bar,cpu,gpu,memory,drives,network,settings}.png`.
The hero's editable layout is [artwork/hero.html](artwork/hero.html), rendered
at 1920 × 1320 with the original CPU, GPU, and Memory captures. It frames
the screenshots without changing their UI text, colours, or measurements.

## Before publishing

With a supported Omarchy install:

```sh
omarchy plugin validate /path/to/omarchy-quadrant
bash tests/qmllint.sh
```

Confirm qmllint actually ran. Exercise AMD, NVIDIA, and Intel dedicated
GPUs; Intel/AMD iGPU-only and hybrid machines; no GPU; IPv6-only networking;
no swap; vertical bars; light themes; two monitors (one `quadrant-stream`
process with the shared service); mawk and gawk; and spinning disks,
LUKS/LVM/RAID, and multiple mounts.

Check keyboard and mouse navigation, typed settings changes from both the
panel and CLI, device changes, a minute/hour toggle, history across a
shell restart, and visible errors when a helper fails. GPU process lists,
disk attribution, and the compact network bar have limits described in
[Measurements](METRICS.md) and [Settings](SETTINGS.md).
