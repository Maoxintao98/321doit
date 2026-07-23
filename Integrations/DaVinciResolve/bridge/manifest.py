# -*- coding: utf-8 -*-
"""Parsing and validation of a 321Doit ``task.json`` offload manifest.

This module has no dependency on DaVinci Resolve and is fully unit-testable.
Only the Python standard library is used and every type annotation is valid
under Python 3.6.
"""

import json
import os
from typing import Any, Dict, List, Optional, Tuple

SUPPORTED_SCHEMA = "com.321doit.offload-task"
SUPPORTED_SCHEMA_VERSION = 2


class ManifestError(Exception):
    """Raised when a task manifest is missing, unreadable or unsupported."""


class TargetResult(object):
    """One copy target row for a single file inside ``task.json``."""

    __slots__ = ("root_path", "output_path", "copied", "verified",
                 "target_hash", "error")

    def __init__(self, root_path, output_path, copied, verified,
                 target_hash=None, error=None):
        # type: (str, str, bool, bool, Optional[str], Optional[str]) -> None
        self.root_path = root_path
        self.output_path = output_path
        self.copied = copied
        self.verified = verified
        self.target_hash = target_hash
        self.error = error

    @classmethod
    def from_dict(cls, data):
        # type: (Dict[str, Any]) -> "TargetResult"
        return cls(
            root_path=str(data.get("rootPath") or ""),
            output_path=str(data.get("outputPath") or ""),
            copied=bool(data.get("copied")),
            verified=bool(data.get("verified")),
            target_hash=data.get("targetHash"),
            error=data.get("error"),
        )

    def to_dict(self):
        # type: () -> Dict[str, Any]
        return {
            "rootPath": self.root_path,
            "outputPath": self.output_path,
            "copied": self.copied,
            "verified": self.verified,
            "targetHash": self.target_hash,
            "error": self.error,
        }


class FileEntry(object):
    """One file row from the manifest ``files`` array."""

    __slots__ = ("relative_path", "size", "source_hash", "targets")

    def __init__(self, relative_path, size, source_hash, targets):
        # type: (str, int, str, List[TargetResult]) -> None
        self.relative_path = relative_path
        self.size = size
        self.source_hash = source_hash
        self.targets = targets

    @property
    def verified_targets(self):
        # type: () -> List[TargetResult]
        return [t for t in self.targets if t.copied and t.verified]

    @property
    def is_verified(self):
        # type: () -> bool
        return any(t.copied and t.verified for t in self.targets)

    @classmethod
    def from_dict(cls, data):
        # type: (Dict[str, Any]) -> "FileEntry"
        targets_raw = data.get("targets") or []
        targets = [TargetResult.from_dict(t) for t in targets_raw]
        return cls(
            relative_path=str(data.get("relativePath") or ""),
            size=int(data.get("size") or 0),
            source_hash=str(data.get("sourceHash") or ""),
            targets=targets,
        )

    def to_dict(self):
        # type: () -> Dict[str, Any]
        return {
            "relativePath": self.relative_path,
            "size": self.size,
            "sourceHash": self.source_hash,
            "targets": [t.to_dict() for t in self.targets],
        }


class TaskManifest(object):
    """Validated, in-memory representation of a ``task.json``."""

    __slots__ = (
        "task_id", "project_association_mode", "linked_project_id",
        "project_name", "card_number", "detected_card", "target_path",
        "started_at", "ended_at", "checksum_algorithm", "failed_results",
        "errors", "files", "raw",
    )

    def __init__(self, task_id, project_association_mode, linked_project_id,
                 project_name, card_number, detected_card, target_path,
                 started_at, ended_at, checksum_algorithm, failed_results,
                 errors, files, raw):
        # type: (str, str, Optional[str], str, str, str, str, str, str, str, int, List[str], List[FileEntry], Dict[str, Any]) -> None
        self.task_id = task_id
        self.project_association_mode = project_association_mode
        self.linked_project_id = linked_project_id
        self.project_name = project_name
        self.card_number = card_number
        self.detected_card = detected_card
        self.target_path = target_path
        self.started_at = started_at
        self.ended_at = ended_at
        self.checksum_algorithm = checksum_algorithm
        self.failed_results = failed_results
        self.errors = errors
        self.files = files
        self.raw = raw

    @property
    def has_failures(self):
        # type: () -> bool
        return self.failed_results > 0 or bool(self.errors)

    @property
    def total_files(self):
        # type: () -> int
        return len(self.files)

    @property
    def verified_files(self):
        # type: () -> List[FileEntry]
        return [f for f in self.files if f.is_verified]

    @classmethod
    def from_dict(cls, data):
        # type: (Dict[str, Any]) -> "TaskManifest"
        schema = str(data.get("schema") or "")
        if schema != SUPPORTED_SCHEMA:
            raise ManifestError(
                "Unknown manifest schema %r; expected %r" % (schema, SUPPORTED_SCHEMA))
        version = data.get("schemaVersion")
        if not isinstance(version, int):
            raise ManifestError("manifest is missing a numeric schemaVersion")
        if version != SUPPORTED_SCHEMA_VERSION:
            if version > SUPPORTED_SCHEMA_VERSION:
                raise ManifestError(
                    "manifest schemaVersion %d is newer than supported %d; "
                    "please upgrade 321Doit Bridge" % (version, SUPPORTED_SCHEMA_VERSION))
            raise ManifestError(
                "manifest schemaVersion %d is not supported; only version %d "
                "is accepted" % (version, SUPPORTED_SCHEMA_VERSION))

        files_raw = data.get("files") or []
        files = [FileEntry.from_dict(f) for f in files_raw]

        linked = data.get("linkedProjectID")
        return cls(
            task_id=str(data.get("taskID") or ""),
            project_association_mode=str(data.get("projectAssociationMode") or "independent"),
            linked_project_id=(str(linked) if linked else None),
            project_name=str(data.get("projectName") or ""),
            card_number=str(data.get("cardNumber") or ""),
            detected_card=str(data.get("detectedCard") or ""),
            target_path=str(data.get("targetPath") or ""),
            started_at=str(data.get("startedAt") or ""),
            ended_at=str(data.get("endedAt") or ""),
            checksum_algorithm=str(data.get("checksumAlgorithm") or ""),
            failed_results=int(data.get("failedResults") or 0),
            errors=[str(e) for e in (data.get("errors") or [])],
            files=files,
            raw=data,
        )


def _candidate_task_json(path):
    # type: (str) -> str
    if os.path.isfile(path) and path.lower().endswith(".json"):
        return path
    dot = os.path.join(path, ".321doit", "task.json")
    if os.path.isfile(dot):
        return dot
    legacy = os.path.join(path, "_321Doit", "task.json")
    if os.path.isfile(legacy):
        return legacy
    raise ManifestError("No task.json found under %r" % path)


def load_manifest(task_root_or_file):
    # type: (str) -> Tuple[TaskManifest, str]
    """Load and validate a task manifest.

    ``task_root_or_file`` may be either the path to ``task.json`` itself or
    the task root directory that contains ``.321doit/task.json``.

    Returns ``(manifest, task_root)`` where ``task_root`` is the authoritative
    task root directory used for media path resolution. Raises
    ``ManifestError`` on any validation failure.
    """
    if not task_root_or_file:
        raise ManifestError("Empty task path")
    path = os.path.expanduser(task_root_or_file)
    if not os.path.exists(path):
        raise ManifestError("Task path does not exist: %s" % path)

    json_path = _candidate_task_json(path)
    try:
        with open(json_path, "r") as fp:
            data = json.load(fp)
    except (IOError, OSError) as exc:
        raise ManifestError("Cannot read manifest %s: %s" % (json_path, exc))
    except ValueError as exc:
        raise ManifestError("Manifest is not valid JSON: %s" % exc)

    manifest = TaskManifest.from_dict(data)

    if os.path.isfile(path):
        task_root = os.path.dirname(os.path.dirname(os.path.abspath(path)))
    else:
        task_root = os.path.abspath(path)
    return manifest, task_root
