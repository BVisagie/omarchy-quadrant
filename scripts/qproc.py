#!/usr/bin/env python3
"""One /proc walk for Quadrant's panel: top processes by CPU, memory and
disk I/O in a single pass, plus process/thread counts.

Prints one JSON object (the bash wrapper `process-sample` wraps it in the
usual envelope). Every rate is an interval over consecutive runs; state
lives in $XDG_RUNTIME_DIR/quadrant-procs.json keyed by pid:starttime so a
reused pid can never inherit the old process's counters. The first run
after a cold start has no rates.

  cpu rows   value = percent of the whole machine (0-100), core = of one core
  mem rows   value = KiB; PSS from smaps_rollup for the top candidates
             (shared pages counted once), RSS otherwise — `kind` says which
  io rows    read/write = bytes per second from /proc/<pid>/io, which the
             kernel only exposes for processes you own; `ioHidden` counts
             the processes whose I/O could not be read

Compact mode reads exe/cmdline and PSS for at most 32 candidates per metric.
--expanded returns one eligible roster with RSS and nullable CPU/I/O rates.
All modes share a locked baseline; requests within 400 ms are skipped. comm is /proc/<pid>/comm, never argv. QUADRANT_PROC_PATH overrides
/proc and QUADRANT_NOW overrides the clock for tests.
"""
from __future__ import annotations

import fcntl
import json
import math
import os
import sys
import time

INTERPRETERS = {
    "python", "python3", "python2", "node", "nodejs", "bun", "deno", "ruby",
    "perl", "bash", "sh", "zsh", "dash", "fish", "lua", "php", "java", "Rscript",
}


def proc_root() -> str:
    return os.environ.get("QUADRANT_PROC_PATH", "/proc")


def now_s() -> float:
    override = os.environ.get("QUADRANT_NOW")
    if override:
        try:
            return float(override)
        except ValueError:
            pass
    return time.monotonic()


def read_text(path: str, limit: int = 65536) -> str | None:
    try:
        with open(path, "rb") as fh:
            return fh.read(limit).decode("utf-8", "replace")
    except OSError:
        return None


def parse_stat(text: str) -> dict | None:
    """Fields after the parenthesised comm: 0=state … 11=utime 12=stime
    19=starttime 17=num_threads 21=rss (pages)."""
    rparen = text.rfind(")")
    if rparen < 0:
        return None
    fields = text[rparen + 1:].split()
    if len(fields) < 22:
        return None
    try:
        return {
            "state": fields[0],
            "ticks": int(fields[11]) + int(fields[12]),
            "threads": int(fields[17]),
            "start": int(fields[19]),
            "rss_pages": int(fields[21]),
        }
    except ValueError:
        return None


def parse_io(text: str) -> tuple[int, int] | None:
    rb = wb = None
    for line in text.splitlines():
        if line.startswith("read_bytes:"):
            rb = int(line.split(":", 1)[1].strip() or 0)
        elif line.startswith("write_bytes:"):
            wb = int(line.split(":", 1)[1].strip() or 0)
    if rb is None or wb is None:
        return None
    return rb, wb


def parse_pss_kb(text: str) -> int | None:
    for line in text.splitlines():
        if line.startswith("Pss:"):
            parts = line.split()
            if len(parts) >= 2 and parts[1].isdigit():
                return int(parts[1])
    return None


def exe_base(proc: str, pid: str) -> str:
    try:
        target = os.readlink(os.path.join(proc, pid, "exe"))
    except OSError:
        return ""
    return os.path.basename(target).replace(" (deleted)", "")[:64]


def cmdline_argv(proc: str, pid: str) -> list[str]:
    try:
        with open(os.path.join(proc, pid, "cmdline"), "rb") as fh:
            raw = fh.read(4096)
    except OSError:
        return []
    return [a.decode("utf-8", "replace") for a in raw.split(b"\0") if a]


def script_name(comm: str, argv: list[str]) -> str:
    """For an interpreter, the script it runs — `python3 foo.py` → foo.py."""
    base = comm.split("/")[-1]
    if base not in INTERPRETERS and not base.startswith("python3."):
        return ""
    for arg in argv[1:]:
        if arg.startswith("-"):
            if arg in ("-m", "-c", "-e", "--"):
                return ""
            continue
        name = os.path.basename(arg.rstrip("/"))
        return name[:64] if name else ""
    return ""


def load_state(path: str) -> dict | None:
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return None
    if not isinstance(data, dict) or "t" not in data or not isinstance(data.get("p"), dict):
        return None
    return data


def save_state(path: str, state: dict) -> None:
    tmp = path + ".tmp"
    try:
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(state, fh, separators=(",", ":"))
        os.replace(tmp, path)
    except OSError:
        try:
            os.unlink(tmp)
        except OSError:
            pass


def sample(count: int, window: float, expanded: bool = False) -> dict:
    """Serialize all modes through the same private counter baseline.

    Skipped requests never walk /proc or advance the baseline. The shell has
    one owner, but the lock also protects manual/overlapping helper runs.
    """
    runtime = os.environ.get("XDG_RUNTIME_DIR") or os.path.join(os.path.expanduser("~"), ".cache")
    state_path = os.path.join(runtime, "quadrant-procs.json")
    fd = os.open(state_path + ".lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        return collect(count, window, expanded, state_path)


def collect(count: int, window: float, expanded: bool, state_path: str) -> dict:
    proc = proc_root()
    now = now_s()
    prev = load_state(state_path)
    try:
        elapsed = now - float(prev["t"]) if prev else 0.0
        if not math.isfinite(elapsed):
            prev = None
    except (TypeError, ValueError):
        prev = None
        elapsed = 0.0
    if prev and 0 <= elapsed < 0.4:
        return {"skipped": True, "retryAfterMs": math.ceil((0.4 - elapsed) * 1000),
                "cpu": [], "mem": [], "io": []}

    clk = os.sysconf("SC_CLK_TCK") or 100
    page = os.sysconf("SC_PAGE_SIZE") or 4096
    ncpu = os.cpu_count() or 1
    limit = min(32, max(count * 4, 16))
    dt = elapsed if prev and 0.4 <= elapsed <= max(window, 0.4) else 0.0
    rate_state = "ready" if dt else ("stale" if prev else "cold")
    before = prev["p"] if dt else {}

    procs_running = 0
    for line in (read_text(os.path.join(proc, "stat")) or "").splitlines():
        if line.startswith("procs_running"):
            parts = line.split()
            if len(parts) > 1 and parts[1].isdigit():
                procs_running = int(parts[1])

    snap: dict[str, dict] = {}
    io_hidden = io_visible = threads = cpu_ready = io_ready = 0
    # An unreadable /proc is an error, never a successful empty roster.
    pids = [p for p in os.listdir(proc) if p.isdigit()]
    for pid in pids:
        st = parse_stat(read_text(os.path.join(proc, pid, "stat"), 4096) or "")
        if not st:
            continue
        comm = (read_text(os.path.join(proc, pid, "comm"), 256) or "").strip().replace("\n", " ")[:128] or pid
        threads += st["threads"]
        rec = {
            "pid": int(pid), "start": st["start"], "key": "%s:%d" % (pid, st["start"]),
            "ticks": st["ticks"], "rss_kb": max(0, st["rss_pages"] * page // 1024),
            "comm": comm, "rb": None, "wb": None, "cpu": None, "core": None,
            "read": None, "write": None,
        }
        try:
            parsed = parse_io(read_text(os.path.join(proc, pid, "io"), 1024) or "")
        except ValueError:
            parsed = None
        if parsed and min(parsed) >= 0:
            rec["rb"], rec["wb"] = parsed
            io_visible += 1
        else:
            io_hidden += 1
        old = before.get(rec["key"])
        if isinstance(old, dict):
            try:
                delta = rec["ticks"] - int(old["tk"])
                if delta >= 0:
                    rec["core"] = round(100.0 * delta / clk / dt, 1)
                    rec["cpu"] = round(100.0 * delta / clk / dt / ncpu, 2)
                    cpu_ready += 1
                if rec["rb"] is not None and old.get("rb") is not None:
                    dr, dw = rec["rb"] - int(old["rb"]), rec["wb"] - int(old["wb"])
                    if min(dr, dw) >= 0:
                        rec["read"], rec["write"] = round(dr / dt), round(dw / dt)
                        io_ready += 1
            except (KeyError, TypeError, ValueError):
                pass  # A corrupt counter or a reset requires another interval.
        snap[rec["key"]] = rec

    save_state(state_path, {
        "t": now,
        "p": {k: {"tk": v["ticks"], "rb": v["rb"], "wb": v["wb"]} for k, v in snap.items()},
    })
    details: dict[str, dict] = {}

    def row(rec: dict) -> dict:
        key = rec["key"]
        if key not in details:
            pid = str(rec["pid"])
            argv = cmdline_argv(proc, pid)
            details[key] = {"pid": rec["pid"], "start": rec["start"], "comm": rec["comm"],
                            "exe": exe_base(proc, pid), "cmd": " ".join(argv)[:160],
                            "script": script_name(rec["comm"], argv)}
        return dict(details[key])

    result = {
        "mode": "expanded" if expanded else "compact", "dt": round(dt, 3), "rateState": rate_state,
        "ncpu": ncpu, "procs": len(snap), "observed": len(pids), "unreadable": len(pids) - len(snap),
        "running": procs_running, "threads": threads, "cpuReady": cpu_ready, "ioReady": io_ready,
        "ioVisible": io_visible, "ioHidden": io_hidden, "candidateLimit": 0 if expanded else limit,
        "cpu": [], "mem": [], "io": [],
    }
    if expanded:
        # One roster, not three copies. RSS avoids opening every smaps_rollup
        # at panel cadence. Shared pages count for each process; the UI says so.
        rows = []
        for rec in snap.values():
            r = row(rec)
            r.update(cpu=rec["cpu"], core=rec["core"], memory=rec["rss_kb"], kind="rss",
                     read=rec["read"], write=rec["write"], ioVisible=rec["rb"] is not None)
            rows.append(r)
        result["rows"] = rows
        return result

    cpu = sorted((r for r in snap.values() if r["cpu"] is not None), key=lambda r: (-r["cpu"], r["pid"]))
    mem = sorted(snap.values(), key=lambda r: (-r["rss_kb"], r["pid"]))
    io = sorted((r for r in snap.values() if r["read"] is not None and r["read"] + r["write"] > 0),
                key=lambda r: (-(r["read"] + r["write"]), r["pid"]))
    for rec in cpu[:limit]:
        r = row(rec)
        r.update(value=rec["cpu"], core=rec["core"])
        result["cpu"].append(r)
    for rec in mem[:limit]:
        r = row(rec)
        pss = parse_pss_kb(read_text(os.path.join(proc, str(rec["pid"]), "smaps_rollup"), 8192) or "")
        r.update(value=pss if pss is not None else rec["rss_kb"], kind="pss" if pss is not None else "rss")
        result["mem"].append(r)
    for rec in io[:limit]:
        r = row(rec)
        r.update(read=rec["read"], write=rec["write"], value=rec["read"] + rec["write"])
        result["io"].append(r)
    return result


def main(argv: list[str]) -> int:
    count = 5
    window = 15.0
    expanded = False
    args = list(argv)
    while args:
        a = args.pop(0)
        if a == "--expanded":
            expanded = True
        elif a == "--window" and args:
            try:
                window = float(args.pop(0))
            except ValueError:
                window = 15.0
        elif a.isdigit():
            count = int(a)
    count = max(1, min(10, count))
    window = max(0.4, min(600.0, window))
    json.dump(sample(count, window, expanded), sys.stdout, separators=(",", ":"))
    print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
