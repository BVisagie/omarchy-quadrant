# Settings

[← README](../README.md)

Open settings with the panel's gear or `S`. Changes apply immediately.

[Copy/open actions](USAGE.md#copy-addresses-and-open-volumes) need no saved
configuration; they run only when activated. Their keyboard help is listed here too.

Settings live inline on the widget's entry in `~/.config/omarchy/shell.json`
and are declared in the manifest schema. The settings view writes them
through the shell, typed; `omarchy bar set` works too and takes effect at
once:

```sh
omarchy bar set dev.bvisagie.quadrant processCount 8 --json
omarchy bar set dev.bvisagie.quadrant networkInterface '"wg0"' --json
```

Entries written by earlier versions (quoted strings, stringified lists)
are still read correctly and are rewritten in the typed form the first
time any setting is saved.

| Key | Default | Meaning |
| --- | --- | --- |
| `segments` | `["cpu","gpu","memory","network"]` | Bar segments to show; any subset of `cpu gpu memory disk network`. An empty list keeps a compact icon. |
| `barOrder` | `["cpu","gpu","memory","disk","network"]` | Saved order of all five resources, independent of enabled segments and hardware presence |
| `barStyle` | `"text"` | `text` or `graph-text`: optional minute trends beside values |
| `barGraphWidth` | `32` | Trend width in logical pixels (16–64), scaled by shell spacing; vertical bars clamp it to the strip width |
| `processCount` | `5` | Top-process rows per tab (1–10) |
| `barIntervalMs` | `1000` | Stream cadence feeding the bar and the graphs (250–60000) |
| `panelIntervalMs` | `2000` | On-demand helper cadence (500–60000), including GPU polling for a visible bar segment |
| `networkInterface` | `"auto"` | `auto` = default route across IPv4 **and** IPv6, lowest metric wins, IPv4 takes ties; without a default route, the first non-loopback interface |
| `gpuDevice` | `"auto"` | Dedicated card for the GPU segment and tab: boot display card among detected dedicated GPUs, else `card0`, else the first detected dedicated card; or a specific `cardN` |
| `gpuDeviceId` | `""` | Persistent dedicated GPU pin, as a PCI address (`0000:03:00.0`); takes precedence over `gpuDevice` |
| `integratedGpuDevice` | `"auto"` | Which card is integrated graphics: `auto` (Intel at `00:02.x` or a known AMD APU), `none` (treat all cards as dedicated), or a `cardN` (force that card to be integrated) |
| `integratedGpuDeviceId` | `""` | Persistent integrated GPU pin, as a PCI address; takes precedence over `integratedGpuDevice`, including `auto` and `none` |
| `diskFallbackWithoutGpu` | `true` | Substitute Drives at its saved position when a configured GPU is unavailable; default position is after Memory |
| `diskDevice` | `"auto"` | `auto` = physical disk backing `/` (LUKS/LVM folded), else the largest; or a sysfs name such as `nvme0n1` |
| `diskDeviceId` | `""` | Persistent whole-disk pin, as a basename from `/dev/disk/by-id`; takes precedence over `diskDevice` |
| `barPalette` | `"theme"` | `theme`, `heat`, or `vivid` (see [Bar](USAGE.md#bar)) |
| `barLabels` | `"glyph"` | `glyph`, `letter`, or `none` |
| `gpuGraphLayout` | `"overlay"` | `overlay` or `aligned`: busy and VRAM on two plots sharing time and a 0–100% scale |
| `networkGraphLayout` | `"overlay"` | `overlay` or `mirrored`: download above zero, upload below, on one shared magnitude scale |
| `diskGraphLayout` | `"overlay"` | `overlay` or `mirrored`: read above zero, write below, on one shared magnitude scale |
| `rateUnit` | `"bytes"` | Network panel and tooltip rates in `bytes` (KiB/s, binary) or `bits` (Mb/s, decimal); compact bar rates stay in bytes |

Every value is validated on read, whatever wrote it: numbers are clamped
to the ranges above, enumerations fall back to their default, device names
must look like a device (an interface name of at most 15 characters, a
`cardN`, a sysfs block name) or they become `auto`, unknown segment names
are dropped. Quadrant's settings view and IPC may only update the keys
listed here.

Changing `barIntervalMs` preserves the graph duration and retains minute
samples collected at the previous cadence until they age out. The **1 min** /
**1 hour** choice belongs to each panel's session and is not a saved setting.

Persistent GPU IDs must have the PCI form `DDDD:BB:DD.F`; disk IDs contain
at most 255 safe basename characters and cannot contain paths, `..`, or a
`-partN` suffix. Invalid IDs become empty. IDs are looked up in inventory;
only resolved kernel names and device paths reach the samplers.
Unknown keys already present in the entry are preserved; settings at their
defaults are omitted when Quadrant saves. The helper scripts check their arguments again before touching anything.

## Bar styles and ordering

In **Bar segments**, switches select what appears and the up/down arrows save
its order. Disabled resources and missing devices remain in the ordered list.
Moving one keeps keyboard focus on that resource's movement control. Use the
panel arrows or an ordered CLI array to change position; use the switches
or `segments` to enable or disable resources.

`barOrder` keeps the first occurrence of each recognized segment, drops unknown
names, and appends missing names in canonical order: CPU, GPU, Memory, Drives,
Network. It accepts typed arrays, JSON-encoded arrays, and comma lists.
`segments` remains an enabled set in canonical order; changing membership
never changes the saved order. Older entries without the new keys retain
text and the existing order. Older Quadrant releases ignore these keys while
preserving them on save. **Reset to defaults** restores text, 32 px trends,
the canonical order, and the default enabled set.

Choose **graph + text** under **Appearance** to add trends. Trend width applies
only in that style; the stored choice survives returning to text. Every style
reserves the widest value before rendering, including Intel's estimated GPU
prefix and both compact network rates. Horizontal values stay beside their own
labels or trends, with spare width after each reading. In a vertical bar, the
plot sits above its value and all visible percentages share a fixed font size
chosen to fit the available strip; network rates fit independently.
The bar's minute window does not follow the panel's **1 hour** selection.

```sh
omarchy bar set dev.bvisagie.quadrant barStyle '"graph-text"' --json
omarchy bar set dev.bvisagie.quadrant barGraphWidth 32 --json
omarchy bar set dev.bvisagie.quadrant barOrder '["network","disk","cpu","gpu","memory"]' --json
```

See [style captures, fallback decisions, and rendering cost](BAR_TRENDS.md).

## Graph layouts

The **Panel graphs** section selects each resource independently. The choices
are saved, apply immediately, and remain available when the corresponding
device or bar segment is absent. Reset restores overlays. CPU's stack and
Memory's band keep their existing layouts.

Aligned GPU plots give each available series a full-height plot. A card
without a VRAM percentage shows only busy. A current or retained percentage
in that card's history enables the VRAM series, so a failed poll does not
remove its plot; the live legend shows `--` while the current value is missing.

Mirrored Network and Drives plots separate direction around zero; the lower half still measures a
positive rate. Network's rate-unit setting applies to both layouts. Rate plots
share a ceiling of at least 1 KiB/s (8.2 kb/s when displayed in bits); they scale
up together when either series needs more room. See the
[matched comparisons and default choice](GRAPH_LAYOUTS.md).

```sh
omarchy bar set dev.bvisagie.quadrant gpuGraphLayout '"aligned"' --json
omarchy bar set dev.bvisagie.quadrant networkGraphLayout '"mirrored"' --json
omarchy bar set dev.bvisagie.quadrant diskGraphLayout '"mirrored"' --json
```

## Device selection and bar fallback

The tab and settings pickers save a persistent ID when one is available,
so a disk or GPU can keep its pin when its kernel name changes. The old
name settings retain the currently resolved name for older Quadrant
releases. Those releases preserve the new ID settings as unknown keys;
their selection remains best effort until the newer release is restored.

Tab pickers wrap within the panel width. A long model name is elided on its
button while its tooltip and accessible name retain the complete label.

Existing name-only pins are migrated when inventory resolves them. A name
left over from another boot cannot establish what it referred to before
the reboot: check the device once when upgrading a legacy pin. Missing
pins remain saved and produce a warning naming the target. `R` re-reads
GPU and disk inventory, updates the selectors, and resolves reappearing
devices without a shell restart.

If a GPU refresh fails, Quadrant keeps the last successful inventory and
readings and shows the detection error. A successful empty scan removes
the old hardware; a startup failure still reports unavailable inventory.

Choose `auto` in settings to clear both parts of a GPU or disk pin; choose
`none` to clear an integrated GPU pin and treat all cards as dedicated.
The Network tab also offers `auto`. Invalid kernel names fall back to
`auto`; `lo` is excluded from interface selection.

GPU pins identify a PCI location. Moving the card to a different slot
requires choosing it again. Saved GPU history also checks the PCI
vendor/device ID, subsystem ID, and revision when present, so a different
model in the same slot starts a new graph. Identical replacement hardware
cannot be distinguished by those fields. If the PCI vendor/device ID is
unreadable, the address can still pin the card, but its history is reused
only within the current boot.

Disk pins prefer WWN or NVMe EUI/UUID aliases, then device serial aliases
and namespace-specific NVMe names. Partition aliases are excluded. A
reported ID shared by multiple inventory rows is ignored; another unique
alias is used if available. Devices without a usable unique ID keep a
kernel-name pin and only reuse name-tagged history within the current
boot. Firmware clones whose collision is hidden by a single udev symlink
cannot be distinguished. The helper bounds inventory to 16 devices and
16 aliases per device.

Network interfaces remain pinned by name: predictable interface names
already describe the connection the user selected, and virtual interfaces
such as VPNs may have no hardware identity. Replacing an adapter without
changing that connection name keeps the selection and its history.

Without a dedicated GPU, `diskFallbackWithoutGpu` replaces a configured
`gpu` token with Drives for display without rewriting `segments`. Drives
uses its own saved position, after Memory in the default order. The Drives
tab's **in bar** switch and the settings Drives switch control the effective
segment in this case. Switching off disables fallback and removes an explicit
`disk` token. Switching on enables fallback if `gpu` is configured, or adds an
explicit `disk` token otherwise. Neither action rewrites `barOrder` or the
saved GPU preference. Missing disks remain hidden without losing their position.

Changing the selected interface or hardware identity starts that metric's
history afresh. Renumbering the same identified disk or GPU keeps its
history, while counter baselines and in-flight GPU results are reset.

## CLI examples

```sh
omarchy bar set dev.bvisagie.quadrant segments '["cpu","memory","network"]' --json
omarchy bar set dev.bvisagie.quadrant barPalette '"heat"' --json
omarchy bar set dev.bvisagie.quadrant rateUnit '"bits"' --json
omarchy bar set dev.bvisagie.quadrant diskFallbackWithoutGpu false --json
omarchy bar set dev.bvisagie.quadrant gpuDeviceId '"0000:03:00.0"' --json
omarchy bar set dev.bvisagie.quadrant diskDeviceId '"wwn-0x5002538e00000000"' --json
```

An ID takes precedence when loading settings or changing the ID itself,
even if its legacy name setting says `auto` or `none`. While Quadrant is
running, changing a name setting to `auto` (or integrated graphics to
`none`) clears its unchanged ID in the same settings write. Each of these
commands resets its device pin:

```sh
omarchy bar set dev.bvisagie.quadrant diskDevice '"auto"' --json
omarchy bar set dev.bvisagie.quadrant gpuDevice '"auto"' --json
omarchy bar set dev.bvisagie.quadrant integratedGpuDevice '"none"' --json
```

If an unresolved ID-only pin already has an `auto`/`none` policy, clear
its ID key directly or choose `auto` in settings. For example:

```sh
omarchy bar set dev.bvisagie.quadrant diskDeviceId '""' --json
```

Use `--json` for typed numbers, booleans, lists, and JSON-quoted strings.
See [IPC](USAGE.md#ipc) for the plugin's own `set` and `setBarSegment`
methods.

## Settings view

The settings view groups ordered bar segments, appearance, panel graphs, sampling, and devices,
with keyboard help and a **Reset to defaults** action at the bottom.

<details>
  <summary>Show the full settings screenshot</summary>
  <p align="center">
    <a href="screenshots/settings.png"><img src="screenshots/settings.png" alt="Full Quadrant settings view showing segment switches and ordering arrows, bar trends and width, panel graphs, sampling, devices, keyboard shortcuts, and Reset to defaults" width="520"></a>
  </p>
</details>
