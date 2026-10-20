# AMD GPU runtime telemetry policy

[← Hardware diagnostics](HARDWARE.md) · [Development](DEVELOPMENT.md)

**Status: visibility and runtime-PM gating implemented; physical suspend
preservation remains unverified.** The RX 7900 XTX desktop baseline did not
runtime-suspend with Quadrant disabled. The implementation is therefore tested
as a collection contract, with no claim of measured power savings or verified
suspend preservation. See the [hardware report](AMD_RUNTIME_POWER_RESULTS.md)
and [initial assessment and implementation plan](AMD_RUNTIME_POWER_PLAN.md).

The intended outcome remains that a supported idle GPU can runtime-suspend
while Quadrant is enabled, and held readings show their actual age. Access
to AMD hardware alone is insufficient: the disabled-Quadrant baseline must
first demonstrate suspend under matching conditions.

## Implemented behavior

The shared Store publishes an atomic, private runtime control file. It contains
one generation and the demand/device for dedicated and integrated roles, with
a three-second lease based on `/proc/uptime` (boot time, unaffected by wall-clock
adjustment). A one-second metadata heartbeat renews the lease while an AMD or
Intel stream target needs control. NVIDIA-only and no-GPU Stores do not create
the control directory or run that heartbeat. Missing, expired,
invalid, or superseded control suppresses controlled AMD reads. Control state
is removed on Store destruction; a later stream start sweeps directories owned
by dead controller processes.

The control path is fixed before stream startup. Its private directory is
created asynchronously with mode 0700, with a two-second retry after failure.
GPU setup never blocks unrelated sampling; controlled GPU reads fail closed
until the first valid control is published. Readiness does not restart the stream.

The stream re-reads control each tick. Device/visibility changes do not restart
it, and CPU, memory, disk and network continue at their configured cadence.
All hidden AMD telemetry stops; no background GPU history is collected. AMD
helpers check the same device demand and generation before reading sysfs or
launching `gpu-drm`. CPU/iGPU demand for the selected physical AMD device is
combined with GPU bar/detail demand rather than launching a duplicate helper.
Hardware's GPU-owned sensor exclusion remains in place.

Before AMD telemetry, `gpu-policy.sh` checks runtime status. Suspended and
transitioning devices are skipped, including when a detail tab or R refresh
requests collection. Missing/unsupported PM status permits visible-only
collection and is labelled unavailable; `power/control=on` and negative
known autosuspend delays are labelled disabled. Present but unreadable or
invalid PM metadata suppresses telemetry and reports failure. Retries are
bounded by the existing stream/helper cadences and helper watchdog. A sleeping
or transitioning stream observation stops dedicated AMD helper polling; the
stream's PM status check observes when collection can resume.

Status checks do not lock the kernel against a transition during subsequent
reads. No additional active-state cooldown is imposed: this machine supplies
no suspending baseline with which to establish a useful quiet period. If a
supported baseline shows that active-state polling postpones suspend, readers
will need a measured shared collection/quiet window before that hardware can
be reported as verified. Visibility/PM gating alone is not proof of that result.

Readings carry their device/generation, acquisition wall/boot times and sample
sequence. Stream and helper acquisitions retain separate ages. Common GPU
readouts use the newest acquisition from either source. Helper-only fields
such as memory clock and junction temperature carry their own age and are
cleared on non-fresh results, errors, or generation changes. Retained readings
are explicitly marked as last readings with an age; the bar shows `zz` for sleep and `--` while held,
waiting or failed. Tooltips explain the state and last reading. Real zero
remains a measurement. Estimate disclosures remain visible alongside age.
CPU/iGPU status is displayed independently of errors. CPU demand without a
matching AMD iGPU does not invalidate dedicated AMD collection. Intentional
helper cancellation does not become a collection error.

AMD history accepts each new acquisition once, using its acquisition time.
Explicit gap markers break minute and bar trends even for short suppression
periods. The hour view keeps one aligned ten-second bucket per interval and
conservatively omits any bucket touched by suppression from plots and summaries.
Its measurement count includes only real readings; repeated transitions do not
consume additional entries or shorten the hour window. Gaps survive v2 history
reload. Late acquisitions preceding a suppression watermark are discarded using
boot time, while a genuine wall-clock rollback still resets chronological history.
Old history expires during suppression. DRM/rate baselines reset across demand
and device generations and observed sleep/transition intervals.

Activity becomes visible within one configured stream interval plus one helper
interval and its six-second watchdog where helper data is needed (normally
1 + 2 + 6 seconds as a conservative bound). Actual helper completion is usually
much quicker. This is a scheduling bound under responsive reads, not a promise
about driver wake timing. Stuck stream reads remain covered by the existing
watchdog. CPU-only iGPU helpers use their panel interval plus watchdog.

Sharing covers one successfully resolved shell service. Embedded compatibility
Stores each enforce their own demand and PM checks; there is no cross-process
batching guarantee between independent Stores. Identity discovery (`lspci`,
GPU/sysfs metadata) remains a startup/explicit-refresh operation and has not
been established as physically wake-neutral on a suspending device.

## Previous behavior and hardware questions

Before this change, the selected dedicated AMD GPU was passed to the stream
at startup and read on every tick, even when hidden. Changing its GPU
arguments restarted the stream. Vendor helpers added their own on-demand
reads, and the CPU tab could also poll integrated graphics.

Reading telemetry may interact with runtime PM on the target driver. The
specific attributes, their effect on idle timing, and the useful collection
window need measurement on that machine. Slowing one helper does not establish
that the GPU is left idle if another reader continues polling.

The Hardware collector already avoids GPU-owned telemetry inputs. Its FIFO
fixtures establish that exclusion, not whether existing stream, helper, DRM,
or metadata reads permit a physical GPU to suspend. Acquisition-aware GPU history is now covered by deterministic tests;
physical wake/suspend behavior remains a separate hardware question.

Runtime suspend here means a device's runtime PM state, not whole-system
suspend, hibernation, a clock-frequency reduction, or a zero-utilization
reading. AMD runtime power-down is conditional on device/driver support and
configuration; see the kernel's [AMDGPU module parameters](https://docs.kernel.org/gpu/amdgpu/module-parameters.html).

## Reader audit for the follow-up

Audit actual file opens and tool launches, not only timer settings. Separate
identity discovery from telemetry, and record which reads affect the target
device rather than assuming every sysfs attribute behaves alike.

| Path | What needs checking |
| --- | --- |
| [Streaming sampler](../scripts/quadrant-stream) | Dedicated AMD busy, VRAM, memory busy, clocks, temperature, power, and engine reads; startup probes and per-tick reads |
| [GPU helper](../scripts/gpu-stats) | Selected-card telemetry, including memory clock and hwmon, plus its launch of the DRM helper |
| [DRM helper](../scripts/gpu-drm) | Per-process fdinfo and device-specific sysfs reads; identify whether each path affects the selected GPU's idle behavior |
| [Shared Store](../components/Store.qml) | Bar, GPU-tab, and CPU/iGPU demand; explicit refreshes, settings visibility, queued/in-flight work, and two monitors |
| [Hardware collector](../scripts/hardware-info.py) | Preserve GPU input exclusion; verify identity/label discovery and future pinned-sensor collection cannot bypass the device policy |
| [System identity](../scripts/system-info) and GPU inventory | Startup/R metadata access, including tools; retain identification without adding periodic telemetry probes |

External readers such as another hardware monitor are outside Quadrant's
coordination. Record them in hardware results so a baseline failure is not
automatically attributed to this plugin.

## Acceptance contract

1. **Start with visibility control.** Add a runtime control channel through
   which the stream can skip GPU reads without exiting. A small atomic control
   file checked with Bash builtins is one candidate. Preserve the no-fork tick
   budget and continuous CPU, memory, drive, and network samples. GPU selection
   changes and visibility changes must have explicit device/generation handling.
2. **Use one policy per physical device.** The shared Store should combine
   demand from all monitors and relevant views, then coordinate stream and
   helper eligibility. A cooldown local to one helper is insufficient. Include
   late requests, replaced/renumbered devices, helper failures, and cleanup of
   stale control state. The compatibility fallback can create independent
   Stores; account for their coordination or explicitly document the degraded
   guarantee rather than claiming sharing across independent processes.
3. **Respect power state before telemetry.** A suspended or transitioning GPU
   should not be queried merely because the UI redraws. Once the GPU becomes
   active, coordinate eligible reads. Checking status is not an atomic lock
   against a subsequent transition; audit the remaining race and verify the
   target driver's behavior instead of treating a status check alone as proof.
4. **Choose batching from evidence.** If active-state telemetry repeatedly
   postpones suspend, group necessary reads into a short window followed by a
   shared quiet period. An available non-negative autosuspend delay plus a
   margin is a candidate input, not a universal fixed interval. Bound the
   policy and specify behavior for missing, negative, unreadable, or disabled
   PM metadata. Linux's [runtime PM documentation](https://docs.kernel.org/power/runtime_pm.html)
   explains autosuspend timing; the actual policy still needs hardware results.
5. **Carry measurement time and state.** Associate each accepted reading with
   its device identity, acquisition time, and collection generation. Distinguish
   sleeping, intentionally held, stale, unavailable, and failed states where
   useful in the bar, tooltip, and panel. Unknown or sleeping must not become
   measured zero. Use monotonic time for policy intervals and preserve the
   appropriate wall-clock timestamp for graph display.
6. **Record only fresh measurements.** Held values may remain visible with an
   age, but must not become new history points on each stream tick. Leave gaps
   when collection is suppressed; reset rate baselines after invalid intervals,
   device changes, and resume where required. Apply this to bar trends, minute
   history, and persisted hour buckets.

The default candidate is to stop GPU telemetry when no relevant view needs it,
leaving history gaps. Before implementation, decide whether any reduced
background-history cadence is justified, whether opening a detail view permits
an active query of a sleeping card, and how missing PM metadata falls back.
Keep those decisions explicit and test them; displaying a bar value alone
should not silently promise uninterrupted, fresh GPU history.

This work concerns collection scheduling. It does not require Quadrant to
change `power/control`, autosuspend delays, driver module parameters, clocks,
or performance profiles. Keep power-policy configuration with the system.
Avoid unrelated NVIDIA/Intel collection changes while preserving their current
behavior under shared contract changes.

## Fixture validation targets

Use private sysfs/proc fixtures, deterministic clocks, and delayed/failing
helpers to test:

- Active, suspended, and transitioning states; missing/invalid status and PM
  metadata; disabled runtime PM; and permission errors.
- GPU segment and tab visibility, CPU/iGPU demand, Hardware details, settings,
  explicit R refreshes, and two monitors resolving one service. Hiding every
  relevant view must stop telemetry reads, not merely hide their output.
- Coalesced requests, shared windows/cooldowns, in-flight responses after close
  or selection changes, GPU removal/return, and stream/helper restart recovery.
- Accurate held/stale age, measured zero versus unknown, fresh-only history,
  gap handling, counter baseline resets, and unchanged unrelated metric streams.
- Both mawk/gawk paths and a fork-budget test that actually enables the fake
  AMD GPU path. Exercise reads enabled, disabled, and toggled while checking
  that the stream PID and non-GPU ticks continue. Use read traps or equivalent
  instrumentation to establish which files were opened.

Fixture tests can prove those software contracts. They cannot prove that a
real driver permits suspend, avoids wakeups, or saves a particular amount of
power. Preserve that distinction in the PR and test report.

## AMD hardware validation procedure

Use the [read-only observer](../scripts/amd-runtime-power.py),
[results template](AMD_RUNTIME_POWER_RESULTS_TEMPLATE.md), and
[recorded desktop results](AMD_RUNTIME_POWER_RESULTS.md). For example:

```sh
python3 scripts/amd-runtime-power.py --pci 0000:03:00.0 --duration 60 \
  --context "Quadrant disabled; idle desktop" > /tmp/amd-baseline.jsonl
```

The observer writes JSONL only to stdout. Every file read and error is included;
its periodic loop reads PM status/timing attributes, not GPU telemetry. It does
not toggle Quadrant or modify any system policy. Record external readers and
view/workload conditions separately. When temporarily disabling the widget,
preserve its complete entry and position: Omarchy disable/enable can remove
inline settings and reinsert it at its default location.

1. **Identify the target and conditions.** Record GPU model and PCI identity,
   driver/kernel versions, relevant module parameters, display connections,
   AC/battery state, running GPU workloads, other monitors, Quadrant settings,
   and the exact baseline/patched commits. Track the physical GPU across any
   `cardN` changes.
2. **Establish a baseline with Quadrant disabled.** Observe runtime status and
   available active/suspended time counters using the same observation method
   for every case. Record `power/control` and `autosuspend_delay_ms` where
   available. A target that never suspends under those idle conditions cannot
   establish the intended suspend-preservation result; report that limitation
   and investigate the baseline rather than treating it as a patched failure.
3. **Measure the current behavior.** Repeat with the existing implementation,
   first with all GPU views hidden, then with the GPU bar/detail visible. Note
   state transitions, time to suspend after a workload, helper activity, and
   whether opening CPU or Hardware changes the result.
4. **Compare the patched behavior.** Use the cases below under matching
   conditions. Choose an idle observation window comfortably longer than the
   reported autosuspend delay plus the proposed quiet period and margin; record
   the actual window. Repeat runs so a single incidental wakeup does not decide
   the result. Missing timing metadata requires a documented observation window.
5. **Isolate readers if needed.** Compare stream-only, vendor/helper/DRM, and
   sensor paths to identify which reads matter before selecting a cooldown.
   Instrumentation should log its own reads. The diagnostic observer should
   avoid periodic telemetry reads during idle tests, since those could change
   the behavior being measured.
6. **Return a compact report.** Include transitions and timestamps, available
   runtime-active/suspended counter deltas, requested/actual collection times,
   relevant read-path logs, visible freshness/history behavior, errors, and any
   deviations from the baseline. Runtime-suspended status alone is not a wattage
   measurement; make power-saving claims only with corresponding measurements.

The sysfs [power-attribute ABI](https://github.com/torvalds/linux/blob/master/Documentation/ABI/testing/sysfs-devices-power)
documents runtime status/timing and control attributes. Missing attributes or
read failures belong in the report, not fabricated defaults. The diagnostic
script should not enable runtime PM or write system configuration for a test.

| Patched case | Expected evidence |
| --- | --- |
| All GPU views hidden on every monitor | Telemetry stops; supported idle suspend remains possible; unrelated samples continue |
| GPU bar visible, detail closed | The chosen held/sleeping policy is visible; collection does not prevent baseline-supported idle suspend |
| GPU detail visible, including settings opened over it | The documented detail policy applies; no second independent collection loop |
| CPU/iGPU and Hardware views | Each physical GPU follows its own demand; generic sensor reads do not bypass the gate |
| Two monitors with different views | One device policy combines their demand; closing one view retains only necessary work, closing the last stops it |
| GPU workload starts and finishes | Useful fresh readings resume within the documented latency bound; suspend remains possible after activity ends |
| Device switch or removal/return | Stale results are discarded; readings, control state, and baselines belong to the correct device |
| PM unavailable/disabled or helper failure | Honest availability/error feedback, bounded collection behavior, and no disruption of unrelated metrics |

Unsupported/disabled-state and removal cases can be covered with fixtures when
the physical machine cannot reproduce them without configuration changes.
Keep any untested hardware cases explicitly marked as such.

## Hardware completion criteria

- A GPU shown to suspend with Quadrant disabled can still suspend under the
  corresponding tested idle conditions with the patched monitor enabled.
- Every relevant Quadrant read path participates in the per-device policy;
  multi-monitor behavior and compatibility-fallback limits are documented.
- Visibility toggles do not restart the stream or create gaps in other metrics.
  The GPU-enabled fork-budget test passes.
- Activity/resume gives useful fresh measurements within a documented bound.
  Sleeping, held, unknown, and failed readings remain understandable.
- Minute, hour, and bar histories use acquisition times and genuine samples,
  with gaps for suppressed collection and no repeated cached samples.
- Fixture coverage and the maintainer's AMD baseline/patched test report are
  included. Any remaining hardware uncertainty or fallback is stated alongside
  the result, with no claim of verified suspend behavior based on fixtures alone.
