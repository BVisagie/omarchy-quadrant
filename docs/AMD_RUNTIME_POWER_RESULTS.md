# AMD desktop runtime PM results, 2026-10-20

[← Collection policy](AMD_RUNTIME_POWER.md) · [Results template](AMD_RUNTIME_POWER_RESULTS_TEMPLATE.md)

**Result: collection behavior passed; preserved runtime suspend is unverified.**
The disabled-Quadrant baseline never suspended. No wattage measurements were
collected, and no power-saving claim follows from these observations.

## Hardware and conditions

- XFX RX 7900 XTX, PCI `0000:03:00.0`, vendor/device `1002:744c`, subsystem
  `1eae:7901`, revision `c8`, `amdgpu`, currently `card1`.
- Intel i7-12700K, ASUS TUF GAMING Z690-PLUS WIFI D4, Omarchy 4.0.6,
  kernel `7.2.8-9-omarchy`. One DRM GPU; no exposed iGPU or battery.
- One enabled G80SD display on DP-1 at 3840 × 2160, about 239.914 Hz.
- Existing black-frame workaround retained: manual performance policy with
  the highest stock memory state, 1249 MHz, active. The recorded display
  debug flag was absent from the running kernel command line. This change
  neither applied nor removed any display/clock/module setting.
- `power/control=auto`, `autosuspend_delay_ms=5000`; `runpm`, `aspm`, `dpm`
  and `dc` module parameters were `-1`. `runtime_enabled` and `runtime_usage`
  were absent (ENOENT), not assumed disabled.
- Normal interactive desktop, with Hyprland, Xwayland, Quickshell, Brave and
  T3 processes running. DRM clients included T3's resource monitor. Their
  descriptors do not establish which programs poll telemetry. External
  readers were not stopped; no deliberate GPU workload was launched.
- Baseline/current installed commit: `0d624c50e55bab37856d7a8c8855be5a6bba03ae`.
  Patched collector commit: `2a125ae` (code in this PR).
- Installed settings used the default 1000 ms stream and 2000 ms panel
  cadences. The GPU segment was visible after re-enabling. Panel state was
  not independently recorded. The patched case used a separate offscreen
  Store with the same cadences, isolated runtime/history, and explicit
  synthetic visibility demand over the real GPU. The installed plugin was
  disabled during that case.

## Observation method

The read-only `amd-runtime-power.py` observer recorded wall/boot times, each
file read/error, runtime state and active/suspended counters every second.
Its periodic loop opened only the three PM status/timing attributes. Metadata
and connector discovery occurred once at startup. Raw JSONL and the patched
Store log were retained locally under `/tmp/quadrant-amd-power-_b_dngvy/`;
they are temporary artifacts, not repository dependencies.

One disabled/current pair was measured, followed by a patched collector case.
These were normal desktop conditions rather than an isolated headless idle
experiment. The unequal patched observation duration and external clients
prevent treating the cases as a power-saving comparison.

## Disabled and current implementation

- **Quadrant disabled:** 11:58:04–11:59:04 UTC; 60.000307 s, 61 samples,
  zero transitions. Active counter delta 60,000 ms; suspended delta 0 ms.
  The installed Quadrant sampler was confirmed stopped before observation.
- **Current implementation enabled:** 11:59:04–12:00:04 UTC; 60.000314 s,
  61 samples, zero transitions. Active delta 60,000 ms; suspended delta 0 ms.

The accumulated suspended counter was also zero in the initial assessment.
This does not identify why the GPU remained active, or establish that
Quadrant was the cause. Repeating forced display/driver configuration changes
to manufacture a suspending baseline was outside this test.

Omarchy's disable/enable path removed the widget entry and reinserted defaults.
Its original center placement and complete disk selection were restored.
For the patched run, restoration preserved the saved widget entry; the full
shell JSON compared equal to its pre-run snapshot afterward.

## Patched collector

The observer ran from 12:11:31–12:12:16 UTC: 45.000399 s, 46 samples,
zero transitions, active delta 45,000 ms and suspended delta 0 ms. This window
included the 40-second Store scenario and startup/exit edges.

The Store's four ten-second visibility stages established:

1. Hidden initially: held state, no acquired GPU value, no GPU measurements.
2. GPU bar demand: fresh native-busy readings and ten measured history points.
3. GPU detail demand: fresh complete helper readings; native stream history
   continued without reinserting cached helper samples on CPU ticks.
4. Hidden again: the last acquisition time stayed at boot-time 10,964,130 ms;
   the measured-history count stayed at 21. Its status age advanced to eight
   seconds. A boundary sample already in flight at close is allowed; results
   from an obsolete generation are rejected.

The stream PID remained 121481 throughout. CPU history grew from zero to 39
points. No forced workload, physical runtime resume, GPU removal or display
change was attempted. The live log establishes acquisition/PID behavior;
no syscall trace was available. Actual telemetry-open exclusion is established
by the private FIFO read-trap tests, not inferred from timestamps alone.

An earlier 80-second visibility run also passed before the final history
refinement. An initial live-harness launch failed because its absolute QML
import lacked a URL scheme; that launch supplies no patched behavior evidence.
The final successful run used a copied, isolated tree at the stated commit.

## Software checks and remaining hardware work

Local checks covered Node model tests, Python helper/observer tests, the real
Store visibility lifecycle, existing device-identity and watchdog recovery,
graph/bar/Hardware UI suites, shell/Python lint, QML lint, Intel path lookup,
and the AMD-enabled/toggled zero-fork test. FIFO inputs cover hidden, sleeping,
transitioning and failed states and malformed/expired/superseded controls.
Permission errors, independent physical-device demand, measured zero, missing
PM metadata and honest fallback are also covered with private fixtures.

Actual suspend/resume, per-attribute wake effects, a justified active-state
quiet window, a two-monitor physical setup, and a separate AMD iGPU remain
unverified. Embedded compatibility Stores have no cross-process batching
guarantee. A future hardware acceptance run needs a device/setup that first
runtime-suspends with Quadrant disabled. Use matching conditions and repeated
runs before claiming preservation; corresponding measurements are required
before reporting watts saved.
