#!/usr/bin/env python3
"""Read-only runtime PM observer. Never opens GPU telemetry or DRM devices.

JSONL stdout includes every file read (including errors), wall/boot time,
transitions and counter deltas. Redirect it to a report; no privileges needed.
"""
import argparse
import datetime
import json
import math
import os
from pathlib import Path
import re
import time


def read(path):
    try:
        return {"path": str(path), "value": path.read_text().strip()}
    except OSError as exc:
        return {"path": str(path), "error": exc.errno}


def emit(event, **values):
    print(json.dumps({"event": event, **values}, separators=(",", ":")), flush=True)


def boot_ms():
    return time.clock_gettime_ns(time.CLOCK_BOOTTIME) // 1_000_000


def observe(sys, proc, pci, duration, interval, context):
    device = sys / "bus/pci/devices" / pci
    if not device.is_dir():
        raise ValueError("PCI device is absent")
    identity = {name: read(device / name) for name in
                ("vendor", "device", "subsystem_vendor", "subsystem_device", "revision")}
    if identity["vendor"].get("value") != "0x1002":
        raise ValueError("target is not an AMD device")
    metadata = list(identity.values())
    metadata += [read(device / "power" / name) for name in
                 ("control", "autosuspend_delay_ms", "runtime_enabled", "runtime_usage")]
    metadata += [read(sys / "module/amdgpu/parameters" / name) for name in ("runpm", "aspm", "dpm", "dc")]
    metadata += [read(proc / "cmdline"), read(proc / "version")]
    cards = []
    for card in sorted((sys / "class/drm").glob("card[0-9]*")):
        if "-" in card.name or (card / "device").resolve() != device.resolve():
            continue
        cards.append(card.name)
        for connector in sorted(card.parent.glob(card.name + "-*")):
            metadata += [read(connector / name) for name in ("status", "enabled")]
    for supply in sorted((sys / "class/power_supply").glob("*")):
        metadata += [read(supply / name) for name in ("type", "online", "status")]
    emit("conditions", pci=pci, cards=cards, context=context, reads=metadata,
         duration_s=duration, interval_s=interval,
         note="Record commit/settings, panel visibility, workloads, other readers and display workaround separately.")
    start = time.monotonic()
    first = last = None
    previous = None
    transitions = 0
    count = 0
    while True:
        reads = {name: read(device / "power" / name) for name in
                 ("runtime_status", "runtime_active_time", "runtime_suspended_time")}
        status = reads["runtime_status"].get("value")
        changed = count > 0 and status != previous
        transitions += int(changed)
        emit("sample", utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
             boot_ms=boot_ms(), elapsed_s=round(time.monotonic() - start, 6),
             transition=changed, reads=list(reads.values()))
        first = first or reads
        last = reads
        previous = status
        count += 1
        remaining = duration - (time.monotonic() - start)
        if remaining <= 0:
            break
        time.sleep(min(interval, remaining))
    deltas = {}
    for name in ("runtime_active_time", "runtime_suspended_time"):
        a, b = first[name].get("value", ""), last[name].get("value", "")
        deltas[name] = int(b) - int(a) if a.isdecimal() and b.isdecimal() and int(b) >= int(a) else None
    emit("summary", elapsed_s=round(time.monotonic() - start, 6), samples=count,
         transitions=transitions, delta_ms=deltas,
         note="Runtime PM counters are not wattage measurements. A baseline must use matching conditions.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pci", required=True, help="physical PCI address, e.g. 0000:03:00.0")
    parser.add_argument("--duration", type=float, default=60)
    parser.add_argument("--interval", type=float, default=1)
    parser.add_argument("--context", default="unspecified")
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-f]{4}:[0-9a-f]{2}:[0-1][0-9a-f]\.[0-7]", args.pci):
        parser.error("invalid PCI address")
    if not math.isfinite(args.duration) or not 0 <= args.duration <= 86400:
        parser.error("duration must be finite and between 0 and 86400 seconds")
    if not math.isfinite(args.interval) or not 0.1 <= args.interval <= 60:
        parser.error("interval must be finite and between 0.1 and 60 seconds")
    try:
        observe(Path(os.environ.get("QUADRANT_SYS_PATH", "/sys")),
                Path(os.environ.get("QUADRANT_PROC_PATH", "/proc")),
                args.pci, args.duration, args.interval, args.context)
    except ValueError as exc:
        parser.error(str(exc))


if __name__ == "__main__":
    main()
