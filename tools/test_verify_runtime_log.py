import unittest

from verify_runtime_log import check_log


class RuntimeLogTests(unittest.TestCase):
    def test_success_requires_a_marker(self):
        self.assertEqual(check_log("PROGRESS PASS\nQUIT PASS\n", ["PROGRESS PASS", "QUIT PASS"]), [])
        self.assertEqual(check_log("PROGRESS PASS\n", ["QUIT PASS"]), ["Missing success marker: QUIT PASS"])

    def test_zero_exit_success_markers_cannot_hide_errors_or_leaks(self):
        for diagnostic in [
            "SCRIPT ERROR: broken script",
            "ERROR: Unable to load resource",
            "WARNING: 2 ObjectDB instances were leaked at exit.",
            "ERROR: 1 resources still in use at exit.",
            "1 RID of type Texture was leaked.",
            "WARNING: leaked 4096 bytes",
        ]:
            with self.subTest(diagnostic=diagnostic):
                self.assertEqual(check_log("PROGRESS PASS\nQUIT PASS\n" + diagnostic,
                                           ["PROGRESS PASS", "QUIT PASS"]), [diagnostic])

    def test_benign_platform_warning_is_not_an_error(self):
        self.assertEqual(check_log("WARNING: V-Sync unavailable\nPASS", ["PASS"]), [])


if __name__ == "__main__":
    unittest.main()
