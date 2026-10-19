import json
import os
from pathlib import Path
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
