# -*- coding: utf-8 -*-
"""Core import orchestration for 321Doit Bridge.

This module coordinates manifest parsing, script-log matching, path
resolution with safety checks, idempotent duplicate detection, Resolve
import and metadata injection. It depends on :mod:`resolve_adapter` for
all Resolve access, so the preflight path is fully unit-testable with a
fake adapter. Standard library only, Python 3.6 compatible.
"""

import os
import re
from typing import Any, Dict, List, Optional, Tuple

from . import manifest as manifest_mod
from . import result_writer
from .manifest import FileEntry, TaskManifest
from .matcher import MatchReport, MediaSpec, match_media_to_takes
from .resolve_adapter import ResolveAdapter
from .scriptlog import ScriptLog, TakeRef

TP_TASK_ID = "321Doit Task ID"
TP_MEDIA_KEY = "321Doit Media Key"
TP_RELATIVE_PATH = "321Doit Relative Path"
TP_SOURCE_HASH = "321Doit Source Hash"
TP_TAKE_ID = "321Doit Take ID"
TP_PROJECT_ID = "321Doit Project ID"

TOP_BIN = "321Doit"

# Extensions Resolve can import as media. Non-media sidecars (XML, CSV,
# checksums, camera metadata) are filtered out before import so we never
# feed Resolve a file it cannot ingest.
_MEDIA_EXTENSIONS = {
    "mov", "mp4", "mxf", "mts", "m2ts", "avi", "mkv", "m4v", "webm",
    "mpg", "mpeg", "m2v", "vob", "wmv", "flv", "3gp", "dv", "m4v",
    "r3d", "braw", "dpx", "tif", "tiff", "exr", "cin", "dng",
    "wav", "aif", "aiff", "mp3", "aac", "m4a", "flac", "ogg",
}


def _is_media_file(relative_path):
    # type: (str) -> bool
    if not relative_path:
        return False
    ext = os.path.splitext(relative_path)[1].lstrip(".").lower()
    return ext in _MEDIA_EXTENSIONS


class ImportOptions(object):
    __slots__ = ("import_originals", "write_script_log_metadata",
                 "apply_status_colors", "apply_circle_flags",
                 "skip_already_imported", "allow_partial", "dry_run")

    def __init__(self):
        # type: () -> None
        self.import_originals = True
        self.write_script_log_metadata = True
        self.apply_status_colors = True
        self.apply_circle_flags = True
        self.skip_already_imported = True
        self.allow_partial = False
        self.dry_run = False


class ResolvedMedia(object):
    __slots__ = ("file_entry", "path", "normalized_path", "file_name",
                 "stem", "media_key", "status")

    def __init__(self, file_entry, path, normalized_path, file_name, stem,
                 media_key, status):
        # type: (FileEntry, str, str, str, str, str, str) -> None
        self.file_entry = file_entry
        self.path = path
        self.normalized_path = normalized_path
        self.file_name = file_name
        self.stem = stem
        self.media_key = media_key
        self.status = status  # "verified" | "missing"


class PreflightResult(object):
    __slots__ = ("resolved", "missing", "match_report", "duplicates",
                 "has_failures", "errors", "warnings", "counts")

    def __init__(self):
        # type: () -> None
        self.resolved = []          # type: List[ResolvedMedia]
        self.missing = []           # type: List[str]
        self.match_report = None    # type: Optional[MatchReport]
        self.duplicates = []        # type: List[str]
        self.has_failures = False
        self.errors = []            # type: List[str]
        self.warnings = []          # type: List[str]
        self.counts = result_writer.empty_counts()

    @property
    def blocking(self):
        # type: () -> bool
        return bool(self.errors)


def _sanitize_component(value, fallback):
    # type: (str, str) -> str
    trimmed = (value or "").strip()
    if not trimmed:
        return fallback
    cleaned = re.sub(r"[^A-Za-z0-9_\-\u4e00-\u9fff]", "_", trimmed)
    cleaned = re.sub(r"__+", "_", cleaned).strip("_-")
    cleaned = cleaned or fallback
    return cleaned


def _media_key(task_id, relative_path, source_hash):
    # type: (str, str, str) -> str
    return "%s|%s|%s" % (task_id, relative_path, source_hash)


_STATUS_KEYWORDS = {
    "good": "OK",
    "ok": "OK",
    "hold": "KP",
    "kp": "KP",
    "ng": "NG",
    "reset": "Reset",
    "wildtrack": "Wild Track",
    "rehearsal": "Rehearsal",
}


def _status_keyword(status):
    # type: (str) -> str
    return _STATUS_KEYWORDS.get((status or "").lower(), "")


def _is_path_safe(task_root_real, candidate_real):
    # type: (str, str) -> bool
    """True if candidate_real is inside task_root_real (both realpath'd)."""
    if not candidate_real or not task_root_real:
        return False
    root = os.path.join(task_root_real, "")
    return candidate_real == task_root_real or candidate_real.startswith(root)


def _relative_path_unsafe(relative_path):
    # type: (str) -> bool
    if not relative_path:
        return True
    if os.path.isabs(relative_path):
        return True
    norm = os.path.normpath(relative_path)
    if norm == ".":
        return False
    parts = norm.split(os.sep)
    if ".." in parts:
        return True
    return False


class Importer(object):
    """Drives a single import task end to end."""

    def __init__(self, adapter, manifest, task_root, script_log=None):
        # type: (ResolveAdapter, TaskManifest, str, Optional[ScriptLog]) -> None
        self.adapter = adapter
        self.manifest = manifest
        self.task_root = os.path.abspath(os.path.expanduser(task_root))
        self.task_root_real = os.path.realpath(self.task_root)
        self.script_log = script_log
        self._take_by_id = {}  # type: Dict[str, TakeRef]
        self._index_takes()

    def _index_takes(self):
        # type: () -> None
        self._take_by_id = {}
        if self.script_log is None:
            return
        for take in self.script_log.takes:
            key = take.take_id or "%s/%s/%d" % (
                take.scene_number, take.shot_number, take.take_number)
            self._take_by_id[key] = take

    # -- path resolution -------------------------------------------------

    def resolve_media(self):
        # type: () -> List[ResolvedMedia]
        """Resolve every manifest file to a safe absolute path.

        Priority:
          1. task_root / files[].relativePath
          2. task_root / MEDIA/<cardNumber>/ / relativePath basename
          3. a verified target outputPath that exists

        Any candidate that would escape task_root (directory traversal or
        symlink egress) is rejected and the file marked missing.
        """
        results = []  # type: List[ResolvedMedia]
        for entry in self.manifest.files:
            media_key = _media_key(
                self.manifest.task_id, entry.relative_path, entry.source_hash)
            if not _is_media_file(entry.relative_path):
                # Skip non-media sidecars (XML, checksums, camera metadata).
                results.append(ResolvedMedia(
                    file_entry=entry, path="", normalized_path="",
                    file_name=os.path.basename(entry.relative_path) or entry.relative_path,
                    stem=os.path.splitext(os.path.basename(entry.relative_path))[0],
                    media_key=media_key, status="nonmedia"))
                continue
            if not entry.is_verified:
                # Only copied && verified media is importable. Files that
                # failed checksum are surfaced via manifest.failedResults.
                results.append(ResolvedMedia(
                    file_entry=entry, path="", normalized_path="",
                    file_name=os.path.basename(entry.relative_path) or entry.relative_path,
                    stem=os.path.splitext(os.path.basename(entry.relative_path))[0],
                    media_key=media_key, status="unverified"))
                continue
            resolved = self._resolve_one(entry, media_key)
            results.append(resolved)
        return results

    def _resolve_one(self, entry, media_key):
        # type: (FileEntry, str) -> ResolvedMedia
        candidates = self._candidates_for(entry)
        for path in candidates:
            if not path:
                continue
            real = os.path.realpath(path)
            if not os.path.isfile(real):
                continue
            if not _is_path_safe(self.task_root_real, real):
                continue
            return ResolvedMedia(
                file_entry=entry,
                path=path,
                normalized_path=os.path.normpath(real),
                file_name=os.path.basename(real),
                stem=os.path.splitext(os.path.basename(real))[0],
                media_key=media_key,
                status="verified",
            )
        return ResolvedMedia(
            file_entry=entry,
            path="",
            normalized_path="",
            file_name=os.path.basename(entry.relative_path) or entry.relative_path,
            stem=os.path.splitext(os.path.basename(entry.relative_path))[0],
            media_key=media_key,
            status="missing",
        )

    def _candidates_for(self, entry):
        # type: (FileEntry) -> List[str]
        out = []  # type: List[str]
        if not _relative_path_unsafe(entry.relative_path):
            out.append(os.path.join(self.task_root, entry.relative_path))

        card = _sanitize_component(self.manifest.card_number, "CARD")
        base = os.path.basename(entry.relative_path)
        if base:
            out.append(os.path.join(self.task_root, "MEDIA", card, base))
            out.append(os.path.join(
                self.task_root, "01_ORIGINALS", card, base))

        for target in entry.verified_targets:
            if target.output_path:
                out.append(target.output_path)
        return out

    # -- existing media (idempotency) ------------------------------------

    def _collect_existing(self, top_folder):
        # type: (Any) -> Dict[str, Any]
        """Recursively collect clips under the 321Doit bin.

        Returns a mapping ``media_key -> clip`` plus parallel structures for
        path- and name-based duplicate detection.
        """
        by_key = {}            # type: Dict[str, Any]
        by_path = {}           # type: Dict[str, Any]
        by_name = {}           # type: Dict[str, List[Any]]
        if top_folder is None:
            return by_key
        self._walk_clips(top_folder, by_key, by_path, by_name)
        return by_key

    def _walk_clips(self, folder, by_key, by_path, by_name):
        # type: (Any, Dict[str, Any], Dict[str, Any], Dict[str, List[Any]]) -> None
        for clip in self.adapter.get_clip_list(folder):
            key = ""
            try:
                tp = self.adapter.get_third_party_metadata(clip) or {}
                key = str(tp.get(TP_MEDIA_KEY) or "")
            except Exception:
                key = ""
            file_path = ""
            props = self.adapter.get_clip_property(clip) or {}
            file_path = str(props.get("File Path") or "")
            name = self.adapter.get_clip_name(clip)
            if key:
                by_key.setdefault(key, clip)
            if file_path:
                by_path[os.path.normpath(file_path)] = clip
            if name:
                by_name.setdefault(name, []).append(clip)
        for sub in self.adapter.get_subfolder_list(folder):
            self._walk_clips(sub, by_key, by_path, by_name)

    def _existing_structures(self, top_folder):
        # type: (Any) -> Tuple[Dict[str, Any], Dict[str, Any], Dict[str, List[Any]]]
        by_key = {}            # type: Dict[str, Any]
        by_path = {}           # type: Dict[str, Any]
        by_name = {}           # type: Dict[str, List[Any]]
        if top_folder is not None:
            self._walk_clips(top_folder, by_key, by_path, by_name)
        return by_key, by_path, by_name

    # -- preflight -------------------------------------------------------

    def run_preflight(self, options):
        # type: (ImportOptions) -> PreflightResult
        pre = PreflightResult()
        pre.has_failures = self.manifest.has_failures

        resolved = self.resolve_media()
        verified = [m for m in resolved if m.status == "verified"]
        missing = [m for m in resolved if m.status == "missing"]
        nonmedia = [m for m in resolved if m.status == "nonmedia"]
        pre.resolved = verified
        pre.missing = [m.file_entry.relative_path for m in missing]

        # discovered counts only real media files (sidecars excluded).
        pre.counts["discovered"] = len(verified) + len(missing)
        pre.counts["verified"] = len(verified)
        pre.counts["missing"] = len(missing)
        for m in nonmedia:
            pre.warnings.append("Skipping non-media file: %s" % m.file_name)

        if pre.has_failures and not options.allow_partial:
            pre.errors.append(
                "Task has %d failed results / errors; enable "
                "\"allow partial import\" to import verified files only."
                % self.manifest.failed_results)

        # Script-log matching
        if self.script_log is not None and verified:
            specs = [
                MediaSpec(
                    index=i,
                    normalized_path=m.normalized_path,
                    file_name=m.file_name,
                    stem=m.stem,
                    relative_path=m.file_entry.relative_path,
                    card=self.manifest.card_number)
                for i, m in enumerate(verified)
            ]
            report = match_media_to_takes(specs, self.script_log.takes)
            pre.match_report = report
            pre.counts["metadataMatched"] = report.matched_media
            pre.counts["metadataConflicts"] = len(report.conflicts)
            for idx, take_ids in report.conflicts:
                pre.warnings.append(
                    "Conflict: media %s matched takes %s"
                    % (verified[idx].file_name, ", ".join(take_ids)))

        # Idempotency: scan the ENTIRE media pool root recursively so that
        # clips already imported into any bin (not just the 321Doit bin) are
        # detected as duplicates and never re-imported.
        root_folder = self.adapter.get_root_folder()
        if root_folder is not None:
            by_key, by_path, by_name = self._existing_structures(root_folder)
            for m in verified:
                if m.media_key in by_key:
                    pre.duplicates.append(m.media_key)
                    continue
                norm = m.normalized_path
                if norm and norm in by_path:
                    pre.duplicates.append(m.media_key)
                    continue
            pre.counts["skippedDuplicate"] = len(pre.duplicates)
        else:
            by_key, by_path, by_name = {}, {}, {}

        pre.counts["warnings"] = len(pre.warnings)
        pre.counts["errors"] = len(pre.errors)
        return pre

    def _find_top_bin(self):
        # type: () -> Optional[Any]
        root = self.adapter.get_root_folder()
        if root is None:
            return None
        return self.adapter.find_subfolder(root, TOP_BIN)

    # -- execution -------------------------------------------------------

    def execute(self, options, preflight):
        # type: (ImportOptions, PreflightResult) -> Dict[str, Any]
        result = result_writer.new_result(
            self.manifest.task_id,
            self.adapter.get_version_string(),
            self.adapter.get_current_project_name())
        result["startedAt"] = result_writer.now_iso()

        if preflight.blocking:
            result["status"] = "failed"
            result["errors"] = list(preflight.errors)
            result["counts"] = preflight.counts
            return self._finalize(result, preflight)

        if self.adapter.get_current_project_name() is None:
            result["status"] = "failed"
            result["errors"].append(
                "Please open or create a DaVinci Resolve project first.")
            return self._finalize(result, preflight)

        if options.dry_run:
            result["status"] = "dryRun"
            result["counts"] = preflight.counts
            return self._finalize(result, preflight)

        saved_folder = self.adapter.get_current_folder()

        root_folder = self.adapter.get_root_folder()
        by_key, by_path, by_name = self._existing_structures(root_folder)

        imported = 0
        skipped = 0
        warnings = list(preflight.warnings)
        errors = []
        clips_out = []
        importable = len(preflight.resolved)

        for media in preflight.resolved:
            if not options.import_originals:
                # Originals disabled and proxies are out of scope for the
                # MVP; nothing to import for this media.
                continue
            if options.skip_already_imported and media.media_key in by_key:
                skipped += 1
                # Backfill ONLY missing fields on the existing 321Doit clip;
                # never overwrite user edits (merge=True).
                if options.write_script_log_metadata and self.script_log:
                    self._write_metadata_for(
                        by_key[media.media_key], media, preflight,
                        options, warnings, merge=True)
                continue
            if options.skip_already_imported and media.normalized_path and media.normalized_path in by_path:
                skipped += 1
                existing_clip = by_path[media.normalized_path]
                # An exact resolved-path match is the same source media even
                # when it predates 321Doit metadata. Attach our namespaced
                # identity and backfill only empty user metadata fields.
                self._write_third_party(
                    existing_clip, media, warnings, merge=True)
                if options.write_script_log_metadata and self.script_log:
                    self._write_metadata_for(
                        existing_clip, media, preflight,
                        options, warnings, merge=True)
                warnings.append(
                    "Duplicate by path skipped; missing 321Doit metadata "
                    "backfilled without overwriting user fields: %s"
                    % media.file_name)
                continue

            try:
                # Resolve each new clip into its own camera bin. A task may
                # contain multiple camera records, so one task-level leaf is
                # not sufficient for A/B/C-camera material.
                leaf = self._ensure_bin_path(preflight, media)
            except Exception as exc:
                errors.append(
                    "Bin creation failed for %s: %s" % (media.file_name, exc))
                continue
            if leaf is None:
                errors.append(
                    "Could not create the 321Doit bin for %s" % media.file_name)
                continue

            self.adapter.set_current_folder(leaf)
            clips = self.adapter.import_media([media.path])
            if not clips:
                errors.append(
                    "Resolve refused to import %s" % media.file_name)
                continue
            imported += 1
            for clip in clips:
                self._write_third_party(clip, media, warnings)
                # Update the in-memory duplicate indexes immediately so a
                # malformed manifest containing the same file twice cannot
                # import it twice during this execution.
                by_key.setdefault(media.media_key, clip)
                if media.normalized_path:
                    by_path.setdefault(media.normalized_path, clip)
                if options.write_script_log_metadata and self.script_log:
                    self._write_metadata_for(
                        clip, media, preflight, options, warnings, merge=False)
                clips_out.append({
                    "mediaKey": media.media_key,
                    "relativePath": media.file_entry.relative_path,
                    "name": self.adapter.get_clip_name(clip),
                })

        if saved_folder is not None:
            self._restore_folder(saved_folder)

        result["counts"] = dict(preflight.counts)
        result["counts"]["imported"] = imported
        result["counts"]["skippedDuplicate"] = skipped
        result["counts"]["errors"] = len(errors)
        result["counts"]["warnings"] = len(warnings)
        result["clips"] = clips_out
        result["warnings"] = warnings
        result["errors"] = errors

        missing_count = preflight.counts.get("missing", 0)
        expected_new = importable - skipped  # importable minus duplicates
        if errors:
            result["status"] = "failed" if imported == 0 else "partial"
        elif not options.import_originals:
            result["status"] = "success"
        elif importable == 0:
            # Nothing importable on disk.
            result["status"] = "failed" if missing_count > 0 else "success"
        elif missing_count > 0:
            # Some verified media could not be located on disk.
            result["status"] = "partial"
        elif imported < expected_new:
            result["status"] = "partial"
        else:
            result["status"] = "success"
        return self._finalize(result, preflight)

    def _restore_folder(self, folder):
        # type: (Any) -> None
        if folder is not None:
            self.adapter.set_current_folder(folder)

    def _camera_bin_name(self, preflight, media=None):
        # type: (Optional[PreflightResult], Optional[ResolvedMedia]) -> str
        """Camera bin label from the script log, NOT the card profile.

        The manifest's ``detectedCard`` is the storage-card profile
        (e.g. "ARRI · ARRI camera card"), which is the media format family,
        NOT the camera unit (A机/B机). The real camera unit only lives in
        the script log's take.cameraRecords[].cameraLabel. When a script
        log is matched we use the most common matched camera label; with no
        script log we honestly label the bin "Unknown" rather than mislabel
        a card profile as a camera.
        """
        if preflight is not None and media is not None:
            take = self._matched_take_for(media, preflight)
            if take is not None:
                label = self._camera_label_for(take, media)
                if label:
                    return _sanitize_component(label, "Unknown")

        report = preflight.match_report if preflight else None
        if self.script_log is not None and report is not None:
            labels = []  # type: List[str]
            for take_id, indices in report.take_matches.items():
                take = self._take_by_id.get(take_id)
                if take is None:
                    continue
                for idx in indices:
                    if 0 <= idx < len(preflight.resolved):
                        media = preflight.resolved[idx]
                        label = self._camera_label_for(take, media)
                        if label:
                            labels.append(label)
            if labels:
                # Most common camera label (multi-camera task edge case).
                counts = {}  # type: Dict[str, int]
                for label in labels:
                    counts[label] = counts.get(label, 0) + 1
                best = max(counts, key=lambda k: counts[k])
                return _sanitize_component(best, "Unknown")
        return "Unknown"

    def _ensure_bin_path(self, preflight=None, media=None):
        # type: (Optional[PreflightResult], Optional[ResolvedMedia]) -> Optional[Any]
        root = self.adapter.get_root_folder()
        if root is None:
            return None
        project = self.manifest.project_name or "Independent"
        if self.manifest.project_association_mode != "linkedProject":
            project = "Independent"
        date = self._task_date()
        camera = self._camera_bin_name(preflight, media)
        card = _sanitize_component(self.manifest.card_number, "CARD")
        path = [TOP_BIN, project, date, camera, card]
        return self.adapter.add_nested_folder(root, path)

    def _task_date(self):
        # type: () -> str
        raw = self.manifest.started_at or ""
        date_part = raw.split("T")[0].split(" ")[0]
        return _sanitize_component(date_part, "UnknownDate")

    # -- metadata --------------------------------------------------------

    def _write_third_party(self, clip, media, warnings, merge=False):
        # type: (Any, ResolvedMedia, List[str], bool) -> None
        existing = self.adapter.get_third_party_metadata(clip) or {}
        pairs = [
            (TP_TASK_ID, self.manifest.task_id),
            (TP_MEDIA_KEY, media.media_key),
            (TP_RELATIVE_PATH, media.file_entry.relative_path),
            (TP_SOURCE_HASH, media.file_entry.source_hash),
            (TP_PROJECT_ID, self.manifest.linked_project_id or ""),
        ]
        for key, value in pairs:
            if not value:
                continue
            if merge and existing.get(key):
                continue
            if not self.adapter.set_third_party_metadata(clip, key, value):
                warnings.append(
                    "Could not write third-party metadata %s for %s"
                    % (key, media.file_name))

    def _matched_take_for(self, media, preflight):
        # type: (ResolvedMedia, PreflightResult) -> Optional[TakeRef]
        report = preflight.match_report
        if report is None:
            return None
        verified = preflight.resolved
        try:
            idx = verified.index(media)
        except ValueError:
            return None
        for take_id, indices in report.take_matches.items():
            if idx in indices:
                return self._take_by_id.get(take_id)
        return None

    def _camera_record_for(self, take, media):
        # type: (TakeRef, ResolvedMedia) -> Optional[Any]
        """Return the camera record whose clip name matches this media."""
        target_name = (media.file_name or "").lower()
        target_stem = (media.stem or "").lower()
        for rec in take.camera_records:
            cn = (rec.clip_name or "").lower()
            if cn and (cn == target_name or cn == target_stem):
                return rec
        return None

    def _camera_label_for(self, take, media):
        # type: (TakeRef, ResolvedMedia) -> str
        """Pick the camera record whose clip matches THIS media, so a B-camera
        clip is not labelled as the A camera."""
        record = self._camera_record_for(take, media)
        if record is not None:
            return record.camera_label or take.camera_label
        # Fall back to the take-level camera label only when no record matched
        # by clip; never assume the first record is the right camera.
        return take.camera_label

    def _status_for(self, take, media):
        # type: (TakeRef, ResolvedMedia) -> str
        """Prefer the matched camera's status over the take-wide fallback."""
        record = self._camera_record_for(take, media)
        if record is not None and record.status:
            return record.status
        return take.status

    def _write_metadata_for(self, clip, media, preflight, options, warnings, merge=False):
        # type: (Any, ResolvedMedia, PreflightResult, ImportOptions, List[str], bool) -> None
        take = self._matched_take_for(media, preflight)
        if take is None:
            return

        supported = self.adapter.get_supported_metadata_keys(clip)
        existing = self.adapter.get_metadata(clip) or {}

        def put(key, value):
            # type: (str, str) -> None
            if not value:
                return
            # When backfilling an existing clip, only fill EMPTY fields so the
            # user's manual edits are preserved.
            if merge and existing.get(key):
                return
            if supported and key not in supported:
                warnings.append(
                    "Metadata key %s not supported by this Resolve "
                    "version for %s" % (key, media.file_name))
                return
            if not self.adapter.set_metadata(clip, key, value):
                warnings.append(
                    "SetMetadata %s rejected for %s" % (key, media.file_name))

        if take.scene_number:
            put("Scene", take.scene_number)
        if take.shot_number:
            put("Shot", take.shot_number)
        put("Take", str(take.take_number))
        camera_label = self._camera_label_for(take, media)
        if camera_label:
            put("Camera", camera_label)

        comments_parts = []
        if take.general_note:
            comments_parts.append(take.general_note)
        if take.performance_note:
            comments_parts.append(take.performance_note)
        if take.technical_note:
            comments_parts.append(take.technical_note)
        camera_record = self._camera_record_for(take, media)
        if camera_record is not None and camera_record.notes:
            comments_parts.append(camera_record.notes)
        if comments_parts:
            put("Comments", "; ".join(comments_parts))

        keywords = []
        status = (self._status_for(take, media) or "").lower()
        status_kw = _status_keyword(status)
        if status_kw:
            keywords.append(status_kw)
        keywords.extend(take.quick_tags)
        if take.scene_number:
            keywords.append("Scene_%s" % take.scene_number)
        if take.shot_number:
            keywords.append("Shot_%s" % take.shot_number)
        if take.is_circle_take:
            keywords.append("Circle Take")
        if status in ("good", "ok"):
            put("Good", "1")
        if keywords:
            if merge:
                # Merge: add only keywords not already present; never remove
                # user-added keywords. Write DIRECTLY (not via put), because
                # put's merge-guard would skip a non-empty Keywords field
                # entirely and the 321Doit tags (OK/Scene_/Shot_/...) would
                # never be backfilled.
                current = [
                    k.strip() for k in str(existing.get("Keywords") or "").split(",")
                    if k.strip()
                ]
                merged_kw = list(current)
                for kw in keywords:
                    if kw not in merged_kw:
                        merged_kw.append(kw)
                if merged_kw != current:
                    if supported and "Keywords" not in supported:
                        warnings.append(
                            "Metadata key Keywords not supported by this "
                            "Resolve version for %s" % media.file_name)
                    elif not self.adapter.set_metadata(
                            clip, "Keywords", ",".join(merged_kw)):
                        warnings.append(
                            "SetMetadata Keywords rejected for %s"
                            % media.file_name)
            else:
                put("Keywords", ",".join(keywords))

        # Third-party Take ID (only known here, not in _write_third_party).
        if take.take_id:
            existing_take_id = self.adapter.get_third_party_metadata(
                clip, TP_TAKE_ID)
            if not merge or not existing_take_id:
                self.adapter.set_third_party_metadata(
                    clip, TP_TAKE_ID, take.take_id)

        self._apply_status(clip, take, media, options, warnings, merge)

    def _apply_status(self, clip, take, media, options, warnings, merge=False):
        # type: (Any, TakeRef, ResolvedMedia, ImportOptions, List[str], bool) -> None
        status = (self._status_for(take, media) or "").lower()
        if not status:
            return
        if options.apply_status_colors:
            color = None
            if status in ("good", "ok"):
                color = "Green"
            elif status in ("hold", "kp"):
                color = "Yellow"
            elif status == "ng":
                color = "Red"
            if color:
                current_color = self.adapter.get_clip_color(clip) or ""
                # When backfilling, do not overwrite a user-chosen color.
                if merge and current_color:
                    pass
                elif not self.adapter.set_clip_color(clip, color):
                    warnings.append(
                        "SetClipColor %s rejected" % color)

        if options.apply_circle_flags and take.is_circle_take:
            existing_flags = self.adapter.get_flag_list(clip)
            if "Green" not in existing_flags:
                if not self.adapter.add_flag(clip, "Green"):
                    warnings.append("AddFlag Green rejected for circle take")

    # -- finalize --------------------------------------------------------

    def _finalize(self, result, preflight):
        # type: (Dict[str, Any], PreflightResult) -> Dict[str, Any]
        result["warnings"] = list(result.get("warnings") or [])
        result["errors"] = list(result.get("errors") or [])
        for w in self.adapter.warnings:
            if w not in result["warnings"]:
                result["warnings"].append(w)
        result["counts"]["warnings"] = len(result["warnings"])
        result["counts"]["errors"] = len(result["errors"])
        return result
