# AMD runtime power implementation plan

[← Requirements and acceptance criteria](AMD_RUNTIME_POWER.md)

**Status: initial plan, recorded before implementation on 2026-10-20.**
See the [implemented policy](AMD_RUNTIME_POWER.md) and [hardware results](AMD_RUNTIME_POWER_RESULTS.md)
for the resulting behavior and validation. At the time of this assessment, no
collection behavior or system power configuration had been changed. The existing requirements
remain the acceptance contract. The phases below can be reviewed in order;
an intermediate phase does not establish the final suspend guarantee.

## Initial AMD desktop assessment

The development checkout and installed Quadrant both resolved to
`0d624c50e55bab37856d7a8c8855be5a6bba03ae`, with clean working trees before
this plan was added.

- Hardware: Intel i7-12700K, ASUS TUF GAMING Z690-PLUS WIFI D4, XFX RX 7900 XTX
  (`1002:744c`, subsystem `1eae:7901`) at PCI `0000:03:00.0`, currently `card1`.
  Only one DRM card was enumerated; no integrated GPU was exposed.
- Environment: Omarchy 4.0.6, kernel `7.2.8-9-omarchy`, `amdgpu` driver.
- Display: the GPU drives an enabled Samsung G80SD over DP-1 at
  3840 × 2160, approximately 239.914 Hz. One monitor was active.
- PM metadata: `power/control=auto`, `autosuspend_delay_ms=5000`, and
  `amdgpu.runpm=-1`. `runtime_enabled` and `runtime_usage` were absent.
  Their absence is not evidence that runtime PM is disabled.
- Existing display workaround: `power_dpm_force_performance_level=manual`
  with the highest stock VRAM state active at 1249 MHz. The corresponding
  one-shot service had completed successfully. The recorded display debug
  flag was absent from the running kernel command line. Preserve this setup;
  changing the display workaround is a separate machine task.
- Quadrant: one installed stream was running with the AMD device argument at
  a 1000 ms interval. Its bar entry used default GPU and interval settings.
  Panel visibility was not captured, so this is not a hidden-view test.
- DRM clients included Hyprland, Xwayland, Quickshell, the browser, and T3
  processes. Open DRM descriptors identify clients; they do not establish
  that a process polls telemetry or prevents suspend. No named standalone
  GPU monitoring tool was found in the process snapshot.

A read-only observer sampled only `runtime_status`, `runtime_active_time`,
and `runtime_suspended_time` every five seconds from 11:37:42 to 11:38:12 UTC.
The actual elapsed window was 30.002 seconds. All seven observations were
`active`; active time increased by 30,002 ms, while suspended time remained
zero, including its accumulated total since boot.

This is an observation of the current enabled desktop session, **not a
disabled-Quadrant baseline or a causal test**. It proves neither that Quadrant
prevents suspend nor that this GPU can suspend in the current display setup.
It also provides no wattage comparison.

The kernel documents runtime power-down as conditional on driver/device
support, and distinguishes the default `runpm=-1` from the mode permitting
power-down with attached displays. An attached active display is therefore
an important test condition, not grounds to change the module parameter.
See [AMDGPU module parameters](https://docs.kernel.org/gpu/amdgpu/module-parameters.html)
and the [runtime PM attribute ABI](https://github.com/torvalds/linux/blob/master/Documentation/ABI/testing/sysfs-devices-power).

## Source audit findings

- `scripts/quadrant-stream`: startup discovers GPU attribute paths, and
  `read_gpu()` reads busy, memory busy, VRAM, hwmon temperature/power, core
  clocks, and engines on every tick. There is no visibility or PM gate.
- `components/Store.qml`: viewer aggregation already provides a useful
  shared-service foundation. AMD helpers are demand-driven, but the stream
  is independent. GPU selection currently calls `restartStream()` and also
  changes its GPU command arguments. Both paths need replacing for runtime
  selection changes.
- `scripts/gpu-stats`: an AMD sample repeats several stream reads, adds
  junction temperature and memory clocks, then launches `gpu-drm`.
- `scripts/gpu-drm`: process fdinfo and device discovery are additional read
  paths. They need instrumentation and participation in the policy; the audit
  has not established their physical effect on this driver.
- `tabs/GpuTab.qml`: opening the tab refreshes identity and explicitly requests
  a sample. CPU/iGPU polling, global refreshes, and settings over an open tab
  must use the same eligibility decisions as timer-triggered work.
- `scripts/hardware-info.py`: GPU-owned sensor inputs are already excluded.
  Preserve that boundary and its FIFO tests. `scripts/system-info` reads GPU
  identity metadata and invokes `lspci`; metadata-only does not by itself
  prove that all those operations are neutral to runtime PM.
- GPU history is recorded at the enclosing stream tick. A non-null busy
  reading is considered stream-fresh, and cached helper readings can be
  appended repeatedly while inside their freshness allowance. Deliberately
  held measurements require a different acceptance and history contract.
- `tests/stream-forks.sh` currently starts the stream without a GPU argument.
  It does not cover the AMD tick path.

These are source findings. No syscall trace or controlled per-attribute
wakeup experiment was performed. `strace` was not available on the machine.

## Recommended policy decisions

Use these as the initial implementation defaults, with fixture coverage:

1. **No demand means no GPU telemetry.** Combine GPU bar/detail and CPU/iGPU
   demand by physical device. Metadata inventory remains bounded to startup,
   selection/discovery, and explicit refresh. Do not add background history
   polling in the first implementation.
2. **Opening a view does not intentionally wake a sleeping GPU.** For
   suspended, suspending, or resuming status, retain an appropriately labelled
   last reading or show unavailable when none exists. Explicit R refreshes
   also respect the gate. Observe PM status while demand exists so activity
   can resume collection. A status check cannot eliminate a transition race.
3. **Keep a usable fallback.** Absent/unsupported PM metadata or explicitly
   disabled runtime PM uses visible-only collection at the existing cadence,
   labelled as PM unavailable/disabled. Transient read errors after supported
   PM was detected hold telemetry and retry status with bounded backoff;
   permission errors are reported. Removal invalidates the device generation.
   No fallback claims verified suspend preservation.
4. **Measure before adding quiet windows.** Start with visibility and PM
   gating. If active-state sampling demonstrably extends time to suspend,
   coordinate stream and helper reads in one bounded window, followed by a
   shared quiet period. Define limits and missing/negative-delay behavior
   from the evidence; 5000 ms on this machine is not a universal interval.
5. **Make freshness explicit.** Keep last measurement time separate from
   status-check and UI-update time. Distinguish sleeping, held, stale,
   unavailable, and failed readings. Measured zero remains a valid reading.
6. **Scope sharing honestly.** Guarantee one coordinated policy within a
   successfully resolved shell service. Independent embedded fallback Stores
   must each gate their own readers; coordinated windows across them are not
   guaranteed unless cross-Store arbitration is implemented and tested.
   Surface and document that degraded mode.

## Implementation order

### 1. Establish repeatable observation

Add a small read-only diagnostic script and a results template. Pin the target
by PCI identity rather than `cardN`. Record versions, display and workload
conditions, other readers, Quadrant commit/settings, PM values and read errors,
timestamped transitions, and active/suspended counter deltas. Log every path
the observer reads. Its observation loop must avoid busy, clock, hwmon, VRAM,
and fdinfo telemetry; inspect those only in separately labelled experiments.

Run repeatable disabled-Quadrant and current-enabled cases with matching
conditions. Choose windows comfortably longer than the autosuspend delay and
any proposed quiet period; the 30-second assessment above is not the final
acceptance window. Add syscall/read instrumentation for the actual reader
audit when the necessary tool is available. Do not install it implicitly as
part of running the observer.

**Exit condition:** a reproducible report, and either a suspending baseline
or an explicit explanation of why suspend acceptance is still unverified.
Development of the software contracts can continue in the latter case.

### 2. Control the stream without restarting it

Add a private runtime control file, atomically published by the Store and
checked with Bash builtins. `FileView` already supports atomic writes in this
project. Include device identity/path, generation, demand and eligibility,
and a bounded validity period. Define one common monotonic time source and
units for policy intervals before finalising the format; wall-clock changes
must not extend a grant. Validate paths and contents; never source the file.

Missing, malformed, expired, or superseded control must suppress controlled
AMD telemetry while unrelated samples continue. Device selection updates
re-probe the selected GPU without restarting the stream. Define startup,
controller death, stream restart, private-directory ownership, and stale-file
cleanup. Check the gate before telemetry, including device-change probes.
Preserve the existing Intel/NVIDIA behavior when adapting shared contracts.

**Exit condition:** real read traps prove no hidden GPU reads, zero forks on
the AMD tick path, unchanged stream PID across toggles/selections, and
continuous CPU, memory, disk, and network ticks.

### 3. Coordinate every AMD reader

Add a pure policy module under `lib/` and wire a per-device policy map into
`Store.qml`. Coalesce stream/helper eligibility, including two roles referring
to one physical GPU. Separate metadata discovery from telemetry. Route timer
polls, tab activation, settings-over-tab, R refreshes, and CPU/iGPU requests
through it; prevent Hardware collection from bypassing it.

Capture device and collection generation for every launched job. Cancel
unneeded queued work and reject late responses after close, removal,
replacement, or selection changes. Account for already in-flight reads;
cancelling a result cannot undo a read. Reset DRM/rate baselines after
suppression, resume, invalid intervals, and identity changes. Add coordinated
quiet windows only if phase 1 supplies evidence for them.

**Exit condition:** fixture lifecycle tests prove all request paths obey the
same device policy, with bounded errors/retries and no unrelated disruptions.

### 4. Carry acquisition time through display and history

Extend the AMD stream/helper contract with identity, generation, unique sample
sequence, acquisition wall time, monotonic time, and collection state. Track
stream and helper acquisitions separately so one source cannot refresh the
age of another source's old fields. Add parsers and validators before wiring
the values into Store and the GPU/CPU views, bar text, and tooltips.

Append minute/history buckets only once per accepted measurement, using its
acquisition time. Expire old history even when no fresh GPU reading arrives.
Represent suppression gaps explicitly: existing graph thresholds can connect
points separated by a short pause, so merely skipping appends is insufficient.
Keep gap markers out of measurement counts and averages, preserve gaps through
saved-history reload, and retain supported old-history behavior. Bar trends
must follow the same rules. Decide whether the persisted format needs a
version change after checking these requirements against the existing loader.

**Exit condition:** deterministic tests cover held values, actual age, real
zero, short/long gaps, wall-clock changes, duplicate and late samples, and
minute/hour/bar histories across restart.

### 5. Complete fixtures and regression checks

Extend stream tests with a fake AMD tree and enabled, disabled, transitioning,
and toggled states. Exercise both mawk/gawk helper paths. Use read traps for
stream and helper inputs, deterministic policy clocks, and delayed/failing
helpers. Include absent/invalid PM metadata, denied reads, stale control,
crash/restart, removal/return, and rapid device changes.

Add real Store tests for two viewers sharing a service, settings overlays,
explicit refresh, CPU/iGPU demand, and fallback Store limitations. Extend UI
tests for status/age and graph gaps. Run the existing Node/Python suites,
script syntax/lint and AMD fork checks, affected Quickshell lifecycle/UI
suites, and the local qmllint gate described in [Development](DEVELOPMENT.md).

### 6. Perform hardware acceptance and update the guarantees

Repeat disabled/current/patched runs under matching display and workaround
conditions, including hidden views, bar/detail, CPU/Hardware, workload ending,
and refreshes. Log requested versus actual reads and measure fresh-data latency
after activity. Set and document its bound from the implemented cadence,
helper deadline, and any measured quiet-window policy.

This desktop can validate actual file access, continuous unrelated metrics,
freshness, active-state behavior, and regression against its display setup.
It does not yet supply a proven runtime-suspending baseline. A separate idle
test session or a supported secondary/headless AMD device may be needed;
do not change the current display/workaround simply to force a passing test.
The physical two-monitor case and iGPU case are also unavailable in the
observed setup and must remain fixture-only until tested on suitable hardware.

Report unverified hardware cases explicitly. Do not claim preserved suspend
until the same device/conditions demonstrate it with Quadrant disabled and
patched. Do not claim watts saved without corresponding power measurements.

## First implementation scope

Start with the read-only observer/results template and AMD stream visibility
control, including the GPU-enabled fork/read-trap tests. Then integrate shared
policy and acquisition-aware history before enabling the complete behavior
in the installed plugin. Reassess batching only after the reader experiments.
No system PM, clock, display, or module-parameter change is part of this work.
