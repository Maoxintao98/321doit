#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""JSON command bridge used by the 321Doit Workflow Integration panel."""

from __future__ import print_function

import hashlib
import json
import os
import sys
import traceback

from bridge import manifest as manifest_mod
from bridge.importer import Importer, ImportOptions
from bridge.resolve_adapter import ResolveAdapter, connect
from bridge.result_writer import write_result
from bridge.scriptlog import find_script_log, parse_script_log


def _options(raw):
    opts = ImportOptions()
    raw = raw or {}
    opts.import_originals = raw.get("importOriginals", True) is not False
    opts.write_script_log_metadata = raw.get(
        "writeScriptLogMetadata", True) is not False
    opts.apply_status_colors = raw.get("applyStatusColors", True) is not False
    opts.apply_circle_flags = raw.get("applyCircleFlags", True) is not False
    opts.skip_already_imported = raw.get(
        "skipAlreadyImported", True) is not False
    opts.allow_partial = raw.get("allowPartial", False) is True
    return opts


def _load(payload):
    manifest, task_root = manifest_mod.load_manifest(payload.get("taskPath") or "")
    log_path = (payload.get("scriptLogPath") or "").strip()
    if not log_path:
        log_path = find_script_log(task_root) or ""
    script_log = parse_script_log(log_path) if log_path else None
    adapter = ResolveAdapter(connect())
    importer = Importer(adapter, manifest, task_root, script_log)
    return importer, adapter, log_path


def _path_stamp(path):
    if not path:
        return None
    try:
        stat = os.stat(path)
        return [os.path.realpath(path), int(stat.st_mtime_ns), int(stat.st_size)]
    except (OSError, AttributeError):
        try:
            stat = os.stat(path)
            return [os.path.realpath(path), int(stat.st_mtime), int(stat.st_size)]
        except OSError:
            return [os.path.realpath(path), 0, 0]


def _token(payload, importer, log_path):
    task_json = manifest_mod._candidate_task_json(payload.get("taskPath") or "")
    source = {
        "task": _path_stamp(task_json),
        "log": _path_stamp(log_path),
        "options": payload.get("options") or {},
        "taskID": importer.manifest.task_id,
    }
    packed = json.dumps(
        source, ensure_ascii=False, sort_keys=True,
        separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(packed).hexdigest()


def _preflight_dict(pre, adapter, log_path, token):
    return {
        "ok": True,
        "action": "preflight",
        "blocking": bool(pre.blocking),
        "counts": dict(pre.counts),
        "missing": list(pre.missing),
        "warnings": list(pre.warnings) + list(adapter.warnings),
        "errors": list(pre.errors),
        "scriptLogPath": log_path,
        "preflightToken": token,
        "resolveVersion": adapter.get_version_string(),
        "projectName": adapter.get_current_project_name() or "",
    }


def run(action, payload):
    importer, adapter, log_path = _load(payload)
    opts = _options(payload.get("options"))
    pre = importer.run_preflight(opts)
    token = _token(payload, importer, log_path)

    if action == "preflight":
        return _preflight_dict(pre, adapter, log_path, token)
    if action != "execute":
        raise ValueError("Unsupported action: %s" % action)
    if payload.get("preflightToken") != token:
        raise ValueError("任务、场记或导入选项已改变，请重新预检。")
    if pre.blocking:
        return _preflight_dict(pre, adapter, log_path, token)

    result = importer.execute(opts, pre)
    emitted_path = ""
    try:
        emitted_path = write_result(result, importer.task_root) or ""
    except Exception as exc:
        result.setdefault("warnings", []).append(
            "写入导入结果失败：%s" % exc)
    return {
        "ok": True,
        "action": "execute",
        "result": result,
        "resultPath": emitted_path,
        "scriptLogPath": log_path,
        "preflightToken": token,
        "projectName": adapter.get_current_project_name() or "",
    }


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        payload = json.load(sys.stdin)
        response = run(action, payload)
    except Exception as exc:
        response = {
            "ok": False,
            "error": "%s: %s" % (type(exc).__name__, exc),
        }
        if os.environ.get("DOIT_BRIDGE_DEBUG") == "1":
            response["traceback"] = traceback.format_exc()
    sys.stdout.write(json.dumps(response, ensure_ascii=False))
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
