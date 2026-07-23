# -*- coding: utf-8 -*-
"""Parsing of 321Doit ``.321log`` script-log documents.

The ``.321log`` file is a JSON document mirroring the on-set script log.
This module turns the deeply nested structure into a flat list of
:class:`TakeRef` records that the matcher can consume. No DaVinci Resolve
dependency and standard library only.
"""

import json
import os
from typing import Any, Dict, List, Optional


class ScriptLogError(Exception):
    """Raised when a script-log file cannot be parsed."""


class ClipRef(object):
    """A ``linkedClips`` entry on a take."""

    __slots__ = ("file_path", "file_name", "camera_card", "checksum")

    def __init__(self, file_path, file_name, camera_card, checksum):
        # type: (str, str, str, str) -> None
        self.file_path = file_path
        self.file_name = file_name
        self.camera_card = camera_card
        self.checksum = checksum

    @classmethod
    def from_dict(cls, data):
        # type: (Dict[str, Any]) -> "ClipRef"
        return cls(
            file_path=str(data.get("filePath") or ""),
            file_name=str(data.get("fileName") or ""),
            camera_card=str(data.get("cameraCard") or ""),
            checksum=str(data.get("checksum") or ""),
        )


class CameraRecord(object):
    """A ``cameraRecords`` entry on a take."""

    __slots__ = ("camera_label", "status", "roll_state", "clip_name",
                 "card_name", "tc_in", "tc_out", "notes")

    def __init__(self, camera_label, status, roll_state, clip_name,
                 card_name, tc_in, tc_out, notes):
        # type: (str, str, str, str, str, str, str, str) -> None
        self.camera_label = camera_label
        self.status = status
        self.roll_state = roll_state
        self.clip_name = clip_name
        self.card_name = card_name
        self.tc_in = tc_in
        self.tc_out = tc_out
        self.notes = notes

    @classmethod
    def from_dict(cls, data):
        # type: (Dict[str, Any]) -> "CameraRecord"
        return cls(
            camera_label=str(data.get("cameraLabel") or ""),
            status=str(data.get("status") or ""),
            roll_state=str(data.get("rollState") or ""),
            clip_name=str(data.get("clipName") or ""),
            card_name=str(data.get("cardName") or ""),
            tc_in=str(data.get("tcIn") or ""),
            tc_out=str(data.get("tcOut") or ""),
            notes=str(data.get("notes") or ""),
        )


class TakeRef(object):
    """A flattened take reference carrying enough context for matching
    and metadata injection."""

    __slots__ = (
        "take_id", "shooting_day_id", "shooting_day_date", "scene_number",
        "shot_number", "shot_camera_setup", "take_number", "camera_label",
        "status", "is_circle_take", "picture_usable", "sound_usable",
        "performance_rating", "technical_rating", "performance_note",
        "technical_note", "general_note", "quick_tags", "camera_records",
        "linked_clips",
    )

    def __init__(self, take_id, shooting_day_id, shooting_day_date,
                 scene_number, shot_number, shot_camera_setup, take_number,
                 camera_label, status, is_circle_take, picture_usable,
                 sound_usable, performance_rating, technical_rating,
                 performance_note, technical_note, general_note, quick_tags,
                 camera_records, linked_clips):
        # type: (str, str, str, str, str, str, int, str, str, bool, bool, bool, int, int, str, str, str, List[str], List[CameraRecord], List[ClipRef]) -> None
        self.take_id = take_id
        self.shooting_day_id = shooting_day_id
        self.shooting_day_date = shooting_day_date
        self.scene_number = scene_number
        self.shot_number = shot_number
        self.shot_camera_setup = shot_camera_setup
        self.take_number = take_number
        self.camera_label = camera_label
        self.status = status
        self.is_circle_take = is_circle_take
        self.picture_usable = picture_usable
        self.sound_usable = sound_usable
        self.performance_rating = performance_rating
        self.technical_rating = technical_rating
        self.performance_note = performance_note
        self.technical_note = technical_note
        self.general_note = general_note
        self.quick_tags = quick_tags
        self.camera_records = camera_records
        self.linked_clips = linked_clips


def _as_int(value, default=0):
    # type: (Any, int) -> int
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _take_from_dict(take_data, day_id, day_date, scene_number,
                    shot_number, shot_camera_setup):
    # type: (Dict[str, Any], str, str, str, str, str) -> TakeRef
    records = [CameraRecord.from_dict(c)
               for c in (take_data.get("cameraRecords") or [])]
    clips = [ClipRef.from_dict(c)
             for c in (take_data.get("linkedClips") or [])]
    return TakeRef(
        take_id=str(take_data.get("id") or ""),
        shooting_day_id=day_id,
        shooting_day_date=day_date,
        scene_number=scene_number,
        shot_number=shot_number,
        shot_camera_setup=shot_camera_setup,
        take_number=_as_int(take_data.get("takeNumber"), 1),
        camera_label=str(take_data.get("cameraLabel") or ""),
        status=str(take_data.get("status") or ""),
        is_circle_take=bool(take_data.get("isCircleTake")),
        picture_usable=bool(take_data.get("pictureUsable", True)),
        sound_usable=bool(take_data.get("soundUsable", True)),
        performance_rating=_as_int(take_data.get("performanceRating"), 3),
        technical_rating=_as_int(take_data.get("technicalRating"), 3),
        performance_note=str(take_data.get("performanceNote") or ""),
        technical_note=str(take_data.get("technicalNote") or ""),
        general_note=str(take_data.get("generalNote") or ""),
        quick_tags=[str(t) for t in (take_data.get("quickTags") or [])],
        camera_records=records,
        linked_clips=clips,
    )


class ScriptLog(object):
    """Parsed script-log document with a flat take index."""

    __slots__ = ("project_name", "takes", "raw")

    def __init__(self, project_name, takes, raw):
        # type: (str, List[TakeRef], Dict[str, Any]) -> None
        self.project_name = project_name
        self.takes = takes
        self.raw = raw


def parse_script_log(path):
    # type: (str) -> ScriptLog
    if not path or not os.path.isfile(path):
        raise ScriptLogError("Script-log file not found: %s" % path)
    try:
        with open(path, "r") as fp:
            data = json.load(fp)
    except (IOError, OSError) as exc:
        raise ScriptLogError("Cannot read script log %s: %s" % (path, exc))
    except ValueError as exc:
        raise ScriptLogError("Script log is not valid JSON: %s" % exc)

    takes = []  # type: List[TakeRef]
    for day in (data.get("shootingDays") or []):
        day_id = str(day.get("id") or "")
        day_date = str(day.get("date") or "")
        for scene in (day.get("scenes") or []):
            scene_number = str(scene.get("sceneNumber") or "")
            for shot in (scene.get("shots") or []):
                shot_number = str(shot.get("shotNumber") or "")
                shot_setup = str(shot.get("cameraSetup") or "")
                for take_data in (shot.get("takes") or []):
                    takes.append(_take_from_dict(
                        take_data, day_id, day_date, scene_number,
                        shot_number, shot_setup))

    return ScriptLog(
        project_name=str(data.get("projectName") or ""),
        takes=takes,
        raw=data,
    )


def find_script_log(task_root):
    # type: (str) -> Optional[str]
    """Auto-search for a ``.321log`` under the task root.

    Search order mirrors the 321Doit offload layout:
      1. ``<task_root>/.321doit/*.321log``
      2. ``<task_root>/.321doit/script-log/*.321log``
      3. ``<task_root>/_ScriptLog/*.321log``
    Returns the first match or ``None``.
    """
    candidates = [
        os.path.join(task_root, ".321doit"),
        os.path.join(task_root, ".321doit", "script-log"),
        os.path.join(task_root, "_ScriptLog"),
        os.path.join(task_root, "_321Doit"),
    ]
    for folder in candidates:
        if not os.path.isdir(folder):
            continue
        try:
            names = sorted(os.listdir(folder))
        except OSError:
            continue
        for name in names:
            if name.lower().endswith(".321log"):
                return os.path.join(folder, name)
    return None
