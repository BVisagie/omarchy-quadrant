#!/usr/bin/env python3
"""Resolve requested theme icon names using filesystem metadata only.

Each invocation is independent: no icon inventory or cache is persisted. SVG,
PNG, then XPM wins, followed by search-root order and the literal absolute path.
"""
from __future__ import annotations

from itertools import islice
import json
import os
from pathlib import Path
import sys

MAX_NAMES = 512
MAX_NAME_LENGTH = 256
FORMATS = {".svg": 0, ".png": 1, ".xpm": 2}
CONTEXTS = {"apps", "devices"}


def requested_names(names):
    """Keep safe, literal names from at most the first MAX_NAMES arguments."""
    return {
        name for name in islice(names, MAX_NAMES)
        if isinstance(name, str) and 0 < len(name) <= MAX_NAME_LENGTH
        and name.strip() and name not in {".", ".."}
        and not any(char in name for char in "/\\:")
        and not any(ord(char) < 32 or 127 <= ord(char) < 160 for char in name)
    }


def search_roots(home=None, environ=None):
    """Return ordered (directory, flat) pairs; explicit inputs isolate tests.

    Flat roots are pixmaps; theme roots require an apps/devices context. Each
    data directory's theme tree precedes its pixmaps, with user data first.
    Relative XDG paths are ignored, as required by the XDG directory convention.
    """
    environ = os.environ if environ is None else environ
    home = Path.home() if home is None else Path(home)
    data_home = environ.get("XDG_DATA_HOME") or str(home / ".local/share")
    if not os.path.isabs(data_home):
        data_home = str(home / ".local/share")
    data_dirs = (environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":")
    roots = [(home / ".icons", False)]
    seen = set()
    for directory in [data_home, *data_dirs]:
        if not os.path.isabs(directory):
            continue
        directory = os.path.normpath(directory)
        if directory in seen:
            continue
        seen.add(directory)
        roots.extend([(Path(directory) / "icons", False), (Path(directory) / "pixmaps", True)])
    return roots


def icon_files(root, flat):
    """Yield candidate paths without reading files or following directory links."""
    if flat:
        try:
            with os.scandir(root) as entries:
                for entry in entries:
                    yield entry.path
        except OSError:
            pass
        return

    for directory, dirs, files in os.walk(root, followlinks=False):
        # Prune actions even if a misleading nested directory is named apps.
        dirs[:] = [name for name in dirs if name != "actions"
                   and not os.path.islink(os.path.join(directory, name))]
        parts = Path(directory).relative_to(root).parts
        if not CONTEXTS.intersection(parts):
            continue
        for filename in files:
            yield os.path.join(directory, filename)


def resolve_icons(names, roots):
    """Return only requested names from explicit (directory, flat) search roots.

    File symlinks are supported; dangling links, special files, missing roots,
    and unreadable directories are ignored. Paths retain their literal names.
    """
    wanted = requested_names(names)
    if not wanted:
        return {}
    matches = {}
    for root_rank, (root, flat) in enumerate(roots):
        root = os.path.abspath(root)
        for path in icon_files(root, flat):
            name, extension = os.path.splitext(os.path.basename(path))
            format_rank = FORMATS.get(extension.lower())
            if name not in wanted or format_rank is None or not os.path.isfile(path):
                continue
            rank = (format_rank, root_rank, path)
            if name not in matches or rank < matches[name]:
                matches[name] = rank
    return {name: matches[name][2] for name in sorted(matches)}


def main(args=None):
    args = sys.argv[1:] if args is None else args
    print(json.dumps({"ok": True, "icons": resolve_icons(args, search_roots())},
                     ensure_ascii=True, separators=(",", ":")), flush=True)


if __name__ == "__main__":
    main()
