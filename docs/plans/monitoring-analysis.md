# Quadrant monitoring analysis

Status: Draft for iteration. Baseline: `66d425c`. Updated: 19 October 2026.

Quadrant's strongest opportunities are hardware selections that survive reboots,
more complete process investigation, and clearer access to existing history and
controls. Its current architecture and measurement detail provide a good base
for those changes.

The recommended initial scope is device identity, GPU polling behavior, and
process exploration. Panel polish and optional bar graphs follow those changes.
Additional sensors, battery details, and broader device overviews should follow
demonstrated use cases.

The [implementation plan](monitoring-improvements.md) defines the proposed work,
dependencies, acceptance criteria, and decisions still open for iteration.

## Current strengths

### Shared collection and bounded work

[Service.qml](../../Service.qml) creates the shared
[Store.qml](../../components/Store.qml). Widgets on multiple monitors report
which segments and tabs need data. The store shares the stream, history, and
pollers instead of assigning a complete collection stack to every monitor.

The streaming sampler uses Bash builtins in its tick path, while more expensive
process, network, GPU, and mount helpers run on demand. Preserve this separation
when adding richer views. Settings currently keep the underlying tab's viewer
state active, so opening settings can leave that tab's pollers running.

The service lookup has an embedded-store compatibility fallback. The guarantee
of one stream across monitors therefore depends on successful service
resolution, as described in [Development](../DEVELOPMENT.md).

### Measurement detail

Quadrant already offers useful diagnostic information beyond headline usage:

- CPU user, system, iowait, and steal series, with physical-core and P/E topology.
- CPU and memory pressure from Linux pressure stall information, or PSI.
- Memory composition, swap activity, and process memory using proportional set
  size, or PSS, where readable, with resident set size, or RSS, as a fallback.
- Dedicated GPU load and VRAM, integrated graphics on the CPU tab, and explicit
  handling of estimated or unavailable readings.
- Drive throughput, utilization, backing-device resolution, and mount capacity.
- Selected-interface network traffic, TCP process attribution, and an explicit
  Other traffic remainder.

These definitions and their limits are part of the product. UI changes should
preserve the contracts in [Measurements](../METRICS.md), especially the meaning
of CPU percentages, memory accounting, GPU estimates, and attribution scope.

### History and navigation

The last-minute view and persisted hour of 10-second mean buckets already
support investigating activity after it happens. Device tagging, stale GPU
handling, and graph gaps help avoid combining unrelated or missing samples.
An hour-view peak represents a bucket average and can be lower than a brief
minute-view spike.

Direct segment clicks, keyboard navigation, sortable process rows, stable row
order, and process sparklines are useful existing interactions. The primary
opportunity is to make these controls easier to discover and extend them when
someone needs to investigate beyond the top rows.

## Functional opportunities

### Stable hardware selection

Settings currently pin disks by a sysfs name such as `nvme0n1`, and GPUs by
`cardN`. Those names describe the current kernel enumeration. They can identify
different hardware after a reboot or a change in probe order.

Persist a disk identity derived from an appropriate `/dev/disk/by-id` entry and
a GPU identity derived from its PCI address when available. Resolve those
identities to current kernel names before collecting data. Apply this to both
dedicated-GPU selection and the integrated-GPU override.

Identity must also govern history and device-specific caches. Preserving a
selection while allowing its history to attach to a different device would
leave the underlying correctness problem unresolved. PCI identity follows a
slot, so changing the installed card in the same slot also needs a documented
history policy.

Migration needs particular care. A legacy kernel name can only be associated
with the hardware it resolves to when migration runs; an earlier association
cannot be reconstructed without saved identity evidence. Missing pinned
hardware should retain its selection and display a warning. Systems without
usable persistent IDs need an explicit fallback.

Relevant code: [settings](../../lib/settings.mjs),
[disk selection](../../lib/disk.mjs), [GPU selection](../../lib/gpu.mjs),
[disk inventory](../../scripts/disk-info), [GPU inventory](../../scripts/gpu-stats),
and [history](../../lib/history.mjs).

### GPU polling and idle power

The stream and the AMD GPU helper both read utilization, clocks, temperature,
and power attributes. They do not currently coordinate those reads through a
runtime power-management gate.

On some suspend-capable AMD systems, reading an awake card's telemetry can
extend its autosuspend timer. Frequent polling can consequently change the
idle behavior being measured. Reproduce this on suitable hardware before
choosing the exact policy; the effect depends on the driver and power settings.

If the risk reproduces, coordinate the stream, GPU helper, and any future sensor
reader around one per-device policy. Merely slowing one helper leaves other
readers able to keep the card active. A read window followed by a cooldown based
on the device's autosuspend delay is a candidate design.

Held readings need a measurement timestamp or equivalent freshness state.
Redrawing a cached value at the bar cadence must not turn it into a newly
measured history point. The display should distinguish a sleeping device,
temporarily held data, unavailable telemetry, and helper failure.

Relevant code: [stream](../../scripts/quadrant-stream),
[GPU helper](../../scripts/gpu-stats), [DRM reader](../../scripts/gpu-drm),
and [store](../../components/Store.qml).

### Process exploration and aggregation

The current process view intentionally exposes a small roster. `processCount`
ranges from 1 to 10. The helper selects between 16 and 32 candidates per metric,
and the model parser also caps each incoming list at 32 rows. The store then
collapses names and trims the visible result.

This has two consequences. Search limited to the existing rows would miss
processes outside the candidate lists. Group totals and counts computed after
candidate selection can also omit workers with the same display name.

A useful expanded view therefore needs collection and model changes as well as
a search field. Aggregate the complete eligible roster before presentation
trimming, preserve member identifiers for PID lookup, and distinguish source
coverage from the number of rows currently rendered. Groups continue to mean
matching normalized display names; they do not establish application ownership
or a process-tree relationship.

The existing name-collapsing function calculates a member count, but the mapped
store rows do not retain that count. Passing it through would make grouping
more visible, provided its scope is accurate. The current limited candidate
count must not be presented as the complete number of workers in an app.

Memory sizes should appear directly alongside percentages. Today the size and
PSS/RSS explanation are in the tooltip. A visible size answers common memory
questions with less interaction. Expanded collection must still distinguish
PSS, RSS, and groups containing a mixture; the current candidate-based PSS
selection is not an exhaustive PSS ranking of every process.

GPU rows can eventually expose process memory beside load when the existing
vendor data supports it. CPU, memory, disk I/O, and network have different
visibility and attribution limits, so expansion should declare coverage for
each metric rather than imply that every page can show every system process.

Relevant code: [process sampler](../../scripts/qproc.py),
[process model](../../lib/processes.mjs), [store](../../components/Store.qml),
[process list](../../components/ProcessList.qml),
and [memory tab](../../tabs/MemoryTab.qml).

### Initial readings and empty states

CPU and disk I/O rates need two counter snapshots. A cold first sample has no
rate, and the helper only accepts intervals of at least 400 ms. Use a measuring
state until a valid second reading arrives, with an initial follow-up around
500 ms if scheduling permits.

That follow-up should be bounded and asynchronous. It should not start a second
collector for another monitor or keep a process poller alive after its last
viewer closes. Genuine inactivity, no search match, restricted visibility, and
collection failure require distinct messages.

## UI opportunities

### Predictable grouping and scan order

Use a consistent sequence where the metric permits it: hardware identity,
current readings and trend, supporting details, then processes. Preserve the
hardware model, driver, topology, interface, and capacity context already
available in the hero sections.

Spacing and restrained group surfaces can separate topics more clearly than a
continuous sequence of rows. The first design pass should use existing theme
controls and spacing tokens. Check whether equal tab slots improve scan speed
within the available width, including the in-bar switch and settings control.

Core topology should remain readable on machines with many threads. The current
physical-core grid carries useful information; a ring for every logical thread
would consume more space without necessarily adding meaning.

Current references: [panel](../../Panel.qml), [hero](../../components/Hero.qml),
[core grid](../../components/CoreGrid.qml), and the
[tab screenshots](../USAGE.md#screenshots).

### Discoverable history and bar controls

The graph's time, average, and peak note is also a control, and uppercase `H`
changes the history window. A labelled `1 min` / `1 hour` switch would expose
that interaction directly while keeping the shortcut and synchronized graphs.
Changing sampling cadence should continue to preserve the chosen duration.

The panel's `in bar` control refers to the active resource, but the wording is
easy to miss. Give it a resource-specific accessible label or tooltip, such as
`Show Network in bar`. Keep panel availability independent of bar visibility.

Relevant code: [graph block](../../components/GraphBlock.qml),
[history graph](../../components/HistoryGraph.qml), and [panel](../../Panel.qml).

### Graph choices and semantic consistency

Separate, aligned GPU load and VRAM graphs may make their relationship easier
to read than the current overlay. A mirrored read/write or upload/download
graph may help distinguish direction. Compare those alternatives against their
extra height, axis clarity, hover behavior, and usefulness at low activity.

Every series still needs a label, unit, and time reference. Bidirectional
graphs need explicit direction labels and a shared scale. Preserve graph gaps,
the hour view's averaging semantics, and visible explanations for estimates.

Memory deserves a specific clarity pass. The used-memory ring and composition
bar use different calculations. Explain that distinction near the visual,
keep composition colours aligned with their legend, and keep swap and
compressed-memory details outside any implied physical-RAM sum. Label the
pressure ring's visual range of 0–25% while continuing to print the actual PSI
percentage.

### Optional bar trends and ordering

The current bar pairs labels with values, reserves width to avoid moving
neighboring widgets, and supports vertical bars. Small history graphs could add
at-a-glance trend context, but they also consume scarce bar space.

Start with text and optional graph-plus-text modes. Reuse the store's existing
history, keep text as the default, and choose an explicit graph width. Reserve
the entire selected style's footprint so changing digits or rates does not
move the rest of the bar.

Segment order currently follows the canonical order in the settings helpers.
Allowing an explicit order requires changes to normalization, toggles, and the
GPU-to-Drives fallback. Reordering must survive an enable/disable cycle and
temporary hardware absence.

Relevant code: [bar widget](../../BarWidget.qml),
[settings model](../../lib/settings.mjs),
and [settings view](../../components/SettingsView.qml).

### Actions and keyboard access

Copying a local address or MAC and opening a mounted volume are small, useful
extensions of information already displayed. Provide success or failure
feedback and keyboard access. Pass copied values through stdin and paths as
arguments rather than interpolating them into shell commands.

Process search must coexist with existing panel shortcuts. `/` should focus
search, typing must stay in the field, and Esc should clear the query before
leaving search. Preserve the shell's ownership of Tab navigation.

## Additional hardware coverage

### Sensors and temperature units

Quadrant deliberately restricts CPU and NVMe temperature sources instead of
substituting an unrelated sensor. A broader sensor inventory could add fans,
motherboard temperatures, and additional devices while retaining that
discipline.

Identify each sensor by its owning physical device, driver, and channel, not
only `hwmonN` or the driver name. Multiple drives and DIMMs can share a driver.
Keep raw values in a canonical unit and convert Celsius/Fahrenheit at display
time. Reuse any GPU read policy when a sensor belongs to that GPU.

### CPU package power and GPU memory clocks

CPU package watts can help explain heat and energy use when readable counters
exist. Energy-counter sources need elapsed-time calculations, wrap handling,
and reset detection. Missing permissions must produce an unavailable value.
An APU's graphics-reported power may represent the entire package and should
not be labelled as dedicated GPU power.

A GPU memory-clock row can help investigate excessive idle power on some
multi-monitor or high-refresh setups. Support it only when the driver exposes
an identifiable memory-clock source; do not infer it from core clock.

### Battery and multiple GPUs

Battery health, charge cycles, power, and peripheral charge can be useful on
laptops. Their value depends on what the shell already exposes and whether a
dedicated diagnostic view is needed. Missing batteries should not leave empty
navigation, and multiple supplies need a deliberate selection or aggregation
policy.

Quadrant already selects among dedicated GPUs and shows integrated graphics on
CPU. A page showing every GPU would help some workloads but could add polling
and visual noise. Establish the workflow first, then decide whether it needs
an overview, multiple bar entries, or just a clearer selector. Inventory should
remain visible even when a card's telemetry tool is unavailable.

## Compatibility and maintenance

### Palette imports

Many QML files import QtQuick and the shell's palette with unqualified `Color`
references. Test whether a newer Qt version introduces a name collision.
Treat this as a compatibility hypothesis until an isolated reproduction
establishes the affected versions. A namespaced shell import is a possible
fix; broad edits should follow that reproduction.

### Keep the existing architecture until measurements justify change

No proposed feature currently requires replacing the shared store or streaming
sampler. Measure closed-panel, compact-panel, and expanded-view cost before
considering a different implementation language or bundled native binaries.
Account for packaging, architecture support, lifecycle behavior, and
maintenance as well as CPU and memory cost.

Process exploration should preserve plain-text rendering of process names,
bounded payloads, and the existing PID-plus-start-time handling in the process
rate sampler. Search-field behavior should be checked for unintended clipboard
reads, including while the field exists but is hidden.

## Priority assessment

| Opportunity | User value | Relative scope | Proposed timing |
| --- | --- | --- | --- |
| Persistent device identity | Correct selections and history across reboots | Medium | First |
| GPU idle polling policy | Avoid changing idle behavior while monitoring | Investigate, then medium if needed | First |
| Palette import compatibility | Preserve usable rendering on affected Qt versions | Small if reproduced | First |
| Expanded process exploration | Find activity outside the top rows | Large | Next |
| Visible sizes, counts, and measuring states | Explain the values already shown | Small to medium, with aggregation dependencies | With process work |
| Clearer grouping and history controls | Faster scanning and discovery | Medium | After collection foundations |
| Optional bar graphs and ordering | Show trends without opening the panel | Medium | Separate optional change |
| Copy and open actions | Reduce routine interaction steps | Small | Follow-up |
| Sensor inventory and readable package power | Broaden thermal and energy diagnostics | Medium to large | Based on hardware need |
| Battery and multi-GPU overview | Support additional laptop and workstation workflows | Large | Conditional |

Relative scope describes implementation complexity, not a calendar estimate.
User benefit and hardware coverage should determine which later items proceed.

## Features to defer

Keep the first iteration focused. A full per-section visibility editor, every
possible bar style, special filesystem attribution, battery coverage, and
multiple GPU bar entries can wait for clearer demand.

Public-IP lookup introduces an external request into a local monitor. If that
workflow is requested, make the lookup an explicit action or opt-in and keep
local networking useful without it.

## Decisions for iteration

The [plan's decision register](monitoring-improvements.md#decisions-for-iteration)
collects the choices that affect implementation. The most consequential are the
device-identity settings format, the first process-expansion scope, and whether
bar trends belong in the initial UI work.
