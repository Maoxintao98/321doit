# -*- coding: utf-8 -*-
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
from bridge import manifest as manifest_mod  # noqa: E402
from bridge.importer import Importer, ImportOptions  # noqa: E402
from bridge.scriptlog import parse_script_log  # noqa: E402
from fake_resolve import FakeAdapter, FakeClip  # noqa: E402

FIX = os.path.join(HERE, "fixtures")


def _opts(**over):
    o = ImportOptions()
    for k, v in over.items():
        setattr(o, k, v)
    return o


def _all_clips(adapter):
    out = []
    def walk(folder):
        out.extend(folder.clips)
        for sub in folder.subfolders.values():
            walk(sub)
    walk(adapter.root)
    return out


class TestIdempotency(unittest.TestCase):
    def setUp(self):
        self.roots = []

    def tearDown(self):
        for r in self.roots:
            cleanup(r)

    def _root(self, **kw):
        r = make_task_root(**kw)
        self.roots.append(r)
        return r

    def test_repeat_run_no_duplicate(self):
        root = self._root(files=[{"rel": "MEDIA/A01/a.mov", "hash": "h1"}])
        manifest, task_root = manifest_mod.load_manifest(root)
        adapter = FakeAdapter()
        imp = Importer(adapter, manifest, task_root)
        pre1 = imp.run_preflight(_opts())
        r1 = imp.execute(_opts(), pre1)
        self.assertEqual(r1["counts"]["imported"], 1)
        self.assertEqual(len(_all_clips(adapter)), 1)

        # second run: same task
        pre2 = imp.run_preflight(_opts())
        self.assertEqual(pre2.counts["skippedDuplicate"], 1)
        r2 = imp.execute(_opts(), pre2)
        self.assertEqual(r2["counts"]["imported"], 0)
        self.assertEqual(len(_all_clips(adapter)), 1)

    def test_backfill_metadata_on_existing_clip(self):
        root = self._root(project_name="LinkedProj", card_number="B02",
                          detected_card="RED", project_mode="linkedProject",
                          linked_project_id="proj-uuid-001",
                          files=[{"rel": "MEDIA/B02/B001_C001_0509X1.R3D",
                                  "hash": "hash-ccc"}])
        manifest, task_root = manifest_mod.load_manifest(root)
        adapter = FakeAdapter()
        # first run: no script log, no metadata
        imp = Importer(adapter, manifest, task_root)
        pre1 = imp.run_preflight(_opts())
        r1 = imp.execute(_opts(), pre1)
        self.assertEqual(r1["counts"]["imported"], 1)
        clip = _all_clips(adapter)[0]
        self.assertEqual(clip.metadata.get("Scene"), None)

        # second run: WITH script log -> backfill metadata, no new clip
        script_log = parse_script_log(os.path.join(FIX, "scriptlog.json"))
        imp2 = Importer(adapter, manifest, task_root, script_log)
        pre2 = imp2.run_preflight(_opts())
        self.assertEqual(pre2.counts["skippedDuplicate"], 1)
        r2 = imp2.execute(_opts(), pre2)
        self.assertEqual(r2["counts"]["imported"], 0)
        self.assertEqual(len(_all_clips(adapter)), 1)
        clip = _all_clips(adapter)[0]
        self.assertEqual(clip.metadata.get("Scene"), "12")
        self.assertEqual(clip.metadata.get("Take"), "1")
        self.assertEqual(clip.clip_color, "Green")

    def test_existing_without_metadata_not_overwritten(self):
        root = self._root(files=[{"rel": "MEDIA/A01/a.mov", "hash": "h1"}])
        manifest, task_root = manifest_mod.load_manifest(root)
        adapter = FakeAdapter()
        # pre-create the bin and drop a clip WITHOUT 321Doit metadata at the
        # same resolved path.
        imp = Importer(adapter, manifest, task_root)
        leaf = imp._ensure_bin_path()
        real = os.path.realpath(os.path.join(root, "MEDIA", "A01", "a.mov"))
        existing = FakeClip("a.mov", file_path=real)
        existing.metadata["Scene"] = "MANUAL"
        leaf.clips.append(existing)

        pre = imp.run_preflight(_opts())
        # matched by path -> duplicate, not imported
        self.assertGreaterEqual(pre.counts["skippedDuplicate"], 1)
        r = imp.execute(_opts(), pre)
        self.assertEqual(r["counts"]["imported"], 0)
        # the existing clip's manual Scene must be preserved (not overwritten)
        clips = _all_clips(adapter)
        self.assertEqual(len(clips), 1)
        self.assertEqual(clips[0].metadata.get("Scene"), "MANUAL")
        self.assertEqual(
            clips[0].third_party.get("321Doit Media Key"),
            imp.manifest.task_id + "|MEDIA/A01/a.mov|h1")

    def test_duplicate_entries_inside_manifest_import_once(self):
        root = self._root(files=[
            {"rel": "MEDIA/A01/a.mov", "hash": "h1"},
            {"rel": "MEDIA/A01/a.mov", "hash": "h1"},
        ])
        manifest, task_root = manifest_mod.load_manifest(root)
        adapter = FakeAdapter()
        imp = Importer(adapter, manifest, task_root)
        pre = imp.run_preflight(_opts())
        result = imp.execute(_opts(), pre)
        self.assertEqual(result["counts"]["imported"], 1)
        self.assertEqual(result["counts"]["skippedDuplicate"], 1)
        self.assertEqual(len(_all_clips(adapter)), 1)

    def test_different_path_same_name_warns(self):
        root = self._root(files=[{"rel": "MEDIA/A01/a.mov", "hash": "h1"}])
        manifest, task_root = manifest_mod.load_manifest(root)
        adapter = FakeAdapter()
        imp = Importer(adapter, manifest, task_root)
        leaf = imp._ensure_bin_path()
        # existing clip with same name but different (non-matching) path & no key
        other = FakeClip("a.mov", file_path="/elsewhere/a.mov")
        leaf.clips.append(other)

        pre = imp.run_preflight(_opts())
        # not a duplicate by key nor by path -> import allowed, but a warning
        r = imp.execute(_opts(), pre)
        self.assertEqual(r["counts"]["imported"], 1)
        # now two clips share the name
        names = [c.name for c in _all_clips(adapter)]
        self.assertEqual(names.count("a.mov"), 2)


if __name__ == "__main__":
    unittest.main()
