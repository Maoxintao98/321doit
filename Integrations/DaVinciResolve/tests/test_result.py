# -*- coding: utf-8 -*-
import os
import sys
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from bridge.result_writer import _safe_filename, write_result, new_result, _task_result_path


class TestResultWriterSafety(unittest.TestCase):
    def test_safe_filename_rejects_traversal(self):
        cases = [
            ("../../tmp/bridge", None),
            ("..", None),
            ("a/../../b", None),
        ]
        for raw, _ in cases:
            name = _safe_filename(raw)
            self.assertNotIn("..", name)
            self.assertNotIn("/", name)
            self.assertNotIn(os.sep, name)

    def test_task_result_path_cannot_escape(self):
        task_root = "/tmp/fake_task_root_%d" % os.getpid()
        path = _task_result_path(task_root, "../../../../tmp/bridge-result")
        # The file must still live under the task root's results dir.
        self.assertTrue(path.startswith(
            os.path.join(task_root, ".321doit", "integrations", "resolve", "")))
        self.assertFalse(os.path.isabs(os.path.basename(path)))
        self.assertEqual(os.path.dirname(path), os.path.join(
            task_root, ".321doit", "integrations", "resolve"))

    def test_write_result_with_malicious_taskid_stays_in_root(self):
        import tempfile
        tmp = tempfile.mkdtemp()
        try:
            result = new_result("../../tmp/evil", "21", "Proj")
            result["status"] = "dryRun"
            path = write_result(result, tmp)
            self.assertTrue(path.startswith(tmp))
            self.assertTrue(path.startswith(os.path.join(
                tmp, ".321doit", "integrations", "resolve", "")))
            # Original taskID is preserved in the JSON content.
            import json
            with open(path) as fp:
                data = json.load(fp)
            self.assertEqual(data["taskID"], "../../tmp/evil")
        finally:
            import shutil
            shutil.rmtree(tmp, ignore_errors=True)

    def test_fallback_file_contains_read_only_warning(self):
        result = new_result("task-id", "21", "Proj")
        writes = []

        def fake_write(path, text):
            writes.append((path, text))
            return len(writes) == 2

        with mock.patch("bridge.result_writer._atomic_write", side_effect=fake_write):
            path = write_result(result, "/read-only-task")

        self.assertEqual(path, writes[1][0])
        import json
        persisted = json.loads(writes[1][1])
        self.assertTrue(any("read-only" in warning.lower()
                            for warning in persisted["warnings"]))
        self.assertEqual(
            persisted["counts"]["warnings"], len(persisted["warnings"]))


if __name__ == "__main__":
    unittest.main()
