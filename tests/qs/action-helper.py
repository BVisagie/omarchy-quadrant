"""QML action transport fixture: never calls a desktop tool."""
import json
import sys
import time

value = json.loads(sys.stdin.readline())["value"]
if value == "SLOW":
    time.sleep(0.4)
if value == "EXIT":
    sys.exit(3)
print(json.dumps({"ok": False, "error": "Fixture action failed"} if value == "FAIL"
                 else {"ok": True, "value": "other" if value == "MISMATCH" else value}), flush=True)
