#!/usr/bin/env python3
"""Explicit local panel actions; one bounded JSON request on stdin.

No clipboard reads or implicit actions. Copied bytes go to wl-copy's stdin;
mounted directories reach the default file manager as one URI argument.
"""
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys

REQUEST_LIMIT = 16384
VALUE_LIMIT = 4096
ACTION_TIMEOUT = 5


class ActionError(Exception):
    pass


def mount_targets(path="/proc/self/mountinfo"):
    """Read literal targets, including bind mounts; ismount() misses some binds."""
    escapes = {"040": " ", "011": "\t", "012": "\n", "134": "\\"}
    with open(path, encoding="utf-8", errors="surrogateescape") as handle:
        for line in handle:
            fields = line.split()
            if len(fields) >= 10 and "-" in fields[6:]:
                yield re.sub(r"\\(040|011|012|134)", lambda match: escapes[match[1]], fields[4])


def run_tool(argv, payload=None):
    # wl-copy normally forks to own the selection. Do not wait for a pipe
    # inherited by that owner; its lifetime is independent of the request.
    try:
        stdin = {"input": payload} if payload is not None else {"stdin": subprocess.DEVNULL}
        result = subprocess.run(argv, stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL, timeout=ACTION_TIMEOUT, **stdin)
    except FileNotFoundError:
        raise ActionError(f"{Path(argv[0]).name} is unavailable") from None
    except subprocess.TimeoutExpired:
        raise ActionError("The desktop tool did not confirm the request in time") from None
    except OSError:
        raise ActionError("The desktop tool could not be started") from None
    if result.returncode:
        raise ActionError(f"{Path(argv[0]).name} failed (exit {result.returncode}); check your desktop session")


def perform(kind, value, mountinfo="/proc/self/mountinfo"):
    if not isinstance(value, str) or not value or "\x00" in value or len(value) > VALUE_LIMIT:
        raise ActionError("The displayed value is empty or cannot be used")
    if kind == "copy":
        run_tool(["wl-copy", "--type", "text/plain;charset=utf-8"], value.encode("utf-8"))
    elif kind == "open-mount":
        if not value.startswith("/") or os.path.normpath(value) != value:
            raise ActionError("The mount path must be an absolute directory")
        try:
            if value not in mount_targets(mountinfo):
                raise ActionError("This volume is no longer mounted here; refresh with R")
            mode = os.stat(value).st_mode
            if not stat.S_ISDIR(mode) or not os.access(value, os.R_OK | os.X_OK):
                raise ActionError("This mounted directory is not accessible to your user")
        except OSError:
            raise ActionError("The mounted directory or mount inventory is unavailable; refresh with R") from None
        # A URI preserves whitespace, #, %, quotes and control characters.
        # GIO hands the request to the directory's registered application.
        uri = Path(value).as_uri()
        if shutil.which("gio"):
            run_tool(["gio", "open", uri])
        else:
            run_tool(["xdg-open", uri])
    else:
        raise ActionError("Unknown panel action")
    return {"ok": True, "value": value}


def main():
    try:
        if len(sys.argv) != 2:
            raise ActionError("Expected copy or open-mount")
        raw = sys.stdin.buffer.readline(REQUEST_LIMIT + 1)
        if len(raw) > REQUEST_LIMIT:
            raise ActionError("The action request is too large")
        request = json.loads(raw)
        if not isinstance(request, dict):
            raise ActionError("Invalid action request")
        response = perform(sys.argv[1], request.get("value"))
    except (UnicodeError, ValueError):
        response = {"ok": False, "error": "Invalid action request"}
    except ActionError as error:
        response = {"ok": False, "error": str(error)}
    print(json.dumps(response, ensure_ascii=True), flush=True)


if __name__ == "__main__":
    main()
