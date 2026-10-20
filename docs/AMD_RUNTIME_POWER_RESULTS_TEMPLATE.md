# AMD runtime PM results template

Copy this template for each physical GPU and test setup. Keep raw observer
JSONL locally; review identifying information before publishing it.

## Conditions

- Date, GPU model, PCI identity, driver/kernel/Omarchy versions:
- Baseline and patched commit SHAs:
- `power/control`, runtime status, autosuspend delay, module parameters:
- Missing/unreadable attributes (include errors):
- Display connections, active modes, existing clock/display workarounds:
- AC/battery state, workloads and other possible GPU readers:
- Quadrant settings, bar/tab/settings visibility and monitor count:
- Shared service or independent embedded fallback Stores:
- Observation interval, requested/actual duration and repetition count:
- Observer command and local output path:

## Cases

For disabled, current-enabled and patched cases, record:

- Transitions with timestamps; active/suspended counter deltas:
- Requested and actual telemetry reads, tools launched, and instrumentation:
- Time from workload completion to suspend, if the baseline supports it:
- Time to useful fresh data after activity:
- Stream PID and non-GPU sample continuity across visibility/device changes:
- Held/sleeping/failed presentation, actual acquisition age and history gaps:
- Errors, external wakeups and deviations between runs:

Cover hidden views, GPU bar, GPU detail/settings, CPU/iGPU, Hardware, two
monitors, workload start/finish, refresh, device changes/removal/return and
failure/fallback cases. Mark fixture-only or untested hardware cases explicitly.

## Conclusion

- Did this GPU runtime-suspend with Quadrant disabled under these conditions?
- If so, did it also suspend with the patched monitor enabled?
- Which read paths affected idle timing, and what supports any quiet window?
- Which software contracts passed independently of physical suspend?
- Remaining limitations and required hardware follow-up:
- Wattage measurements, or explicitly state that none were collected:

The read-only observer does not disable Quadrant, change system power policy,
read telemetry periodically or establish a wattage saving. Preserve the whole
widget entry and its position when toggling it: Omarchy's disable/enable path
can remove inline settings and restore default placement.
