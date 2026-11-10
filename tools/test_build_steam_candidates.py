"""Offline builder contract tests; never launch Godot, Steam, or a game."""
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import re

import build_steam_candidates as subject

# The fixture copies the REAL export_presets.cfg, and the builder rejects presets whose
# version disagrees with project.godot — so the fixture's project version has to be the real
# one too. It used to be the literal "1.4.4", which made a version bump break ten tests that
# have nothing to do with versions (the 1.5.0 bump did exactly that).
VERSION = re.search(r'^config/version="([^"]+)"$',
                    (subject.ROOT / "project.godot").read_text(), re.MULTILINE).group(1)


class SteamCandidateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "project.godot").write_text(f'config/version="{VERSION}"\n')
        (self.root / "export_presets.cfg").write_bytes((subject.ROOT / "export_presets.cfg").read_bytes())
        (self.root / "src").mkdir()
        (self.root / "src/main.gd").write_text("current source\n")
        icons = self.root / "assets/fontawesome/solid"
        icons.mkdir(parents=True)
        svg = icons / "gear.svg"
        svg.write_bytes(b"runtime icon")
        (icons.parent / "LICENSE.txt").write_bytes(b"official retained license")
        (icons.parent / "manifest.json").write_text(json.dumps({
            "icons_license": "CC BY 4.0", "icons": [{"icon": "gear",
            "local_sha256": hashlib.sha256(svg.read_bytes()).hexdigest()}]}))
        self.templates = self.root / "templates"
        pins = {}
        for relative in subject.PINNED:
            path = self.templates / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(relative.encode())
            pins[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
        self.addCleanup(patch.stopall)
        patch.object(subject, "ROOT", self.root).start()
        patch.object(subject, "TEMPLATES", self.templates).start()
        patch.object(subject, "PINNED", pins).start()
        patch.object(subject, "command_output", side_effect=lambda command:
                     "4.7.2.stable.official.ed1daf0bf" if "--version" in command else
                     "a" * 40 if "rev-parse" in command else " M src/main.gd").start()
        self.output = self.root / "output"

    def export(self, command, **kwargs):
        artifact = Path(command[-1])
        if artifact.suffix == ".zip":
            with zipfile.ZipFile(artifact, "w") as archive:
                archive.writestr("Game.app/Contents/MacOS/libsteam_api.dylib", b"runtime")
                archive.writestr("Game.app/Contents/Info.plist", plistlib.dumps({
                    "CFBundleShortVersionString": VERSION, "CFBundleVersion": VERSION}))
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
        self.assertEqual(receipt["project_version"], VERSION)
        self.assertEqual(receipt["source_before"], receipt["source_after"])
        self.assertEqual(receipt["source_before"]["revision"], "a" * 40)
        self.assertTrue(receipt["source_before"]["dirty"])
        self.assertEqual(receipt["source_before"]["files"]["src/main.gd"], subject.sha(self.root / "src/main.gd"))
        for record in receipt["exports"]:
            self.assertEqual(record["export_log_sha256"], subject.sha(self.output / record["platform"] / "export.log"))
            for name, checksum in record["files"].items():
                self.assertEqual(subject.sha(self.output / record["platform"] / name), checksum)
            for name, checksum in record["attribution"].items():
                if record["platform"] == "macos":
                    with zipfile.ZipFile(self.output / "macos/CommanderInChief-macos.zip") as archive:
                        self.assertEqual(hashlib.sha256(archive.read(name)).hexdigest(), checksum)
                else:
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

    def test_source_change_during_export_has_no_success_receipt(self):
        def changed_export(command, **kwargs):
            result = self.export(command, **kwargs)
            (self.root / "src/main.gd").write_text("changed during export\n")
            return result
        with patch.object(subject.subprocess, "run", side_effect=changed_export):
            with self.assertRaisesRegex(ValueError, "Source changed during export"):
                subject.build(self.output, ["linux"], "unused")
        self.assertFalse((self.output / "manifest.json").exists())

    def test_new_runtime_svg_changes_source_fingerprint(self):
        before = subject.source_state()
        (self.root / "assets").mkdir(exist_ok=True)
        (self.root / "assets/icon.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg"/>')
        after = subject.source_state()
        self.assertNotEqual(before["fingerprint_sha256"], after["fingerprint_sha256"])
        self.assertIn("assets/icon.svg", after["files"])

    def test_revision_change_during_export_has_no_success_receipt(self):
        revision = ["a" * 40]
        def provenance(command):
            return "4.7.2.stable.official.ed1daf0bf" if "--version" in command else \
                revision[0] if "rev-parse" in command else " M src/main.gd"
        def changed_revision(command, **kwargs):
            result = self.export(command, **kwargs)
            revision[0] = "b" * 40
            return result
        with patch.object(subject, "command_output", side_effect=provenance), \
             patch.object(subject.subprocess, "run", side_effect=changed_revision):
            with self.assertRaisesRegex(ValueError, "Source changed during export"):
                subject.build(self.output, ["linux"], "unused")
        self.assertFalse((self.output / "manifest.json").exists())

    def test_wrong_exporter_version_rejected_before_export(self):
        def provenance(command):
            return "4.6.3.stable.official" if "--version" in command else \
                "a" * 40 if "rev-parse" in command else ""
        with patch.object(subject, "command_output", side_effect=provenance), \
             patch.object(subject.subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "does not match pinned"):
                subject.build(self.output, ["linux"], "unused")
            run.assert_not_called()
        self.assertFalse(self.output.exists())

    def test_stale_preset_metadata_rejected_before_export(self):
        path = self.root / "export_presets.cfg"
        for setting in (f'application/short_version="{VERSION}"', f'application/product_version="{VERSION}.0"'):
            current = path.read_text()
            path.write_text(current.replace(setting, setting.replace(VERSION, "0.3.0")))
            with patch.object(subject.subprocess, "run") as run:
                with self.assertRaisesRegex(ValueError, "Stale export metadata"):
                    subject.build(self.output, ["linux"], "unused")
                run.assert_not_called()
            self.assertFalse(self.output.exists())
            path.write_text(current)

    def test_stale_actual_mac_metadata_rejected(self):
        def stale_mac(command, **kwargs):
            artifact = Path(command[-1])
            with zipfile.ZipFile(artifact, "w") as archive:
                archive.writestr("Game.app/Contents/MacOS/libsteam_api.dylib", b"runtime")
                archive.writestr("Game.app/Contents/Info.plist", plistlib.dumps({
                    "CFBundleShortVersionString": "0.3.0", "CFBundleVersion": "0.3.0"}))
            return subprocess.CompletedProcess(command, 0)
        with patch.object(subject.subprocess, "run", side_effect=stale_mac):
            with self.assertRaisesRegex(ValueError, "Stale macOS archive metadata"):
                subject.build(self.output, ["macos"], "unused")
        self.assertFalse((self.output / "manifest.json").exists())

    def test_leaked_export_has_no_success_receipt(self):
        def leaked_export(command, **kwargs):
            result = self.export(command, **kwargs)
            kwargs["stdout"].write("WARNING: 2 ObjectDB instances were leaked at exit.\n")
            return result
        with patch.object(subject.subprocess, "run", side_effect=leaked_export):
            with self.assertRaisesRegex(ValueError, "emitted errors"):
                subject.build(self.output, ["linux"], "unused")
        self.assertFalse((self.output / "manifest.json").exists())


if __name__ == "__main__":
    unittest.main()
