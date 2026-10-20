"""Exercise the real collector with optional delayed/failing fixture requests."""
import importlib.util
import json
import os
from pathlib import Path
import sys
import time

path = Path(__file__).with_name("hardware-real.py")
spec = importlib.util.spec_from_file_location("hardware_real", path)
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)
state = json.loads(Path(os.environ["QUADRANT_TEST_HARDWARE_STATE"]).read_text())
mode = sys.argv[1]
if state.get("packageDenied"):
    access = collector.os.access
    read_number = collector.number
    def denied_access(path, mode):
        return False if Path(path).name in {"energy_uj", "max_energy_range_uj"} else access(path, mode)
    def denied_number(path, *args, **kwargs):
        return (None, "Permission denied") if Path(path).name in {"energy_uj", "max_energy_range_uj"} else read_number(path, *args, **kwargs)
    collector.os.access = denied_access
    collector.number = denied_number
data = collector.snapshot(Path(os.environ["QUADRANT_SYS_PATH"]), mode)
with open(os.environ["QUADRANT_TEST_HARDWARE_REQUESTS"], "a") as stream:
    stream.write(json.dumps({"mode": mode, "marker": state.get("marker"), "delay": state.get("delay", 0)}) + "\n")
if "marker" in state and mode == "sample":
    for sensor in data["sensors"]:
        if sensor["kind"] == "temperature" and not sensor["gpu"]:
            sensor["value"] = state["marker"]
time.sleep(state.get("delay", 0))
if state.get("fail"):
    print(json.dumps({"ok": False, "error": "Fixture hardware unavailable"}))
else:
    print(json.dumps(data, ensure_ascii=True))
