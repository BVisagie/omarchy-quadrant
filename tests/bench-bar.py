#!/usr/bin/env python3
"""Measure bar rendering with identical synthetic history and a shared service.

This isolates UI work, not hardware collection or power. Example:
  python3 tests/bench-bar.py --cases baseline,text --baseline origin/main
  python3 tests/bench-bar.py --cases graph,graph2
"""
import argparse
import json
import os
import signal
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def children(pid):
    try:
        return [int(child) for child in Path(f"/proc/{pid}/task/{pid}/children").read_text().split()]
    except FileNotFoundError:
        return []


def quickshell_pid(parent):
    for pid in children(parent):
        try:
            if Path(f"/proc/{pid}/exe").resolve().name in ("quickshell", "qs"):
                return pid
        except FileNotFoundError:
            continue
        found = quickshell_pid(pid)
        if found:
            return found
    return None


def sample(pid):
    fields = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
    cpu = (int(fields[11]) + int(fields[12])) / os.sysconf("SC_CLK_TCK")
    rss = int(Path(f"/proc/{pid}/statm").read_text().split()[1]) * os.sysconf("SC_PAGE_SIZE") / 1048576
    return cpu, rss, len(children(pid))


def measure(case, args):
    with tempfile.TemporaryDirectory(prefix="quadrant-bar-bench-") as temp:
        env = dict(os.environ, QUADRANT_RENDER_BAR_STYLE="graph-text" if case.startswith("graph") else "text",
                   QUADRANT_RENDER_ORDER="cpu,gpu,memory,disk,network", QUADRANT_RENDER_MONITORS="2" if case == "graph2" else "1",
                   QUADRANT_BENCH_SECONDS=str(args.seconds + 5))
        env.pop("QUADRANT_RENDER_BAR_REF", None)
        if case == "baseline":
            env["QUADRANT_RENDER_BAR_REF"] = args.baseline
        with open(Path(temp) / "render.log", "w+") as log:
            process = subprocess.Popen(["bash", "tests/render-bar.sh", str(Path(temp) / "bar.png")], cwd=ROOT, env=env, stdout=log, stderr=log, start_new_session=True)
            try:
                deadline = time.monotonic() + 5
                pid = None
                while time.monotonic() < deadline and not pid and process.poll() is None:
                    pid = quickshell_pid(process.pid)
                    time.sleep(0.05)
                if not pid:
                    raise RuntimeError("quickshell did not start")
                time.sleep(3)
                start_cpu, _, _ = sample(pid)
                start = time.monotonic()
                readings = []
                while time.monotonic() - start < args.seconds:
                    readings.append(sample(pid))
                    time.sleep(0.5)
                end_cpu, rss, child_count = sample(pid)
                elapsed = time.monotonic() - start
                readings.append((end_cpu, rss, child_count))
                process.wait(timeout=10)
                if process.returncode:
                    log.seek(0)
                    raise RuntimeError(log.read())
                log.seek(0)
                layout = next(line.split("BAR_LAYOUT ", 1)[1] for line in log if "BAR_LAYOUT {" in line)
                return {"case": case, "seconds": round(elapsed, 2), "cpuSeconds": round(end_cpu - start_cpu, 3),
                        "corePercent": round((end_cpu - start_cpu) / elapsed * 100, 2), "peakRssMiB": round(max(row[1] for row in readings), 2),
                        "peakChildren": max(row[2] for row in readings), "layout": json.loads(layout)}
            finally:
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGTERM)
                    process.wait(timeout=5)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", default="origin/main")
    parser.add_argument("--cases", default="baseline,text,graph,graph2")
    parser.add_argument("--seconds", type=int, default=10, choices=range(3, 21))
    arguments = parser.parse_args()
    for selected in arguments.cases.split(","):
        if selected not in ("baseline", "text", "graph", "graph2"):
            parser.error(f"unknown case: {selected}")
        print(json.dumps(measure(selected, arguments)), flush=True)
