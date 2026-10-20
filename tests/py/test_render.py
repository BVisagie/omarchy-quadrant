import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import unittest

from tests.py.helpers import ROOT


class RenderEnvironment(unittest.TestCase):
    def test_bar_with_real_shell_in_both_modes(self):
        shell = Path(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy")) / "shell"
        if not shutil.which("quickshell") or not all((shell / name).is_dir() for name in ("Ui", "Commons")):
            self.skipTest("needs Quickshell and Omarchy shell imports")
        # The real WidgetButton must see the same bar host contract as the
        # installed shell. A launcher stub cannot catch missing QML properties.
        env = {key: value for key, value in os.environ.items() if not key.startswith("QUADRANT_RENDER_")}
        with tempfile.TemporaryDirectory() as tmp:
            for documentation in ("0", "1"):
                with self.subTest(documentation=documentation):
                    out = Path(tmp) / f"bar-{documentation}.png"
                    result = subprocess.run(
                        ["bash", str(Path(ROOT) / "tests/render.sh"), "bar", str(out)],
                        env=dict(env, QUADRANT_RENDER_DOCUMENTATION=documentation),
                        capture_output=True, text=True, check=False, timeout=40)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual(out.read_bytes()[:8], b"\x89PNG\r\n\x1a\n")

    def test_platform_theme_and_runtime_isolation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            runtime = root / "session"
            runtime.mkdir()
            original = runtime / "quadrant-procs.json"
            original.write_text("session counters")
            shell = root / "omarchy" / "shell"
            (shell / "Ui").mkdir(parents=True)
            (shell / "Commons").mkdir()
            binaries = root / "bin"
            binaries.mkdir()
            launcher = binaries / "quickshell"
            # Inspect the actual render script's launch environment without
            # needing Qt or a compositor on CI. The real render is checked on
            # an Omarchy install; this stub also writes an isolated counter.
            launcher.write_text('''#!/usr/bin/env python3
import json
import os
from pathlib import Path
runtime = Path(os.environ["XDG_RUNTIME_DIR"])
display = os.environ.get("WAYLAND_DISPLAY", "")
data = {
    "runtime": str(runtime),
    "theme": os.environ.get("QT_QPA_PLATFORMTHEME"),
    "entries": sorted(os.listdir(runtime)),
    "socket": str((runtime / display).resolve()) if display else None,
}
(runtime / "quadrant-procs.json").write_text("render counters")
Path(os.environ["QUADRANT_RENDER_OUT"]).write_bytes(b"fresh capture")
Path(os.environ["RENDER_TEST_REPORT"]).write_text(json.dumps(data))
''')
            launcher.chmod(0o700)
            source = runtime / "wayland-source"
            with socket.socket(socket.AF_UNIX) as session:
                session.bind(str(source))
                for display, linked in ((source.name, True), (str(source), True),
                                        ("missing-socket", False), ("", False)):
                    with self.subTest(display=display):
                        report = root / "report.json"
                        out = root / "capture.png"
                        env = dict(os.environ, PATH=str(binaries) + os.pathsep + os.environ["PATH"],
                                   XDG_RUNTIME_DIR=str(runtime), WAYLAND_DISPLAY=display,
                                   QT_QPA_PLATFORMTHEME="gtk3", OMARCHY_PATH=str(shell.parent),
                                   RENDER_TEST_REPORT=str(report))
                        result = subprocess.run(["bash", str(Path(ROOT) / "tests/render.sh"), "mem", str(out)],
                                                env=env, capture_output=True, text=True, check=False, timeout=10)
                        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                        data = json.loads(report.read_text())
                        self.assertNotEqual(data["runtime"], str(runtime))
                        self.assertEqual(data["entries"], ["wayland-render"] if linked else [])
                        self.assertEqual(data["theme"], "gtk3" if linked else "")
                        self.assertEqual(data["socket"], str(source) if linked else None)
                        self.assertEqual(original.read_text(), "session counters")
                        self.assertEqual(out.read_bytes(), b"fresh capture")

    def test_qml_errors_do_not_replace_an_existing_capture(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shell = root / "omarchy" / "shell"
            (shell / "Ui").mkdir(parents=True)
            (shell / "Commons").mkdir()
            binaries = root / "bin"
            binaries.mkdir()
            launcher = binaries / "quickshell"
            # A successful process exit and a PNG are insufficient: Qt may
            # still have rendered a partially broken component.
            launcher.write_text('''#!/usr/bin/env python3
import os
from pathlib import Path
Path(os.environ["QUADRANT_RENDER_OUT"]).write_bytes(b"broken capture")
print("WARN qml: TypeError: Cannot read property 'cfg' of null")
''')
            launcher.chmod(0o700)
            out = root / "capture.png"
            out.write_bytes(b"previous good capture")
            env = dict(os.environ, PATH=str(binaries) + os.pathsep + os.environ["PATH"],
                       OMARCHY_PATH=str(shell.parent), WAYLAND_DISPLAY="")
            result = subprocess.run(["bash", str(Path(ROOT) / "tests/render.sh"), "mem", str(out)],
                                    env=env, capture_output=True, text=True, check=False, timeout=10)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((result.stdout + result.stderr).count("TypeError"), 1)
            self.assertEqual(out.read_bytes(), b"previous good capture")
