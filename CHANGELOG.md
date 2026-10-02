# Changelog

## 1.0.0 — 2026-10-02

The best-in-class release: one PR, thirteen commits, every tab rebuilt.

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
  long; per-process CPU is a share of the machine, memory is PSS.
- Muted text and graph colours follow the theme on light and dark themes.
- `barPalette: vivid` does what the manifest promised.
- History follows one interface and one disk.

### Added
- One store per shell (service kind): a two-monitor desktop runs one
  sampler, not two.
- One hour of persisted history per graph, with gaps drawn as gaps.
- Per-process GPU rows (DRM fdinfo / NVIDIA compute apps), per-process
  disk I/O for your own processes, sparklines on every process row.
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
