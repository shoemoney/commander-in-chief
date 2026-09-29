"""Offline builder contract tests; never launch Godot, Steam, or a game."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import build_steam_candidates as subject


class SteamCandidateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.templates = self.root / "templates"
        pins = {}
        for relative in subject.PINNED:
            path = self.templates / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(relative.encode())
            pins[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
        self.addCleanup(patch.stopall)
        patch.object(subject, "TEMPLATES", self.templates).start()
        patch.object(subject, "PINNED", pins).start()
        self.output = self.root / "output"

    def export(self, command, **kwargs):
        artifact = Path(command[-1])
        if artifact.suffix == ".zip":
            with zipfile.ZipFile(artifact, "w") as archive:
                archive.writestr("Game.app/Contents/MacOS/libsteam_api.dylib", b"runtime")
        else:
            artifact.write_bytes(b"executable")
            artifact.with_suffix(".pck").write_bytes(b"game pack")
        return subprocess.CompletedProcess(command, 0)

    def test_existing_output_is_preserved_without_export(self):
        self.output.mkdir()
        sentinel = self.output / "keep"
        sentinel.write_bytes(b"user data")
        with patch.object(subject.subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "already exists"):
                subject.build(self.output, ["linux"], "unused")
            run.assert_not_called()
        self.assertEqual(sentinel.read_bytes(), b"user data")

    def test_modified_template_rejected_before_creating_output(self):
        (self.templates / "linux64/godotsteam.472.template.x86_64").write_bytes(b"different")
        with patch.object(subject.subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "non-pinned"):
                subject.build(self.output, ["linux"], "unused")
            run.assert_not_called()
        self.assertFalse(self.output.exists())

    def test_missing_library_rejected_before_creating_output(self):
        (self.templates / "win64/steam_api64.dll").unlink()
        with self.assertRaisesRegex(ValueError, "non-pinned"):
            subject.build(self.output, ["windows"], "unused")
        self.assertFalse(self.output.exists())

    def test_success_copies_sidecars_and_records_actual_bytes(self):
        with patch.object(subject.subprocess, "run", side_effect=self.export) as run:
            subject.build(self.output, list(subject.TARGETS), "fake-godot")
        self.assertEqual(run.call_count, 3)
        receipt = json.loads((self.output / "manifest.json").read_text())
        self.assertEqual(len(receipt["exports"]), 3)
        for record in receipt["exports"]:
            for name, checksum in record["files"].items():
                self.assertEqual(subject.sha(self.output / record["platform"] / name), checksum)
        for platform, relative in [("linux", "linux64/libsteam_api.so"),
                                   ("windows", "win64/steam_api64.dll")]:
            self.assertEqual((self.output / platform / Path(relative).name).read_bytes(),
                             (self.templates / relative).read_bytes())

    def test_zero_exit_with_script_error_is_not_success(self):
        def bad_export(command, **kwargs):
            result = self.export(command, **kwargs)
            kwargs["stdout"].write("SCRIPT ERROR: broken project\n")
            return result
        with patch.object(subject.subprocess, "run", side_effect=bad_export):
            with self.assertRaisesRegex(ValueError, "emitted errors"):
                subject.build(self.output, ["linux"], "unused")
        self.assertFalse((self.output / "manifest.json").exists())

    def test_nonzero_export_is_not_success(self):
        with patch.object(subject.subprocess, "run", return_value=subprocess.CompletedProcess([], 1)):
            with self.assertRaisesRegex(ValueError, "Export failed"):
                subject.build(self.output, ["windows"], "unused")
        self.assertFalse((self.output / "manifest.json").exists())

    def test_missing_pack_is_not_success(self):
        def no_pack(command, **kwargs):
            Path(command[-1]).write_bytes(b"executable only")
            return subprocess.CompletedProcess(command, 0)
        with patch.object(subject.subprocess, "run", side_effect=no_pack):
            with self.assertRaisesRegex(ValueError, "game data missing"):
                subject.build(self.output, ["linux"], "unused")

    def test_mac_archive_without_library_is_not_success(self):
        def no_library(command, **kwargs):
            with zipfile.ZipFile(command[-1], "w") as archive:
                archive.writestr("Game.app/Contents/MacOS/Game", b"executable")
            return subprocess.CompletedProcess(command, 0)
        with patch.object(subject.subprocess, "run", side_effect=no_library):
            with self.assertRaisesRegex(ValueError, "lacks its Steam runtime"):
                subject.build(self.output, ["macos"], "unused")


if __name__ == "__main__":
    unittest.main()
