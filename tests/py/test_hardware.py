"""Read-only hardware contracts against temporary sysfs trees."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from .helpers import SCRIPTS, load_script

hardware = load_script("hardware-info.py")


class Hardware(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name) / "sys"
        self.root.mkdir()

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, path, value):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(str(value) + "\n")

    def hwmon(self, name, owner="platform/board.0", driver="board", channels=None):
        device = self.root / "devices" / owner
        hw = device / "hwmon" / name
        hw.mkdir(parents=True)
        self.write(hw / "name", driver)
        (hw / "device").symlink_to(device)
        alias = self.root / "class/hwmon" / name
        alias.parent.mkdir(parents=True, exist_ok=True)
        alias.symlink_to(hw)
        for key, value in (channels or {"temp1_input": 42000}).items():
            self.write(hw / key, value)
        return hw, alias

    def package(self, source="intel-rapl:0", name="package-0", energy=1000000000, maximum=100000000000):
        path = self.root / "devices/virtual/powercap" / source
        self.write(path / "name", name)
        self.write(path / "energy_uj", energy)
        self.write(path / "max_energy_range_uj", maximum)
        self.write(path / "enabled", 0)  # disabled capping still measures energy
        alias = self.root / "class/powercap" / source
        alias.parent.mkdir(parents=True, exist_ok=True)
        alias.symlink_to(path)
        return path

    def battery(self, name="BAT0", **fields):
        path = self.root / "devices/platform/power_supply" / name
        self.write(path / "type", "Battery")
        for key, value in fields.items():
            self.write(path / key, value)
        alias = self.root / "class/power_supply" / name
        alias.parent.mkdir(parents=True, exist_ok=True)
        alias.symlink_to(path)
        return path

    def test_sensor_pins_survive_hwmon_and_nvme_renumbering(self):
        owner = "pci0000:00/0000:01:00.0/nvme/nvme0"
        hw, alias = self.hwmon("hwmon2", owner, "nvme", {"temp1_input": 41000, "temp1_label": "Composite"})
        self.write(hw.parent.parent / "serial", "Drive-A")
        before = hardware.snapshot(self.root, "sample")["sensors"][0]
        alias.unlink()
        moved = hw.with_name("hwmon88")
        hw.rename(moved)
        alias.with_name("hwmon88").symlink_to(moved)
        controller = moved.parent.parent
        (moved / "device").unlink()
        renamed = controller.with_name("nvme7")
        controller.rename(renamed)
        new_hw = renamed / "hwmon/hwmon88"
        alias.with_name("hwmon88").unlink()
        alias.with_name("hwmon88").symlink_to(new_hw)
        (new_hw / "device").symlink_to(renamed)
        after = hardware.snapshot(self.root, "sample")["sensors"][0]
        self.assertEqual(before["id"], after["id"])
        self.assertEqual(before["owner"], after["owner"])
        self.write(renamed / "serial", "Drive-B")
        self.assertNotEqual(hardware.snapshot(self.root, "list")["sensors"][0]["id"], before["id"])

    def test_duplicate_drivers_have_distinct_owners_and_channels(self):
        self.hwmon("hwmon0", "platform/board.0", channels={"temp1_input": 42000, "fan1_input": 0})
        self.hwmon("hwmon1", "platform/board.1", channels={"temp1_input": 43000})
        rows = hardware.snapshot(self.root, "sample")["sensors"]
        self.assertEqual(len({row["id"] for row in rows}), 3)
        self.assertEqual(next(row["value"] for row in rows if row["kind"] == "fan"), 0)
        self.assertEqual(sorted(row["value"] for row in rows if row["kind"] == "temperature"), [42, 43])

    def test_fault_disabled_malformed_and_calibration_are_unavailable(self):
        self.hwmon("hwmon0", channels={"temp1_input": 42000, "temp1_fault": 1, "temp2_input": 1,
                                     "temp2_type": 4, "fan1_input": 0, "fan1_enable": 0, "fan2_input": "N/A"})
        rows = hardware.snapshot(self.root, "sample")["sensors"]
        self.assertTrue(all(row["value"] is None for row in rows))
        self.assertEqual({row["status"] for row in rows}, {"Sensor fault", "Thermistor calibration required", "Disabled", "Invalid reading"})

    def test_gpu_channels_and_inventory_never_read_telemetry(self):
        hw, _ = self.hwmon("hwmon0", "pci0000:00/0000:01:00.0", "mystery", {"temp1_label": "GPU edge"})
        self.write(hw.parent.parent / "class", "0x030000")
        for name in ["temp1_input", "temp1_fault", "temp1_enable", "temp1_type", "temp1_crit"]:
            os.mkfifo(hw / name)
        env = dict(os.environ, QUADRANT_SYS_PATH=str(self.root))
        for mode in ["list", "sample", "power"]:
            result = subprocess.run([os.sys.executable, str(Path(SCRIPTS) / "hardware-info.py"), mode],
                                    env=env, capture_output=True, text=True, timeout=3)
            self.assertEqual(result.returncode, 0, result.stderr)
            rows = json.loads(result.stdout)["sensors"]
            if mode == "power":
                self.assertEqual(rows, [])
            else:
                self.assertEqual(rows[0]["status"], "Read on the GPU detail tab")
                self.assertIsNone(rows[0]["value"])
        self.hwmon("hwmon1", "platform/cpu", "coretemp", {"temp1_label": "CPU"})
        cpu_hw = self.root / "class/hwmon/hwmon1"
        os.mkfifo(cpu_hw / "temp1_input")
        result = subprocess.run([os.sys.executable, str(Path(SCRIPTS) / "hardware-info.py"), "list"],
                                env=env, capture_output=True, text=True, timeout=3)
        self.assertEqual(result.returncode, 0, "list must not open CPU input either")

    def test_package_aliases_and_subdomains_are_not_counted_twice(self):
        self.package()
        self.package("intel-rapl-mmio:0", energy=2000000000)
        self.package("intel-rapl:0:0", name="core")
        self.package("intel-rapl:0:1", name="uncore")
        self.package("intel-rapl:1", name="package-1")
        rows = hardware.snapshot(self.root, "power")["packages"]
        self.assertEqual([row["id"] for row in rows], ["package-0", "package-1"])
        self.assertEqual(rows[0]["source"], "intel-rapl:0")
        self.assertEqual(rows[0]["energyUj"], 1000000000)
        self.assertGreater(rows[0]["monotonicS"], 0)

    def test_permission_failure_stays_unknown_and_can_use_a_readable_alias(self):
        denied = self.package()
        original_open = Path.open
        def guarded_open(path, *args, **kwargs):
            if path.resolve() == (denied / "energy_uj").resolve():
                raise PermissionError("fixture denied")
            return original_open(path, *args, **kwargs)
        with patch.object(Path, "open", guarded_open):
            row = hardware.snapshot(self.root, "power")["packages"][0]
            self.assertIsNone(row["energyUj"])
            self.assertEqual(row["status"], "Permission denied")
            self.package("intel-rapl-mmio:0", energy=55)
            row = hardware.snapshot(self.root, "power")["packages"][0]
            self.assertEqual(row["source"], "intel-rapl-mmio:0")
            self.assertEqual(row["energyUj"], 55)

    def test_invalid_energy_and_range_are_not_zero(self):
        path = self.package(energy="12 uJ")
        self.assertIsNone(hardware.snapshot(self.root, "power")["packages"][0]["energyUj"])
        for energy, maximum in [(100, 100), (0, 0), (1, "N/A"), (-1, 100)]:
            self.write(path / "energy_uj", energy)
            self.write(path / "max_energy_range_uj", maximum)
            self.assertIsNone(hardware.snapshot(self.root, "power")["packages"][0]["energyUj"])

    def test_batteries_keep_each_device_and_do_not_mix_charge_with_energy(self):
        self.battery(energy_full=50000000, energy_full_design=60000000, capacity=80, power_now=0, cycle_count=0)
        self.battery("BAT1", charge_full=3000000, charge_full_design=4000000,
                     charge_now=1500000, current_now=-2000000, voltage_now=12000000)
        self.battery("mouse", scope="Device", capacity=55)
        self.battery("missing", present=0, capacity=0)
        rows = {row["name"]: row for row in hardware.snapshot(self.root, "sample")["batteries"]}
        self.assertEqual(set(rows), {"BAT0", "BAT1", "mouse"})
        self.assertAlmostEqual(rows["BAT0"]["healthPct"], 100 * 5 / 6)
        self.assertEqual(rows["BAT0"]["powerW"], 0)
        self.assertEqual(rows["BAT0"]["cycles"], 0)
        self.assertEqual(rows["BAT1"]["healthPct"], 75)
        self.assertEqual(rows["BAT1"]["chargePct"], 50)
        self.assertEqual(rows["BAT1"]["powerW"], 24)
        self.assertTrue(rows["BAT1"]["powerEstimated"])
        self.assertIsNone(rows["BAT1"]["fullWh"])
        self.assertEqual(rows["mouse"]["scope"], "Device")
        self.assertIsNone(rows["mouse"]["healthPct"])
        self.assertIsNone(rows["mouse"]["powerW"])

    def test_mismatched_or_malformed_battery_units_remain_unavailable(self):
        self.battery(energy_full=50000000, charge_full_design=6000000, capacity="N/A", power_now="bad", voltage_now=12000000)
        row = hardware.snapshot(self.root, "sample")["batteries"][0]
        for field in ["healthPct", "chargePct", "powerW"]:
            self.assertIsNone(row[field], field)

    def test_caps_and_unknown_modes_are_explicit(self):
        self.hwmon("hwmon0", channels={"temp" + str(i) + "_input": 42000 for i in range(1, 131)})
        data = hardware.snapshot(self.root, "sample")
        self.assertEqual(len(data["sensors"]), hardware.MAX_SENSORS)
        self.assertTrue(data["truncated"])
        with patch.object(hardware, "MAX_ENTRIES", 2):
            self.assertTrue(hardware.snapshot(self.root, "list")["truncated"])
        result = subprocess.run([os.sys.executable, str(Path(SCRIPTS) / "hardware-info.py"), "write"], capture_output=True, text=True, timeout=3)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(json.loads(result.stdout)["ok"])

    def test_missing_hardware_is_an_empty_inventory(self):
        data = hardware.snapshot(self.root, "sample")
        self.assertTrue(data["ok"])
        self.assertEqual(data["sensors"], [])
        self.assertEqual(data["packages"], [])
        self.assertEqual(data["batteries"], [])
        self.assertFalse(data["truncated"])
