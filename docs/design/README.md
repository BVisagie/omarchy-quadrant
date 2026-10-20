# Wider panel layout studies

Direction **A** was selected for implementation. The QML now uses the wider
popover with responsive columns; the [native captures](../USAGE.md#screenshots)
show the implemented views. This HTML preserves the two options from design
review, including B, which was not selected.

Open [layout-review.html](layout-review.html) directly in a browser. It is
self-contained, works offline and does not connect to telemetry or change
Omarchy settings.

Two directions cover CPU, Memory and Hardware. Switch the direction above
the mockup, then select a resource inside it. The width selector demonstrates
a 440-unit single-column fallback; “View at 100%” disables preview scaling.
History ranges, process sorting, process expansion, information disclosures
and the bar switch are interactive demonstrations. Arrow keys switch the
three mocked resources; H changes the history range.

## Recommendation

Start with **A, the 720-unit wider popover**. It preserves the existing tab
model and uses two columns to make usage and processes visible together.
The default CPU and Memory views are approximately 710 units tall in the
preview, and Hardware approximately 780. These are browser mockup dimensions,
not promises about the eventual QML layout or physical screen pixels.

**B, the 960-unit inspector**, adds a resource sidebar with summary values.
It makes sense as an expanded inspection view, but occupies more desktop
space and changes the character of the bar popover.

At the time of review, the source checkout used `Style.space(440)` in
`Panel.qml` and single-column tab layouts. The installed plugin had additional Hardware and
process-grouping functionality visible in the supplied screenshots. These
studies deliberately covered those screenshots. Implementation was based on
the subsequent `main`, which contains the Hardware and process improvements.

## What changes

- CPU: a short row of essential values, a history/core/graphics column, and
  a process/system column. Remove frequency duplication from the lower
  system details.
- Memory: replace large utilization and empty pressure rings with numeric
  values. Keep history, composition, processes and swap visible together.
  Put measurement explanations in disclosures; retain RSS/PSS distinctions
  beside the numbers and a visible unreadable-process count.
- Hardware: group sensors by device and show core temperatures in a grid
  labelled with the actual reported sensor IDs. Put paths in device-level
  details. Keep battery information alongside sensors, and keep unavailable,
  invalid and permission-denied readings explicit.

The mockups retain monospace type, restrained borders and the palette from
the screenshots. Production should continue to use the active Omarchy theme
and font rather than hardcoding this preview palette or its browser sizes.

## Implementation considerations

- Fit width to the available monitor using the shell's existing sizing
  helpers. The implementation prefers 720 theme-scaled units and changes to
  two columns at 640, with a minimum based on the current font size.
- Cap the panel to the available screen height. Keep the tab strip fixed
  with one scrolling content area; expanded details and long process lists
  must remain reachable. The review page shows each panel's natural height
  to make its content and arrangement easy to assess.
- Collapse to one column on narrow screens without shrinking the native
  font. Preserve a predictable reading and keyboard order.
- Preserve conditional dedicated-GPU navigation, per-device selection,
  stable process identity/order, keyboard shortcuts, and sensor pinning.
  Those behaviours are outside this focused mockup.
- Keep temperature thresholds sensor-specific. A temperature alone should
  not create a generic warning state. Missing readings must never become
  zero or a fabricated “healthy” status.
- Reuse the existing store and samplers. This is primarily a presentation
  change; a wider view should not require new telemetry polling.

## Data and verification

Most displayed values come from the three supplied screenshots. Available
RAM is illustrated as usable minus used; sensor ranges are calculated from
the displayed readings. These are separate sample snapshots, not a synchronized
system measurement. Graphs, trends and the two additional expanded process
rows are illustrative. Drives and Network are disabled context items.

The original Hardware crop starts with an invalid reading without its device
identity. The mockup keeps that state visible without inventing an identity.

Checked both directions and all three tabs at wide and narrow panel widths,
including content overflow, history switching, process sorting/expansion,
the local bar switch and information disclosures. Visual previews use T3's
HTML renderer. The prototype itself does not modify QML or desktop configuration.
