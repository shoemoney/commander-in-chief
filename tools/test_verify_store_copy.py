import tempfile
import unittest
from pathlib import Path

from verify_store_copy import validate


class StoreCopyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in ["short-description.txt", "mature-content.txt", "ai-disclosure.txt",
                     "README.md", "claim-evidence.md", "owner-review.md"]:
            (self.root / name).write_text("Example game description.", encoding="utf-8")
        (self.root / "about.bbcode").write_text("[h2]Example[/h2]\n[list][*]Feature[/list]", encoding="utf-8")

    def test_accepts_complete_structural_package_without_claiming_approval(self):
        result = validate(self.root)
        self.assertEqual(result["structural_checks"], "pass")
        self.assertEqual(result["platform_approval"], "not assessed")

    def test_rejects_missing_disclosure(self):
        (self.root / "ai-disclosure.txt").unlink()
        with self.assertRaisesRegex(ValueError, "Missing"):
            validate(self.root)

    def test_rejects_long_or_multiline_short_description(self):
        for content in ["x" * 301, "First\nSecond", "[b]Game[/b]"]:
            with self.subTest(content=content[:30]):
                (self.root / "short-description.txt").write_text(content, encoding="utf-8")
                with self.assertRaisesRegex(ValueError, "Short description"):
                    validate(self.root)

    def test_rejects_bad_bbcode(self):
        for content in ["[list]Unclosed", "[h2]Wrong[/list]", "[*]Orphan", "[img]x[/img]"]:
            with self.subTest(content=content):
                (self.root / "about.bbcode").write_text(content, encoding="utf-8")
                with self.assertRaises(ValueError):
                    validate(self.root)

    def test_rejects_empty_fields_and_external_links(self):
        for content in ["", "https://example.com", "WWW.example.com", "[url=example]Site[/url]"]:
            with self.subTest(content=content):
                (self.root / "ai-disclosure.txt").write_text(content, encoding="utf-8")
                with self.assertRaises(ValueError):
                    validate(self.root)


if __name__ == "__main__":
    unittest.main()
