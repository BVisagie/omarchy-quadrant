"""Real vendor helper paths with private devices and a stub nvidia-smi."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

from .helpers import SCRIPTS


class GpuClocks(unittest.TestCase):
    def test_amd_memory_clock_uses_its_own_active_dpm_state(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            dev = root / "class/drm/card0/device"
            dev.mkdir(parents=True)
            (dev / "gpu_busy_percent").write_text("15\n")
            (dev / "pp_dpm_sclk").write_text("0: 100Mhz\n1: 2100Mhz *\n")
            (dev / "pp_dpm_mclk").write_text("S: 19Mhz *\n0: 1000Mhz\n")
            env = dict(os.environ, QUADRANT_SYS_PATH=str(root))
            def collect():
                result = subprocess.run([str(Path(SCRIPTS) / "gpu-stats"), "sample", "amd", str(dev)],
                                        env=env, capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
                return json.loads(result.stdout)["payload"]
            payload = collect()
            self.assertIn("sclk_mhz=2100\n", payload)
            self.assertIn("mclk_mhz=19\n", payload)
            self.assertIn("mclk_source=pp_dpm_mclk\n", payload)
            (dev / "pp_dpm_mclk").write_text("0: malformed *\n")
            self.assertNotIn("mclk_mhz=", collect())
            (dev / "pp_dpm_mclk").unlink()
            self.assertNotIn("mclk_source=", collect())
            self.assertNotIn("mclk_mhz=", collect())

    def test_nvidia_query_identifies_the_extended_column_layout(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            stub = root / "nvidia-smi"
            sink = root / "argv.json"
            stub.write_text(f"#!{os.sys.executable}\nimport json, pathlib, sys\n"
                            f"p=pathlib.Path({str(sink)!r})\n"
                            "if any(a.startswith('--query-gpu=') for a in sys.argv):\n"
                            " p.write_text(json.dumps(sys.argv[1:]))\n"
                            " print('0, NVIDIA Model, Laptop, 12, 1024, 8192, 50, 35, 1800, N/A')\n")
            stub.chmod(0o755)
            source = (Path(SCRIPTS) / "gpu-stats").read_text()
            assignment = 'SMI=$(resolve_bin nvidia-smi) || fail "nvidia-smi not found"'
            self.assertEqual(source.count(assignment), 1)
            helper = root / "gpu-stats"
            helper.write_text(source.replace(assignment, "SMI=" + shlex.quote(str(stub)), 1))
            helper.chmod(0o755)
            (root / "gpu-intel-paths.sh").write_text((Path(SCRIPTS) / "gpu-intel-paths.sh").read_text())
            result = subprocess.run([str(helper), "sample", "nvidia", "0000:03:00.0"], capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            data = json.loads(result.stdout)
            self.assertTrue(data["memoryClock"])
            argv = json.loads(sink.read_text())
            self.assertIn("-i", argv)
            self.assertEqual(argv[argv.index("-i") + 1], "0000:03:00.0")
            self.assertTrue(any(arg.endswith(",clocks.mem") for arg in argv))
            self.assertTrue(data["payload"].endswith(", N/A"))
