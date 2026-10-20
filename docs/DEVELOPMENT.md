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

`PanelHeader.qml` owns wrapping tab/action layout; `PanelKeys.qml` owns the
same shortcut path used by the offscreen interaction tests. Device choices
keep full labels separate from their width-limited presentation.

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
| `gpu-stats list` | Startup and `R`; detected GPU inventory and PCI identities |
| `process-sample` → `qproc.py` | CPU, Memory, or Drives tab open; one `/proc` walk for all three |
| `process-net` | Network tab open with a valid interface; TCP attribution |
| `gpu-stats sample nvidia` | NVIDIA segment or GPU tab visible |
| `gpu-stats sample amd/intel` → `gpu-drm` | GPU tab open, or GPU segment visible when DRM polling is needed for busy; integrated GPU while CPU tab is open |
| `disk-info usage` | Drives tab open; mount capacity and NVMe temperatures |
| `hardware-info.py list` | Startup and `R`; sensor/package/battery metadata, without telemetry inputs |
| `hardware-info.py power/sample` | Hardware tab open, or CPU with all package counters/ranges readable; one serialized helper shared across monitors; CPU alone reads package counters only |
| `panel-action.py` | Explicit Copy/Open activation only; clipboard stdin or a validated mount URI passed to the desktop tool |
| `process-icons.py` | Process view opens, desktop inventory changes, or R; one lazy Store-owned file index, with coalesced requests and no per-sample scans |

`panelIntervalMs` controls poll timers, including GPU polls needed by a
visible bar segment. `barIntervalMs` controls the stream and graph ticks.
Settings-view visibility does not clear the current metric tab's viewer
flag, so its polls can continue while settings is open. `R` re-enumerates
GPU and disk inventory; settings and history resolve physical identities
before choosing kernel names. GPU pollers capture their command and device
identity at launch, so a result from a replaced or renumbered card cannot
seed the new card's live readings or DRM rate state. NVIDIA queries use
the resolved PCI address instead of inferring its driver index from card
order. A failed GPU refresh preserves the last successful inventory and
live state while reporting its error; startup failures remain unavailable.

See [Process exploration](PROCESS_EXPLORATION.md) for collection contracts and
performance observations, [Measurements](METRICS.md) for calculations and [Security](../SECURITY.md)
for state paths and failure behavior.

The [deferred AMD runtime power-management work](AMD_RUNTIME_POWER.md) records
the current reader audit, proposed collection boundaries, planned fixture coverage,
and the baseline/patched hardware procedure for a future PR. It is a follow-up
plan, not a guarantee provided by the current collectors.

## Checks

Run from the repository root. Pure tests need Node and Python; the script
checks need the runtime tools, ShellCheck, Ruff, mawk, and gawk.

```sh
node --test tests/lib/*.test.js
python3 -m unittest discover -s tests/py -t . -v
ruff check --no-cache scripts/gpu-drm scripts/qproc.py scripts/helper-envelope.py scripts/panel-action.py scripts/hardware-info.py scripts/process-icons.py tests/py tests/bench-bar.py tests/qs/*.py
python3 -m py_compile scripts/gpu-drm scripts/qproc.py scripts/helper-envelope.py scripts/panel-action.py scripts/hardware-info.py scripts/process-icons.py tests/bench-bar.py tests/qs/*.py
bash tests/intel-freq-paths.sh
bash tests/stream-forks.sh
shellcheck -x scripts/quadrant-stream scripts/system-info scripts/disk-info scripts/gpu-stats scripts/gpu-intel-paths.sh scripts/process-sample scripts/process-net tests/*.sh
mawk -f tests/check-plaintext.awk *.qml components/*.qml tabs/*.qml tests/qs/*.qml
gawk -f tests/check-plaintext.awk *.qml components/*.qml tabs/*.qml tests/qs/*.qml
mawk -f tests/check-qml-imports.awk *.qml components/*.qml tabs/*.qml tests/qs/*.qml
gawk -f tests/check-qml-imports.awk *.qml components/*.qml tabs/*.qml tests/qs/*.qml
```

[CI](../.github/workflows/test.yml) also parses the manifest, checks Bash
syntax, and runs helper smoke checks in a mawk/gawk matrix. The
`QUADRANT_AWK` environment variable selects the helper's awk executable.

### Quickshell checks and rendering

```sh
bash tests/qs-smoke.sh
bash tests/qs-device-identity.sh
bash tests/qs-process-lifecycle.sh
bash tests/qs-process-ui.sh
bash tests/qs-process-icons.sh
bash tests/qs-panel-ui.sh
bash tests/qs-graph-ui.sh
bash tests/qs-bar-ui.sh
bash tests/qs-actions-ui.sh
bash tests/qs-hardware-ui.sh
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

`qs-device-identity.sh` runs the real store offscreen with staged helper
inventories. It exercises delayed disk identity, GPU and disk enumeration
swaps via `refreshHardware()` (the `R` path), absent pins and recovery,
legacy history across a simulated boot, replacement hardware, stale GPU
poll results, NVIDIA PCI targeting, and failed GPU refreshes (envelope and
process failures, startup recovery, and a successful empty scan). Settings
regressions cover shell/IPC policy resets, inventory refresh before the
writer acknowledges a reset, and paired writes through the CLI fallback.
It skips only if Quickshell is missing. Pure tests include a frozen released
settings reader/writer to check downgrade preservation. Python tests run
disk/GPU inventory against temporary roots selected by
`QUADRANT_SYS_PATH` / `QUADRANT_DEV_PATH`; these are fixture hooks, not
plugin settings.

`qs-process-lifecycle.sh` uses the real process helper over 80 fixture processes
and two viewers. It checks cold warm-up, baseline spacing, compact/expanded
acquisition and release, permission coverage, payload failure, panel close,
follow-up cancellation when a valid sample arrives first, in-flight mode
changes, helper failures without a retry loop, stateless collection, and
memory-history accounting boundaries.
`qs-process-ui.sh` runs Qt Quick Test inside Quickshell (the standalone runner
cannot load statically linked Quickshell plugins). It exercises the actual
shell key handler and process list: printable input, staged Esc, Tab,
pointer controls, identity retention, filtering before caps, virtualization,
scroll retention across sample/reorder updates, keyboard handoff into
filtered results, and cursor scrolling at a narrow width, with and without
the load-patch pragma. It requires QtTest and shell imports;
the lifecycle test needs only Quickshell. Both use isolated temporary state.
`qs-process-icons.sh` installs an icon into a private XDG directory after the
initial miss and checks that the same delegate updates without restarting.
It also checks desktop-name search, shared resolution, optional native icon
callbacks, and that process updates do not start filesystem scans. Node and
Python fixtures cover matching ambiguity, launcher parsing, hint bounds,
filesystem context/format precedence and safe path handling.

`qs-panel-ui.sh` exercises the real panel shortcut dispatcher, duration
buttons, synchronized graphs, summary click and wheel, search focus,
settings Esc, and access when a bar segment is absent. Four- and five-tab
headers are checked at 320 and 440 px, plus a one-pixel width sweep for
font sizes 12–18 and spacing scales 1, 1.5, and 2. It rejects avoidable extra
rows and clipped labels, and checks new labels and live text-size changes.
These style fixtures change only the throwaway test process. Device choices
and hardware details keep long names within the panel. PSI prints its actual
value without a gauge ceiling. Wide-header and responsive-column cases check
that controls do not overlap and resizing preserves search and disclosures.
The suite also runs `cards-ui.qml` in its own offscreen process. It checks
all five activity/process layouts at 320 and 720 logical units, with 12 and
18 px base text, detail-button interaction, and state retention through
resizing. Repeated samples must preserve unchanged process groups and device
choices; one active change produces one update. The `D` shortcut opens
details when only some disclosures are open, then closes them together.
A real Store fixture changes from 250 ms to 10 s
and 60 s collection, verifying that minute history expires by timestamp
rather than by the new cadence's point count. Both load-patch modes run.

`qs-graph-ui.sh` checks shared time and fixed scales, synchronized GPU hover,
positive mirrored readouts (including bit units), blank gaps, real zero and
unknown values, visible-window summaries, bucket captions, summary click and
wheel controls, and per-resource settings/reset without hardware. It also
checks real Store settings reaching all three tabs, cards without a VRAM
percentage, retained support through failed polls, and hardware changes.
Hover readings occupy reserved summary space above the plot; CPU, Memory,
GPU and rate fixtures check that moving the pointer never changes block
height or covers a curve, including unknown and differently sized values.
At 320/440 px, font size 18 and spacing scales 1/1.5/2, axes, time labels, duration controls and readouts
stay inside the graph. Both load-patch modes run.

`qs-bar-ui.sh` runs 48 native cases in each load-patch mode. Two actual widgets
resolve the same synthetic service and histories, with no embedded Store or
extra collectors. Checks cover all values through 100%, estimated GPU prefixes,
compact rate extremes, horizontal/vertical styles, glyph/letter/no labels,
left-aligned horizontal readings, uniform vertical percentage fonts, Intel-only
estimate space, live font and spacing changes, fixed segment positions,
dynamic click-target registration, icon-only mode, scale tooltips/offline history, and hardware
loss/return. Settings tests use mouse and keyboard ordering, retained focus,
effective Drives switches, style/width/reset, and persistence through the real
Store, including QML's initial QVariantList settings. The panel is a small contract stand-in; these
offscreen cases establish routing, not layer-shell popup placement. Pure
tests exercise all 120 segment orders through fallback and hardware recovery.

`qs-actions-ui.sh` runs 19 cases in each load-patch mode against the real Network
and Drives tabs, shared action controls, panel dispatcher, and native Process
stdin. Its echo/failure helper never reads or writes the desktop clipboard or
opens a file manager. It covers mouse and A/arrow/Enter activation, staged Esc,
shell Tab, search handoff, adjacent selectors, literal MAC/IPv4/IPv6/path values,
selection across inventory changes, visible errors, helper exit/mismatch/timeout,
and stale responses. Process selection leaves action navigation; late feedback
preserves settings and other views. A usage refresh between mouse press and
release preserves the same Open button while updating its usage text and bar.
Access hints disable known inaccessible targets with a working hover explanation,
keyboard feedback, and recovery on the next inventory update. The explanation
wraps within a 320 px panel at font size 18 and spacing scale 2.
Layout cases use 320/440 px, font size 18 and spacing scales
1/1.5/2. Python tests cover actual helper validation and argv/stdin boundaries,
including bind-mount escapes, missing tools, permissions, unmounted targets,
and literal URI arguments through `uwsm-app --` with a direct-launch fallback.
Both disk inventory modes discard a cut final `df` row while retaining rows
whose terminating newline fits within the 65,536-character bound. Fixtures
cover a truncated target matching another mount, exact newline boundaries,
and UTF-8 payloads larger than a single argv argument permits.
Mount fields travel as ASCII base64 on stdin before jq decodes the complete
value, avoiding UTF-8 corruption in older jq raw-input readers.

`PanelActions.qml` keeps mount identity entries separate from a target-keyed
details map. Capacity and access updates therefore do not replace delegates.
`disk-info` reports read/search access hints with the existing mount polls;
the action helper still checks current mount membership and access at activation.

`qs-hardware-ui.sh` exercises Hardware,
settings, six-tab headers, and the real Store with a private sysfs tree. It
checks unit/pin persistence, missing pins, stopped versus unreadable fans,
critical colours in Fahrenheit, CPU/APU package labels, separate memory clocks,
per-battery units and real zero power, GPU Details routing and unavailable
cards, mouse/keyboard controls, shell Tab, and Hardware scrolling. Details
preserves automatic GPU choices; selecting another card explicitly saves the
shared choice. Tests also cover singular/plural counts, equal and single-core
temperature summaries, driver-name collisions after friendly-name mapping,
default system battery labels without a scope attribute, waiting versus
unavailable battery readings, and preservation of real zero values. Core
summaries, live battery updates, and narrow layouts with large text run in
both load-patch modes. Native
lifecycle cases cover two viewers sharing one helper, metadata-only startup,
no hidden polls, CPU-only package reads, late results after close/mode changes,
coalesced refreshes, visible failures, and recovery. Known unreadable packages
produce no CPU-only polls, remain diagnosable in Hardware, and recover after R
refreshes access. Layout cases use 320/440 px,
font size 18, and spacing scales 1/1.5/2. Python fixtures verify physical sensor
identity and ordering across hwmon/NVMe renumbering, numeric channel order,
converted thermistor readings, permission-denied counters, MSR/MMIO
deduplication, battery units, bounds, and actual AMD/NVIDIA clock helper paths.
FIFO inputs establish that inventory and GPU-owned hwmon discovery never read
telemetry. Pure tests cover elapsed-time rates, wraps/resets, source/range
changes, malformed values, and downgrade settings preservation.

`LocalAction.qml` captures each request in its own job. It serializes requests
within a panel action group; a device-context change drops the previous result
and lets its accepted desktop request finish before enabling another. Status
is panel-local and never belongs to the sampling Store. The tool timeout is
five seconds; a separate eight-second QML watchdog covers a stuck helper.

`qmllint.sh` needs qmllint and an Omarchy shell at
`${OMARCHY_PATH:-/usr/share/omarchy}/shell`; it skips when either is
missing. The regular CI runner therefore does not establish that the QML
passes this local gate. The harnesses under `tests/qs/` run from copied
trees and are excluded from qmllint.

Shell singletons use the `Commons` import namespace to avoid Qt type-name
collisions. CI checks this in plugin and harness QML. On Qt 6.12 and later,
qmllint's block-scope `var` style diagnostic is informational; other enabled
warnings still fail the gate.

### Documentation screenshots

Refresh the complete current screenshot set from the repository root:

```sh
bash tests/render-docs.sh
# Or write a review set without replacing the checked-in images:
bash tests/render-docs.sh /tmp/quadrant-docs
```

This runs the actual QML tabs, settings, bar widget, and graph components
against deterministic synthetic data. The tab renderer's documentation mode
uses `tests/qs/DocumentationFixture.qml` and does not instantiate the live
sampling Store. Invented process names, device identifiers, mount paths, and
documentation-range IP addresses keep the captures independent of the host.
Fixtures establish presentation, not driver support, hardware accuracy, or
power-management behavior.

The script refreshes all 17 files in `docs/screenshots/`: six resource panels,
settings, expanded process exploration, the bare README bar, five bar
comparisons, and three graph comparisons. It resets inherited
`QUADRANT_RENDER_*` options and fixes the timezone, scale, and font DPI.
The bare README bar is captured at 2× (516 × 116 px) and displayed at its
258 px logical width; the remaining captures use 1×.
Panel captures have 720 px of content plus 16 px margins, use the dark,
light, or monochrome palette fixtures, and fit their full content. The live
popup may scroll on a smaller monitor. Fonts, Qt/icon versions, and the
rendering environment can still affect antialiasing and raster output;
inspect the refreshed images before committing.
The archived proposals and original before-image under `docs/design/` are
historical evidence and are not refreshed.

The README artwork is a separate composition of the refreshed CPU, GPU,
Memory, and Hardware captures. Serve the repository locally:

```sh
python3 -m http.server 8768 --bind 127.0.0.1
```

Open [artwork/hero.html](artwork/hero.html) through that server, wait for all
images and fonts to load, and capture its 1920 × 2300 px viewport at 1× into
`preview.png`. The HTML frames the native screenshots without modifying
their UI text or measurements.

### Individual panel captures

`render.sh` needs Quickshell and Omarchy's shell imports. It uses Qt's
offscreen platform and temporary state to render `cpu`, `gpu`, `mem`,
`disk`, `net`, `hardware`, `settings`, or `bar`. Missing shell imports are an error,
not a skip. By default it samples this machine's real hardware. Use
`QUADRANT_RENDER_DOCUMENTATION=1` for synthetic panel/settings captures;
use `render-bar.sh` for synthetic bar captures. Do not publish live captures
without reviewing process names, addresses, and device identifiers.

Use `QUADRANT_RENDER_PALETTE=dark`, `light`, or `mono` for temporary palette
fixtures in the render process. `QUADRANT_RENDER_EXPANDED=1` opens the full
process view; `QUADRANT_RENDER_QUERY`, `QUADRANT_RENDER_WIDTH`, and
`QUADRANT_RENDER_HEIGHT` select a query and viewport for layout review.
`QT_SCALE_FACTOR=1.25` or `2` exercises device scaling. These do not change the installed theme.
The renderer uses isolated state and runtime directories, requires a fresh
capture, and rejects QML runtime errors before replacing the output file.
`python3 -m unittest tests.py.test_render -v` checks output preservation and
runtime isolation, and renders the real `bar` target in live and documentation
modes. The native bar case skips when Quickshell or Omarchy imports are absent;
the environment and error-handling cases run without either dependency.
When a session Wayland socket is
available, it links only that socket into the temporary runtime and retains
the desktop platform theme so process icons match the live panel. Without a
socket it disables the platform theme for headless rendering.

Use `QUADRANT_RENDER_HEADER=1` to include the shared panel header and
`QUADRANT_RENDER_FIT=1` to size the capture to its content. Set
`QUADRANT_RENDER_GPU_LAYOUT=aligned`,
`QUADRANT_RENDER_NETWORK_LAYOUT=mirrored`, or
`QUADRANT_RENDER_DISK_LAYOUT=mirrored` to render the corresponding setting
without writing shell configuration. For focused GPU cases, set
`QUADRANT_RENDER_GPU_FIXTURE=percent` or `bytes` for a card without a VRAM
denominator. The complete documentation fixture includes a dedicated GPU.

Set `QUADRANT_RENDER_ACTION_FIXTURE=1` for deterministic Network and Drives
captures with documentation-range addresses and literal mount-path characters.
The fixture supplies existing history data and never triggers clipboard or
launcher actions. `QUADRANT_RENDER_FIT=1 QUADRANT_RENDER_HEADER=1` includes the
panel header and fits the full content. These captures check presentation;
they do not establish access to a physical removable volume.

Set `QUADRANT_RENDER_WIDTH=752` for a 720 px content area at standard theme
spacing, including the harness's 16 px margins. The production panel scales
its preferred width with the theme and clamps to the monitor. Smaller render
widths exercise the single-column fallback.

Set `QUADRANT_RENDER_HARDWARE_FIXTURE=1` for synthetic Hardware sensors,
package watts, batteries, and GPU inventory. It avoids publishing real device
identifiers. `QUADRANT_RENDER_TEMPERATURE_UNIT=fahrenheit` selects display units
without saving configuration. For example:

```sh
QUADRANT_RENDER_WIDTH=752 QUADRANT_RENDER_HARDWARE_FIXTURE=1 QUADRANT_RENDER_HEADER=1 QUADRANT_RENDER_FIT=1 \
  bash tests/render.sh hardware /tmp/quadrant-hardware.png
```

### Matched graph comparisons

```sh
bash tests/render-graphs.sh /tmp/quadrant-graphs.png
QUADRANT_RENDER_PALETTE=light QUADRANT_RENDER_WIDTH=320 QUADRANT_RENDER_LONG=1 \
  QUADRANT_RENDER_PATTERN=gaps QUADRANT_RENDER_HOVER=1 \
  bash tests/render-graphs.sh /tmp/quadrant-graphs-hour.png
```

This renderer pairs the real GraphBlock in overlay and alternative layouts
using the same deterministic synthetic data from `tests/qs/graph-data.mjs`.
It needs shell imports and uses isolated runtime/state. `QUADRANT_RENDER_WIDTH`
is the outer panel width; each graph gets that minus 32 px of padding.
Patterns are `normal`, `gaps` (also missing values in one series), `low`, and
`unknown`. Palettes are `dark`, `light`, and `mono`; `QUADRANT_RENDER_LONG=1`
uses synthetic 10 s means across an hour. `QUADRANT_RENDER_HOVER=1` sets the
same hover time in every chart. Device scaling uses `QT_SCALE_FACTOR`.
It reports graph-block heights and rejects QML runtime errors.

See [Graph layouts](GRAPH_LAYOUTS.md) for the recorded comparisons and the
default decision. These fixtures verify presentation; they do not establish
GPU driver or power-management behavior.

### Bar comparisons and rendering cost

```sh
bash tests/render-bar.sh /tmp/quadrant-bar-trends.png
QUADRANT_RENDER_BAR_STYLE=text bash tests/render-bar.sh /tmp/quadrant-bar-text.png
QUADRANT_RENDER_VERTICAL=1 QUADRANT_RENDER_PALETTE=light \
  bash tests/render-bar.sh /tmp/quadrant-bar-vertical.png
python3 tests/bench-bar.py --baseline a260bf2 --cases baseline,text,graph,graph2
```

The bar renderer uses the actual widget with deterministic minute histories
from `BarFixture.qml`, one shared service, isolated runtime/state, and a panel
contract stand-in. It fails on QML runtime errors. Its defaults show all five
segments with Network first; `QUADRANT_RENDER_ORDER` accepts comma-separated
segment names. `QUADRANT_RENDER_SEGMENTS` controls membership and
`QUADRANT_RENDER_BARE=1` captures just one widget without the harness title.
`QUADRANT_RENDER_GRAPH_WIDTH`, `QUADRANT_RENDER_LABELS`,
`QUADRANT_RENDER_BAR_SIZE`, `QUADRANT_RENDER_GPU_VENDOR=intel|amd|nvidia`,
`QUADRANT_RENDER_MISSING_GPU=1`, and
`QUADRANT_RENDER_MONITORS=2` select additional cases. Use
`QUADRANT_RENDER_TAB=settings` for the settings view. Palettes and device
scaling use the same variables as the tab renderer. These are process-local
fixtures and never change installed settings.

The manifest uses the shell's existing `multiselect` array metadata for
`barOrder`; the installed shell does not generate plugin settings controls
from it. The full order is edited with panel arrows or the CLI. A future
schema-generated form needs an ordering control here, since removing a name
from this list appends it during normalization. Membership belongs to
`segments`. The schema description makes this distinction explicit.

The benchmark applies identical 1 Hz synthetic readings and samples the
Quickshell process's CPU time, RSS, and child count after a three-second warmup.
Cases are merged text, current text, one graph widget, and two graph widgets.
`--seconds` selects a 3–20 s observation window (default 10 s).
`QUADRANT_RENDER_BAR_REF` replaces only the widget source with the baseline
revision; both runs use the same current model and fixture. The measurement
therefore isolates bar rendering, including common harness cost, and does not
profile the complete sampler or idle power. See [Bar trends](BAR_TRENDS.md)
for recorded results, the local comparison budget, and limits.

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

For Hardware, check readable and denied RAPL counters, at least two packages,
hwmon renumbering, duplicate drivers, stopped/faulted fans, a laptop and a
peripheral battery, multi-GPU role routing, and a card without telemetry.
Verify memory clocks on physical AMD/NVIDIA hardware and GPU sleep behavior
on a suitable hybrid machine. Fixture coverage does not establish those
hardware properties. AMD runtime power-management work remains deferred.
