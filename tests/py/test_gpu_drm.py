import json
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from helpers import SCRIPTS, fake_process, load_script, write  # noqa: E402

gpu_drm = load_script("gpu-drm")

I915 = """pos:\t0
flags:\t02100002
drm-driver:\ti915
drm-client-id:\t{cid}
drm-pdev:\t{slot}
drm-engine-render:\t{render} ns
drm-engine-video:\t{video} ns
drm-engine-capacity-video:\t2
drm-total-memory:\t1024 KiB
drm-resident-system:\t512 KiB
"""

XE = """drm-driver:\txe
drm-client-id:\t{cid}
drm-pdev:\t{slot}
drm-cycles-rcs:\t{cycles}
drm-total-cycles-rcs:\t{total}
drm-engine-capacity-rcs:\t1
drm-resident-vram0:\t2 MiB
"""


class ParseFdinfo(unittest.TestCase):
    def test_capacity_applies_whether_it_precedes_or_follows(self):
        before = "drm-pdev: 0000:00:02.0\ndrm-engine-capacity-video: 2\ndrm-engine-video: 10 ns\n"
        after = "drm-pdev: 0000:00:02.0\ndrm-engine-video: 10 ns\ndrm-engine-capacity-video: 2\n"
        for text in (before, after):
            parsed = gpu_drm.parse_fdinfo(text)
            self.assertEqual(parsed["engines"][0]["capacity"], 2)
            self.assertEqual(parsed["engines"][0]["ns"], 10)

    def test_xe_cycles_pair_up(self):
        parsed = gpu_drm.parse_fdinfo(XE.format(cid=4, slot="0000:00:02.0", cycles=30, total=100))
        eng = parsed["engines"][0]
        self.assertEqual((eng["name"], eng["cycles"], eng["total"]), ("rcs", 30, 100))
        self.assertEqual(parsed["dedicated"], 2 * 1024 * 1024)

    def test_non_drm_fdinfo_is_ignored(self):
        self.assertIsNone(gpu_drm.parse_fdinfo("pos:\t0\nflags:\t02\n"))

    def test_parse_size(self):
        self.assertEqual(gpu_drm.parse_size("512 KiB"), 512 * 1024)
        self.assertEqual(gpu_drm.parse_size("3 MiB"), 3 * 1024 * 1024)
        self.assertEqual(gpu_drm.parse_size("77"), 77)
        self.assertIsNone(gpu_drm.parse_size(""))


class Snapshot(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.proc = os.path.join(self.tmp.name, "proc")
        self.sys = os.path.join(self.tmp.name, "sys")
        os.makedirs(self.proc)
        os.makedirs(self.sys)
        self.env = dict(os.environ, QUADRANT_PROC_PATH=self.proc, QUADRANT_SYS_PATH=self.sys)
        os.environ["QUADRANT_PROC_PATH"] = self.proc
        os.environ["QUADRANT_SYS_PATH"] = self.sys

    def tearDown(self):
        os.environ.pop("QUADRANT_PROC_PATH", None)
        os.environ.pop("QUADRANT_SYS_PATH", None)
        self.tmp.cleanup()

    def card(self, name: str, slot: str, **files: str) -> str:
        card_dir = os.path.join(self.sys, "class", "drm", name)
        write(os.path.join(card_dir, "device", "uevent"), "DRIVER=i915\nPCI_SLOT_NAME=%s\n" % slot)
        for rel, text in files.items():
            write(os.path.join(card_dir, rel.replace("__", "/")), text)
        return card_dir

    def test_rows_carry_pid_and_slot_filter_applies(self):
        igpu = "0000:00:02.0"
        dgpu = "0000:03:00.0"
        fake_process(self.proc, 100, {5: ("/dev/dri/renderD128", I915.format(cid=1, slot=igpu, render=100, video=0))})
        fake_process(self.proc, 200, {7: ("/dev/dri/renderD129", I915.format(cid=2, slot=dgpu, render=900, video=50))})
        snap = gpu_drm.snap_fdinfo(igpu)
        self.assertEqual([e["pid"] for e in snap["engines"]], [100, 100])
        self.assertEqual(snap["clients"][0]["pid"], 100)
        self.assertEqual(snap["clients"][0]["shared"], 512 * 1024)
        video = [e for e in snap["engines"] if e["name"] == "video"][0]
        self.assertEqual(video["capacity"], 2)
        everything = gpu_drm.snap_fdinfo("")
        self.assertEqual(sorted({e["pid"] for e in everything["engines"]}), [100, 200])

    def test_client_shared_across_fork_is_counted_once(self):
        slot = "0000:00:02.0"
        text = I915.format(cid=9, slot=slot, render=5, video=0)
        fake_process(self.proc, 300, {3: ("/dev/dri/renderD128", text)})
        fake_process(self.proc, 301, {3: ("/dev/dri/renderD128", text)})  # forked child, same file
        snap = gpu_drm.snap_fdinfo(slot)
        self.assertEqual(len(snap["clients"]), 1)
        self.assertEqual(snap["clients"][0]["pid"], 300)
        self.assertEqual(snap["shared"], 512 * 1024)

    def test_non_drm_fds_are_skipped(self):
        fake_process(self.proc, 400, {1: ("/dev/null", "pos: 0\n"), 2: ("socket:[1]", "pos: 0\n")})
        self.assertEqual(gpu_drm.snap_fdinfo("")["engines"], [])

    def test_rc6_is_filtered_to_the_selected_card(self):
        self.card("card0", "0000:00:02.0", gt__gt0__rc6_residency_ms="1000\n", gt__gt0__rc6_enable="1\n")
        self.card("card1", "0000:03:00.0", gt__gt0__rc6_residency_ms="5000\n")
        rows = gpu_drm.snap_rc6("0000:03:00.0")
        self.assertEqual([(r["card"], r["ms"]) for r in rows], [("card1", 5000)])
        both = gpu_drm.snap_rc6("")
        self.assertEqual(sorted(r["card"] for r in both), ["card0", "card1"])

    def test_rc6_disabled_counter_is_skipped(self):
        self.card("card0", "0000:00:02.0", gt__gt0__rc6_residency_ms="1000\n", gt__gt0__rc6_enable="0\n")
        self.assertEqual(gpu_drm.snap_rc6("0000:00:02.0"), [])

    def test_xe_gtidle_residency_counts_as_idle(self):
        self.card("card2", "0000:00:02.0", device__tile0__gt0__gtidle__idle_residency_ms="777\n")
        rows = gpu_drm.snap_rc6("0000:00:02.0")
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["ms"], 777)
        self.assertTrue(rows[0]["id"].endswith("gtidle/idle_residency_ms"))

    def test_card_slot_falls_back_to_device_symlink(self):
        card_dir = os.path.join(self.sys, "class", "drm", "card3")
        os.makedirs(card_dir)
        os.symlink("../../../0000:07:00.0", os.path.join(card_dir, "device"))
        self.assertEqual(gpu_drm.card_slot(card_dir), "0000:07:00.0")

    def test_cli_emits_envelope_and_rejects_bad_slot(self):
        fake_process(self.proc, 500, {4: ("/dev/dri/card0", I915.format(cid=3, slot="0000:00:02.0", render=1, video=1))})
        out = subprocess.run([sys.executable, os.path.join(SCRIPTS, "gpu-drm"), "--slot", "0000:00:02.0"],
                             capture_output=True, text=True, env=self.env, check=False)
        self.assertEqual(out.returncode, 0, out.stderr)
        data = json.loads(out.stdout)
        self.assertTrue(data["ok"])
        self.assertEqual(data["clients"][0]["pid"], 500)
        self.assertIn("tsNs", data)
        bad = subprocess.run([sys.executable, os.path.join(SCRIPTS, "gpu-drm"), "--slot", "x;rm"],
                             capture_output=True, text=True, env=self.env, check=False)
        self.assertEqual(bad.returncode, 1)
        self.assertFalse(json.loads(bad.stdout)["ok"])


if __name__ == "__main__":
    unittest.main()
