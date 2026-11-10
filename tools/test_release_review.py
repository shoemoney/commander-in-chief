"""Copy-contract fixtures; no game execution or launch acceptance is implied."""
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
        self.root = Path(self.temp.name).resolve()
        (self.root / "project.godot").write_text('config/version="1.4.4"\n')
        (self.root / "docs/steam-store").mkdir(parents=True)
        for name in ("ASSETS.md", "NOTICE.md"):
            (self.root / name).write_bytes(b"fixture reference")
        self.builds = self.root / "candidates"
        self.builds.mkdir()
        exports = []
        for platform in ("macos", "linux", "windows"):
            directory = self.builds / platform
            directory.mkdir()
            (directory / "game.bin").write_bytes(b"fixture content")
            (directory / "export.log").write_bytes(b"fixture export log")
            exports.append({"platform": platform, "files": {"game.bin": subject.sha(directory / "game.bin")},
                            "export_log_sha256": subject.sha(directory / "export.log")})
        files = subject.current_source_files(self.root)
        identity = {"revision": "a" * 40, "project_version": "1.4.4", "files": files,
                    "fingerprint_sha256": hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest()}
        (self.builds / "manifest.json").write_text(json.dumps({
            "source_before": identity, "source_after": identity, "exports": exports}))
        self.source = self.builds / "linux/game.bin"
        self.sources = {"builds": self.builds}
        self.output = self.root / "review"

    def assemble(self):
        with patch.object(subject, "validate_copy"):
            subject.assemble(self.root, self.output, self.sources)

    def test_checked_copy_and_archive_preserve_bytes(self):
        self.assemble()
        manifest = json.loads((self.output / "manifest.json").read_text())
        with zipfile.ZipFile(self.output.with_suffix(".zip")) as archive:
            for row in manifest["files"]:
                self.assertEqual(hashlib.sha256(archive.read(row["file"])).hexdigest(), row["sha256"])
        self.assertEqual((self.output / "builds/linux/game.bin").read_bytes(), self.source.read_bytes())
        self.assertIn("not uploaded", manifest["status"])

    def test_verifier_rejects_modified_copied_file(self):
        self.assemble()
        (self.output / "builds/linux/game.bin").write_bytes(b"modified")
        with self.assertRaisesRegex(ValueError, "checksum differs"):
            subject.verify(self.output)

    def test_existing_destination_is_not_overwritten(self):
        self.output.mkdir()
        marker = self.output / "keep.txt"
        marker.write_bytes(b"preserve")
        with patch.object(subject, "plan") as plan:
            with self.assertRaisesRegex(ValueError, "already exists"):
                subject.assemble(self.root, self.output, self.sources)
            plan.assert_not_called()
        self.assertEqual(marker.read_bytes(), b"preserve")

    def test_changed_source_cannot_be_receipted_as_original(self):
        self.source.write_bytes(b"changed after export receipt")
        with self.assertRaisesRegex(ValueError, "checksum differs"):
            self.assemble()
        self.assertFalse(self.output.with_suffix(".zip").exists())
        self.assertFalse((self.output / "manifest.json").exists())

    def test_paths_cannot_escape_manifest_root(self):
        for name in ["../input.txt", str(self.source.resolve())]:
            with self.assertRaisesRegex(ValueError, "Unsafe"):
                subject.safe_member(self.root, name)


if __name__ == "__main__":
    unittest.main()
