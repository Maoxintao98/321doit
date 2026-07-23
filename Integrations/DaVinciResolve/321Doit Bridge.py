#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""321Doit Bridge for DaVinci Resolve — Utility Script entry point.

Run from: Workspace -> Scripts -> 321Doit Bridge
This script only launches the UI window; it never modifies the Resolve
project on startup. All import actions require explicit preflight + execute.
"""

import os
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
# The bridge package is installed outside Resolve's Scripts tree so Resolve
# does not enumerate the internal modules in the Scripts menu.
SUPPORT_DIR = os.path.expanduser(
    "~/Library/Application Support/321Doit/ResolveBridge")
if os.path.isdir(os.path.join(SUPPORT_DIR, "bridge")):
    if SUPPORT_DIR not in sys.path:
        sys.path.insert(0, SUPPORT_DIR)
elif SCRIPT_DIR not in sys.path:
    # Development fallback when running directly from the repository.
    sys.path.insert(0, SCRIPT_DIR)


def _bootstrap_resolve():
    # type: () -> object
    api = os.environ.get(
        "RESOLVE_SCRIPT_API",
        "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting")
    modules = os.path.join(api, "Modules")
    if modules not in sys.path:
        sys.path.append(modules)
    import DaVinciResolveScript as bmd  # type: ignore
    resolve = bmd.scriptapp("Resolve")
    if resolve is None:
        raise RuntimeError(
            "Resolve 拒绝了本机脚本连接。请在 Resolve 的偏好设置 → "
            "系统 → 常规中，把“外部脚本访问”设为 Local/本地，然后重启 Resolve。")
    return resolve, bmd


def _show_startup_error(message):
    # type: (str) -> None
    sys.stderr.write("321Doit Bridge: %s\n" % message)
    if sys.platform != "darwin":
        return
    escaped = str(message).replace("\\", "\\\\").replace('"', '\\"')
    script = (
        'display alert "321Doit Bridge 无法启动" '
        'message "%s" as warning' % escaped)
    try:
        subprocess.run(
            ["/usr/bin/osascript", "-e", script],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL)
    except Exception:
        pass


def main():
    try:
        resolve, bmd = _bootstrap_resolve()
    except Exception as exc:
        _show_startup_error(str(exc))
        return

    fusion = resolve.Fusion()
    from bridge.ui import run_ui
    run_ui(resolve, fusion, bmd)


if __name__ == "__main__":
    main()
