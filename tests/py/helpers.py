"""Shared helpers for Quadrant's python helper tests.

The helper scripts have no .py extension, so they are loaded by path.
Each test builds a throwaway /proc and /sys tree and points the script at
it through QUADRANT_PROC_PATH / QUADRANT_SYS_PATH.
"""
from __future__ import annotations

import importlib.util
import os
import sys
import types

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCRIPTS = os.path.join(ROOT, "scripts")


def load_script(name: str) -> types.ModuleType:
    path = os.path.join(SCRIPTS, name)
    loader = importlib.machinery.SourceFileLoader(name.replace("-", "_"), path)
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    sys.modules[loader.name] = module
    loader.exec_module(module)
    return module


def write(path: str, text: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


def fake_process(proc: str, pid: int, fds: dict[int, tuple[str, str]], **files: str) -> None:
    """Create /proc/<pid> with fd symlinks and fdinfo texts.

    fds maps fd number -> (symlink target, fdinfo text).
    Extra keyword files (stat, comm, ...) are written verbatim.
    """
    base = os.path.join(proc, str(pid))
    os.makedirs(os.path.join(base, "fd"), exist_ok=True)
    os.makedirs(os.path.join(base, "fdinfo"), exist_ok=True)
    for fd, (target, info) in fds.items():
        os.symlink(target, os.path.join(base, "fd", str(fd)))
        write(os.path.join(base, "fdinfo", str(fd)), info)
    for name, text in files.items():
        write(os.path.join(base, name), text)
