# Panel layout studies

## Consistent resource panels

[All-panel review](panels-review.html) extends the approved Hardware concept
to CPU, GPU, Memory, Drives and Network. It is a self-contained interactive
HTML proposal with all six resource tabs, consistent section boundaries,
headline readings, process groups and expandable technical details.

Try tab switching, the light/dark palette, narrow width, units, history
windows, process expansion/search/sorting and per-resource bar switches.
GPU examples include an Intel frequency estimate with byte-only memory and
unavailable telemetry. Drives includes an unmounted device; Network includes
a disconnected interface. Copy/Open simulate feedback without changing the
clipboard or launching applications.

Hardware retains the supplied screenshot's readings. Other views use
illustrative values and mock history, not live measurements. The prototype
keeps Other traffic, RSS/PSS labels, collection limits and missing values
explicit. It also identifies process I/O as machine-wide, separate from
the selected drive's throughput.

The grouped design is now implemented across all six QML resource tabs.
Shared theme-aware cards and readouts reuse the existing process/action
controls and collectors. Headline readings live in their corresponding
groups, and **Expand details** shares the `D` shortcut's scope. See the
[native captures](../USAGE.md#screenshots), including the
[Hardware capture](../HARDWARE.md). Settings retains its existing workflow.

Reviewed all six views and both theme polarities. In-browser verification
passed 183 checks covering wide/narrow layouts with details open/closed,
state across tab changes and resizing, D and H shortcuts, search input,
device examples, units, simulated actions and horizontal overflow.
The 720-unit production sizing remains subject to Omarchy's theme/font
scale and monitor-fitting rules.

## Hardware follow-up

After A merged, [Hardware hierarchy review](hardware-review.html) explores
four clearly bounded groups: processor, other temperatures, batteries, and
power/cooling. It uses the supplied [current screenshot](hardware-current.png)
for a before/after comparison. The prototype supports expandable details,
the `D` shortcut, Celsius/Fahrenheit and a narrow layout.

The HTML preserves the review proposal. The QML implementation retains raw
device identities and distinguishes repeated devices, with unknown drivers
keeping their names. Live values do not change group order. Missing, invalid
and permission-denied readings remain explicit. The collapsed core summary
includes unavailable and critical reading counts, based on actual sensor
thresholds. GPU inventory actions and diagnostic fields absent from the
cropped screenshot remain available in the native view.

Keep `hardware-review.html` and `hardware-current.png` together to use the
comparison offline.

Reviewed wide and narrow renders, including expanded details. In-browser
checks covered 19 interaction/layout assertions: comparison switching,
detail buttons and D, Celsius/Fahrenheit, original sparse core labels,
unchanged missing values, retained disclosure state and text overflow.
The mockup uses a fixed illustrative palette; production continues to use
the current Omarchy theme and font.

## Original layout selection

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
