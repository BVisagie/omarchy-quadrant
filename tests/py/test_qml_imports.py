import os
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
