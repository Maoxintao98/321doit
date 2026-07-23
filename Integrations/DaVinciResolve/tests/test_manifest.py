# -*- coding: utf-8 -*-
import json
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from bridge import manifest as manifest_mod

FIX = os.path.join(HERE, "fixtures")


class TestManifestValidation(unittest.TestCase):
    def test_load_valid_independent(self):
        manifest, task_root = manifest_mod.load_manifest(
            os.path.join(FIX, "task_independent.json"))
        self.assertEqual(manifest.task_id,
                         "11111111-2222-3333-4444-555555555555")
        self.assertEqual(manifest.project_association_mode, "independent")
        self.assertEqual(manifest.project_name, "IndieProj")
        self.assertEqual(manifest.card_number, "A01")
        self.assertEqual(len(manifest.files), 2)
        self.assertEqual(manifest.failed_results, 0)
        self.assertFalse(manifest.has_failures)
        # verified files
        verified = manifest.verified_files
        self.assertEqual(len(verified), 2)
        self.assertTrue(all(f.is_verified for f in verified))

    def test_load_linked_with_failures(self):
        manifest, _ = manifest_mod.load_manifest(
            os.path.join(FIX, "task_linked_failures.json"))
        self.assertEqual(manifest.project_association_mode, "linkedProject")
        self.assertIsNotNone(manifest.linked_project_id)
        self.assertTrue(manifest.has_failures)
        self.assertEqual(manifest.failed_results, 1)
        self.assertTrue(manifest.errors)
        # one verified, one failed
        verified = [f for f in manifest.files if f.is_verified]
        self.assertEqual(len(verified), 1)

    def test_unknown_schema_rejected(self):
        with self.assertRaises(manifest_mod.ManifestError):
            manifest_mod.load_manifest(os.path.join(FIX, "task_bad_schema.json"))

    def test_unsupported_version_rejected(self):
        with self.assertRaises(manifest_mod.ManifestError):
            manifest_mod.load_manifest(os.path.join(FIX, "task_bad_version.json"))

    def test_v1_rejected_only_v2_accepted(self):
        with self.assertRaises(manifest_mod.ManifestError):
            manifest_mod.load_manifest(os.path.join(FIX, "task_v1.json"))

    def test_missing_path(self):
        with self.assertRaises(manifest_mod.ManifestError):
            manifest_mod.load_manifest("/no/such/path/xyz")


class TestManifestFromDir(unittest.TestCase):
    def test_load_from_dir_finds_task_json(self):
        import tempfile
        tmp = tempfile.mkdtemp()
        try:
            dot = os.path.join(tmp, ".321doit")
            os.makedirs(dot)
            payload = {
                "schema": manifest_mod.SUPPORTED_SCHEMA,
                "schemaVersion": manifest_mod.SUPPORTED_SCHEMA_VERSION,
                "taskID": "t",
                "projectName": "P",
                "cardNumber": "C",
                "files": [],
            }
            with open(os.path.join(dot, "task.json"), "w") as fp:
                json.dump(payload, fp)
            manifest, task_root = manifest_mod.load_manifest(tmp)
            self.assertEqual(task_root, os.path.abspath(tmp))
            self.assertEqual(manifest.project_name, "P")
        finally:
            import shutil
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
