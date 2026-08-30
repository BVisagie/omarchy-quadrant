# Quadrant

A unified system monitor for the Omarchy Quattro bar: CPU, memory, GPU, and
network in one compact bar widget and one tabbed panel. Each panel tab
identifies the hardware it is measuring — CPU model and topology, GPU name
and driver, installed RAM and swap devices — then shows live usage.

```
┌──────────────────────────────┐
│ C▮  M▮  G▮   ↑ 1.1K          │   bar slot (segments toggleable)
│              ↓ 3.6K          │
└──────────────────────────────┘
```

Clicking a segment opens the panel on that segment's tab; clicking anywhere
else toggles the panel on the last-used tab.

```
┌────────────────────────────────────────────┐
│  CPU   MEMORY   GPU   NETWORK              │
│  ──────────────────────────────────────    │
│  Ryzen 9 7950X · 16 cores · 32 threads     │
│  60s history / rings / process list        │
│  ←/→ or 1-N switch tab · R refresh · Esc   │
└────────────────────────────────────────────┘
```

Built against the documented Quattro plugin contract. Supports **Omarchy 4**
(the Quattro shell). Requires `bash` ≥ 5, `jq`, `ps` (procps), `ss`
(iproute2), and `awk` (mawk or gawk); `nvidia-smi` only if you have an
NVIDIA card; `lspci` (pciutils) is optional and used to name AMD/Intel
GPUs.

## Install

```sh
omarchy plugin add https://github.com/BVisagie/omarchy-quadrant.git
```

The plugin lands **disabled**. Review the code — it will run unsandboxed
inside the shell — then enable it:

```sh
omarchy plugin enable dev.bvisagie.quadrant
```

The widget starts in the right bar section (`barWidget.defaultSection`).
Move it with `omarchy bar move dev.bvisagie.quadrant --section center`.

## Usage

- **Bar segments**: `C` (CPU user+system stacked fill), `M` (memory used),
  `G` (GPU busy), and two-line network rates. Each segment toggles
  independently; the slot shrinks to fit. The GPU segment hides itself when
  no supported GPU is detected — no dead chrome for hardware that is not
  there. Vertical bars are supported (segments stack). Meter fills follow
  the live Omarchy accent (with the theme's urgent color at ≥90% load);
  `barPalette vivid` restores the original per-resource hues. Network rates
  use a fixed-width compact format (`1.0K`, `99K`) so the slot does not
  resize as the magnitude changes. C/M/G meters stretch to the two-line
  network stack and sit vertically centered in the slot.
- **Panel**: click the widget. `←`/`→` or `1`–`N` (N = visible tabs; GPU
  is omitted when no supported card is present) switch tabs, `R`
  refreshes the active tab, `Esc` closes. `Tab` keeps its Quattro meaning
  (switch to the adjacent bar panel) and is deliberately not used inside
  Quadrant.
- **IPC** (for scripts and keybinds):

```sh
quickshell ipc -p "$OMARCHY_PATH/shell" call dev.bvisagie.quadrant showTab gpu   # cpu | mem | gpu | net
omarchy-shell shell summon dev.bvisagie.quadrant '{}'   # open on last-used tab
omarchy-shell shell hide dev.bvisagie.quadrant
```

## Settings

All settings live inline on the widget's entry in
`~/.config/omarchy/shell.json` and are declared in the manifest schema, so
`omarchy bar set` works:

```sh
omarchy bar set dev.bvisagie.quadrant processCount 8
omarchy bar set dev.bvisagie.quadrant networkInterface '"wg0"'
```

| Key | Default | Meaning |
| --- | --- | --- |
| `segments` | `["cpu","memory","gpu","network"]` | Which bar segments to show |
| `processCount` | `5` | Top-process rows per tab (1–10) |
| `barIntervalMs` | `1000` | Stream cadence feeding bar + history (250–60000) |
| `panelIntervalMs` | `2000` | On-demand sampler cadence while the panel is open (500–60000) |
| `networkInterface` | `"auto"` | `auto` = default route across IPv4 **and** IPv6, lowest metric wins, IPv4 takes ties |
| `gpuDevice` | `"auto"` | `auto` = boot display card when determinable, else `card0`; or a specific `cardN` |
| `barPalette` | `"theme"` | `theme` = live Omarchy accent fills, foreground track, urgent at ≥90%; `vivid` = original per-resource hues |

## What it measures (and what it does not)

- **CPU**: user (incl. nice) and system (incl. irq/softirq) are stacked in
  the graph; `iowait` is its own series; `steal` is labeled separately and
  never folded into "system". The tab header is the `model name` from
  `/proc/cpuinfo` with physical cores / threads, L3 cache, scaling
  governor, and current/max frequency (`scaling_cur_freq` when present,
  else the cpuinfo snapshot).
- **Memory**: composition splits RAM into Applications / Kernel
  (unreclaimable slab) / Cache (page cache + **Buffers** + SReclaimable) /
  Free. The process column is "% of RAM". The pressure ring is PSI memory
  `some avg10`; PSI is **optional per resource** — when `/proc/pressure/cpu`
  or `/proc/pressure/memory` is unreadable that half is JSON `null` and the
  ring shows `--`, not zero. The tab header is installed RAM; swap devices
  from `/proc/swaps` are listed (zram includes the active compression
  algorithm and disk size). DMI vendor/product and the kernel release
  appear as a caption when readable.
- **GPU**: AMD reads `amdgpu` sysfs (`gpu_busy_percent`, `mem_busy_percent`,
  per-engine `engine/*/busy_percent`, VRAM info, hwmon temp/power, active
  DPM sclk). NVIDIA runs `nvidia-smi` (timeout-bounded,
  row-capped) **only while the GPU segment or tab is visible** — never in
  the 1 Hz stream. Intel shows a **frequency-ratio estimate labeled
  "freq"**, never "busy": true busy % needs `CAP_PERFMON`, which Quadrant
  refuses to require. Every sysfs file is treated as optional; availability
  varies by kernel and ASIC. Multi-GPU systems get a card selector in the
  GPU tab; the choice is persisted with `omarchy bar set … gpuDevice`.
  The tab header is the card's marketing name: NVIDIA's `nvidia-smi` name,
  or `lspci -D -mm` joined by PCI slot for AMD/Intel, falling back to
  vendor + PCI ID when pciutils is not installed. Driver and slot come
  from sysfs `uevent`. Per-process GPU attribution is v2.
- **Network**: rates for the selected interface plus 60s down/up history.
  Per-process attribution uses per-socket TCP byte counters from
  `ss -tinp`, scoped to the watched interface's addresses (ss is global;
  the byte counters are not). UDP, sockets on other interfaces, sockets
  owned by other users, and closed-socket remainders cannot be attributed
  — they appear as an honest **Other traffic** row (keyed on `pid == 0`; a
  process literally named "Other traffic" can never collide with it). The
  tab footer says **Default route via …** when the interface is auto-picked,
  or **Pinned interface …** when `networkInterface` is set.
- **Temperature**: hwmon whitelist only (`k10temp`, `coretemp`,
  `zenpower`, `cpu_thermal`). There is no first-readable-sensor fallback —
  Quadrant shows `--` rather than another chip's temperature.

## Security posture

Quadrant runs **unsandboxed inside `omarchy-shell` with your user
permissions** — the same model as every Quattro plugin. Concretely:

- **Read-only.** The plugin sends no signals to other processes and writes
  nothing outside a `mktemp -d` directory under `$XDG_RUNTIME_DIR` (a FIFO
  used as the sampler's tick clock, removed on exit). Process actions
  (terminate from the panel) are deferred to v2 behind an
  `allowProcessActions` setting that defaults off.
- **No secrets in process data.** Process lists read `ps -o comm=` — never
  `args`, never `/proc/*/cmdline`, never `environ`.
- **Injection-safe rendering.** Every `Text` element bound to script output
  or process names sets `textFormat: Text.PlainText` (Qt's default
  AutoText can interpret HTML-like strings, including inline images). CI
  enforces this with a check over all QML files. The bar tooltip is
  rates/percentages (never process comm) and is rendered by the shell's
  WidgetButton tooltip, which is already PlainText.
- **Safe transport.** Process names, firmware strings, PCI-DB names, and
  raw tool output travel as JSON strings built with `jq --arg` — never TSV
  through a name. The `ss` parser anchors on the kernel's trailing `pid=`
  field, so a forged process name cannot borrow another pid. `lspci -mm`
  is parsed in Model.js (fixture-tested), never concatenated in bash.
- **Exact-match icons.** Desktop-entry matching for process icons/names is
  exact-match only (normalized id, Name, Icon, `StartupWMClass`); the raw
  `comm` is always shown beside any friendly name.
- **Failures are visible.** A helper that exits non-zero or times out
  surfaces an error in the panel — never an empty list presented as "no
  activity". QML distinguishes `[]` + exit 0 from failure.
- **Hardened scripts.** `set -euo pipefail`, helpers resolved from
  `/usr/bin/<name>` first then `command -v`, quoted expansions, POSIX awk
  only (CI runs the suite under mawk **and** gawk).
- **Binaries invoked**: `bash`, `jq`, `ps`, `ss`, `ip`, `timeout`, `mktemp`,
  `mkfifo`, `nvidia-smi` (NVIDIA only, on demand), `lspci` (optional, one
  shot at startup / on R). No root, no setcap, no setuid, no daemons.

### Data layer

One long-lived sampler, `scripts/quadrant-stream`, emits one JSON line per
tick (CPU ticks, meminfo, PSI, vmstat swap counters, per-interface net
counters, default routes, whitelisted CPU temp, cheap GPU sysfs fields,
optional `scaling_cur_freq`). It is a **single bash process with zero
fork/exec per tick** — timing comes from `read -t` on a self-held FIFO —
consumed in QML via `Process` + `SplitParser` with a restart timer. The
stream ships raw counters only; all deltas and rates are pure functions in
`Model.js`, tested with `node --test` against captured fixtures (including
hostile ones). Panel samplers (`process-cpu`, `process-memory`,
`process-net`, `gpu-stats`) run on demand while the panel is open, each
with a kill watchdog. Hardware identity (`scripts/system-info`) runs once
at startup and again when the user hits R — never on the 1 Hz path.

## Development

```sh
node --test tests/model.test.js          # pure-logic tests
shellcheck scripts/*                     # script lint
mawk -f tests/check-plaintext.awk BarWidget.qml Panel.qml tabs/*.qml components/*.qml
```

CI runs all of the above on every push, with the script smoke tests and the
PlainText check under both mawk and gawk.

Pre-publish gate (needs an Omarchy install):

```sh
omarchy plugin validate /path/to/omarchy-quadrant
qmllint -I "$OMARCHY_PATH/shell" /path/to/omarchy-quadrant/BarWidget.qml /path/to/omarchy-quadrant/Panel.qml
```

Manual test matrix before publishing: AMD / NVIDIA / Intel / no-GPU,
IPv6-only network, swapless machine, vertical bar, both mawk and gawk as
`awk`.

## License

MIT — see [LICENSE](LICENSE).
