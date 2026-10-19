# Quadrant monitoring improvement plan

Status: Draft for iteration. Baseline: `66d425c`. Updated: 19 October 2026.

Improve the reliability of hardware selection and collection first, then make
process investigation and existing controls easier to use. Keep Quadrant's
shared service, diagnostic detail, compact default bar, and Omarchy theme
integration throughout the work.

The [analysis](monitoring-analysis.md) explains the current behavior and the
tradeoffs behind these priorities. This plan specifies the proposed changes,
acceptance criteria, validation, and decisions still open for iteration. All
work items below are pending.

## Goals

- Keep explicit hardware selections attached to the intended device across
  reboots and enumeration changes.
- Collect GPU telemetry without unnecessarily preventing idle power states.
- Let users investigate eligible processes beyond the current top-row limits.
- Make grouped values, memory sizes, history controls, and unavailable readings
  easier to understand.
- Add visual options without compromising bar stability or multi-monitor sharing.

Preserve the measurement contracts in [Measurements](../METRICS.md), including
network attribution limits, total process I/O scope, PSS/RSS distinctions,
estimated GPU readings, history gaps, and hour-view bucket averages.

## Proposed delivery order

| Phase | Deliverable | Dependency | Initial scope |
| --- | --- | --- | --- |
| 1 | Persistent device identity and collection reliability | Settings and history design | Recommended |
| 2 | Process exploration and clearer process values | Expanded collection contract | Recommended |
| 3 | Panel readability and optional bar trends | Stable identity and collection semantics | Panel controls recommended; bar trends optional |
| 4 | Small actions and additional hardware coverage | Relevant use case and hardware | Follow-up |

Keep individual changes reviewable. Device identity, power management, process
collection, process UI, panel controls, and bar styles should have separate
implementation boundaries even when delivered in the same phase.

## Phase 1 Device identity and collection reliability

### Persistent device identities

**Outcome:** a pinned drive or GPU remains selected when the kernel assigns it
a different name, and its saved history follows the same identity policy.

Implementation outline:

1. Add stable identities to the disk and GPU inventories. Prefer an appropriate
   whole-disk by-id name for disks and PCI identity for GPUs. Retain current
   kernel names as resolved runtime values and useful secondary labels.
2. Define a typed, validated settings representation for stable selection.
   Cover dedicated GPUs, integrated-GPU overrides, and disks. Keep `auto` as a
   separate selection policy rather than resolving and persisting it as a pin.
3. Migrate legacy names only when inventory can resolve them. Preserve an
   unresolved legacy selection and explain it rather than silently choosing
   different hardware. Do not claim to recover an association from a previous
   boot without evidence.
4. Resolve settings through inventory before constructing helper commands.
   Stable IDs are lookup keys, not arbitrary filesystem paths or command input.
5. Apply the identity policy to history, per-device caches, and GPU rate state.
   Define behavior for replacement hardware in the same PCI slot and for disks
   with missing or duplicate IDs.
6. Refresh inventory deliberately on `R` so device changes can be discovered
   without a shell restart. Preserve warnings for missing pinned hardware.

Primary files: [settings](../../lib/settings.mjs),
[identity helpers](../../lib/identity.mjs), [disk model](../../lib/disk.mjs),
[GPU model](../../lib/gpu.mjs), [history](../../lib/history.mjs),
[store](../../components/Store.qml), [disk helper](../../scripts/disk-info),
[GPU helper](../../scripts/gpu-stats), and [manifest](../../manifest.json).

Acceptance criteria:

- Renaming `cardN` or swapping disk enumeration does not change a stable pin's
  selected physical target.
- An absent target keeps its pin and produces a useful warning; reappearance
  resolves it again.
- Legacy typed and stringified settings still load. Unknown unrelated settings
  remain preserved, and saving uses the established typed settings path.
- Automatic selection and the GPU-to-Drives fallback continue to behave as
  documented.
- Old history is adopted only when its identity can be matched safely. Device
  changes never combine unrelated histories or inherit another device's deltas.
- Inventory refresh updates selectors without resetting unrelated metrics.
- Devices without a usable persistent identity follow a documented fallback.

Validation: add fixtures for enumeration swaps, duplicate IDs, missing devices,
legacy settings, and history migration. Exercise one real reboot or equivalent
enumeration change on suitable hardware before claiming persistence support.

### GPU runtime power management

**Outcome:** monitoring permits supported idle GPU suspend and reports the age
of held readings accurately.

Implementation outline:

1. Establish a baseline on a suspend-capable AMD system. Record power control,
   runtime status, autosuspend delay, relevant reader activity, and transition
   timing with the monitor active and inactive.
2. Inventory all reads that may reach the same GPU, including stream, helper,
   integrated-GPU, and future sensor paths. Determine which affect suspend on
   the target driver before choosing the gate.
3. Coordinate reads per device across processes and monitors. A single
   process-local cooldown is insufficient if another reader remains active.
4. If needed, batch reads into a short window followed by a cooldown derived
   from the autosuspend delay plus a margin. Keep a sensible policy when power
   management is disabled or metadata is unavailable.
5. Include measurement time and freshness in the sample contract. Separate
   sleeping, held, stale, unavailable, and failed states as needed by the UI.
6. Feed history from fresh measurements. Held values may remain visible, but
   must not create fabricated new measurements on each stream tick.

Primary files: [stream](../../scripts/quadrant-stream),
[GPU helper](../../scripts/gpu-stats), [DRM reader](../../scripts/gpu-drm),
[GPU model](../../lib/gpu.mjs), [store](../../components/Store.qml),
and [history model](../../lib/history.mjs).

Acceptance criteria:

- A target GPU that can suspend with monitoring inactive can still suspend
  while monitored under the tested idle conditions.
- A GPU workload produces useful updated readings after activity resumes.
- Two monitors and multiple active views share the same device policy.
- Held readings have accurate freshness, and history reflects fresh samples
  and gaps rather than redraw cadence.
- Missing power metadata, disabled runtime PM, and helper errors remain
  understandable and do not break unrelated metrics.
- Changes preserve the stream's no-fork tick budget unless a deliberate,
  measured design change is accepted.

Validation: use deterministic clock and power-state fixtures for the policy,
then test real suspend and resume behavior. Compare all relevant readers;
stopping only one helper does not establish that collection is coordinated.

### Palette import compatibility

**Outcome:** supported Qt versions consistently resolve the shell's palette.

Build a minimal QML reproduction with the same imports and representative
palette references. Include newer Qt versions, including 6.12 where supported.
If a collision reproduces, qualify the shell palette import and apply the fix
consistently to affected files.

Acceptance criteria:

- Palette references resolve without undefined-colour errors on the affected
  version and an established supported version.
- Dark, light, and monochrome renders retain legible text and theme colours.
- The change remains confined to import resolution and any necessary checks.

## Phase 2 Process exploration

### Define the expanded collection contract

**Outcome:** the UI can search a complete eligible roster while keeping normal
top-process mode inexpensive and honest about coverage.

Implementation outline:

1. Add an explicit expanded-data request to viewer state. The shared store
   should collect expanded data only while at least one viewer requires it.
2. Specify coverage separately for CPU, memory, disk I/O, network, and GPU.
   Start with CPU, memory, and disk I/O; extend network and GPU through their
   own attribution contracts when ready. Describe scope in the UI.
3. Separate eligible source rows from presentation rows. Search and aggregation
   must occur before a rendering or transport cap can discard the match.
4. Aggregate matching normalized names before selecting the top groups.
   Preserve member identifiers for PID lookup and an accurate group count.
   Cache expensive naming details by PID and start time where appropriate.
5. Define bounds for serialized bytes and rendered rows, with explicit
   truncation or coverage metadata. A safety limit must not silently make
   search appear exhaustive when it is incomplete.
6. Define memory accounting for expanded rows. Preserve PSS/RSS information and
   identify mixed groups. Decide whether expanded collection reads PSS
   exhaustively or offers a clearly labelled cheaper mode.
7. Preserve existing CPU normalization, I/O scope, permission handling, and
   rate-sampler protection against PID reuse. Grouping by name does not imply
   application ownership or a process tree.

Primary files: [process sampler](../../scripts/qproc.py),
[wrapper](../../scripts/process-sample), [process model](../../lib/processes.mjs),
[store](../../components/Store.qml), and, for later network scope,
[network helper](../../scripts/process-net).

Acceptance criteria:

- A matching eligible process outside the current 32-candidate ceiling can be
  found through expanded search.
- Groups include every eligible matching member covered by the selected mode;
  truncation and permission limits remain explicit.
- PID search finds the group containing that PID and can identify the matching
  member without implying that the group's representative PID is every worker.
- Compact mode retains its row limit and low collection cost.
- Mixed PSS/RSS groups and unavailable fields have accurate labels.
- Expanded collection stops after the last requesting viewer closes or leaves
  the applicable view. Two monitors do not duplicate the collection stack.
- A bounded payload failure or partial result does not replace valid readings
  with a fabricated zero.

### Build the process investigation view

**Outcome:** users can move from top consumers to a specific process without
leaving the panel.

Add `Show all` and `Show less`, a search field, visible grouped counts, and
memory sizes beside percentages. Preserve app icons, sorting, compact-mode
stable order, and row sparklines. Decide whether the expanded list uses stable
or value order while preserving the keyboard cursor's logical target.

Route text input to the search field before panel shortcuts. `/` focuses it;
Esc clears a nonempty query before leaving search. Keep the shell's meaning
of Tab and the existing panel navigation when text input is inactive.

Primary files: [process list](../../components/ProcessList.qml),
[panel](../../Panel.qml), [CPU tab](../../tabs/CpuTab.qml),
[memory tab](../../tabs/MemoryTab.qml), and [disk tab](../../tabs/DiskTab.qml).

Acceptance criteria:

- Keyboard and pointer workflows both support entering, clearing, and leaving
  search. Process names remain plain text.
- Measuring, no activity, no match, restricted visibility, and failure have
  distinct messages.
- Memory size, percentage, count, and metric headers remain readable with long
  names and narrow panels.
- Filtering and reordering do not unexpectedly move a selected process to a
  different logical target.
- Expanded rows remain bounded or virtualized, with visible result counts and
  coverage when the full roster exceeds the rendered portion.
- Creating or hiding the search field does not cause unintended clipboard
  reads; any supported paste behavior requires a deliberate user action.

### Improve initial process readings

Use a measuring state for cold CPU and I/O rates. Schedule a bounded second
sample around 500 ms after opening, respecting the existing 400 ms minimum
valid interval, rather than waiting only for the normal panel cadence.

Acceptance criteria:

- The first cold sample is not labelled as genuine inactivity.
- A valid second sample produces rates without blocking the UI.
- Closing the last applicable viewer cancels unnecessary follow-up work.
- Opening multiple viewers does not start duplicate warm-up loops.
- Counter resets, PID reuse, and long gaps still invalidate inappropriate rates.

## Phase 3 Panel clarity and optional bar trends

### Expose existing controls and organize the panel

Use a common scan order: hardware identity, current readings and trend,
supporting details, then processes. Prototype spacing and restrained surfaces
with existing theme tokens. Compare equal-width tabs against the available
header width before adopting them.

Add explicit `1 min` / `1 hour` controls while retaining uppercase `H` and the
existing synchronized window behavior. Give the in-bar switch an accessible
resource-specific label or tooltip.

Primary files: [panel](../../Panel.qml), [hero](../../components/Hero.qml),
[section header](../../components/SectionHeader.qml),
[graph block](../../components/GraphBlock.qml), and
[settings view](../../components/SettingsView.qml).

Acceptance criteria:

- Each graph's duration can be changed through a labelled control and keyboard
  shortcut. Changing refresh cadence preserves the duration.
- Hardware identity, values, units, legend, and supporting details have a clear
  hierarchy in dark, light, and monochrome themes.
- The pressure ring identifies its 0–25% visual scale while printing actual PSI.
  Memory composition and used-memory definitions are explained accurately.
- Panel navigation stays usable without horizontal clipping at supported scale
  factors and panel widths.
- Settings and controls remain accessible when a device or bar segment is absent.

### Evaluate graph alternatives

Prototype aligned GPU load/VRAM plots and mirrored network/disk plots as
separate options. Compare clarity with the current overlays using the same
data, width, and time span. Choose defaults after reviewing the height and
readability tradeoff.

Acceptance criteria:

- Direction, series names, units, axes, hover readings, and time alignment
  remain explicit.
- Gaps and stale readings retain their meaning across layouts.
- Low activity does not fill the chart misleadingly through unconstrained
  autoscaling.
- Average and peak labels still describe the displayed series and bucket
  semantics.

### Add optional bar trends and ordering

Start with text and graph-plus-text styles. Keep text as the default and reuse
existing shared history. Add a bounded graph width and an ordered segment
setting with simple movement controls.

Update normalization, enable/disable actions, and fallback resolution together.
Keep configured order distinct from the currently available hardware, so a
temporarily missing device does not erase the user's preference.

Primary files: [bar widget](../../BarWidget.qml),
[settings model](../../lib/settings.mjs),
[settings view](../../components/SettingsView.qml),
[manifest](../../manifest.json), and [store](../../components/Store.qml).

Acceptance criteria:

- Digits, units, and graph updates do not shift neighboring bar widgets.
- The selected order survives toggles, restarts, and temporary device absence.
- GPU-to-Drives substitution preserves a documented position without duplicate
  disk entries or rewriting the configured intent.
- Vertical bars fit the selected style and keep rates readable.
- Two monitors reuse existing collection and history.
- Existing settings without style or order fields retain their current behavior.

Defer additional ring-only, text-plus-ring, and per-device bar styles until
these two modes establish the need and maintenance cost.

## Phase 4 Actions and hardware coverage

### Copy addresses and open mounts

Make displayed local IP addresses and MAC values copyable, and allow opening a
mounted volume in the file manager. Supply keyboard access and clear feedback.

Acceptance criteria:

- Copied text matches the displayed value; failures remain visible.
- Values reach clipboard tools through stdin, and paths reach launchers as
  arguments. Spaces and special characters do not change command meaning.
- Unmounted or inaccessible paths have useful feedback.
- Ordinary clicks on adjacent selectors retain their existing meaning.

### Sensor inventory and temperature units

Add sensor discovery keyed by owning device, driver, and channel. Begin with a
detail view for additional temperatures and fans; evaluate selected bar sensors
separately. Convert units at display time while preserving canonical samples.

Acceptance criteria:

- Duplicate driver names and hwmon renumbering do not change a pinned sensor.
- Missing values remain unavailable. A stopped fan may display a measured
  zero RPM distinctly from an unreadable channel.
- CPU, GPU, drive, and board labels identify the measured device accurately.
- GPU-owned sensors honor the shared power-management policy.
- Temperature conversion preserves thresholds and graph interpretation.

### Package power and memory clocks

Add CPU package watts only where counters are readable, with elapsed-time,
wrap, reset, and unit handling. Treat APU package power as CPU/package data.
Add GPU memory clock only when a driver exposes an identifiable source.

Acceptance criteria:

- Missing permissions or unsupported counters do not produce zero watts.
- Counter wrap/reset and malformed units cannot create implausible spikes.
- Package and GPU readings avoid presenting the same package total as separate
  independent consumption figures.
- Memory clock has its own source and label rather than a core-clock estimate.

### Conditional battery and GPU overview work

Before implementation, identify the task the current shell and GPU selector do
not satisfy. For battery, define whether the view covers health, cycles, charge
history, power, peripherals, or some subset. For multiple GPUs, compare an
overview with improving the existing selector.

Acceptance criteria for any selected scope:

- Missing hardware does not leave an empty tab.
- Multiple devices have an explicit selection or aggregation rule.
- Detected hardware remains identifiable when telemetry is unavailable.
- Hidden detail views do not force unnecessary polling of every device.

## Validation strategy

Use the existing [development checks](../DEVELOPMENT.md#checks) as the starting
point. Add tests for changed contracts and meaningful failure cases; avoid
duplicating rendering details in implementation-shaped tests.

| Area | Required checks when that area changes |
| --- | --- |
| Settings and identity | Legacy/typed settings, absent and duplicate IDs, automatic selection, enumeration changes, pin recovery |
| History | Identity migration, replacement devices, stale/held samples, gaps, bucket averages, reload across restart |
| Process collection | More than 32 candidates, many same-name workers, PID reuse, permission limits, PSS/RSS mixtures, search before trimming |
| Viewer lifecycle | Two monitors, expanded mode acquisition/release, panel close, settings open, warm-up cancellation, helper failure |
| UI | Keyboard focus, long names, narrow widths, dark/light/monochrome, horizontal/vertical bar, 1x/1.25x/2x scaling |
| Hardware | AMD runtime suspend, NVIDIA tool failure, Intel measured/estimated/unavailable cases, integrated-only and hybrid systems |
| System variants | IPv6-only network, no swap, missing sensors, LUKS/LVM/RAID, multiple mounts, supported awk variants |

Run relevant Node and Python suites, script checks, Quickshell smoke checks,
qmllint, and plugin validation according to the changed area. Render comparison
screenshots using the existing harness and inspect QML diagnostics. Confirm
when a gate actually ran instead of treating a prerequisite skip as a pass.

For performance, compare the same machine, workload, cadence, and observation
window across closed-panel, compact-panel, expanded-process, graph-bar, and
multiple-monitor scenarios. Record CPU time, resident memory, child-process
count, collection duration, sample gaps, and idle power-state behavior where
available. Set an acceptable regression budget after establishing a baseline;
do not infer one from a different machine or sampler implementation.

## Decisions for iteration

| Decision | Proposed starting position | Alternative or unresolved detail |
| --- | --- | --- |
| First delivery scope | Phases 1 and 2, with history-control clarity next | Separate small UI controls from the larger process work if preferred |
| Stable selection settings | Keep current automatic-selection semantics and migrate explicit pins | Choose versioned existing values versus new stable-ID fields before coding |
| Hardware replacement | Require identity compatibility before adopting history | Define PCI slot plus device fingerprint and missing-ID fallbacks |
| Expanded process scope | CPU, memory, and disk I/O first | Network and GPU need their own coverage contracts |
| Memory accounting | Preserve precise PSS/RSS labels and explicit mixed groups | Decide exhaustive PSS collection versus a cheaper expanded mode after profiling |
| Expanded ordering | Preserve the selected logical target while values update | Stable roster versus descending-value order remains a UI choice |
| Query lifetime | Keep query/expansion state in the active panel session | Decide persistence across tabs and close/reopen without forcing hidden collection |
| Graph layout | Compare alternatives using matched data before changing defaults | Overlay, aligned, and mirrored views trade height for separation |
| Bar trends | Optional graph-plus-text, with text remaining default | Whether to include this in the first UI delivery |
| Sensor presentation | Detail inventory first | Separate Sensors tab versus sections on existing tabs |
| Battery and GPU overview | Wait for a concrete workflow | Determine target hardware and overlap with shell features |

## Completion criteria

Each implemented change should include its relevant contract tests, runtime
checks, documentation updates, and any necessary settings migration. Update
[Usage](../USAGE.md), [Settings](../SETTINGS.md),
[Measurements](../METRICS.md), [Development](../DEVELOPMENT.md), and the
[changelog](../../CHANGELOG.md) when behavior changes. Refresh screenshots when
the visible UI changes materially.

This planning branch contains documentation only. Implementation work begins
after the scope and outstanding design choices have been refined.
