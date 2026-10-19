import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

from .helpers import SCRIPTS


class DeviceInventory(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.sys = self.root / "sys"
        self.dev = self.root / "dev"
        self.links = self.dev / "disk/by-id"
        self.links.mkdir(parents=True)
        self.env = dict(os.environ, QUADRANT_SYS_PATH=str(self.sys), QUADRANT_DEV_PATH=str(self.dev))

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def disk(self, name, model="Test drive"):
        path = self.sys / "block" / name
        self.write(path / "device/model", model + "\n")
        self.write(path / "queue/rotational", "0\n")
        self.write(path / "size", "1024\n")
        (self.dev / name).touch()
        return path

    def alias(self, identity, name):
        (self.links / identity).symlink_to("../../" + name)

    def run_helper(self, helper, *args):
        result = subprocess.run([str(Path(SCRIPTS) / helper), *args], env=self.env, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        return json.loads(result.stdout)

    def fixture_df(self, payload):
        """Substitute only df's fixed executable; run the actual helper body."""
        data = self.root / "df.txt"
        data.write_text(payload)
        tool = self.root / "df-fixture"
        tool.write_text(f"#!{os.sys.executable}\nfrom pathlib import Path\nimport sys\nsys.stdout.write(Path({str(data)!r}).read_text())\n")
        tool.chmod(0o755)
        source = (Path(SCRIPTS) / "disk-info").read_text()
        assignment = 'DF=$(resolve_bin df) || fail "df not found"'
        self.assertEqual(source.count(assignment), 1)
        script = self.root / "disk-info-fixture"
        script.write_text(source.replace(assignment, "DF=" + shlex.quote(str(tool)), 1))
        script.chmod(0o755)
        self.env["LC_ALL"] = "C.UTF-8"
        return str(script)

    def test_mount_access_preserves_literal_paths_and_checks_read_and_search(self):
        paths = [self.root / 'space "quote" \\ $(touch NO) café  ', self.root / "no-read", self.root / "no-search"]
        for path in paths:
            path.mkdir()
        paths[1].chmod(0o300)
        paths[2].chmod(0o600)
        missing = self.root / "missing"
        regular = self.root / "file"
        regular.touch()
        paths.extend([missing, regular])
        payload = "Filesystem Type 1B-blocks Used Available Capacity Mounted on\n" + "".join(
            f"/dev/sda{i + 1} ext4 {1000 + i} 100 900 10% {path}\n" for i, path in enumerate(paths))
        helper = self.fixture_df(payload)
        try:
            for mode in ["identity", "usage"]:
                with self.subTest(mode=mode):
                    data = self.run_helper(helper, mode)
                    expected = {str(path): path.is_dir() and os.access(path, os.R_OK | os.X_OK) for path in paths}
                    self.assertEqual(data["mountAccess"], expected)
                    self.assertEqual(data["dfPayload"], payload.rstrip("\n"))
                    self.assertFalse((self.root / "NO").exists())
        finally:
            for path in paths[:3]:
                path.chmod(0o700)

    def test_df_cap_keeps_only_complete_rows_in_both_inventory_modes(self):
        header = "Filesystem Type 1B-blocks Used Available Capacity Mounted on\n"
        retained = self.root / "retained"
        retained.mkdir()
        partial = self.root / "prefix"
        partial.mkdir()
        first = f"/dev/sda1 ext4 1000 100 900 10% {retained}\n"
        last = f"/dev/sda2 ext4 2000 100 1900 5% {partial}"
        padding_start = "tmpfs tmpfs 1 0 1 0% /"
        for character in ["x", "🦉"]:
            padding = padding_start + character * (65536 - len(header + first + padding_start + last) - 1) + "\n"
            payload = header + first + padding + last + "/different-mount\n"
            self.assertEqual(payload[65536 - len(str(partial)):65536], str(partial))
            helper = self.fixture_df(payload)
            for mode in ["identity", "usage"]:
                with self.subTest(mode=mode, character=character):
                    data = self.run_helper(helper, mode)
                    self.assertEqual(data["dfPayload"], (header + first + padding).rstrip("\n"))
                    self.assertEqual(data["mountAccess"], {str(retained): True})
            # If the bound includes the newline, the whole final row survives.
            padding = padding_start + character * (65536 - len(header + first + padding_start + last) - 2) + "\n"
            complete = header + first + padding + last + "\n"
            self.assertEqual(len(complete), 65536)
            helper = self.fixture_df(complete + "/dev/sda3 ext4 3000 100 2900 4% /another\n")
            for mode in ["identity", "usage"]:
                with self.subTest(mode=mode, character=character, boundary="newline"):
                    data = self.run_helper(helper, mode)
                    self.assertEqual(data["dfPayload"], complete.rstrip("\n"))
                    self.assertEqual(data["mountAccess"], {str(retained): True, str(partial): True})
        helper = self.fixture_df("/dev/sda1 ext4 1000 100 900 10% /" + "x" * 65536)
        for mode in ["identity", "usage"]:
            with self.subTest(mode=mode, boundary="no completed row"):
                data = self.run_helper(helper, mode)
                self.assertEqual(data["dfPayload"], "")
                self.assertEqual(data["mountAccess"], {})

    def test_disk_aliases_only_resolve_to_whole_devices_inside_dev(self):
        self.disk("sda")
        self.alias("ata-serial", "sda")
        self.alias("wwn-0x1234", "sda")
        self.alias("ata-serial-part1", "sda")  # never pin a partition alias
        self.alias("bad name", "sda")
        self.alias("bad..name", "sda")
        self.alias("broken", "missing")
        (self.dev / "sda1").touch()
        self.alias("partition-without-suffix", "sda1")
        outside = self.root / "sda"
        outside.touch()
        (self.links / "outside-root").symlink_to(outside)
        data = self.run_helper("disk-info")
        self.assertTrue(data["ok"])
        self.assertEqual(len(data["disks"]), 1)
        self.assertEqual(data["disks"][0]["deviceIds"], ["ata-serial", "wwn-0x1234"])
        self.assertEqual(data["disks"][0]["sizeBytes"], 1024 * 512)

    def test_disk_aliases_follow_swapped_kernel_names(self):
        self.disk("sda", "First")
        self.disk("sdb", "Second")
        self.alias("ata-first", "sda")
        self.alias("ata-second", "sdb")
        before = self.run_helper("disk-info")["disks"]
        for link in self.links.iterdir():
            link.unlink()
        self.alias("ata-first", "sdb")
        self.alias("ata-second", "sda")
        after = self.run_helper("disk-info")["disks"]
        self.assertEqual(before[0]["deviceIds"], ["ata-first"])
        self.assertEqual(after[1]["deviceIds"], ["ata-first"])

    def test_mapper_folding_and_usage_keep_working_with_ids(self):
        self.disk("nvme0n1")
        mapper = self.disk("dm-0")
        self.write(mapper / "dm/name", "cryptroot\n")
        (mapper / "slaves").mkdir()
        (mapper / "slaves/nvme0n1p2").symlink_to(self.sys / "block/nvme0n1")
        self.alias("nvme-eui.1234", "nvme0n1")
        data = self.run_helper("disk-info")
        self.assertEqual([d["name"] for d in data["disks"]], ["nvme0n1"])
        self.assertEqual(data["backing"], {"dm-0": "nvme0n1", "cryptroot": "nvme0n1"})
        self.assertEqual(data["disks"][0]["deviceIds"], ["nvme-eui.1234"])
        usage = self.run_helper("disk-info", "usage")
        self.assertTrue(usage["usage"])
        self.assertIn("dfPayload", usage)
        self.assertNotIn("disks", usage)

    def test_disk_alias_count_bounds_the_encoded_inventory_below_one_argv_limit(self):
        for n in range(16):
            name = f"vd{chr(ord('a') + n)}"
            self.disk(name)
            for alias in range(20):
                self.alias(f"ata-{n:02}-{alias:02}-" + "x" * 245, name)
        data = self.run_helper("disk-info")
        self.assertEqual(len(data["disks"]), 16)
        self.assertTrue(all(len(d["deviceIds"]) == 16 for d in data["disks"]))
        self.assertLess(len(json.dumps(data["disks"]).encode()), 100_000)

    def card(self, card, slot):
        path = self.sys / "class/drm" / card / "device"
        for name, value in {
            "vendor": "0x1002", "device": "0x744c", "class": "0x030000",
            "subsystem_vendor": "0x1002", "subsystem_device": "0x0e3b", "revision": "0xc8",
            "gpu_busy_percent": "0", "boot_vga": "1", "uevent": f"DRIVER=amdgpu\nPCI_SLOT_NAME={slot}",
        }.items():
            self.write(path / name, value + "\n")

    def test_gpu_inventory_carries_strict_pci_and_fingerprint_fields(self):
        self.card("card2", "0000:AF:1F.7")
        self.card("card3", "../../not-a-slot")
        data = self.run_helper("gpu-stats", "list")
        self.assertEqual(len(data["gpus"]), 2)
        gpu = data["gpus"][0]
        self.assertEqual(gpu["card"], "card2")
        self.assertEqual(gpu["path"], "/sys/class/drm/card2/device")
        self.assertEqual(gpu["slot"], "0000:af:1f.7")
        self.assertEqual(gpu["pciId"], "1002:744c")
        self.assertEqual(gpu["subsystemId"], "1002:0e3b")
        self.assertEqual(gpu["revision"], "c8")
        self.assertEqual(data["gpus"][1]["slot"], "")
