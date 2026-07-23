# -*- coding: utf-8 -*-
"""Shared helpers for importer/idempotency tests.

Builds throwaway task roots with real (empty) media files and matching
``task.json`` manifests so the importer's path resolution can be exercised
without touching the real filesystem layout.
"""

import json
import os
import shutil
import tempfile

from bridge import manifest as manifest_mod


def make_task_root(project_name="TestProj", card_number="A01",
                   detected_card="ARRI Alexa", project_mode="independent",
                   linked_project_id=None, failed_results=0, errors=None,
                   files=None, started_at="2026-05-04T10:00:00Z"):
    # type: (...) -> str
    """Create a temp task root with ``.321doit/task.json`` and media files.

    ``files`` is a list of dicts: {"rel": "MEDIA/A01/x.mov", "hash": "h1",
    "verified": True}. The media files are created empty on disk under the
    task root following ``rel``. Returns the task root path.
    """
    root = tempfile.mkdtemp(prefix="321doit_test_")
    dot = os.path.join(root, ".321doit")
    os.makedirs(dot)

    file_payload = []
    for spec in files or []:
        rel = spec["rel"]
        verified = spec.get("verified", True)
        copied = spec.get("copied", verified)
        source_hash = spec.get("hash", "h-" + os.path.basename(rel))
        abs_path = os.path.join(root, rel)
        os.makedirs(os.path.dirname(abs_path), exist_ok=True)
        with open(abs_path, "wb") as fp:
            fp.write(b"")
        file_payload.append({
            "relativePath": rel,
            "size": spec.get("size", 0),
            "sourceHash": source_hash,
            "targets": [{
                "rootPath": root,
                "outputPath": abs_path,
                "copied": copied,
                "verified": verified,
                "targetHash": source_hash if verified else None,
                "error": None if verified else "fail",
            }],
        })

    manifest = {
        "schema": manifest_mod.SUPPORTED_SCHEMA,
        "schemaVersion": manifest_mod.SUPPORTED_SCHEMA_VERSION,
        "taskID": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        "projectAssociationMode": project_mode,
        "linkedProjectID": linked_project_id,
        "projectName": project_name,
        "cardNumber": card_number,
        "detectedCard": detected_card,
        "targetPath": root,
        "startedAt": started_at,
        "endedAt": started_at,
        "checksumAlgorithm": "xxHash64",
        "failedResults": failed_results,
        "files": file_payload,
        "errors": errors or [],
    }
    with open(os.path.join(dot, "task.json"), "w") as fp:
        json.dump(manifest, fp)
    return root


def cleanup(root):
    # type: (str) -> None
    shutil.rmtree(root, ignore_errors=True)


def load_manifest(task_root):
    # type: (str) -> object
    return manifest_mod.load_manifest(task_root)
