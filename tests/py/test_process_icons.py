import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from .helpers import SCRIPTS, load_script

icons = load_script("process-icons.py")


class ProcessIcons(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="quadrant icon tests ")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.home = self.root / "home"
        self.user = self.root / "user data"
        self.system = self.root / "system data"
        self.other = self.root / "other system data"
        self.env = {
            "XDG_DATA_HOME": str(self.user),
            "XDG_DATA_DIRS": os.pathsep.join(map(str, [self.system, self.other])),
        }
        self.roots = icons.search_roots(self.home, self.env)

    def file(self, path):
        path.parent.mkdir(parents=True, exist_ok=True)
        # No image contents are needed: discovery must use metadata alone.
        path.touch()
        return str(path)

    def theme(self, name, directory=None, theme="test", context="apps", size="scalable"):
        directory = self.user if directory is None else directory
        return self.file(directory / "icons" / theme / size / context / name)

    def resolve(self, *names):
        return icons.resolve_icons(names, self.roots)

    def run_helper(self, *names):
        result = subprocess.run(
            [sys.executable, str(Path(SCRIPTS) / "process-icons.py"), *names],
            env=dict(os.environ, HOME=str(self.home), **self.env), cwd=self.root,
            capture_output=True, text=True, timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertEqual(len(result.stdout.splitlines()), 1)
        return json.loads(result.stdout)

    def test_only_requested_names_are_returned_with_original_case(self):
        upper = self.theme("Editor.svg")
        lower = self.theme("editor.png")
        self.theme("unrequested.svg")
        self.assertEqual(self.resolve("Editor", "editor", "EDITOR", "missing", "Editor"),
                         {"Editor": upper, "editor": lower})
        self.assertEqual(self.resolve("editor"), {"editor": lower})

    def test_only_apps_and_devices_contexts_and_flat_pixmaps_are_searched(self):
        app = self.theme("Editor.png")
        device = self.theme("drive.svg", context="devices")
        self.theme("Editor.svg", context="actions")
        self.theme("action-only.svg", context="actions")
        self.theme("misleading.svg", context="actions/apps")
        self.theme("status-only.svg", context="status")
        self.file(self.user / "icons/root-only.svg")
        self.file(self.user / "icons/test/scalable/no-context.svg")
        pixmap = self.file(self.user / "pixmaps/flat.xpm")
        self.file(self.user / "pixmaps/nested/hidden.svg")
        self.assertEqual(self.resolve("Editor", "drive", "action-only", "misleading", "status-only",
                                      "root-only", "no-context", "flat", "hidden"),
                         {"Editor": app, "drive": device, "flat": pixmap})

    def test_formats_precede_root_order_then_paths_break_ties(self):
        self.theme("format.png")
        svg = self.theme("format.svg", self.other)
        self.theme("png-wins.xpm")
        png = self.theme("png-wins.png", self.system)
        xpm = self.theme("xpm-only.xpm")
        self.theme("stable.svg", theme="z-first-created")
        stable = self.theme("stable.svg", theme="a-last-created")
        self.theme("unsupported.jpg")
        self.theme("unsupported.svgz")
        self.assertEqual(self.resolve("format", "png-wins", "xpm-only", "stable", "unsupported"),
                         {"format": svg, "png-wins": png, "xpm-only": xpm, "stable": stable})

    def test_legacy_user_and_system_data_directory_precedence(self):
        legacy = self.file(self.home / ".icons/z/scalable/apps/legacy.svg")
        self.theme("legacy.svg")
        self.theme("legacy.svg", self.system)
        user = self.theme("user.svg")
        self.theme("user.svg", self.system)
        system = self.theme("system.svg", self.system)
        self.theme("system.svg", self.other)
        pixmap = self.file(self.user / "pixmaps/pixmap.svg")
        self.theme("pixmap.svg", self.system)
        self.assertEqual(self.resolve("legacy", "user", "system", "pixmap"),
                         {"legacy": legacy, "user": user, "system": system, "pixmap": pixmap})

    def test_cli_treats_spaces_unicode_and_shell_characters_literally(self):
        name = "My App 'café' $(touch MARKER) `touch BACKTICK` ; & #"
        path = self.theme(name + ".svg", theme="Theme with spaces")
        dash = self.theme("--literal.png")
        self.assertEqual(self.run_helper(name, "--literal", "missing"),
                         {"ok": True, "icons": {name: path, "--literal": dash}})
        self.assertFalse((self.root / "MARKER").exists())
        self.assertFalse((self.root / "BACKTICK").exists())
        self.assertTrue(Path(path).is_absolute())

    def test_calls_rescan_new_icons_and_do_not_retain_removed_ones(self):
        self.assertEqual(self.resolve("fresh"), {})
        path = self.theme("fresh.svg")
        self.assertEqual(self.resolve("fresh"), {"fresh": path})
        self.assertEqual(self.run_helper("fresh"), {"ok": True, "icons": {"fresh": path}})
        Path(path).unlink()
        self.assertEqual(self.resolve("fresh"), {})
        self.assertEqual(self.run_helper("fresh"), {"ok": True, "icons": {}})

    def test_symlink_files_work_without_traversing_directory_links_or_loops(self):
        target = Path(self.theme("target.svg"))
        alias = target.with_name("alias.svg")
        alias.symlink_to(target.name)
        target.with_name("dangling.svg").symlink_to("absent.svg")
        target.with_name("cycle.svg").symlink_to("cycle.svg")
        self.file(self.root / "outside/apps/hidden.svg")
        (self.user / "icons/linked-theme").symlink_to(self.root / "outside", target_is_directory=True)
        (target.parent / "loop").symlink_to(self.user / "icons", target_is_directory=True)
        os.mkfifo(target.with_name("fifo.svg"))
        target.with_name("directory.svg").mkdir()
        with patch("builtins.open", side_effect=AssertionError("must not read image contents")):
            self.assertEqual(self.resolve("alias", "target", "dangling", "cycle", "hidden", "fifo", "directory"),
                             {"alias": str(alias), "target": str(target)})

    def test_missing_unreadable_and_non_directory_roots_are_ignored(self):
        expected = self.theme("available.svg", self.system)
        self.file(self.home / ".icons")
        denied = self.user / "icons"
        scan = os.scandir

        def restricted(path):
            if os.fspath(path) == str(denied):
                raise PermissionError("private fixture")
            return scan(path)

        with patch.object(icons.os, "scandir", side_effect=restricted):
            self.assertEqual(self.resolve("available"), {"available": expected})

    def test_malformed_names_are_omitted_without_a_scan(self):
        invalid = ["", " ", ".", "..", "/absolute", "../relative", "dir/name", "dir\\name",
                   "file:icon", "https://example", "bad\nname", "bad\x00name", "bad\x7fname",
                   "x" * 257, None, 42]
        with patch.object(icons.os, "scandir", side_effect=AssertionError("empty request must not scan")):
            self.assertEqual(icons.resolve_icons(invalid, self.roots), {})
        self.assertEqual(icons.requested_names(["x" * 256, "safe..name", "has spaces"]),
                         {"x" * 256, "safe..name", "has spaces"})
        self.assertEqual(self.run_helper("", "../icon", "file:icon", "x" * 257), {"ok": True, "icons": {}})
        self.assertEqual(self.run_helper(), {"ok": True, "icons": {}})

    def test_request_cap_is_512_arguments_even_with_duplicates_or_invalid_names(self):
        last = self.theme("last.svg")
        self.theme("overflow.svg")
        names = [f"missing-{n}" for n in range(511)] + ["last", "overflow"]
        self.assertEqual(icons.resolve_icons(names, self.roots), {"last": last})
        self.assertEqual(self.run_helper(*names), {"ok": True, "icons": {"last": last}})
        self.assertEqual(icons.resolve_icons([""] * 512 + ["last"], self.roots), {})
        self.assertEqual(icons.resolve_icons(["missing"] * 512 + ["last"], self.roots), {})

    def test_default_xdg_roots_and_explicit_roots_do_not_depend_on_machine(self):
        fallback = self.home / ".local/share"
        self.assertEqual(icons.search_roots(self.home, {}), [
            (self.home / ".icons", False), (fallback / "icons", False), (fallback / "pixmaps", True),
            (Path("/usr/local/share/icons"), False), (Path("/usr/local/share/pixmaps"), True),
            (Path("/usr/share/icons"), False), (Path("/usr/share/pixmaps"), True),
        ])
        self.assertEqual(icons.search_roots(self.home, {
            "XDG_DATA_HOME": "relative", "XDG_DATA_DIRS": f":relative:{self.system}:{self.system}/",
        }), [
            (self.home / ".icons", False), (fallback / "icons", False), (fallback / "pixmaps", True),
            (self.system / "icons", False), (self.system / "pixmaps", True),
        ])
        self.assertEqual(icons.resolve_icons(["missing"], []), {})


if __name__ == "__main__":
    unittest.main()
