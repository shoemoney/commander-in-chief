"""Small copy-contract tests; the real bundle supplies end-to-end receipt evidence."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import assemble_release_review as subject


class ReviewPackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "input.txt"
        self.source.write_bytes(b"fixture content")
        self.output = self.root / "review"

    def test_checked_copy_and_archive_preserve_bytes(self):
        with patch.object(subject, "plan", return_value={
                "docs/input.txt": (self.source, subject.sha(self.source))}):
            subject.assemble(self.root, self.output)
        manifest = json.loads((self.output / "manifest.json").read_text())
        with zipfile.ZipFile(self.output.with_suffix(".zip")) as archive:
            for row in manifest["files"]:
                self.assertEqual(hashlib.sha256(archive.read(row["file"])).hexdigest(), row["sha256"])
        self.assertEqual((self.output / "docs/input.txt").read_bytes(), self.source.read_bytes())
        self.assertIn("not uploaded", manifest["status"])

    def test_verifier_rejects_modified_copied_file(self):
        with patch.object(subject, "plan", return_value={
                "docs/input.txt": (self.source, subject.sha(self.source))}):
            subject.assemble(self.root, self.output)
        (self.output / "docs/input.txt").write_bytes(b"modified")
        with self.assertRaisesRegex(ValueError, "checksum differs"):
            subject.verify(self.output)

    def test_existing_destination_is_not_overwritten(self):
        self.output.mkdir()
        marker = self.output / "keep.txt"
        marker.write_bytes(b"preserve")
        with patch.object(subject, "plan") as plan:
            with self.assertRaisesRegex(ValueError, "already exists"):
                subject.assemble(self.root, self.output)
            plan.assert_not_called()
        self.assertEqual(marker.read_bytes(), b"preserve")

    def test_changed_source_cannot_be_receipted_as_original(self):
        with patch.object(subject, "plan", return_value={"input.txt": (self.source, "0" * 64)}):
            with self.assertRaisesRegex(ValueError, "checksum differs"):
                subject.assemble(self.root, self.output)
        self.assertFalse(self.output.with_suffix(".zip").exists())
        self.assertFalse((self.output / "manifest.json").exists())

    def test_paths_cannot_escape_manifest_root(self):
        for name in ["../input.txt", str(self.source.resolve())]:
            with self.assertRaisesRegex(ValueError, "Unsafe"):
                subject.safe_member(self.root, name)


if __name__ == "__main__":
    unittest.main()
