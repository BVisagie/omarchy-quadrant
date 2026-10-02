# Using Quadrant

[← README](../README.md)

## Bar

- **Segments**: CPU, GPU, memory, drives and network each pair a Nerd Font
  glyph (or `C`/`G`/`M`/`D`/`N` with `barLabels letter`) with a live value.
  Network shows compact `↓`/`↑` byte rates, down first. Vertical bars
  stack the segments and drop the glyphs. `barLabels none` hides labels.
  Each segment toggles independently from its tab's **in bar** switch or the settings view; unchecking every segment leaves a
  compact system-monitor glyph.
- **Click a segment** to open its tab (or close the panel when that tab is
  already showing); click elsewhere in the slot to toggle the panel on the
  last-used tab. **Right-click** opens btop; **middle-click**
  toggles the panel. **Scroll** over the slot to switch tabs while the
  panel is open. Hovering a segment shows its tooltip.
- **GPU** is dedicated cards only; integrated graphics live on the CPU tab.
  When no dedicated card is detected the GPU slot shows **Drives** instead
  (`diskFallbackWithoutGpu`). A separate drives segment is off by default.
- **Colour** (`barPalette`): `theme` paints a value in the theme's urgent
  colour at 90 % and keeps it there until it drops below 80 % (no flicker
  on the line); `heat` ramps percentage values from muted through accent to
  urgent; `vivid` uses one hue per metric until the same hot threshold
  switches it to urgent. Network rates keep the foreground colour.

## Panel

Tabs combine hardware identity, graphs, stats, and top processes. Hiding
a bar segment leaves its panel tab available. The GPU tab appears only
when a dedicated card is selected and available.

| Key | Action |
| --- | --- |
| `←` `→` or `1`–`N` | switch tab (`N` = visible tabs; GPU is omitted without a dedicated card) |
| `↑` `↓` | move the cursor through the process rows (hover does the same; the row's tooltip shows the pid and a detail) |
| uppercase `H` | every graph: last hour ↔ last minute (clicking the graph header or scrolling over the graph does the same) |
| `S` | settings view (gear in the header) |
| `R` | re-read system and disk identity and refresh the active tab |
| `Esc` | close settings, then the panel |
| `Tab` | keeps its Quattro meaning: switch to the adjacent bar panel |

These shortcuts apply while a metric tab is visible. In settings, use the
controls and close the view with the gear or `Esc`. The shell also maps
lowercase `h` / `l` to tab navigation and `j` / `k` to process-row navigation;
use uppercase `H` for history.

The last-used tab survives closing and reopening the panel within the
running shell. The history-window choice also stays until changed; closing
the panel closes the settings view and clears the process cursor.

## Graphs and processes

Click the graph's time/average/peak note, scroll over a graph, or press
uppercase `H` to switch every graph between 60 s and 1 h. Hovering a graph
shows the readings at that point. The header reports the displayed CPU
stack total, memory usage, GPU busy, drive **read** rate, or network
**download** rate. In the hour view, peak means the highest 10 s bucket
average, so short spikes can be lower than in the minute view.

Click a process-list heading to cycle between the stable roster order,
descending value, and name. CPU, Memory, and Drives group same-name rows;
a grouped row's tooltip uses a representative PID. CPU, Memory, Drives,
and attributed Network rows keep sparklines of up to thirty samples while
they remain in the roster. GPU and **Other traffic** rows have no sparkline.
See [measurement limits](METRICS.md) for what each process value represents.

## IPC

The shell must be running with Quadrant enabled. Tab names in IPC are
`cpu`, `gpu`, `mem`, `disk`, and `net`; segment names are `cpu`, `gpu`,
`memory`, `disk`, and `network`. Unknown or unavailable tabs are ignored.
The `set` method takes its value as JSON text:

```sh
quickshell ipc -p "$OMARCHY_PATH/shell" call dev.bvisagie.quadrant showTab gpu     # cpu | gpu | mem | disk | net
quickshell ipc -p "$OMARCHY_PATH/shell" call dev.bvisagie.quadrant settings
quickshell ipc -p "$OMARCHY_PATH/shell" call dev.bvisagie.quadrant setBarSegment disk true
quickshell ipc -p "$OMARCHY_PATH/shell" call dev.bvisagie.quadrant set processCount 8
quickshell ipc -p "$OMARCHY_PATH/shell" call dev.bvisagie.quadrant set networkInterface '"wg0"'
omarchy-shell shell summon dev.bvisagie.quadrant '{}'   # open on last-used tab
omarchy-shell shell hide dev.bvisagie.quadrant
```

The plugin also exposes `open`, `close`, `show`, `hide`, and `toggle` IPC
methods. See [Settings](SETTINGS.md) for typed values and validation.

## Screenshots

These captures show the current panel across dark, light, and monochrome
Omarchy themes. Click a screenshot to view the original at full size.

<table>
  <tr>
    <td width="50%" valign="top">
      <p><strong>CPU</strong><br>Core activity and process CPU.</p>
      <a href="screenshots/cpu.png"><img src="screenshots/cpu.png" alt="CPU tab showing an Intel Core i7-12700K, load history, physical cores, and top processes in a dark teal theme" width="420"></a>
    </td>
    <td width="50%" valign="top">
      <p><strong>GPU</strong><br>Dedicated GPU activity and VRAM.</p>
      <a href="screenshots/gpu.png"><img src="screenshots/gpu.png" alt="GPU tab showing a Radeon RX 7900 XT, busy and VRAM gauges, history, and GPU processes in a light theme" width="420"></a>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <p><strong>Memory</strong><br>RAM composition, pressure, and swap.</p>
      <a href="screenshots/memory.png"><img src="screenshots/memory.png" alt="Memory tab showing used RAM, pressure, composition, memory history, swap, and process memory in a black monochrome theme" width="420"></a>
    </td>
    <td width="50%" valign="top">
      <p><strong>Drives</strong><br>Disk selection, throughput, and mounts.</p>
      <a href="screenshots/drives.png"><img src="screenshots/drives.png" alt="Drives tab showing a Samsung SSD, the disk picker, read and write throughput, mount usage, and process I/O" width="420"></a>
    </td>
  </tr>
</table>

**Network** — interface selection, download/upload history, and TCP
process attribution.

<p align="center">
  <a href="screenshots/network.png"><img src="screenshots/network.png" alt="Network tab showing an Ethernet interface, interface picker, traffic graph, totals, and process traffic in a dark theme with orange and green accents" width="540"></a>
</p>

The [settings guide includes the full settings view](SETTINGS.md#settings-view).
