# Measurement sources and limits

[← README](../README.md)

## CPU

User time (including nice), system time (including irq/softirq), iowait,
and steal have separate stacked graph series. The live steal legend is
shown only when non-zero. The bar percentage is non-idle time, including
iowait, so a disk-bound machine is not shown as idle.

Topology comes from sysfs: online cores keyed by package and core ID,
Intel `cpu_core`/`cpu_atom` lists, or capacity/max-frequency clusters.
The core grid collapses SMT siblings and keys load by CPU ID so offline
cores do not shift other cores' readings. Frequency is the mean of the
readable cpufreq policies. Pressure uses PSI CPU some/full avg10.

Process CPU is the interval change in `/proc/<pid>/stat`, expressed as a
share of the whole machine; the tooltip shows the one-core figure.
Counter snapshots are keyed by PID **and start time** so a reused PID
cannot inherit old counters. CPU and I/O rates need two samples after a
cold start. One shared follow-up runs around 500 ms after a cold opening;
requests within 400 ms never replace the baseline. Long gaps, counter resets,
and new PID/start-time identities require another interval. Interpreter rows can use the script basename (`worker.py`);
wrapper applications use a fixed name map, and same-name rows are summed.

## Memory

The ring and bar show `(MemTotal − MemAvailable) / MemTotal`. The
composition bar separates Applications, Kernel unreclaimable slab,
Cache (page cache + Buffers + SReclaimable), and Free. These slices use a
different calculation from the used-memory ring and need not match it.

The pressure ring displays PSI memory some avg10 on a 0–25 % scale; its
numeric value remains the actual percentage. The used-memory graph
follows its own range when usage varies; a flat series uses the full scale.

Compact process memory uses proportional set size (PSS) from `smaps_rollup` where
readable, apportioning shared pages across the processes that map them;
otherwise it uses resident set size (RSS). Rows label PSS, RSS, or mixed
PSS/RSS accounting and show both size and percentage. The row percentage is its KiB value
divided by usable RAM. Candidates are selected by RSS before PSS is read,
so the list is not an exhaustive ranking of every process by PSS.

Expanded memory reads RSS for every readable process stat, avoiding an
exhaustive `smaps_rollup` walk at panel cadence. Shared pages count for each
process; summing these rows can exceed physical RAM. This mode is labelled
RSS in the rows and scope note. CPU/memory/I/O name groups are formed over
all eligible source members before search or the 256-group display cap.
Unknown members are omitted from the known subtotal, marked `≥` with measured
member coverage. Completely unknown fields remain unavailable. A PID search
keeps the group's full subtotal and identifies the matching member. Memory
sparklines restart on collection-mode or PSS/RSS/mixed accounting changes.

DIMM identity comes from unprivileged udev DMI data; swap devices come
from `/proc/swaps`. Missing firmware details are omitted.

## GPU

The GPU segment and tab follow a dedicated card. Integrated AMD/Intel
metrics appear on the CPU tab. Automatic role detection uses positive
hardware/name evidence; [device settings](SETTINGS.md) can override it.

- **AMD:** `amdgpu` sysfs supplies busy, memory busy, per-engine busy,
  VRAM, edge/junction temperature, power, and active DPM clock when
  readable. Direct sysfs busy takes priority over a DRM overlay.
- **NVIDIA:** timeout-bounded `nvidia-smi` polls supply utilization, VRAM,
  temperature, power, and clock while its segment or tab is visible.
  It does not run in the streaming sampler.
- **Intel:** DRM fdinfo engine time supplies busy, with the selected
  card's RC6 / xe `gtidle` residency as a fallback. Both are presented as
  busy without an estimate prefix. The frequency-ratio fallback is an
  estimate of clock activity, not measured utilization; it gets a `~`
  prefix in the bar and GPU tab, or a frequency-estimate label on the CPU
  tab's integrated-GPU card. Multi-engine capacity is honored so
  multi-instance engines still read 0–100 %.

AMD/Intel process rows use DRM fdinfo busy and resident memory. A DRM
client shared across fork is attributed once, to the first PID found.
Rows depend on readable fdinfo and may be incomplete. NVIDIA process
rows use `nvidia-smi --query-compute-apps`: memory only, covering compute
apps rather than all graphics clients. Same-name GPU rows are grouped,
with busy and resident memory summed and the lowest PID used in the
tooltip. Multiple dedicated cards get a picker with model names where
available.

AMD model names come from libdrm's `amdgpu.ids`, matched by PCI device ID
and revision, because one device ID can cover several retail cards
(`1002:7550` is the RX 9070 XT, 9070 GRE, and 9070). Without a match the
`lspci` name is shown, listing every model that shares the ID rather than
guessing one. NVIDIA names come from `nvidia-smi`.

## Drives

Whole-device counters come from `/proc/diskstats`, excluding partitions
and `loop*`, `ram*`, `zram*`, `fd*`, `nbd*`, and `sr*`. Device-mapper and
md RAID with one physical parent fold onto it (a LUKS root can show as
`nvme0n1`); arrays spanning multiple disks stay selectable as `md0`.
Busy percentage is `io_ticks` over wall time, not a throughput percentage.

Mounts come from `df -P -B1 -T`; bind mounts collapse to the shortest path.
The tab lists mounts on the selected device with capacity bars. Drive
temperature comes only from the device's `nvme` hwmon sensor.

Process I/O comes from readable `/proc/<pid>/io` counters, normally those
of your own processes. The panel reports how many it could not read.
These rows report total process I/O across devices; they are **not scoped
to the selected drive** and need not sum to its throughput.

## Network

The stream supplies selected-interface rates and received/sent totals.
Identity adds link speed, Ethernet/Wi-Fi/virtual type, MAC, and global
addresses, using sysfs and an `ip -j addr` call when system identity is
refreshed (startup, `R`, and GPU-tab refresh).

Process attribution uses established TCP socket counters from `ss`,
matched against the interface's local addresses when available. Each
poll separately asks `ip` for those addresses. This is address-based
attribution rather than tracing each packet's route; VPNs and virtual
interfaces can make it approximate. UDP, other users' sockets, and
closed-socket remainders fall into **Other traffic** (keyed on PID 0).

The interface picker pins `networkInterface`; `auto` follows the lowest
metric default route across IPv4 and IPv6, preferring IPv4 on ties. With
no default route, it uses the first non-loopback interface. See
[Settings](SETTINGS.md) for rate units and the compact bar's behavior.

## History

Graphs keep a 60 s window at the stream cadence and an hour of 10 s mean
buckets. The hour survives a shell restart when the state directory is
writable (see [stored data](../SECURITY.md#stored-data)). History is saved
every 30 s and when the store is destroyed; a crash can lose recent
samples. Minute history and process sparklines are not persisted.

Saved GPU, interface, and disk histories are adopted only when their
device tags match. Disk tags use whole-disk by-id names; GPU tags use PCI
location plus hardware fingerprint. Renumbering a matched device keeps
its history. A new identity starts fresh, and its first sample seeds new
counter baselines. The store waits for disk inventory before adopting
disk history, even when stream rates arrived first.

Old history files with only `cardN` or disk names are adopted only if
their save time is within the current boot, checked against `/proc/stat`
`btime`. Missing boot/save metadata discards that device history. CPU and
memory history is unaffected; network history still follows the interface
name. Version 2 history files make the identity tags explicit; older
Quadrant releases ignore that file version. See [Settings](SETTINGS.md)
for replacement hardware and missing-ID limits.

Graphs leave breaks between samples beyond a cadence-dependent gap
threshold; shorter interruptions may still be joined. The hour view's
bucket averages cannot preserve every brief spike's size or exact timing.

GPU history that relies on on-demand polling stops collecting once its
last poll becomes stale. It does not fill hidden periods with a cached
value. AMD direct sysfs busy can continue through the stream.

## Temperature and missing values

CPU sensors are restricted to `k10temp`, `coretemp`, `zenpower`, and
`cpu_thermal`; drive sensors to `nvme`. Quadrant shows `--` rather than
substituting an unrelated sensor. Available identity and metrics depend
on the firmware, driver, and current user's read permissions; missing
fields may be omitted or shown as `--`.

Process and network helper envelopes are limited to 1 MiB of encoded JSON.
An over-limit sample is omitted in full and the panel shows a process-coverage
error. Network interface graphs and totals continue independently; discarded
socket counters are not used as a baseline for subsequent process rates.
