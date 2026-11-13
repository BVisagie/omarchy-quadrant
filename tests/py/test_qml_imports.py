import glob
import os
import re
import shutil
import subprocess
import unittest

from tests.py.helpers import ROOT


class QmlImports(unittest.TestCase):
    def test_namespaced_shell_singletons(self):
        for awk in ("mawk", "gawk"):
            if not shutil.which(awk):
                continue
            for singleton in ("Color", "Style", "Util", "Border"):
                for prefix, valid in (("", False), ("Commons.", True)):
                    with self.subTest(awk=awk, singleton=singleton, prefix=prefix):
                        result = subprocess.run(
                            [awk, "-f", os.path.join(ROOT, "tests/check-qml-imports.awk")],
                            input=f"Item {{ property var value: {prefix}{singleton}.value }}\n",
                            text=True, capture_output=True, check=False,
                        )
                        self.assertEqual(result.returncode == 0, valid, result.stdout)

    def test_animations_follow_the_shell_setting(self):
        # `omarchy toggle animations` only reaches durations given through Style.duration().
        shipped = [os.path.join(ROOT, name) for name in ("BarWidget.qml", "Panel.qml")]
        shipped += glob.glob(os.path.join(ROOT, "components", "*.qml")) + glob.glob(os.path.join(ROOT, "tabs", "*.qml"))
        for path in shipped:
            with open(path, encoding="utf-8") as handle, self.subTest(path=os.path.relpath(path, ROOT)):
                self.assertIsNone(re.search(r"\bduration:\s*\d", handle.read()))
