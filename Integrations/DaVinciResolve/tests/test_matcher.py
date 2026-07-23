# -*- coding: utf-8 -*-
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from bridge.matcher import MediaSpec, match_media_to_takes
from bridge.scriptlog import CameraRecord, ClipRef, TakeRef


def _take(tid, scene="1", shot="1", tnum=1, status="good",
          circle=False, linked=None, records=None, quick=None,
          general=""):
    return TakeRef(
        take_id=tid, shooting_day_id="d", shooting_day_date="2026-05-04",
        scene_number=scene, shot_number=shot, shot_camera_setup="A",
        take_number=tnum, camera_label="A", status=status,
        is_circle_take=circle, picture_usable=True, sound_usable=True,
        performance_rating=3, technical_rating=3,
        performance_note="", technical_note="", general_note=general,
        quick_tags=quick or [], camera_records=records or [],
        linked_clips=linked or [])


class TestMatcherRules(unittest.TestCase):
    def test_rule1_filepath_exact(self):
        path = "/media/MEDIA/A01/A001C001.mov"
        takes = [_take("t1", linked=[ClipRef(path, "A001C001.mov", "A01", "h")])]
        media = [MediaSpec(0, os.path.normpath(path), "A001C001.mov", "A001C001", path)]
        rep = match_media_to_takes(media, takes)
        self.assertEqual(rep.matched_media, 1)
        self.assertIn("t1", rep.take_matches)

    def test_rule2_filename_exact(self):
        takes = [_take("t1", linked=[ClipRef("", "A001C001.mov", "A01", "h")])]
        media = [MediaSpec(0, "/other/x.mov", "A001C001.mov", "A001C001", "x.mov")]
        rep = match_media_to_takes(media, takes)
        self.assertEqual(rep.matched_media, 1)

    def test_rule3_stem_exact(self):
        takes = [_take("t1", linked=[ClipRef("", "A001C001", "", "")])]
        media = [MediaSpec(0, "/x/A001C001.mov", "A001C001.mov", "A001C001", "A001C001.mov")]
        rep = match_media_to_takes(media, takes)
        self.assertEqual(rep.matched_media, 1)

    def test_rule4_camerarecord_clipname(self):
        rec = CameraRecord("A", "good", "recorded", "A001C001.mov", "A01",
                           "10:00:00:00", "10:01:00:00", "")
        takes = [_take("t1", records=[rec])]
        media = [MediaSpec(0, "/x/A001C001.mov", "A001C001.mov", "A001C001", "A001C001.mov")]
        rep = match_media_to_takes(media, takes)
        self.assertEqual(rep.matched_media, 1)

    def test_no_match(self):
        takes = [_take("t1", linked=[ClipRef("/p/X.mov", "X.mov", "", "")])]
        media = [MediaSpec(0, "/p/Y.mov", "Y.mov", "Y", "Y.mov")]
        rep = match_media_to_takes(media, takes)
        self.assertEqual(rep.matched_media, 0)
        self.assertEqual(len(rep.unmatched), 1)

    def test_conflict_one_media_many_takes(self):
        # two takes both reference the same filename -> conflict
        t1 = _take("t1", linked=[ClipRef("", "A001C001.mov", "", "")])
        t2 = _take("t2", linked=[ClipRef("", "A001C001.mov", "", "")])
        media = [MediaSpec(0, "/x/A001C001.mov", "A001C001.mov", "A001C001", "A001C001.mov")]
        rep = match_media_to_takes(media, [t1, t2])
        self.assertTrue(rep.has_conflicts)
        self.assertEqual(len(rep.conflicts), 1)
        self.assertEqual(len(rep.conflicts[0][1]), 2)

    def test_one_take_many_media_allowed(self):
        t1 = _take("t1", records=[
            CameraRecord("A", "good", "recorded", "a.mov", "A01", "", "", ""),
            CameraRecord("A", "good", "recorded", "b.mov", "A01", "", "", "")])
        media = [
            MediaSpec(0, "/x/a.mov", "a.mov", "a", "a.mov", card="A01"),
            MediaSpec(1, "/x/b.mov", "b.mov", "b", "b.mov", card="A01"),
        ]
        rep = match_media_to_takes(media, [t1])
        self.assertEqual(rep.matched_media, 2)
        self.assertEqual(len(rep.take_matches["t1"]), 2)
        self.assertFalse(rep.has_conflicts)

    def test_rule5_card_joint_disambiguates(self):
        # Two takes, same clipName on different cards. Without the card joint
        # rule (5) both would match; with the card, only the matching one does.
        t1 = _take("t1", records=[
            CameraRecord("A", "good", "recorded", "clip.mov", "A01", "", "", "")])
        t2 = _take("t2", records=[
            CameraRecord("B", "good", "recorded", "clip.mov", "B02", "", "", "")])
        media = [MediaSpec(0, "/x/clip.mov", "clip.mov", "clip", "clip.mov", card="B02")]
        rep = match_media_to_takes(media, [t1, t2])
        self.assertEqual(rep.matched_media, 1)
        self.assertIn("t2", rep.take_matches)
        self.assertNotIn("t1", rep.take_matches)
        self.assertFalse(rep.has_conflicts)


if __name__ == "__main__":
    unittest.main()
