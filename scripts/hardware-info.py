#!/usr/bin/env python3
"""Bounded, read-only hwmon, package-energy and power-supply snapshots.

list reads identity only. power samples package counters only. sample also
reads non-GPU sensors and battery diagnostics. No privilege changes, device
controls, subprocesses, or GPU telemetry reads belong to this collector.
"""
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import time

MAX_SENSORS = 128
MAX_BATTERIES = 16
MAX_PACKAGES = 16
MAX_ENTRIES = 512
MAX_SAFE_INT = 9007199254740991


def text(path, limit=160):
    try:
        with path.open(encoding="utf-8", errors="replace") as stream:
            value = stream.read(limit + 1).strip()[:limit]
            return "".join(c for c in value if ord(c) >= 32 and ord(c) != 127)
    except OSError:
        return ""


def number(path, minimum=0, maximum=MAX_SAFE_INT):
    try:
        with path.open(encoding="ascii") as stream:
            raw = stream.read(80).strip()
        if not re.fullmatch(r"-?[0-9]{1,16}", raw):
            return None, "Invalid reading"
        value = int(raw)
        return (value, "") if minimum <= value <= maximum else (None, "Invalid reading")
    except PermissionError:
        return None, "Permission denied"
    except (OSError, UnicodeError):
        return None, "Unavailable"


def entries(path, pattern="*", coverage=None):
    # Bounded discovery even when a fixture or a pathological host is large.
    try:
        out = []
        with os.scandir(path) as scan:
            for index, entry in enumerate(scan):
                if index >= MAX_ENTRIES:
                    if coverage is not None:
                        coverage["truncated"] = True
                    break
                if fnmatch.fnmatchcase(entry.name, pattern):
                    out.append(path / entry.name)
        return sorted(out)
    except OSError:
        return []


def relative(path, root):
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except (OSError, ValueError):
        return ""


def sensor_owner(hw, root):
    owner = (hw / "device").resolve() if (hw / "device").exists() else hw.resolve().parent.parent
    owner_path = relative(owner, root)
    if not owner_path:
        return None
    # Controller and hwmon enumeration are not physical identities. A PCI
    # location plus NVMe serial distinguishes replacement drives as well.
    stable = re.sub(r"/nvme/nvme[0-9]+(?=/|$)", "/nvme/controller", owner_path)
    serial = text(owner / "serial", 80)
    driver = text(hw / "name", 64) or "hwmon"
    gpu = driver.lower() in {"amdgpu", "radeon", "nouveau", "nvidia", "i915", "xe"}
    for parent in [owner, *owner.parents]:
        if parent == root or parent == root.parent:
            break
        if text(parent / "class", 16).lower().startswith("0x03"):
            gpu = True
            break
    return {"owner": stable if len(stable) <= 512 else stable[:511] + "…",
            "identity": [stable, serial, driver], "driver": driver, "gpu": gpu}


def sensors(root, sample, coverage=None):
    out = []
    seen = set()
    truncated = False
    for hw in entries(root / "class/hwmon", "hwmon*", coverage):
        if len(out) >= MAX_SENSORS:
            truncated = True
            break
        owner = sensor_owner(hw, root)
        if not owner:
            continue
        for path in entries(hw, "*_input", coverage):
            match = re.fullmatch(r"(temp|fan)([0-9]{1,3})_input", path.name)
            if not match:
                continue
            if len(out) >= MAX_SENSORS:
                truncated = True
                break
            channel = path.stem.removesuffix("_input")
            identity = json.dumps([*owner["identity"], channel], ensure_ascii=True)
            key = "hwmon:" + hashlib.sha256(identity.encode()).hexdigest()
            if key in seen:
                continue
            seen.add(key)
            label = text(hw / (channel + "_label"), 80) or channel
            kind = "temperature" if match[1] == "temp" else "fan"
            value, status, critical = None, "Not sampled", None
            # Discover GPU channels but leave reads to the selected GPU's
            # existing collector. Opening Hardware must not wake every GPU.
            if owner["gpu"]:
                status = "Read on the GPU detail tab"
            elif sample:
                enabled, _ = number(hw / (channel + "_enable"), maximum=1)
                fault, _ = number(hw / (channel + "_fault"), maximum=1)
                sensor_type, _ = number(hw / (channel + "_type"), maximum=6)
                if enabled == 0:
                    status = "Disabled"
                elif fault == 1:
                    status = "Sensor fault"
                elif kind == "temperature" and sensor_type == 4:
                    status = "Thermistor calibration required"
                else:
                    value, status = number(path, -273150 if kind == "temperature" else 0,
                                           1000000 if kind == "temperature" else 100000)
                    if kind == "temperature":
                        value = value / 1000 if value is not None else None
                        critical, _ = number(hw / (channel + "_crit"), -273150, 1000000)
                        critical = critical / 1000 if critical is not None else None
            out.append({"id": key, "owner": owner["owner"], "driver": owner["driver"],
                        "channel": channel, "label": label, "kind": kind, "gpu": owner["gpu"],
                        "value": value, "criticalC": critical, "status": status})
    return out, truncated


def packages(root, sample, coverage=None):
    candidates = {}
    for path in entries(root / "class/powercap", coverage=coverage):
        if not relative(path, root):
            continue
        name = text(path / "name", 64)
        if not re.fullmatch(r"package-[0-9]{1,3}", name):
            continue
        value, status, maximum = None, "Not sampled", None
        if sample:
            # powercap 'enabled' controls capping, not whether energy is
            # measured. Reading a counter never enables or changes a limit.
            value, status = number(path / "energy_uj")
            maximum, range_status = number(path / "max_energy_range_uj", minimum=1)
            if not range_status and value is not None and value >= maximum:
                value, status = None, "Invalid energy counter"
            if range_status:
                value, status = None, range_status
        row = {"id": name, "label": name.replace("package-", "Package "),
               "source": path.name[:80], "energyUj": value, "maxEnergyUj": maximum, "status": status,
               "monotonicS": time.monotonic() if sample else None}
        # MMIO and MSR domains can describe the same package. Use one source,
        # preferring a readable counter, then the non-MMIO interface.
        rank = (value is None if sample else not os.access(path / "energy_uj", os.R_OK), "mmio" in path.name, path.name)
        if name not in candidates or rank < candidates[name][0]:
            candidates[name] = (rank, row)
    return [candidates[key][1] for key in sorted(candidates)[:MAX_PACKAGES]], len(candidates) > MAX_PACKAGES


def batteries(root, sample, coverage=None):
    out = []
    truncated = False
    for path in entries(root / "class/power_supply", coverage=coverage):
        if text(path / "type", 32) != "Battery":
            continue
        present, _ = number(path / "present", maximum=1)
        if present == 0:
            continue
        if len(out) >= MAX_BATTERIES:
            truncated = True
            break
        owner = relative(path, root)
        if not owner:
            continue
        scope = text(path / "scope", 24)
        model = text(path / "model_name", 80)
        identity = json.dumps([owner, model, text(path / "serial_number", 80)], ensure_ascii=True)
        row = {"id": "battery:" + hashlib.sha256(identity.encode()).hexdigest(), "name": path.name[:80], "model": model,
               "manufacturer": text(path / "manufacturer", 80), "scope": scope,
               "status": "Not sampled", "chargePct": None, "healthPct": None,
               "healthBasis": "",
               "cycles": None, "powerW": None, "powerEstimated": False,
               "fullWh": None, "designWh": None, "fullAh": None, "designAh": None}
        if sample:
            row["status"] = text(path / "status", 32) or "Unavailable"
            row["chargePct"], _ = number(path / "capacity", maximum=100)
            row["cycles"], _ = number(path / "cycle_count", maximum=1000000)
            power, _ = number(path / "power_now", maximum=10000000000)
            if power is not None:
                row["powerW"] = power / 1000000
            else:
                current, _ = number(path / "current_now", -1000000000, 1000000000)
                voltage, _ = number(path / "voltage_now", maximum=1000000000)
                if current is not None and voltage is not None:
                    derived = abs(current * voltage) / 1000000000000
                    if derived <= 10000:
                        row["powerW"], row["powerEstimated"] = derived, True
            for unit, label in [("energy", "Wh"), ("charge", "Ah")]:
                full, _ = number(path / (unit + "_full"), maximum=10000000000)
                design, _ = number(path / (unit + "_full_design"), maximum=10000000000)
                row["full" + label] = full / 1000000 if full is not None else None
                row["design" + label] = design / 1000000 if design is not None else None
                if full is not None and design is not None and design > 0 and full <= 2 * design:
                    if row["healthPct"] is None:
                        row["healthPct"] = 100 * full / design
                        row["healthBasis"] = unit
                if row["chargePct"] is None and full is not None and full > 0:
                    now, _ = number(path / (unit + "_now"), maximum=full)
                    if now is not None:
                        row["chargePct"] = 100 * now / full
        out.append(row)
    return out, truncated


def snapshot(root, mode):
    root = root.resolve()
    coverage = {"truncated": False}
    sensor_rows, sensor_cap = sensors(root, mode == "sample", coverage) if mode != "power" else ([], False)
    battery_rows, battery_cap = batteries(root, mode == "sample", coverage) if mode != "power" else ([], False)
    package_rows, package_cap = packages(root, mode != "list", coverage)
    return {"ok": True, "mode": mode, "monotonicS": time.monotonic(),
            "sensors": sensor_rows, "packages": package_rows, "batteries": battery_rows,
            "truncated": sensor_cap or package_cap or battery_cap or coverage["truncated"]}


def main():
    mode = sys.argv[1] if len(sys.argv) == 2 else ""
    if mode not in {"list", "power", "sample"}:
        print(json.dumps({"ok": False, "error": "Expected list, power, or sample"}))
        return 1
    try:
        print(json.dumps(snapshot(Path(os.environ.get("QUADRANT_SYS_PATH", "/sys")), mode),
                         ensure_ascii=True, allow_nan=False))
        return 0
    except (OSError, ValueError):
        print(json.dumps({"ok": False, "error": "Hardware inventory is unavailable"}))
        return 1


if __name__ == "__main__":
    sys.exit(main())
