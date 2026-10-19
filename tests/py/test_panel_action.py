"""Literal transport and desktop/mount failures without touching the desktop."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from .helpers import load_script, SCRIPTS

action = load_script("panel-action.py")


class PanelActions(unittest.TestCase):
    def test_cli_copy_transports_exact_bytes_through_a_real_child(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            tool = root / "wl-copy"
            tool.write_text(f"#!{os.sys.executable}\nimport json, os, pathlib, sys\np = pathlib.Path(os.environ['QUADRANT_ACTION_TEST_SINK'])\np.write_bytes(sys.stdin.buffer.read())\np.with_suffix('.argv').write_text(json.dumps(sys.argv[1:]))\n")
            tool.chmod(0o755)
            value = '192.0.2.4 "quote" \\ $(touch NO) café\n'
            sink = root / "copied"
            env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ["PATH"], QUADRANT_ACTION_TEST_SINK=str(sink))
            result = subprocess.run([os.sys.executable, os.path.join(SCRIPTS, "panel-action.py"), "copy"],
                                    input=(json.dumps({"value": value}) + "\n").encode(), capture_output=True, env=env, timeout=3)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(json.loads(result.stdout), {"ok": True, "value": value})
            self.assertEqual(sink.read_bytes(), value.encode())
            self.assertEqual(json.loads(sink.with_suffix(".argv").read_text()), ["--type", "text/plain;charset=utf-8"])
            self.assertFalse((root / "NO").exists())

    def test_copy_uses_exact_utf8_stdin_and_fixed_argv(self):
        value = '2001:db8::1 "quote" \\ $(touch NO) café\n'
        with patch.object(action.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)) as run:
            self.assertEqual(action.perform("copy", value), {"ok": True, "value": value})
        args, kwargs = run.call_args
        self.assertEqual(args[0], ["wl-copy", "--type", "text/plain;charset=utf-8"])
        self.assertEqual(kwargs["input"], value.encode())
        self.assertNotIn("shell", kwargs)
        self.assertEqual(kwargs["stderr"], subprocess.DEVNULL, "clipboard owners cannot hold a captured pipe open")

    def test_clipboard_missing_failure_and_timeout_are_explicit(self):
        for error, message in [(FileNotFoundError(), "unavailable"),
                               (subprocess.TimeoutExpired("wl-copy", 5), "in time"),
                               (PermissionError(), "could not be started")]:
            with self.subTest(error=error), patch.object(action.subprocess, "run", side_effect=error):
                with self.assertRaisesRegex(action.ActionError, message):
                    action.perform("copy", "192.0.2.1")
        with patch.object(action.subprocess, "run", return_value=subprocess.CompletedProcess([], 1)):
            with self.assertRaisesRegex(action.ActionError, "failed"):
                action.perform("copy", "192.0.2.1")

    def mount_fixture(self, root, target):
        encoded = target.replace("\\", "\\134").replace(" ", "\\040").replace("\t", "\\011").replace("\n", "\\012")
        path = root / "mountinfo"
        path.write_text(f"51 21 8:1 / {encoded} rw - ext4 /dev/sda1 rw\n")
        return str(path)

    def test_open_checks_mount_and_passes_one_encoded_uri_argument(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            target = root / 'space "quote" \\ $(touch NO) % # café\t\n  '
            target.mkdir()
            mountinfo = self.mount_fixture(root, str(target))
            self.assertEqual(list(action.mount_targets(mountinfo)), [str(target)])
            for gio in [True, False]:
                with self.subTest(gio=gio), patch.object(action.shutil, "which", return_value="gio" if gio else None), \
                        patch.object(action.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)) as run:
                    result = action.perform("open-mount", str(target), mountinfo)
                    self.assertTrue(result["ok"])
                    expected = ["gio", "open", target.as_uri()] if gio else ["xdg-open", target.as_uri()]
                    self.assertEqual(run.call_args.args[0], expected)
                    self.assertEqual(run.call_args.kwargs["stdin"], subprocess.DEVNULL)
                    self.assertNotIn("shell", run.call_args.kwargs)
            self.assertFalse((root / "NO").exists())

    def test_unmounted_inaccessible_missing_and_non_directory_do_not_launch(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            mounted = root / "mounted"
            mounted.mkdir()
            inventory = self.mount_fixture(root, str(mounted))
            with patch.object(action.subprocess, "run") as run:
                with self.assertRaisesRegex(action.ActionError, "no longer mounted"):
                    action.perform("open-mount", str(root), inventory)
                with patch.object(action.os, "access", return_value=False):
                    with self.assertRaisesRegex(action.ActionError, "not accessible"):
                        action.perform("open-mount", str(mounted), inventory)
                mounted.rmdir()
                with self.assertRaisesRegex(action.ActionError, "unavailable"):
                    action.perform("open-mount", str(mounted), inventory)
                mounted.write_text("file")
                with self.assertRaisesRegex(action.ActionError, "not accessible"):
                    action.perform("open-mount", str(mounted), inventory)
                run.assert_not_called()

    def test_invalid_requests_never_launch_and_cli_is_bounded(self):
        with patch.object(action.subprocess, "run") as run:
            for value in [None, "", "\x00", "a" * 4097]:
                with self.subTest(value=repr(value)[:30]), self.assertRaises(action.ActionError):
                    action.perform("copy", value)
            for path in ["relative", "//host/path", "/tmp/../home", "/tmp/"]:
                with self.subTest(path=path), self.assertRaises(action.ActionError):
                    action.perform("open-mount", path)
            run.assert_not_called()
        for raw in [b"not json\n", b"[]\n", b"x" * 16385 + b"\n"]:
            result = subprocess.run([os.sys.executable, os.path.join(SCRIPTS, "panel-action.py"), "copy"], input=raw, capture_output=True, timeout=3)
            self.assertEqual(result.returncode, 0)
            self.assertFalse(json.loads(result.stdout)["ok"])

    def test_real_root_mount_is_found_without_launching(self):
        self.assertIn("/", list(action.mount_targets()))
