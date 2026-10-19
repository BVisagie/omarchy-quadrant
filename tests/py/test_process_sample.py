import json
import os
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from helpers import SCRIPTS, load_script, write  # noqa: E402

qproc = load_script("qproc.py")


def stat_line(pid, comm, utime, stime, threads, start, rss_pages, state="S"):
    # pid (comm) state ppid pgrp session tty tpgid flags minflt cminflt majflt cmajflt
    # utime stime cutime cstime priority nice num_threads itrealvalue starttime vsize rss ...
    fields = [str(pid), "(%s)" % comm, state, "1", "1", "1", "0", "-1", "0", "0", "0", "0", "0",
              str(utime), str(stime), "0", "0", "20", "0", str(threads), "0", str(start), "1000", str(rss_pages)]
    return " ".join(fields) + " 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0\n"


class ParseHelpers(unittest.TestCase):
    def test_parse_stat_handles_parenthesised_comm(self):
        st = qproc.parse_stat(stat_line(7, "evil) R 1 (x", 10, 5, 3, 999, 40))
        self.assertEqual((st["ticks"], st["threads"], st["start"], st["rss_pages"]), (15, 3, 999, 40))
        self.assertIsNone(qproc.parse_stat("garbage"))

    def test_parse_io_and_pss(self):
        self.assertEqual(qproc.parse_io("rchar: 1\nread_bytes: 20\nwrite_bytes: 30\n"), (20, 30))
        self.assertIsNone(qproc.parse_io("rchar: 1\n"))
        self.assertEqual(qproc.parse_pss_kb("Rss: 10 kB\nPss: 7 kB\n"), 7)
        self.assertIsNone(qproc.parse_pss_kb(""))

    def test_script_name_only_for_interpreters(self):
        self.assertEqual(qproc.script_name("python3", ["python3", "/opt/app/worker.py", "--x"]), "worker.py")
        self.assertEqual(qproc.script_name("python3.12", ["python3.12", "-u", "svc.py"]), "svc.py")
        self.assertEqual(qproc.script_name("node", ["node", "server.js"]), "server.js")
        self.assertEqual(qproc.script_name("python3", ["python3", "-m", "http.server"]), "")
        self.assertEqual(qproc.script_name("python3", ["python3", "-c", "print(1)"]), "")
        self.assertEqual(qproc.script_name("brave", ["brave", "page.html"]), "")
        self.assertEqual(qproc.script_name("bash", ["bash"]), "")


class Sampling(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.proc = os.path.join(self.tmp.name, "proc")
        self.runtime = os.path.join(self.tmp.name, "run")
        os.makedirs(self.proc)
        os.makedirs(self.runtime)
        os.environ["QUADRANT_PROC_PATH"] = self.proc
        os.environ["XDG_RUNTIME_DIR"] = self.runtime
        write(os.path.join(self.proc, "stat"), "cpu 1 2 3 4 5 6 7 8\nprocs_running 3\n")

    def tearDown(self):
        for k in ("QUADRANT_PROC_PATH", "XDG_RUNTIME_DIR", "QUADRANT_NOW"):
            os.environ.pop(k, None)
        self.tmp.cleanup()

    def process(self, pid, comm, ticks, start, rss_pages=100, io=None, cmdline=None, exe=None, pss=None, threads=1):
        base = os.path.join(self.proc, str(pid))
        os.makedirs(base, exist_ok=True)
        write(os.path.join(base, "stat"), stat_line(pid, comm, ticks, 0, threads, start, rss_pages))
        write(os.path.join(base, "comm"), comm + "\n")
        if io is not None:
            write(os.path.join(base, "io"), "read_bytes: %d\nwrite_bytes: %d\n" % io)
        if cmdline is not None:
            with open(os.path.join(base, "cmdline"), "wb") as fh:
                fh.write(b"\0".join(a.encode() for a in cmdline) + b"\0")
        if exe is not None and not os.path.lexists(os.path.join(base, "exe")):
            os.symlink(exe, os.path.join(base, "exe"))
        if pss is not None:
            write(os.path.join(base, "smaps_rollup"), "Rss: 999 kB\nPss: %d kB\n" % pss)

    def run_at(self, now, count=5, window=15.0, expanded=False):
        os.environ["QUADRANT_NOW"] = str(now)
        return qproc.sample(count, window, expanded)

    def test_rates_are_intervals_keyed_by_pid_and_starttime(self):
        clk = os.sysconf("SC_CLK_TCK")
        ncpu = os.cpu_count() or 1
        self.process(100, "python3", ticks=0, start=50, io=(0, 0), cmdline=["python3", "/srv/worker.py"], exe="/usr/bin/python3.12", pss=4096)
        self.process(200, "kworker/0:1", ticks=0, start=60)
        first = self.run_at(1000.0)
        self.assertEqual(first["dt"], 0)
        self.assertEqual(first["cpu"], [])
        self.assertEqual(first["procs"], 2)
        self.assertEqual(first["running"], 3)
        self.assertEqual((first["ioVisible"], first["ioHidden"]), (1, 1))
        # Two seconds later: pid 100 burned one full core; pid 200 was reused by a new process.
        self.process(100, "python3", ticks=2 * clk, start=50, io=(2048, 1024), cmdline=["python3", "/srv/worker.py"], exe="/usr/bin/python3.12", pss=4096)
        self.process(200, "kworker/0:1", ticks=5000, start=61)
        second = self.run_at(1002.0)
        self.assertAlmostEqual(second["dt"], 2.0, places=2)
        cpu = {r["pid"]: r for r in second["cpu"]}
        self.assertIn(100, cpu)
        self.assertNotIn(200, cpu)  # new starttime: no inherited counters
        self.assertAlmostEqual(cpu[100]["core"], 100.0, places=0)
        self.assertAlmostEqual(cpu[100]["value"], 100.0 / ncpu, places=1)
        self.assertEqual(cpu[100]["script"], "worker.py")
        self.assertEqual(cpu[100]["exe"], "python3.12")
        mem = {r["pid"]: r for r in second["mem"]}
        self.assertEqual((mem[100]["value"], mem[100]["kind"]), (4096, "pss"))
        self.assertEqual(mem[200]["kind"], "rss")
        io = {r["pid"]: r for r in second["io"]}
        self.assertEqual((io[100]["read"], io[100]["write"]), (1024, 512))
        self.assertEqual(len(io), 1)

    def test_window_too_wide_or_too_narrow_yields_no_rates(self):
        self.process(1, "a", ticks=0, start=1)
        self.run_at(1000.0)
        self.process(1, "a", ticks=100, start=1)
        self.assertEqual(self.run_at(1000.1)["cpu"], [])          # 0.1 s: too narrow
        self.process(1, "a", ticks=200, start=1)
        self.assertEqual(self.run_at(1100.0, window=15)["cpu"], [])   # 100 s > window
        self.process(1, "a", ticks=300, start=1)
        self.assertEqual(len(self.run_at(1102.0, window=15)["cpu"]), 1)

    def test_state_file_is_private_and_corruption_is_tolerated(self):
        self.process(1, "a", ticks=0, start=1)
        self.run_at(1000.0)
        path = os.path.join(self.runtime, "quadrant-procs.json")
        self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)
        write(path, "{not json")
        self.assertEqual(self.run_at(1002.0)["cpu"], [])

    def test_expanded_roster_exceeds_compact_cap_and_uses_explicit_rss(self):
        for pid in range(1, 81):
            self.process(pid, "worker", ticks=0, start=pid, rss_pages=pid, pss=1, io=(0, 0))
        compact = self.run_at(1000, count=10)
        self.assertEqual(len(compact["mem"]), 32)
        with patch.object(qproc, "parse_pss_kb", side_effect=AssertionError("expanded must not read PSS")):
            expanded = self.run_at(1001, expanded=True)
        self.assertEqual(expanded["mode"], "expanded")
        self.assertEqual(len(expanded["rows"]), 80)
        row = next(r for r in expanded["rows"] if r["pid"] == 1)
        self.assertEqual(row["kind"], "rss")
        self.assertEqual(row["memory"], os.sysconf("SC_PAGE_SIZE") // 1024)
        self.assertEqual(row["cpu"], 0)
        self.assertEqual((row["read"], row["write"]), (0, 0))  # measured idle
        self.assertEqual(expanded["cpu"], [])  # no triplicate payload

    def test_sub_400ms_request_never_walks_or_advances_baseline(self):
        self.process(1, "worker", ticks=0, start=1, io=(0, 0))
        self.run_at(1000)
        path = os.path.join(self.runtime, "quadrant-procs.json")
        with open(path, encoding="utf-8") as fh:
            baseline = fh.read()
        with patch.object(qproc.os, "listdir", side_effect=AssertionError("too soon")):
            skipped = self.run_at(1000.2, expanded=True)
        self.assertTrue(skipped["skipped"])
        self.assertGreaterEqual(skipped["retryAfterMs"], 200)
        with open(path, encoding="utf-8") as fh:
            self.assertEqual(fh.read(), baseline)
        self.process(1, "worker", ticks=100, start=1, io=(1000, 0))
        valid = self.run_at(1000.5, expanded=True)
        self.assertEqual(valid["dt"], 0.5)
        self.assertEqual(valid["rows"][0]["read"], 2000)

    def test_unknown_reset_and_reused_fields_are_not_idle_zero(self):
        self.process(1, "worker", ticks=100, start=1, io=(1000, 1000))
        self.process(2, "root-worker", ticks=0, start=2)
        cold = self.run_at(1000, expanded=True)
        self.assertTrue(all(r["cpu"] is None and r["read"] is None for r in cold["rows"]))
        self.process(1, "worker", ticks=1, start=1, io=(0, 0))  # reset
        self.process(3, "new-worker", ticks=3000, start=3, io=(1000, 1000))
        second = self.run_at(1001, expanded=True)
        rows = {r["pid"]: r for r in second["rows"]}
        self.assertIsNone(rows[1]["cpu"])
        self.assertIsNone(rows[1]["read"])
        self.assertFalse(rows[2]["ioVisible"])
        self.assertIsNone(rows[2]["read"])
        self.assertIsNone(rows[3]["cpu"])
        self.process(1, "worker", ticks=9000, start=99, io=(9000, 9000))
        reused = next(r for r in self.run_at(1002, expanded=True)["rows"] if r["pid"] == 1)
        self.assertEqual(reused["start"], 99)
        self.assertIsNone(reused["cpu"])
        self.assertIsNone(reused["read"])
        stale = self.run_at(1100, expanded=True)
        self.assertEqual(stale["rateState"], "stale")
        self.assertTrue(all(r["cpu"] is None for r in stale["rows"]))

    def test_permission_and_disappeared_process_coverage(self):
        self.process(1, "worker", ticks=0, start=1)
        os.makedirs(os.path.join(self.proc, "2"))
        sample = self.run_at(1000, expanded=True)
        self.assertEqual((sample["observed"], sample["procs"], sample["unreadable"], sample["ioHidden"]), (2, 1, 1, 1))
        with patch.object(qproc.os, "listdir", side_effect=PermissionError("restricted /proc")):
            with self.assertRaises(PermissionError):
                self.run_at(1001, expanded=True)

    def test_overlapping_helpers_share_one_baseline(self):
        self.process(1, "worker", ticks=0, start=1)
        os.environ["QUADRANT_NOW"] = "1000"
        commands = [subprocess.Popen([sys.executable, os.path.join(SCRIPTS, "qproc.py"), "--expanded"],
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) for _ in range(2)]
        outputs = []
        for child in commands:
            out, err = child.communicate(timeout=5)
            self.assertEqual(child.returncode, 0, err)
            outputs.append(json.loads(out))
        self.assertEqual(sum(r.get("skipped", False) for r in outputs), 1)

    def test_wrapper_envelope(self):
        self.process(1, "a", ticks=0, start=1)
        env = dict(os.environ)
        out = subprocess.run([os.path.join(SCRIPTS, "process-sample"), "3", "--window", "20"],
                             capture_output=True, text=True, env=env, check=False)
        self.assertEqual(out.returncode, 0, out.stderr)
        data = json.loads(out.stdout)
        self.assertTrue(data["ok"])
        self.assertEqual(data["metric"], "procs")
        self.assertEqual(json.loads(data["payload"])["procs"], 1)
        bad = subprocess.run([os.path.join(SCRIPTS, "process-sample"), "nope"], capture_output=True, text=True, env=env, check=False)
        self.assertEqual(bad.returncode, 1)
        self.assertFalse(json.loads(bad.stdout)["ok"])


if __name__ == "__main__":
    unittest.main()
