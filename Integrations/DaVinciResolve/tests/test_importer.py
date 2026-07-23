# -*- coding: utf-8 -*-
import json
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)
if HERE not in sys.path:
    sys.path.insert(0, HERE)

from _util import make_task_root, cleanup  # noqa: E402
from bridge.importer import Importer, ImportOptions  # noqa: E402
from bridge.scriptlog import parse_script_log  # noqa: E402
from fake_resolve import FakeAdapter  # noqa: E402

FIX = os.path.join(HERE, "fixtures")


def _opts(**over):
    o = ImportOptions()
    for k, v in over.items():
        setattr(o, k, v)
    return o


class TestPreflightAndImport(unittest.TestCase):
    def setUp(self):
        self.roots = []

    def tearDown(self):
        for r in self.roots:
            cleanup(r)

    def _new_root(self, **kw):
        root = make_task_root(**kw)
        self.roots.append(root)
        return root

    def test_independent_no_scriptlog(self):
        root = self._new_root(project_name="Indie", files=[
            {"rel": "MEDIA/A01/a.mov", "hash": "h1"},
            {"rel": "MEDIA/A01/b.mov", "hash": "h2"},
        ])
        manifest, task_root = _load(root)
        adapter = FakeAdapter()
        imp = Importer(adapter, manifest, task_root)
        pre = imp.run_preflight(_opts())
        self.assertEqual(pre.counts["discovered"], 2)
        self.assertEqual(pre.counts["verified"], 2)
        self.assertEqual(pre.counts["missing"], 0)
        self.assertFalse(pre.blocking)

        result = imp.execute(_opts(), pre)
        self.assertEqual(result["status"], "success")
        self.assertEqual(result["counts"]["imported"], 2)
        # bin path created: 321Doit/Independent/<date>/ARRI_ALEXA/A01
        top = adapter.find_subfolder(adapter.root, "321Doit")
        self.assertIsNotNone(top)
        self.assertIsNotNone(adapter.find_subfolder(top, "Independent"))

    def test_linked_with_scriptlog_writes_metadata(self):
        root = self._new_root(
            project_name="LinkedProj", card_number="B02",
            detected_card="RED", project_mode="linkedProject",
            linked_project_id="proj-uuid-001",
            files=[{"rel": "MEDIA/B02/B001_C001_0509X1.R3D", "hash": "hash-ccc"}])
        manifest, task_root = _load(root)
        script_log = parse_script_log(os.path.join(FIX, "scriptlog.json"))
        adapter = FakeAdapter()
        imp = Importer(adapter, manifest, task_root, script_log)
        pre = imp.run_preflight(_opts())
        self.assertEqual(pre.counts["metadataMatched"], 1)
        result = imp.execute(_opts(), pre)
        self.assertEqual(result["status"], "success")
        # find the clip and check metadata
        clips = _all_clips(adapter)
        self.assertEqual(len(clips), 1)
        clip = clips[0]
        self.assertEqual(clip.metadata.get("Scene"), "12")
        self.assertEqual(clip.metadata.get("Shot"), "A")
        self.assertEqual(clip.metadata.get("Take"), "1")
        self.assertIn("OK", clip.metadata.get("Keywords", ""))
        self.assertEqual(clip.clip_color, "Green")
        self.assertIn("Green", clip.flags)
        # third-party identity
        self.assertEqual(clip.third_party.get("321Doit Media Key"),
                         imp.manifest.task_id + "|MEDIA/B02/B001_C001_0509X1.R3D|hash-ccc")

    def test_mount_point_change_relative_path_still_resolves(self):
        root = self._new_root(files=[
            {"rel": "MEDIA/A01/a.mov", "hash": "h1"}])
        # Corrupt the outputPath to a stale path that no longer exists.
        manifest, task_root = _load(root)
        manifest.files[0].targets[0].output_path = "/Volumes/OLD/stale.mov"
        adapter = FakeAdapter()
        imp = Importer(adapter, manifest, task_root)
        pre = imp.run_preflight(_opts())
        self.assertEqual(pre.counts["verified"], 1)
        self.assertEqual(pre.counts["missing"], 0)

    def test_missing_media(self):
        root = self._new_root(files=[
            {"rel": "MEDIA/A01/exists.mov", "hash": "h1"},
            {"rel": "MEDIA/A01/gone.mov", "hash": "h2"}])
        # delete gone.mov so it's actually missing
        os.remove(os.path.join(root, "MEDIA", "A01", "gone.mov"))
        manifest, task_root = _load(root)
        adapter = FakeAdapter()
        imp = Importer(adapter, manifest, task_root)
        pre = imp.run_preflight(_opts())
        self.assertEqual(pre.counts["missing"], 1)
        self.assertEqual(pre.counts["verified"], 1)
        result = imp.execute(_opts(), pre)
        self.assertEqual(result["counts"]["imported"], 1)

    def test_failures_block_by_default_allow_partial(self):
        root = self._new_root(failed_results=1, errors=["fail"],
                              files=[
                                  {"rel": "MEDIA/A01/ok.mov", "hash": "h1", "verified": True},
                                  {"rel": "MEDIA/A01/bad.mov", "hash": "h2", "verified": False, "copied": False}])
        manifest, task_root = _load(root)
        adapter = FakeAdapter()
        imp = Importer(adapter, manifest, task_root)
        # blocked by default
        pre = imp.run_preflight(_opts(allow_partial=False))
        self.assertTrue(pre.blocking)
        result = imp.execute(_opts(allow_partial=False), pre)
        self.assertEqual(result["status"], "failed")
        # allow partial -> only verified imported
        pre2 = imp.run_preflight(_opts(allow_partial=True))
        self.assertFalse(pre2.blocking)
        result2 = imp.execute(_opts(allow_partial=True), pre2)
        self.assertEqual(result2["counts"]["imported"], 1)

    def test_unicode_project_and_chinese_path(self):
        root = self._new_root(project_name="电影项目", card_number="卡01",
                              files=[{"rel": "MEDIA/卡01/素材001.mov", "hash": "h1"}])
        manifest, task_root = _load(root)
        adapter = FakeAdapter()
        imp = Importer(adapter, manifest, task_root)
        pre = imp.run_preflight(_opts())
        self.assertEqual(pre.counts["verified"], 1)
        result = imp.execute(_opts(), pre)
        self.assertEqual(result["status"], "success")

    def test_directory_traversal_blocked(self):
        root = self._new_root(files=[
            {"rel": "../secret.mov", "hash": "h1"}])
        # create the escaped file at sibling of root
        with open(os.path.join(os.path.dirname(root), "secret.mov"), "wb") as fp:
            fp.write(b"x")
        self.roots.append(os.path.dirname(root))  # ensure cleanup
        manifest, task_root = _load(root)
        adapter = FakeAdapter()
        imp = Importer(adapter, manifest, task_root)
        pre = imp.run_preflight(_opts())
        # must be missing and never imported
        self.assertEqual(pre.counts["missing"], 1)
        self.assertEqual(pre.counts["verified"], 0)
        result = imp.execute(_opts(), pre)
        self.assertEqual(result["counts"]["imported"], 0)

    def test_resolve_api_returns_false_partial(self):
        root = self._new_root(files=[
            {"rel": "MEDIA/A01/ok.mov", "hash": "h1"},
            {"rel": "MEDIA/A01/blocked.mov", "hash": "h2"}])
        manifest, task_root = _load(root)
        adapter = FakeAdapter()
        blocked = os.path.join(root, "MEDIA", "A01", "blocked.mov")
        adapter.import_blacklist.add(blocked)
        imp = Importer(adapter, manifest, task_root)
        pre = imp.run_preflight(_opts())
        result = imp.execute(_opts(), pre)
        self.assertIn(result["status"], ("partial", "failed"))
        self.assertEqual(result["counts"]["imported"], 1)
        self.assertTrue(result["errors"])

    def test_blocking_preflight_returns_failed(self):
        root = self._new_root(failed_results=1, errors=["x"],
                              files=[{"rel": "MEDIA/A01/a.mov", "hash": "h1"}])
        manifest, task_root = _load(root)
        adapter = FakeAdapter()
        imp = Importer(adapter, manifest, task_root)
        pre = imp.run_preflight(_opts(allow_partial=False))
        result = imp.execute(_opts(allow_partial=False), pre)
        self.assertEqual(result["status"], "failed")

    def test_no_project_open_fails(self):
        root = self._new_root(files=[{"rel": "MEDIA/A01/a.mov", "hash": "h1"}])
        manifest, task_root = _load(root)
        adapter = FakeAdapter(project_name=None)  # no project
        imp = Importer(adapter, manifest, task_root)
        pre = imp.run_preflight(_opts())
        result = imp.execute(_opts(), pre)
        self.assertEqual(result["status"], "failed")
        self.assertTrue(any("open" in e.lower() or "project" in e.lower()
                            for e in result["errors"]))

    def test_dry_run_does_not_import(self):
        root = self._new_root(files=[{"rel": "MEDIA/A01/a.mov", "hash": "h1"}])
        manifest, task_root = _load(root)
        adapter = FakeAdapter()
        imp = Importer(adapter, manifest, task_root)
        pre = imp.run_preflight(_opts())
        result = imp.execute(_opts(dry_run=True), pre)
        self.assertEqual(result["status"], "dryRun")
        self.assertEqual(result["counts"]["imported"], 0)
        self.assertEqual(len(_all_clips(adapter)), 0)

    def test_non_media_sidecars_skipped(self):
        root = self._new_root(files=[
            {"rel": "MEDIA/A01/a.mov", "hash": "h1"},
            {"rel": "MEDIA/A01/a.xml", "hash": "h2"},
            {"rel": "MEDIA/A01/a.mhl", "hash": "h3"},
        ])
        manifest, task_root = _load(root)
        adapter = FakeAdapter()
        imp = Importer(adapter, manifest, task_root)
        pre = imp.run_preflight(_opts())
        self.assertEqual(pre.counts["discovered"], 1)  # only a.mov
        self.assertEqual(pre.counts["verified"], 1)
        result = imp.execute(_opts(), pre)
        self.assertEqual(result["counts"]["imported"], 1)
        # Only one clip should exist (no xml/mhl attempted).
        self.assertEqual(len(_all_clips(adapter)), 1)

    def test_missing_verified_yields_partial_not_success(self):
        root = self._new_root(files=[
            {"rel": "MEDIA/A01/here.mov", "hash": "h1"},
            {"rel": "MEDIA/A01/gone.mov", "hash": "h2"},
        ])
        os.remove(os.path.join(root, "MEDIA", "A01", "gone.mov"))
        manifest, task_root = _load(root)
        adapter = FakeAdapter()
        imp = Importer(adapter, manifest, task_root)
        pre = imp.run_preflight(_opts())
        self.assertEqual(pre.counts["missing"], 1)
        result = imp.execute(_opts(), pre)
        self.assertEqual(result["status"], "partial")
        self.assertEqual(result["counts"]["imported"], 1)

    def test_all_missing_yields_failed(self):
        root = self._new_root(files=[{"rel": "MEDIA/A01/a.mov", "hash": "h1"}])
        os.remove(os.path.join(root, "MEDIA", "A01", "a.mov"))
        manifest, task_root = _load(root)
        adapter = FakeAdapter()
        imp = Importer(adapter, manifest, task_root)
        pre = imp.run_preflight(_opts())
        result = imp.execute(_opts(), pre)
        self.assertEqual(result["status"], "failed")
        self.assertEqual(result["counts"]["imported"], 0)

    def test_import_originals_unchecked_no_import(self):
        root = self._new_root(files=[{"rel": "MEDIA/A01/a.mov", "hash": "h1"}])
        manifest, task_root = _load(root)
        adapter = FakeAdapter()
        imp = Importer(adapter, manifest, task_root)
        pre = imp.run_preflight(_opts(import_originals=False))
        result = imp.execute(_opts(import_originals=False), pre)
        self.assertEqual(result["status"], "success")
        self.assertEqual(result["counts"]["imported"], 0)
        self.assertEqual(len(_all_clips(adapter)), 0)

    def test_duplicate_across_other_bin_skipped(self):
        root = self._new_root(files=[{"rel": "MEDIA/A01/a.mov", "hash": "h1"}])
        manifest, task_root = _load(root)
        adapter = FakeAdapter()
        # Pre-create a clip in an UNRELATED bin (not under 321Doit) with the
        # same resolved path. It must still be detected as a duplicate.
        other = adapter.add_subfolder(adapter.root, "Editorial")
        real = os.path.realpath(os.path.join(root, "MEDIA", "A01", "a.mov"))
        from fake_resolve import FakeClip
        other.clips.append(FakeClip("a.mov", file_path=real))
        imp = Importer(adapter, manifest, task_root)
        pre = imp.run_preflight(_opts())
        self.assertGreaterEqual(pre.counts["skippedDuplicate"], 1)
        result = imp.execute(_opts(), pre)
        self.assertEqual(result["counts"]["imported"], 0)
        self.assertEqual(len(_all_clips(adapter)), 1)

    def test_take_id_written_to_third_party(self):
        root = self._new_root(
            project_name="LinkedProj", card_number="B02",
            detected_card="RED", project_mode="linkedProject",
            linked_project_id="proj-uuid-001",
            files=[{"rel": "MEDIA/B02/B001_C001_0509X1.R3D", "hash": "hash-ccc"}])
        manifest, task_root = _load(root)
        script_log = parse_script_log(os.path.join(FIX, "scriptlog.json"))
        adapter = FakeAdapter()
        imp = Importer(adapter, manifest, task_root, script_log)
        pre = imp.run_preflight(_opts())
        imp.execute(_opts(), pre)
        clip = _all_clips(adapter)[0]
        self.assertEqual(clip.third_party.get("321Doit Take ID"), "take-1")

    def test_multicamera_camera_label_per_clip(self):
        # One take with two camera records (A and B); each media must get its
        # own camera label, not the first record's.
        root = self._new_root(files=[
            {"rel": "MEDIA/A01/A_cam.mov", "hash": "h1"},
            {"rel": "MEDIA/B02/B_cam.mov", "hash": "h2"},
        ])
        manifest, task_root = _load(root)
        adapter = FakeAdapter()
        # Build a script log with one take, two camera records.
        from bridge.scriptlog import (ScriptLog, TakeRef, CameraRecord, ClipRef)
        take = TakeRef(
            take_id="multi", shooting_day_id="d", shooting_day_date="2026-05-04",
            scene_number="1", shot_number="1", shot_camera_setup="A",
            take_number=1, camera_label="A", status="good",
            is_circle_take=False, picture_usable=True, sound_usable=True,
            performance_rating=3, technical_rating=3,
            performance_note="", technical_note="", general_note="",
            quick_tags=[], camera_records=[
                CameraRecord("A机", "good", "recorded", "A_cam.mov", "A01",
                              "", "", "A camera note"),
                CameraRecord("B机", "ng", "recorded", "B_cam.mov", "B02",
                              "", "", "B camera fault"),
            ], linked_clips=[
                ClipRef("", "A_cam.mov", "A01", "h1"),
                ClipRef("", "B_cam.mov", "B02", "h2"),
            ])
        script_log = ScriptLog("Multi", [take], {})
        imp = Importer(adapter, manifest, task_root, script_log)
        pre = imp.run_preflight(_opts())
        imp.execute(_opts(), pre)
        clips = _all_clips(adapter)
        cam_by_name = {c.name: c.metadata.get("Camera") for c in clips}
        self.assertEqual(cam_by_name.get("A_cam.mov"), "A机")
        self.assertEqual(cam_by_name.get("B_cam.mov"), "B机")
        clip_by_name = {c.name: c for c in clips}
        self.assertEqual(clip_by_name["A_cam.mov"].clip_color, "Green")
        self.assertEqual(clip_by_name["B_cam.mov"].clip_color, "Red")
        self.assertIn("A camera note", clip_by_name["A_cam.mov"].metadata.get("Comments", ""))
        self.assertNotIn("B camera fault", clip_by_name["A_cam.mov"].metadata.get("Comments", ""))
        self.assertIn("B camera fault", clip_by_name["B_cam.mov"].metadata.get("Comments", ""))
        self.assertNotIn("A camera note", clip_by_name["B_cam.mov"].metadata.get("Comments", ""))
        # The physical media-bin hierarchy must also split by camera; correct
        # clip metadata alone is not enough.
        top = adapter.find_subfolder(adapter.root, "321Doit")
        project = adapter.find_subfolder(top, "Independent")
        date = list(project.subfolders.values())[0]
        self.assertIn("A机", date.subfolders)
        self.assertIn("B机", date.subfolders)
        a_clips = _all_clips_in(date.subfolders["A机"])
        b_clips = _all_clips_in(date.subfolders["B机"])
        self.assertEqual([c.name for c in a_clips], ["A_cam.mov"])
        self.assertEqual([c.name for c in b_clips], ["B_cam.mov"])

    def test_backfill_preserves_user_edits(self):
        root = self._new_root(
            project_name="LinkedProj", card_number="B02",
            detected_card="RED", project_mode="linkedProject",
            linked_project_id="proj-uuid-001",
            files=[{"rel": "MEDIA/B02/B001_C001_0509X1.R3D", "hash": "hash-ccc"}])
        manifest, task_root = _load(root)
        script_log = parse_script_log(os.path.join(FIX, "scriptlog.json"))
        adapter = FakeAdapter()
        imp = Importer(adapter, manifest, task_root, script_log)
        # First import: writes Scene=12, color Green.
        pre1 = imp.run_preflight(_opts())
        imp.execute(_opts(), pre1)
        clip = _all_clips(adapter)[0]
        self.assertEqual(clip.metadata.get("Scene"), "12")
        # Simulate the user manually changing Scene and color.
        clip.metadata["Scene"] = "USER_EDIT"
        clip.clip_color = "Blue"
        clip.metadata["Comments"] = "my note"
        # Re-run the same task (merge/backfill): must NOT overwrite.
        pre2 = imp.run_preflight(_opts())
        imp.execute(_opts(), pre2)
        clip = _all_clips(adapter)[0]
        self.assertEqual(clip.metadata.get("Scene"), "USER_EDIT")
        self.assertEqual(clip.metadata.get("Comments"), "my note")
        self.assertEqual(clip.clip_color, "Blue")  # not reset to Green
        self.assertEqual(len(_all_clips(adapter)), 1)  # no duplicate

    def test_backfill_keyword_merge_adds_321doit_tags(self):
        root = self._new_root(
            project_name="LinkedProj", card_number="B02",
            detected_card="RED", project_mode="linkedProject",
            linked_project_id="proj-uuid-001",
            files=[{"rel": "MEDIA/B02/B001_C001_0509X1.R3D", "hash": "hash-ccc"}])
        manifest, task_root = _load(root)
        script_log = parse_script_log(os.path.join(FIX, "scriptlog.json"))
        adapter = FakeAdapter()
        imp = Importer(adapter, manifest, task_root, script_log)
        pre1 = imp.run_preflight(_opts())
        imp.execute(_opts(), pre1)
        clip = _all_clips(adapter)[0]
        # Simulate a user-added keyword.
        clip.metadata["Keywords"] = "USER_TAG"
        # Re-run: 321Doit tags (OK, Scene_12, Shot_A, ...) must be added,
        # USER_TAG preserved.
        pre2 = imp.run_preflight(_opts())
        imp.execute(_opts(), pre2)
        clip = _all_clips(adapter)[0]
        kw = clip.metadata.get("Keywords", "")
        self.assertIn("USER_TAG", kw)
        self.assertIn("OK", kw)
        self.assertIn("Scene_12", kw)
        self.assertIn("Shot_A", kw)

    def test_camera_bin_from_scriptlog_not_card_profile(self):
        root = self._new_root(
            project_name="LinkedProj", card_number="B02",
            detected_card="ARRI · ARRI camera card",  # a card profile, not a unit
            project_mode="linkedProject",
            linked_project_id="proj-uuid-001",
            files=[{"rel": "MEDIA/B02/B001_C001_0509X1.R3D", "hash": "hash-ccc"}])
        manifest, task_root = _load(root)
        script_log = parse_script_log(os.path.join(FIX, "scriptlog.json"))
        adapter = FakeAdapter()
        imp = Importer(adapter, manifest, task_root, script_log)
        pre = imp.run_preflight(_opts())
        imp.execute(_opts(), pre)
        top = adapter.find_subfolder(adapter.root, "321Doit")
        self.assertIsNotNone(top)
        proj = adapter.find_subfolder(top, "LinkedProj")
        date = list(proj.subfolders.values())[0]
        camera = list(date.subfolders.values())[0]
        # The camera bin must be the script-log camera label, NOT the
        # detectedCard card profile.
        self.assertEqual(camera.name, "A机")
        self.assertNotIn("ARRI", camera.name)

    def test_camera_bin_unknown_without_scriptlog(self):
        root = self._new_root(
            detected_card="ARRI · ARRI camera card",
            files=[{"rel": "MEDIA/A01/a.mov", "hash": "h1"}])
        manifest, task_root = _load(root)
        adapter = FakeAdapter()
        imp = Importer(adapter, manifest, task_root)
        pre = imp.run_preflight(_opts())
        imp.execute(_opts(), pre)
        top = adapter.find_subfolder(adapter.root, "321Doit")
        proj = adapter.find_subfolder(top, "Independent")
        date = list(proj.subfolders.values())[0]
        camera = list(date.subfolders.values())[0]
        self.assertEqual(camera.name, "Unknown")  # honest, no guess

    def test_exact_card_match_no_false_positive(self):
        # A01 must NOT match A010 (substring would).
        from bridge.matcher import _cards_match
        self.assertTrue(_cards_match("A01", "A01"))
        self.assertFalse(_cards_match("A01", "A010"))
        self.assertFalse(_cards_match("A010", "A01"))


def _load(task_root):
    from bridge import manifest as m
    return m.load_manifest(task_root)


def _all_clips(adapter):
    out = []
    def walk(folder):
        out.extend(folder.clips)
        for sub in folder.subfolders.values():
            walk(sub)
    walk(adapter.root)
    return out


def _all_clips_in(folder):
    out = list(folder.clips)
    for sub in folder.subfolders.values():
        out.extend(_all_clips_in(sub))
    return out


if __name__ == "__main__":
    unittest.main()
