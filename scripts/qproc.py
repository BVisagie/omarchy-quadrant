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

exe and cmdline are read for the top candidates only, never for every
pid. comm is /proc/<pid>/comm, never argv. QUADRANT_PROC_PATH overrides
/proc and QUADRANT_NOW overrides the clock for tests.
"""
from __future__ import annotations

import json
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


def sample(count: int, window: float) -> dict:
    proc = proc_root()
    runtime = os.environ.get("XDG_RUNTIME_DIR") or os.path.join(os.path.expanduser("~"), ".cache")
    state_path = os.path.join(runtime, "quadrant-procs.json")
    clk = os.sysconf("SC_CLK_TCK") or 100
    page = os.sysconf("SC_PAGE_SIZE") or 4096
    ncpu = os.cpu_count() or 1
    now = now_s()
    limit = min(32, max(count * 4, 16))

    procs_running = 0
    stat_text = read_text(os.path.join(proc, "stat"))
    if stat_text:
        for line in stat_text.splitlines():
            if line.startswith("procs_running"):
                parts = line.split()
                if len(parts) > 1 and parts[1].isdigit():
                    procs_running = int(parts[1])

    snap: dict[str, dict] = {}
    io_hidden = 0
    io_visible = 0
    threads = 0
    try:
        pids = [p for p in os.listdir(proc) if p.isdigit()]
    except OSError:
        pids = []
    for pid in pids:
        text = read_text(os.path.join(proc, pid, "stat"), 4096)
        if not text:
            continue
        st = parse_stat(text)
        if not st:
            continue
        comm = (read_text(os.path.join(proc, pid, "comm"), 256) or "").strip().replace("\n", " ")[:128] or pid
        threads += st["threads"]
        rec = {
            "pid": int(pid),
            "key": "%s:%d" % (pid, st["start"]),
            "ticks": st["ticks"],
            "rss_kb": st["rss_pages"] * page // 1024,
            "comm": comm,
            "rb": None,
            "wb": None,
        }
        io_text = read_text(os.path.join(proc, pid, "io"), 1024)
        if io_text is None:
            io_hidden += 1
        else:
            parsed = parse_io(io_text)
            if parsed:
                rec["rb"], rec["wb"] = parsed
                io_visible += 1
            else:
                io_hidden += 1
        snap[rec["key"]] = rec

    prev = load_state(state_path)
    save_state(state_path, {
        "t": now,
        "p": {k: {"tk": v["ticks"], "rb": v["rb"], "wb": v["wb"]} for k, v in snap.items()},
    })

    dt = 0.0
    cpu_rows: list[tuple] = []
    io_rows: list[tuple] = []
    if prev:
        dt = now - float(prev["t"])
        before = prev["p"]
        if 0.4 <= dt <= max(window, 0.4):
            for key, cur in snap.items():
                old = before.get(key)
                if not old or old.get("tk") is None:
                    continue
                delta = cur["ticks"] - int(old["tk"])
                if delta >= 0:
                    core_pct = 100.0 * delta / float(clk) / dt
                    cpu_rows.append((core_pct, cur))
                if cur["rb"] is not None and old.get("rb") is not None:
                    dr = cur["rb"] - int(old["rb"])
                    dw = cur["wb"] - int(old["wb"] or 0)
                    if dr >= 0 and dw >= 0 and (dr > 0 or dw > 0):
                        io_rows.append((dr / dt, dw / dt, cur))
        else:
            dt = 0.0

    cpu_rows.sort(key=lambda r: (-r[0], r[1]["pid"]))
    io_rows.sort(key=lambda r: (-(r[0] + r[1]), r[2]["pid"]))
    mem_rows = sorted(snap.values(), key=lambda r: (-r["rss_kb"], r["pid"]))

    # exe/cmdline (and PSS for memory) only for the rows that can show.
    details: dict[str, dict] = {}

    def detail(rec: dict) -> dict:
        key = rec["key"]
        if key not in details:
            pid = str(rec["pid"])
            argv = cmdline_argv(proc, pid)
            details[key] = {
                "exe": exe_base(proc, pid),
                "cmd": " ".join(argv)[:160],
                "script": script_name(rec["comm"], argv),
            }
        return details[key]

    def row(rec: dict) -> dict:
        d = detail(rec)
        return {"pid": rec["pid"], "comm": rec["comm"], "exe": d["exe"], "cmd": d["cmd"], "script": d["script"]}

    out_cpu = []
    for core_pct, rec in cpu_rows[:limit]:
        r = row(rec)
        r["value"] = round(core_pct / ncpu, 2)
        r["core"] = round(core_pct, 1)
        out_cpu.append(r)
    out_mem = []
    for rec in mem_rows[:limit]:
        r = row(rec)
        pss = parse_pss_kb(read_text(os.path.join(proc, str(rec["pid"]), "smaps_rollup"), 8192) or "")
        r["value"] = pss if pss is not None else rec["rss_kb"]
        r["kind"] = "pss" if pss is not None else "rss"
        out_mem.append(r)
    out_io = []
    for rbps, wbps, rec in io_rows[:limit]:
        r = row(rec)
        r["read"] = round(rbps)
        r["write"] = round(wbps)
        r["value"] = round(rbps + wbps)
        out_io.append(r)

    return {
        "dt": round(dt, 3),
        "ncpu": ncpu,
        "procs": len(snap),
        "running": procs_running,
        "threads": threads,
        "ioVisible": io_visible,
        "ioHidden": io_hidden,
        "cpu": out_cpu,
        "mem": out_mem,
        "io": out_io,
    }


def main(argv: list[str]) -> int:
    count = 5
    window = 15.0
    args = list(argv)
    while args:
        a = args.pop(0)
        if a == "--window" and args:
            try:
                window = float(args.pop(0))
            except ValueError:
                window = 15.0
        elif a.isdigit():
            count = int(a)
    count = max(1, min(10, count))
    window = max(0.4, min(600.0, window))
    json.dump(sample(count, window), sys.stdout, separators=(",", ":"))
    print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
