# -*- coding: utf-8 -*-
"""Rule-based matching between offloaded media and script-log takes.

Matching is purely in-memory: the caller supplies already-resolved media
descriptors and parsed takes. No filesystem access, no DaVinci Resolve.
Standard library only, Python 3.6 compatible.
"""

from typing import Dict, List, Optional, Tuple

from .scriptlog import TakeRef


class MediaSpec(object):
    """A media file ready to be matched against takes."""

    __slots__ = ("index", "normalized_path", "file_name", "stem",
                 "relative_path", "card")

    def __init__(self, index, normalized_path, file_name, stem, relative_path, card=""):
        # type: (int, str, str, str, str, str) -> None
        self.index = index
        self.normalized_path = normalized_path
        self.file_name = file_name
        self.stem = stem
        self.relative_path = relative_path
        self.card = card


class MatchReport(object):
    """Result of matching media against takes."""

    __slots__ = ("take_matches", "conflicts", "unmatched", "matched_media")

    def __init__(self, take_matches, conflicts, unmatched, matched_media):
        # type: (Dict[str, List[int]], List[Tuple[int, List[str]]], List[int], int) -> None
        self.take_matches = take_matches
        self.conflicts = conflicts
        self.unmatched = unmatched
        self.matched_media = matched_media

    @property
    def has_conflicts(self):
        # type: () -> bool
        return len(self.conflicts) > 0


def _norm_path(path):
    # type: (str) -> str
    import os
    if not path:
        return ""
    return os.path.normpath(path)


def _stem(name):
    # type: (str) -> str
    import os
    base = os.path.basename(name or "")
    root, _ = os.path.splitext(base)
    return root


def _cards_match(record_card, media_card):
    # type: (str, str) -> bool
    """Exact card match (case-insensitive).

    Substring matching was rejected because it lets ``A01`` match ``A010``,
    risking associating a clip with the wrong take. The joint rule must be
    strict; if the card does not match exactly we do not bind by this rule.
    """
    if not record_card or not media_card:
        return False
    return record_card.strip().upper() == media_card.strip().upper()


def _take_identity(take):
    # type: (TakeRef) -> str
    return take.take_id or "%s/%s/%d" % (
        take.scene_number, take.shot_number, take.take_number)


def match_media_to_takes(media_list, takes):
    # type: (List[MediaSpec], List[TakeRef]) -> MatchReport
    """Match each media to exactly one take.

    Rules are evaluated in priority order; the first rule that yields a
    match set is used for that media. If the resulting set contains more
    than one take, the media is recorded as a conflict and is not bound.

    A single take may own multiple media files (multi-camera).
    """
    take_matches = {}  # type: Dict[str, List[int]]
    conflicts = []     # type: List[Tuple[int, List[str]]]
    unmatched = []     # type: List[int]
    matched_media = 0

    for media in media_list:
        # Each rule produces a set of candidate take identities. A rule
        # "resolves" the media only when it narrows to EXACTLY ONE take.
        # If a rule yields several takes we do not stop; we keep the most
        # specific rule's multi-match and continue to later rules, which may
        # disambiguate (e.g. rule 5's card+clipName joint match). Only if no
        # rule yields a single take do we report a conflict.
        single = None         # type: Optional[str]
        first_multi = None     # type: Optional[List[str]]

        def consider(hits):
            # type: (List[str]) -> None
            nonlocal single, first_multi
            if not hits:
                return
            unique = []
            seen = set()  # type: set
            for c in hits:
                if c not in seen:
                    seen.add(c)
                    unique.append(c)
            if len(unique) == 1:
                if single is None:
                    single = unique[0]
            else:
                if first_multi is None:
                    first_multi = unique

        # Rule 1: linkedClips[].filePath == media.normalized_path
        if media.normalized_path:
            hits = []
            for take in takes:
                for clip in take.linked_clips:
                    if not clip.file_path:
                        continue
                    if _norm_path(clip.file_path) == media.normalized_path:
                        hits.append(_take_identity(take))
                        break
            consider(hits)

        # Rule 2: linkedClips[].fileName == media.file_name
        if single is None and media.file_name:
            hits = []
            for take in takes:
                for clip in take.linked_clips:
                    if not clip.file_name:
                        continue
                    if clip.file_name == media.file_name:
                        hits.append(_take_identity(take))
                        break
            consider(hits)

        # Rule 3: linkedClips[].fileName == media.stem (no extension)
        if single is None and media.stem:
            hits = []
            for take in takes:
                for clip in take.linked_clips:
                    if not clip.file_name:
                        continue
                    if _stem(clip.file_name) == media.stem:
                        hits.append(_take_identity(take))
                        break
            consider(hits)

        # Rule 4: cameraRecords[].clipName == media.file_name or stem
        if single is None and (media.file_name or media.stem):
            hits = []
            for take in takes:
                matched_this_take = False
                for rec in take.camera_records:
                    if not rec.clip_name:
                        continue
                    if rec.clip_name == media.file_name or rec.clip_name == media.stem:
                        matched_this_take = True
                        break
                if matched_this_take:
                    hits.append(_take_identity(take))
            consider(hits)

        # Rule 5: cameraRecords cardName + clipName joint match. The media's
        # card (from the manifest cardNumber) must match the record cardName,
        # disambiguating multi-camera takes where clip names happen to repeat.
        if single is None and (media.file_name or media.stem) and media.card:
            hits = []
            for take in takes:
                matched_this_take = False
                for rec in take.camera_records:
                    if not rec.clip_name or not rec.card_name:
                        continue
                    if not _cards_match(rec.card_name, media.card):
                        continue
                    if rec.clip_name == media.file_name or rec.clip_name == media.stem:
                        matched_this_take = True
                        break
                if matched_this_take:
                    hits.append(_take_identity(take))
            consider(hits)

        if single is not None:
            take_matches.setdefault(single, []).append(media.index)
            matched_media += 1
            continue

        if first_multi is not None:
            conflicts.append((media.index, first_multi))
            continue

        unmatched.append(media.index)

    return MatchReport(
        take_matches=take_matches,
        conflicts=conflicts,
        unmatched=unmatched,
        matched_media=matched_media,
    )
