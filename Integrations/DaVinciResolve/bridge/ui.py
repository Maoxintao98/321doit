# -*- coding: utf-8 -*-
"""Fusion UIManager window for 321Doit Bridge.

Uses only Resolve's built-in UIManager (no PyQt/Tkinter). The window is
single-instance keyed ``com.321doit.resolve.bridge``. Opening the window
or selecting a task never modifies the Resolve project; the user must run
preflight, then execute.

This module is imported only when running inside DaVinci Resolve, so the
lazy import of ``DaVinciResolveScript`` is acceptable.
"""

import os
import sys

from . import manifest as manifest_mod
from .importer import Importer, ImportOptions
from .result_writer import write_and_emit

WIN_ID = "com.321doit.resolve.bridge"

ID_VERSION = "ResolveVersion"
ID_PROJECT = "ProjectName"
ID_TASK_BTN = "SelectTask"
ID_TASK_PATH = "TaskPath"
ID_LOG_BTN = "SelectLog"
ID_LOG_PATH = "LogPath"
ID_SUMMARY = "Summary"
ID_CHK_ORIG = "ChkOriginals"
ID_CHK_META = "ChkMetadata"
ID_CHK_COLOR = "ChkColor"
ID_CHK_FLAG = "ChkFlag"
ID_CHK_SKIP = "ChkSkipDup"
ID_CHK_PARTIAL = "ChkPartial"
ID_BTN_PRE = "BtnPreflight"
ID_BTN_EXEC = "BtnExecute"
ID_BTN_CLOSE = "BtnClose"
ID_LOG = "LogArea"


def _log(win, message):
    # type: (Any, str) -> None
    try:
        area = win.Find(ID_LOG)
        text = area.PlainText or ""
        area.PlainText = text + message + "\n"
    except Exception:
        sys.stdout.write(message + "\n")


def _set_text(win, item_id, text):
    # type: (Any, str, str) -> None
    try:
        # Labels and LineEdit expose a Text property; use it (PlainText is
        # a TextEdit-only attribute and will raise on a Label/LineEdit).
        win.Find(item_id).Text = text
    except Exception:
        pass


def _get_text(win, item_id):
    # type: (Any, str) -> str
    try:
        return str(win.Find(item_id).Text or "")
    except Exception:
        return ""


def _osascript_pick(prompt, choose_folder=True):
    # type: (str, bool) -> str
    """Native macOS file/folder picker via AppleScript (no third-party deps).

    Returns the chosen POSIX path, or "" if cancelled. Falls back to "" on
    any error so the caller can prompt the user to paste a path instead.
    """
    import subprocess
    if choose_folder:
        cmd = ['set theResult to choose folder with prompt "%s"\n'
               'POSIX path of theResult' % _escape_applescript_string(prompt)]
    else:
        cmd = ['set theResult to choose file with prompt "%s"\n'
               'POSIX path of theResult' % _escape_applescript_string(prompt)]
    # Wrap in try so a user cancel (error -128) returns "" instead of raising.
    script = (
        'try\n'
        + ''.join(cmd) +
        '\non error\n'
        '  return ""\n'
        'end try\n'
    )
    try:
        proc = subprocess.Popen(
            ["osascript", "-"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE)
        out, _ = proc.communicate(script.encode("utf-8"))
        return out.decode("utf-8", "replace").strip()
    except Exception:
        return ""


def _escape_applescript_string(text):
    # type: (str) -> str
    return (text or "").replace("\\", "\\\\").replace('"', '\\"')


def _browse(win, ui, title, choose_folder=True):
    # type: (Any, Any, str, bool) -> str
    # Resolve's UIManager has no documented cross-version file dialog, so we
    # use the macOS-native AppleScript picker (standard library only).
    return _osascript_pick(title, choose_folder=choose_folder)


def run_ui(resolve, fusion, bmd):
    # type: (Any, Any, Any) -> None
    ui = fusion.UIManager
    dispatcher = bmd.UIDispatcher(ui)

    existing = ui.FindWindow(WIN_ID)
    if existing:
        existing.Show()
        existing.Raise()
        return

    adapter_mod = __import__("bridge.resolve_adapter", fromlist=["ResolveAdapter"])
    ResolveAdapter = adapter_mod.ResolveAdapter

    adapter = ResolveAdapter(resolve)
    version = adapter.get_version_string()
    project = adapter.get_current_project_name() or "(no project open)"

    win = dispatcher.AddWindow({
        "ID": WIN_ID,
        "Geometry": [120, 120, 760, 720],
        "WindowTitle": "321Doit Bridge",
    }, ui.VGroup([
        ui.Label({"Text": "<b>321Doit Bridge for DaVinci Resolve</b>",
                  "Weight": 0, "Font": ui.Font({"PixelSize": 16})}),
        ui.Label({"ID": ID_VERSION,
                  "Text": "Resolve: %s" % version, "Weight": 0}),
        ui.Label({"ID": ID_PROJECT,
                  "Text": "Project: %s" % project, "Weight": 0}),
        ui.VGap(6),
        ui.HGroup({"Weight": 0}, [
            ui.Button({"ID": ID_TASK_BTN, "Text": "Select Task\u2026",
                       "Weight": 0}),
            ui.LineEdit({"ID": ID_TASK_PATH, "PlaceholderText": "task root or .321doit/task.json",
                         "ReadOnly": False}),
        ]),
        ui.HGroup({"Weight": 0}, [
            ui.Button({"ID": ID_LOG_BTN, "Text": "Select Script Log\u2026",
                       "Weight": 0}),
            ui.LineEdit({"ID": ID_LOG_PATH, "PlaceholderText": ".321log (optional)",
                         "ReadOnly": False}),
        ]),
        ui.VGap(6),
        ui.Label({"ID": ID_SUMMARY, "Text": "Summary: (run preflight)",
                  "Weight": 0}),
        ui.VGap(6),
        ui.HGroup({"Weight": 0, "Margin": 4}, [
            ui.CheckBox({"ID": ID_CHK_ORIG, "Text": "Import originals",
                          "Checked": True}),
            ui.CheckBox({"ID": ID_CHK_META, "Text": "Write script-log metadata",
                          "Checked": True}),
            ui.CheckBox({"ID": ID_CHK_COLOR, "Text": "Apply status colors",
                          "Checked": True}),
            ui.CheckBox({"ID": ID_CHK_FLAG, "Text": "Apply circle-take flags",
                          "Checked": True}),
        ]),
        ui.HGroup({"Weight": 0, "Margin": 4}, [
            ui.CheckBox({"ID": ID_CHK_SKIP, "Text": "Skip already imported",
                          "Checked": True}),
            ui.CheckBox({"ID": ID_CHK_PARTIAL,
                          "Text": "Allow import of verified part only",
                          "Checked": False}),
        ]),
        ui.VGap(6),
        ui.HGroup({"Weight": 0}, [
            ui.Button({"ID": ID_BTN_PRE, "Text": "Preflight only"}),
            ui.Button({"ID": ID_BTN_EXEC, "Text": "Execute Import", "Enabled": False}),
            ui.HGap(2),
            ui.Button({"ID": ID_BTN_CLOSE, "Text": "Close"}),
        ]),
        ui.VGap(4),
        ui.TextEdit({"ID": ID_LOG, "ReadOnly": True, "Weight": 1,
                     "AcceptRichText": False}),
    ]))

    state = {"importer": None, "preflight": None}

    def refresh_project_info():
        # type: () -> None
        try:
            name = adapter.get_current_project_name()
            _set_text(win, ID_PROJECT, "Project: %s" % (name or "(no project open)"))
        except Exception:
            pass

    def build_importer():
        # type: () -> Importer
        task_path = _get_text(win, ID_TASK_PATH).strip()
        manifest, task_root = manifest_mod.load_manifest(task_path)
        log_path = _get_text(win, ID_LOG_PATH).strip()
        script_log = None
        if log_path:
            from .scriptlog import parse_script_log
            script_log = parse_script_log(log_path)
        else:
            from .scriptlog import find_script_log
            found = find_script_log(task_root)
            if found:
                from .scriptlog import parse_script_log
                script_log = parse_script_log(found)
                _set_text(win, ID_LOG_PATH, found)
        return Importer(adapter, manifest, task_root, script_log)

    def options_from_ui():
        # type: () -> ImportOptions
        opts = ImportOptions()
        opts.import_originals = bool(win.Find(ID_CHK_ORIG).Checked)
        opts.write_script_log_metadata = bool(win.Find(ID_CHK_META).Checked)
        opts.apply_status_colors = bool(win.Find(ID_CHK_COLOR).Checked)
        opts.apply_circle_flags = bool(win.Find(ID_CHK_FLAG).Checked)
        opts.skip_already_imported = bool(win.Find(ID_CHK_SKIP).Checked)
        opts.allow_partial = bool(win.Find(ID_CHK_PARTIAL).Checked)
        return opts

    def update_summary(pre):
        # type: (Any) -> None
        if pre is None:
            pre = state.get("preflight")
        if pre is None:
            return
        c = pre.counts
        text = ("Files: %d  Verified: %d  Missing: %d  Matched: %d  "
                "Conflicts: %d  Duplicates: %d") % (
            c["discovered"], c["verified"], c["missing"],
            c["metadataMatched"], c["metadataConflicts"],
            c["skippedDuplicate"])
        _set_text(win, ID_SUMMARY, "Summary: " + text)

    def on_select_task(ev):
        refresh_project_info()
        path = _browse(win, ui, "Select task root", choose_folder=True)
        if path:
            _set_text(win, ID_TASK_PATH, path)
            _log(win, "Task selected: %s" % path)
        _invalidate()

    def on_select_log(ev):
        path = _browse(win, ui, "Select .321log", choose_folder=False)
        if path:
            _set_text(win, ID_LOG_PATH, path)
            _log(win, "Script log selected: %s" % path)
        _invalidate()

    def _invalidate(ev=None):
        # type: (Any) -> None
        # Clear prefetched state and disable Execute so a stale preflight
        # result can never drive an import on changed inputs. Resolve passes
        # an event dictionary to TextChanged/Clicked handlers, while direct
        # callers pass nothing, so the optional argument is intentional.
        state["importer"] = None
        state["preflight"] = None
        state["pf_task"] = None
        state["pf_log"] = None
        state["pf_opts_sig"] = None
        try:
            win.Find(ID_BTN_EXEC).Enabled = False
        except Exception:
            pass
        _set_text(win, ID_SUMMARY, "Summary: (run preflight)")

    def _opts_sig(opts):
        # type: (ImportOptions) -> str
        return "|".join([
            str(opts.import_originals),
            str(opts.write_script_log_metadata),
            str(opts.apply_status_colors),
            str(opts.apply_circle_flags),
            str(opts.skip_already_imported),
            str(opts.allow_partial),
        ])

    def on_preflight(ev):
        try:
            state["importer"] = build_importer()
        except manifest_mod.ManifestError as exc:
            _log(win, "[ERROR] %s" % exc)
            return
        except Exception as exc:  # noqa
            _log(win, "[ERROR] %s: %s" % (type(exc).__name__, exc))
            return
        opts = options_from_ui()
        try:
            pre = state["importer"].run_preflight(opts)
        except Exception as exc:  # noqa
            _log(win, "[ERROR] preflight: %s: %s" % (type(exc).__name__, exc))
            return
        state["preflight"] = pre
        # Record the exact inputs this preflight is valid for, so Execute can
        # detect staleness if change events didn't fire.
        state["pf_task"] = _get_text(win, ID_TASK_PATH).strip()
        state["pf_log"] = _get_text(win, ID_LOG_PATH).strip()
        state["pf_opts_sig"] = _opts_sig(opts)
        for w in pre.warnings:
            _log(win, "[warn] %s" % w)
        for e in pre.errors:
            _log(win, "[error] %s" % e)
        if pre.missing:
            _log(win, "[missing] %d files" % len(pre.missing))
        update_summary(pre)
        win.Find(ID_BTN_EXEC).Enabled = not pre.blocking
        _log(win, "Preflight complete. status=%s" % (
            "blocked" if pre.blocking else "ok"))

    def on_execute(ev):
        imp = state.get("importer")
        pre = state.get("preflight")
        if imp is None or pre is None:
            _log(win, "[ERROR] Run preflight first.")
            return
        # Safety net: if any input changed since the last preflight, refuse to
        # execute on stale results and require a fresh preflight. This guards
        # against Resolve versions where change events don't fire.
        current_task = _get_text(win, ID_TASK_PATH).strip()
        current_log = _get_text(win, ID_LOG_PATH).strip()
        opts = options_from_ui()
        opts.dry_run = False
        if (current_task != state.get("pf_task")
                or current_log != state.get("pf_log")
                or _opts_sig(opts) != state.get("pf_opts_sig")):
            _invalidate()
            _log(win, "[ERROR] Inputs changed since preflight. Run preflight again.")
            return
        result = imp.execute(opts, pre)
        for w in result.get("warnings", []):
            _log(win, "[warn] %s" % w)
        for e in result.get("errors", []):
            _log(win, "[error] %s" % e)
        _log(win, "Import finished: %s (imported=%d skipped=%d)" % (
            result.get("status"),
            result.get("counts", {}).get("imported", 0),
            result.get("counts", {}).get("skippedDuplicate", 0)))
        try:
            write_and_emit(result, imp.task_root)
        except Exception as exc:  # noqa
            _log(win, "[warn] result emit failed: %s" % exc)
        refresh_project_info()

    def on_close(ev):
        dispatcher.ExitLoop()

    win.On[ID_TASK_BTN].Clicked = on_select_task
    win.On[ID_LOG_BTN].Clicked = on_select_log
    win.On[ID_BTN_PRE].Clicked = on_preflight
    win.On[ID_BTN_EXEC].Clicked = on_execute
    win.On[ID_BTN_CLOSE].Clicked = on_close
    win.On[WIN_ID].Close = on_close

    # Invalidate the prefetched preflight whenever any input changes so a
    # stale result can never drive an import on different inputs. Wrapped
    # defensively since some Resolve builds may not expose every event.
    for _id in (ID_TASK_PATH, ID_LOG_PATH):
        try:
            win.On[_id].TextChanged = _invalidate
        except Exception:
            pass
    for _id in (ID_CHK_ORIG, ID_CHK_META, ID_CHK_COLOR, ID_CHK_FLAG,
                ID_CHK_SKIP, ID_CHK_PARTIAL):
        try:
            win.On[_id].Clicked = _invalidate
        except Exception:
            pass

    _log(win, "Ready. Select a task, then run Preflight.")
    win.Show()
    dispatcher.RunLoop()
