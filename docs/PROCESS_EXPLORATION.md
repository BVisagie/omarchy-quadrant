# Process exploration contract and validation

CPU, Memory, and Drives support a compact top-consumer view and an expanded,
searchable roster. Network and GPU retain their own attribution limits.

## Collection and presentation

| Contract | Behavior |
| --- | --- |
| Ownership | The shared Store owns one process helper and one rate-state file across viewers and modes. |
| Request lifetime | A visible expanded CPU/Memory/Drives view requests full data. Settings, an unsupported tab, Show less, and panel close release that request. The last applicable viewer closing stops scheduled work. An in-flight helper can finish. |
| Cadence | Normal panel cadence plus one bounded cold follow-up around 500 ms. The Store waits at least 400 ms after completion before another helper; the helper independently skips intervals below 400 ms without touching its baseline. |
| Compact source | At most `min(32, max(processCount × 4, 16))` candidates per metric; `processCount` displayed groups. Counts cover those candidates. Naming/PSS work stays limited to candidates. |
| Expanded source | One row for each readable process stat, carrying identity, naming hints, RSS, and nullable CPU/I/O fields. All eligible members are grouped before search and presentation limits. |
| Memory | Compact candidates use readable PSS, RSS otherwise. Expanded mode uses RSS, explicitly labelled; shared pages count per process. Mixed compact groups say PSS/RSS. A change in collected mode or accounting kind starts a new memory sparkline. |
| Identity | PID plus kernel start time. A group retains history, position, or cursor selection only while a member identity survives. A name alone cannot transfer identity. |
| Search | Local normalized group name, desktop display name, and all member PIDs. A PID match identifies the matching members without replacing the group's totals. Search does not sample. |
| Bounds | At most 1 MiB of encoded envelope JSON; an oversized sample is omitted in full and reported as unavailable coverage. Search runs before the 256-group display cap. Counts and a refinement message expose that cap. |
| Rendering | Value/name order in expanded mode, sticky/value/name in compact mode. Samples retain the first visible group and pixel offset when it moves less than one viewport; larger rank changes keep the scroll position. Selection is reconciled without scrolling to it. Filter changes and explicit cursor movement reveal the target. A ListView creates only visible delegates. Installed desktop entries are indexed on inventory changes; icon paths use a 256-name cache. |
| Unknown data | Missing/reset/new CPU and I/O intervals stay null. Restricted I/O stays unavailable. Partial group totals show a lower-bound prefix and measured-member count. Sparkline gaps stay gaps. |

Name grouping describes matching process names; it does not establish
application ownership or a process tree. CPU remains a share of all machine
CPUs; I/O remains readable process `read_bytes`/`write_bytes` across all devices.
Unreadable or vanished stats are counted, rather than silently presented as
complete coverage. No names or argument hints are persisted in the counter
cache. If the state lock cannot be opened or acquired, memory/counts still
work; CPU/I/O rates are marked unavailable and shared counters are neither
read nor written unlocked. Existing helper envelopes and timeout handling
are preserved.

Keyboard and pointer behavior is described in [Usage](USAGE.md). Expansion
and queries last for the panel session; closing resets them. Settings and
other tabs suspend requests without changing process settings on disk.

## Validation performed

The Node and Python suites cover an 80-process collector, 400-row grouping
and search, mixed PSS/RSS, partial/unavailable metrics, PID reuse, overlapping
helpers, sub-400 ms baseline preservation, and transport limits. The Store
lifecycle fixture uses the real helper and two viewers: exactly one cold
sample, one warm-up, one expanded sample, and one return to compact mode.
Separate cases close the last viewer or inject an earlier valid result and
verify that the follow-up is cancelled. Oversized output preserves prior
readings; a reused member starts a new sparkline. Tests also check stateless
memory collection without a cold retry, failed lock acquisition preserving
the old baseline, and memory-history resets across modes and PSS/RSS/mixed
accounting changes.

Qt Quick Test runs inside Quickshell with the real shell key handler and
process list. It covers printable navigation letters, Space/Enter, staged
Esc, shell Tab, Down/Return/Enter handoff into filtered results, pointer
controls, search beyond the cap, cursor identity,
PID-search reuse while another group member survives, sorting in both modes,
selection after filtering, narrow-width virtualization, and scrolling the
retained target into view after clearing a filter. The UI suite runs with and
without the shell load-patch pragma. Additional regressions keep wheel/
scrollbar position across repeated samples with no cursor, a visible cursor,
an offscreen cursor, and changing value order. Nearby rank changes retain the
visible group and offset; jumps of a viewport or more in either direction
hold the scroll position while explicit navigation still reveals the cursor.

All seven offscreen render targets ran on Qt 6.12 / Quickshell 0.3.2.
Additional views covered expanded CPU/Memory/Drives, dark/light/monochrome,
320 px width, horizontal/vertical bars, and 1×/1.25×/2× device scaling. The
narrow memory view wraps its composition legend below the gauges. These
checks exercise rendering and focus delivery within a test window; they do
not measure physical compositor focus across monitors or idle power states.

## Performance observations

Measurements below were taken on 2026-10-19, on an Intel Core Ultra 9 185H
with roughly 480–500 processes, using the same machine and workload. The
merged baseline is `02b74a9`. Timings are local observations, not portable
budgets for all machines. No extra runtime dependency was installed.

Twelve direct helper collections per mode, with separate temporary runtime
state and a 2 s counter interval, produced:

| Mode | Median collection wall time | Median CPU time | Largest encoded envelope |
| --- | ---: | ---: | ---: |
| Baseline compact, 5 groups | 66.36 ms | 66.19 ms | 9,069 B |
| Current compact, 5 groups | 69.11 ms | 68.93 ms | 9,598 B |
| Current expanded RSS, 483 eligible processes | 13.26 ms | 13.22 ms | 115,043 B |

The preliminary profiling walk over 470 processes measured about 6 ms for
RSS/names and another 66 ms for all readable `smaps_rollup` files (105 PSS
readable). This supported choosing explicit RSS for the expanded view.
Compact collection remains within a 10 ms / 10% local regression allowance;
the expanded walk stays below a 50 ms observation target at this roster size.
The larger expanded envelope remains well below the 1 MiB safety boundary.

A second comparison ran the real Store without panel delegates, using a
1 s stream cadence and 2 s panel cadence. Each case settled for 3 s, then
was observed for 10 s. CPU includes the Store and its descendants; 100%
means one fully occupied CPU. RSS is median Store resident memory.

| Version / viewer state | CPU | Store RSS | Process helper runs | Median helper wall time |
| --- | ---: | ---: | ---: | ---: |
| Baseline / closed | 0.80% | 77.8 MiB | 0 | — |
| Current / closed | 0.80% | 78.0 MiB | 0 | — |
| Baseline / compact | 9.57% | 81.6 MiB | 5 | 87.91 ms |
| Current / compact | 9.47% | 82.0 MiB | 5 | 87.84 ms |
| Current / expanded | 8.57% | 101.6 MiB | 5 | 39.67 ms |
| Baseline / two compact viewers | 9.17% | 81.5 MiB | 5 | 85.54 ms |
| Current / two compact viewers | 9.27% | 82.6 MiB | 5 | 86.81 ms |
| Current / two expanded viewers | 8.57% | 105.7 MiB | 5 | 40.49 ms |

Both versions had at most one live descendant while closed and five during
panel sampling. Steady process samples stayed approximately 2 s apart,
including two viewers; expanded viewers did not add a helper stack. Local
review budgets are +1 CPU percentage point and +5 MiB for compact
operation, with less than 32 MiB extra Store RSS for this expanded roster.
These observations fit those limits. Expanded memory retains a full roster
and short histories; RSS is expected to exceed compact mode. UI tests
separately confirmed fewer than 25 delegates for a 256-row displayed model.
Graph-bar performance belongs to its later implementation phase.

To repeat, use isolated runtime/state directories, the same `/proc` workload,
`processCount=5`, `barIntervalMs=1000`, and `panelIntervalMs=2000`. Compare a
fresh Store from the baseline and current tree; record `/proc` CPU/RSS and
child trees every 100 ms after settling, along with helper start/end times.
For direct collection timings, use `time.perf_counter` / `time.process_time`
around `qproc.sample`, keeping each mode's counter file separate. Run the
standard checks in [Development](DEVELOPMENT.md) before interpreting timings.
