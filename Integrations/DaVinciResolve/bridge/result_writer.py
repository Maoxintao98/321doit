# -*- coding: utf-8 -*-
"""Atomic result-writer for 321Doit Bridge imports.

Writes the import result under the task root when writable, otherwise
falls back to a per-user directory. Never modifies ``task.json``.
Also emits the ``321DOIT_RESULT_BEGIN/END`` envelope on stdout that the
321Doit Launcher consumes. Standard library only.
"""

import datetime
import json
import os
import re
import sys
import tempfile
from typing import Any, Dict, List, Optional

RESULT_SCHEMA = "com.321doit.resolve-import-result"
RESULT_SCHEMA_VERSION = 1

USER_FALLBACK_DIR = os.path.expanduser(
    "~/Library/Application Support/321Doit/ResolveBridge/results")


def _safe_filename(task_id):
    # type: (Optional[str]) -> str
    """Sanitize a taskID for use as a filename.

    The manifest ``taskID`` is expected to be a UUID, but a corrupt or
    hostile manifest could carry path separators / ``..`` to escape the
    results directory. Strip to a safe component and never allow traversal.
    """
    raw = str(task_id or "task")
    cleaned = re.sub(r"[^A-Za-z0-9_\-.]", "_", raw)
    cleaned = re.sub(r"\.{2,}", "_", cleaned).strip(".-_")
    if not cleaned or cleaned in (".", ".."):
        cleaned = "task"
    return cleaned


def now_iso():
    # type: () -> str
    return datetime.datetime.now().astimezone().isoformat()


def empty_counts():
    # type: () -> Dict[str, int]
    return {
        "discovered": 0,
        "verified": 0,
        "imported": 0,
        "skippedDuplicate": 0,
        "missing": 0,
        "metadataMatched": 0,
        "metadataConflicts": 0,
        "warnings": 0,
        "errors": 0,
    }


def new_result(task_id, resolve_version, resolve_project_name):
    # type: (str, str, Optional[str]) -> Dict[str, Any]
    return {
        "schema": RESULT_SCHEMA,
        "schemaVersion": RESULT_SCHEMA_VERSION,
        "taskID": task_id,
        "resolveVersion": resolve_version,
        "resolveProjectName": resolve_project_name,
        "startedAt": now_iso(),
        "endedAt": None,
        "status": "dryRun",
        "counts": empty_counts(),
        "clips": [],
        "warnings": [],
        "errors": [],
    }


def _atomic_write(path, text):
    # type: (str, str) -> bool
    directory = os.path.dirname(path)
    try:
        if not os.path.isdir(directory):
            os.makedirs(directory)
    except OSError:
        return False
    tmp = None
    try:
        fd, tmp = tempfile.mkstemp(dir=directory, prefix=".tmp-")
        with os.fdopen(fd, "w") as fp:
            fp.write(text)
        os.replace(tmp, path)
        return True
    except OSError:
        if tmp is not None:
            try:
                os.remove(tmp)
            except OSError:
                pass
        return False


def _task_result_path(task_root, task_id):
    # type: (str, str) -> str
    return os.path.join(task_root, ".321doit", "integrations",
                        "resolve", _safe_filename(task_id) + ".json")


def _fallback_path(task_id):
    # type: (str) -> str
    return os.path.join(USER_FALLBACK_DIR, _safe_filename(task_id) + ".json")


def write_result(result, task_root):
    # type: (Dict[str, Any], str) -> str
    """Atomically persist ``result`` and return the path written.

    Prefers ``<task_root>/.321doit/integrations/resolve/<taskID>.json``;
    if that location is read-only, falls back to the per-user directory.
    """
    result["endedAt"] = now_iso()
    text = json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True)

    primary = _task_result_path(task_root, str(result.get("taskID") or "task"))
    if _atomic_write(primary, text):
        return primary

    fallback = _fallback_path(str(result.get("taskID") or "task"))
    result.setdefault("warnings", []).append(
        "Task root is read-only; result written to %s" % fallback)
    counts = result.get("counts")
    if isinstance(counts, dict):
        counts["warnings"] = len(result["warnings"])
    fallback_text = json.dumps(
        result, ensure_ascii=False, indent=2, sort_keys=True)
    if _atomic_write(fallback, fallback_text):
        return fallback

    result.setdefault("warnings", []).append(
        "Failed to persist result to disk.")
    if isinstance(counts, dict):
        counts["warnings"] = len(result["warnings"])
    return ""


def emit_result(result):
    # type: (Dict[str, Any]) -> None
    """Print the result wrapped in the BEGIN/END envelope for the Launcher."""
    text = json.dumps(result, ensure_ascii=False)
    sys.stdout.write("321DOIT_RESULT_BEGIN\n")
    sys.stdout.write(text)
    sys.stdout.write("\n321DOIT_RESULT_END\n")
    sys.stdout.flush()


def write_and_emit(result, task_root):
    # type: (Dict[str, Any], str) -> Dict[str, Any]
    path = write_result(result, task_root)
    emit_result(result)
    return result
