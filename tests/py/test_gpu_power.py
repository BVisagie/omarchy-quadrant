"""Real Bash readers against private sysfs, including traps for forbidden opens."""
import json
import os
from pathlib import Path
import select
import subprocess
import tempfile
import time
import unittest

from .helpers import SCRIPTS


class GpuPower(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory()
        self.addCleanup(self.work.cleanup)
        self.root = Path(self.work.name)
        self.sys = self.root / "sys"
        self.dev = self.sys / "class/drm/card0/device"
        self.dev.mkdir(parents=True)
        (self.dev / "power").mkdir()
        (self.dev / "power/runtime_status").write_text("active\n")
        (self.dev / "power/control").write_text("auto\n")
        (self.dev / "power/autosuspend_delay_ms").write_text("5000\n")
        (self.dev / "gpu_busy_percent").write_text("0\n")
        self.control = self.root / "control"
        self.env = dict(os.environ, QUADRANT_SYS_PATH=str(self.sys),
                        QUADRANT_PROC_PATH=str(self.root / "proc"), XDG_RUNTIME_DIR=str(self.root))

    def policy(self, wanted=1, generation=2, expiry=None, target=None):
        expiry = expiry if expiry is not None else time.clock_gettime_ns(time.CLOCK_BOOTTIME) // 1_000_000 + 2900
        temp = self.control.with_suffix(".new")
        temp.write_text(f"1\t{generation}\t{expiry}\t{wanted}\t{target or self.dev}\tamd\t0\t-\t-\n")
        temp.replace(self.control)

    def stream(self, *extra, ticks=1):
        return subprocess.run([str(Path(SCRIPTS) / "quadrant-stream"), "250", *extra],
                              env=dict(self.env, QUADRANT_STREAM_TICKS=str(ticks)),
                              capture_output=True, text=True, timeout=3)

    def helper(self, controlled=False):
        args = [str(Path(SCRIPTS) / "gpu-stats"), "sample", "amd", str(self.dev)]
        if controlled:
            args += [str(self.control), "2"]
        result = subprocess.run(args, env=self.env, capture_output=True, text=True, timeout=3)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        return json.loads(result.stdout)

    def trap(self):
        # Every AMD telemetry group includes at least one of these FIFO traps.
        files = ["gpu_busy_percent", "mem_busy_percent", "mem_info_vram_used", "mem_info_vram_total",
                 "pp_dpm_sclk", "pp_dpm_mclk", "hwmon/hwmon0/temp1_input", "hwmon/hwmon0/temp2_input",
                 "hwmon/hwmon0/power1_average", "engine/gfx/busy_percent"]
        for name in files:
            path = self.dev / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.unlink(missing_ok=True)
            os.mkfifo(path)

    def test_hidden_and_sleeping_never_open_telemetry(self):
        self.trap()
        for status, wanted, expected in [("active", 0, "held"), ("suspended", 1, "sleeping"),
                                         ("suspending", 1, "transitioning"), ("resuming", 1, "transitioning"),
                                         ("error", 1, "failed"), ("bad", 1, "failed")]:
            with self.subTest(status=status, wanted=wanted):
                (self.dev / "power/runtime_status").write_text(status + "\n")
                self.policy(wanted)
                result = self.stream("--control", str(self.control), ticks=2)
                self.assertEqual(result.returncode, 0, result.stderr)
                rows = [json.loads(line) for line in result.stdout.splitlines()]
                self.assertEqual(len(rows), 2)
                self.assertTrue(all(row["gpu"]["state"] == expected and row["cpu"] for row in rows))
                self.assertEqual(self.helper(True)["state"], expected)

    def test_invalid_expired_missing_and_superseded_control_fail_closed(self):
        self.trap()
        for content in ("", "1\tgarbage\n", "$(touch /tmp/should-never-run)\n"):
            self.control.write_text(content)
            self.assertIsNone(json.loads(self.stream("--control", str(self.control)).stdout)["gpu"])
            self.assertEqual(self.helper(True)["state"], "held")
        self.policy(expiry=1)
        self.assertIsNone(json.loads(self.stream("--control", str(self.control)).stdout)["gpu"])
        self.policy(generation=3)
        self.assertEqual(self.helper(True)["state"], "held")
        self.control.unlink()
        self.assertIsNone(json.loads(self.stream("--control", str(self.control)).stdout)["gpu"])

    def test_visible_zero_and_pm_fallback_have_real_acquisition_times(self):
        self.policy()
        for status, pm in [("active", "active"), ("unsupported", "unsupported"), (None, "unavailable")]:
            path = self.dev / "power/runtime_status"
            if status is None:
                path.unlink()
            else:
                path.write_text(status + "\n")
            row = json.loads(self.stream("--control", str(self.control)).stdout)["gpu"]
            self.assertEqual((row["busy"], row["state"], row["pm"], row["generation"]), (0, "fresh", pm, 2))
            self.assertGreater(row["at"], 0)
            self.assertGreater(row["monoMs"], 0)
            self.assertIn("gpu_busy_percent=0", self.helper(True)["payload"])
        path.write_text("active\n")
        (self.dev / "power/control").write_text("on\n")
        self.assertEqual(self.helper(True)["pm"], "disabled")

    def test_pm_read_errors_and_invalid_delays_fail_closed(self):
        self.trap()
        self.policy()
        status = self.dev / "power/runtime_status"
        status.chmod(0)
        try:
            self.assertEqual(self.helper(True)["state"], "failed")
            self.assertEqual(json.loads(self.stream("--control", str(self.control)).stdout)["gpu"]["state"], "failed")
        finally:
            status.chmod(0o600)
        (self.dev / "power/autosuspend_delay_ms").write_text("invalid\n")
        self.assertEqual(self.helper(True)["state"], "failed")
        # Direct helper callers also respect suspend, without a Store control.
        status.write_text("suspended\n")
        self.assertEqual(self.helper()["state"], "sleeping")

    def test_same_stream_toggles_and_switches_devices_without_losing_ticks(self):
        self.policy()
        proc = subprocess.Popen([str(Path(SCRIPTS) / "quadrant-stream"), "250", "--control", str(self.control)],
                                env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.addCleanup(lambda: proc.poll() is None and proc.kill())

        def sample():
            self.assertTrue(select.select([proc.stdout], [], [], 2)[0], "stream stalled on forbidden read")
            line = proc.stdout.readline()
            self.assertTrue(line, proc.stderr.read() if proc.poll() is not None else "empty output")
            return json.loads(line)

        self.assertEqual(sample()["gpu"]["busy"], 0)
        pid = proc.pid
        self.policy(wanted=0)
        self.trap()
        self.assertEqual(sample()["gpu"]["state"], "held")
        self.assertEqual(sample()["gpu"]["state"], "held")
        other = self.dev.parent.parent / "card1/device"
        other.mkdir(parents=True)
        (other / "gpu_busy_percent").write_text("42\n")
        self.policy(generation=3, target=other)
        row = sample()
        self.assertEqual((row["gpu"]["busy"], row["gpu"]["generation"]), (42, 3))
        self.assertEqual(proc.pid, pid)
        self.assertTrue(row["cpu"] and row["mem"] and "disk" in row and "net" in row)
        proc.terminate()
        proc.communicate(timeout=3)

    def test_observer_never_reads_telemetry_and_reports_missing_attributes(self):
        (self.dev / "vendor").write_text("0x1002\n")
        pci = self.sys / "bus/pci/devices/0000:03:00.0"
        pci.parent.mkdir(parents=True)
        pci.symlink_to(self.dev, target_is_directory=True)
        self.trap()
        result = subprocess.run([os.sys.executable, str(Path(SCRIPTS) / "amd-runtime-power.py"),
                                 "--pci", pci.name, "--duration", "0"], env=self.env,
                                capture_output=True, text=True, timeout=3)
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual([row["event"] for row in rows], ["conditions", "sample", "summary"])
        self.assertTrue(any("error" in entry for entry in rows[0]["reads"]))
        self.assertIsNone(rows[-1]["delta_ms"]["runtime_suspended_time"])
        self.assertFalse(any("gpu_busy_percent" in entry["path"] for row in rows for entry in row.get("reads", [])))
