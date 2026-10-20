# Changelog

## Unreleased

### Added

- Conditional Hardware diagnostics: device-owned temperature/fan inventory,
  stable sensor pins, Celsius/Fahrenheit across panels, readable CPU package
  watts, and individual system/peripheral battery health, capacity, cycles,
  and power. A measured stopped fan remains distinct from unavailable input.
- Separate AMD/NVIDIA memory clocks and a metadata-only GPU overview with
  Details actions, including detected cards without telemetry. Live hardware
  reads are shared across monitors and stop with the last relevant viewer.
- Copy buttons for collected local IPv4/IPv6 and MAC values, plus Open actions
  for mounted volumes. A/arrow/Enter navigation keeps shell Tab and staged Esc;
  success, missing tools, inaccessible/unmounted paths, and timeouts have visible
  feedback. Copied bytes use stdin and mount URIs use literal argument lists.
  Known inaccessible volumes have disabled buttons with explanatory tooltips;
  file-manager requests use `uwsm-app` when available.
- Optional graph-plus-text bar with bounded minute trends from shared history;
  text remains the default. Segment switches now have ordering arrows, and
  disabled or absent devices retain their saved positions.
- Optional aligned GPU and mirrored Network/Drives plots, saved independently
  in Panel graphs settings. Overlays remain the default. Each series has a
  named average/peak summary; hour plots label their 10 s mean buckets.
- Labelled `1 min` / `1 hour` controls switch the panel's graphs together,
  retaining uppercase `H`, summary clicks, and the graph wheel. Summaries
  name their series, and missing readings remain excluded.
- Equal tab slots wrap on narrow panels, device choices keep full names in
  tooltips, and the bar switch names its resource. Hardware details adapt to
  narrow widths; memory explains used/composition accounting.

### Changed

- Prefer a wider, theme-scaled 720-unit panel with graphs and details beside
  processes. Header controls share a row when they fit; narrow screens stack
  the same content without resetting search, selection or disclosures.
- CPU, GPU and Memory show compact overview values; Memory pressure is numeric
  without an empty gauge. Hardware groups sensors by device, uses a core
  temperature grid and keeps battery/power/fan details alongside it. Repeated
  device paths and measurement explanations expand on demand; `D` toggles
  the current tab's visible details without taking over the shell's Tab key.
- Network addresses appear as individual Copy rows in the Interface section,
  replacing the first two addresses previously shown in the hero summary.
- Bar styles reserve fixed slots through 100%, estimated GPU prefixes, and
  compact network rate changes. Vertical trends fit within the strip, with
  complete download/upload rates beneath them. Drives fallback follows its
  saved position, after Memory in the default order, without duplicate cells.
- Graphs show a time axis ending at the last sample's local clock time,
  explicit floor labels, and timestamped hover readings in reserved summary
  space above the plot. Hovering leaves the curves visible and the layout steady.
- Network and Drives share a scale across both series with a minimum 1 KiB/s
  ceiling. At standard style and 408 px graph width, default graph blocks grow
  from 162 to 182 px for CPU/Memory and from 162 to 196 px for two-series
  GPU/Network/Drives. Narrow or larger-text layouts can reserve more readout space.

### Fixed

- Hardware accepts converted thermistor temperatures and orders numbered
  channels naturally, with chip order stable across hwmon renumbering.
- CPU-only package polling skips unreadable counters, whose access errors
  remain visible in Hardware. R refreshes access; incomplete package totals
  stay hidden. GPU Details preserves automatic selection, with an explicit
  Select action for changing the shared card. Battery labels default to
  system scope without `scope=Device`, and counts use singular wording.
- Mount paths retain up to 4096 characters, including spaces, backslashes and
  trailing whitespace, replacing the previous 128-character display limit.
- Horizontal bar values stay beside their own labels and trends within fixed
  slots. Only Intel reserves the GPU estimate prefix, and visible vertical
  percentage values share a font size without shrinking AMD/NVIDIA needlessly.
- Compact network rates promote before rounding exceeds their reserved width.
  Typed QML list settings are read correctly during initial object creation.
  The Drives switch can enable an explicit segment when GPU is disabled.
- Unknown graph values remain gaps instead of becoming zero. Incomplete CPU
  stacks are unknown, and hovering a long collection gap shows no old reading.
- Cards without a VRAM percentage show only the busy series. A retained
  percentage measurement keeps the VRAM plot through a failed poll, with
  missing current values shown as `--`.
- Changing stream cadence preserves the existing minute history until its
  samples age out, instead of discarding them to fit the slower point count.
- GPU and disk pins use persistent hardware identities when available,
  with legacy settings and best-effort downgrade selection preserved. `R`
  refreshes GPU inventory as well as drives. Renumbering keeps matching
  history; previous-boot name-only history and in-flight readings from a
  different device are discarded.
- Failed GPU inventory refreshes keep the last successful topology and
  readings while showing the error. Changing a device policy to `auto` or
  integrated graphics to `none` clears the pin without a second CLI command.
- Shell palette and style references are namespaced for Qt 6.12. The
  offscreen renderer and local QML lint gate work with the current Qt tools.
  Captures retain the desktop icon theme when a session socket is available.
- Process helpers stream payloads instead of passing them as command-line
  arguments, so large TCP socket lists no longer fail at the argument-size
  limit. Samples above the 1 MiB envelope limit show an explicit coverage
  error; incomplete socket counters never become a rate baseline.
- A cold Drives process sample shows its measuring state. Settings help uses
  the visible tab count and names Esc for closing settings. The bar reserves
  enough space for 100%, and documentation describes the Drives fallback's
  position after Memory.
- AMD cards that share a PCI device ID with other models are named
  exactly: an RX 9070 XT no longer shows as "Radeon RX 9070", nor an RX
  7900 XTX as "7900 XT". The name comes from libdrm's `amdgpu.ids` by
  device ID and revision; without a match the panel lists every model
  that shares the ID instead of the first one.
  ([#24](https://github.com/BVisagie/omarchy-quadrant/issues/24))

## 1.0.0 — 2026-10-02

A rebuilt system monitor with a shared data store, saved history, and
updated tabs.

### Fixed

- The stream really forks nothing per tick; a killed sampler's FIFO
  directory is swept at the next start and SIGTERM cleans up.
- Per-core usage is keyed by cpu id (offline cores no longer shift the
  grid); physical cores are counted per package.
- DRM engine capacity is honoured; idle residency is read for the selected
  card only; a card change clears everything sampled for the old one; the
  stream's sysfs busy wins over the DRM overlay.
- Settings persist typed through the shell's writer instead of as quoted
  strings; old entries are migrated on first save; `omarchy bar set` takes
  effect at once (no more stale local copies).
- The process list no longer empties for good when `panelIntervalMs` is
  long; per-process CPU is a share of the machine, and memory uses PSS
  where readable, with RSS as a fallback.
- Muted text and graph colours follow the theme on light and dark themes.
- `barPalette: vivid` does what the manifest promised.
- History follows one interface and one disk.

### Added

- One store per shell (service kind): a two-monitor desktop runs one
  sampler, not two.
- One hour of persisted history per graph, with graph breaks for gaps
  beyond the cadence-dependent threshold.
- Per-process GPU rows (DRM fdinfo / NVIDIA compute apps), per-process
  disk I/O for readable processes across devices, and sparklines on CPU,
  Memory, Drives, and attributed Network rows.
- Labelled time graphs with average and peak and a 60 s / 1 h toggle;
  memory framed on its own range; hover readout.
- Network identity (type, link speed, addresses), an interface picker, a
  bits/bytes rate unit; a disk picker with model names; mount usage bars.
- Bar: per-segment click targets and tooltips, right-click btop, wheel
  tab switching, hysteresis on hot colouring, a heat palette.
- Panel: settings view for every manifest key, keyboard cursor over
  process rows, typed IPC with `settings`, `setBarSegment` and `set`.
- Tests: python helpers against fake `/proc` and `/sys`, a stream
  fork-count test, a headless store smoke test, an offscreen tab renderer,
  a qmllint gate.

### Changed

- Requires Omarchy 4.0.3 or later.
- `Model.js` is now `lib/*.mjs`; `process-cpu` and `process-memory` are
  `process-sample`; `Theme.js` is gone.
