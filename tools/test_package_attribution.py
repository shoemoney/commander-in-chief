import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

import package_attribution as subject


class PackageAttributionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "assets/fontawesome"
        (self.source / "solid").mkdir(parents=True)
        (self.source / "solid/gear.svg").write_bytes(b"svg runtime icon")
        (self.source / "LICENSE.txt").write_bytes(b"retained upstream Font Awesome license")
        (self.source / "manifest.json").write_text(json.dumps({
            "pack": "Font Awesome Free", "copyright": "Fonticons, Inc.",
            "icons_license": "CC BY 4.0", "icons": [{"icon": "gear",
            "local_sha256": hashlib.sha256(b"svg runtime icon").hexdigest(),
            "change": "white fill for runtime tint"}]}))
        self.output = self.root / "release"
        self.output.mkdir()

    def test_native_folder_keeps_exact_license_and_attribution(self):
        for filename in ("game.exe", "game.x86_64"):
            with self.subTest(filename=filename):
                artifact = self.output / filename
                artifact.write_bytes(b"native executable")
                records = subject.package(artifact, self.root)
                self.assertEqual(records, subject.check(artifact, self.root))
                for name in subject.RECORDS:
                    self.assertEqual((self.output / subject.DESTINATION / name).read_bytes(),
                                     (self.source / name).read_bytes())
                self.assertEqual(artifact.read_bytes(), b"native executable")

    def test_mac_archive_license_sits_outside_app_without_changing_app_bytes(self):
        artifact = self.output / "game.zip"
        original = {"Game.app/Contents/MacOS/Game": b"signed executable bytes",
                    "Game.app/Contents/_CodeSignature/CodeResources": b"existing signature",
                    "Game.app/Contents/Resources/Game.pck": b"exact game pack"}
        with zipfile.ZipFile(artifact, "w") as archive:
            for name, data in original.items():
                archive.writestr(name, data)
        subject.package(artifact, self.root)
        with zipfile.ZipFile(artifact) as archive:
            for name, data in original.items():
                self.assertEqual(archive.read(name), data)
            for name in subject.RECORDS:
                self.assertEqual(archive.read(f"{subject.DESTINATION}/{name}"),
                                 (self.source / name).read_bytes())

    def test_repeated_package_is_idempotent(self):
        artifact = self.output / "game.zip"
        with zipfile.ZipFile(artifact, "w") as archive:
            archive.writestr("Game.app/Contents/MacOS/Game", b"executable")
        subject.package(artifact, self.root)
        before = artifact.read_bytes()
        subject.package(artifact, self.root)
        self.assertEqual(artifact.read_bytes(), before)
        with zipfile.ZipFile(artifact) as archive:
            self.assertEqual(archive.namelist().count(f"{subject.DESTINATION}/LICENSE.txt"), 1)

    def test_missing_license_in_actual_archive_fails(self):
        artifact = self.output / "game.zip"
        with zipfile.ZipFile(artifact, "w") as archive:
            archive.writestr(f"{subject.DESTINATION}/manifest.json", (self.source / "manifest.json").read_bytes())
        with self.assertRaisesRegex(ValueError, "missing or has stale attribution"):
            subject.check(artifact, self.root)

    def test_stale_folder_attribution_cannot_be_silently_replaced(self):
        artifact = self.output / "game.exe"
        artifact.write_bytes(b"executable")
        subject.package(artifact, self.root)
        (self.output / subject.DESTINATION / "manifest.json").write_bytes(b"old attribution")
        with self.assertRaisesRegex(ValueError, "Existing release attribution differs"):
            subject.package(artifact, self.root)

    def test_svg_change_requires_updated_source_attribution(self):
        artifact = self.output / "game.exe"
        artifact.write_bytes(b"executable")
        (self.source / "solid/gear.svg").write_bytes(b"different adapted icon")
        with self.assertRaisesRegex(ValueError, "does not match runtime icon"):
            subject.package(artifact, self.root)
        self.assertFalse((self.output / "licenses").exists())

    def test_missing_retained_source_license_fails_before_package_write(self):
        artifact = self.output / "game.exe"
        artifact.write_bytes(b"executable")
        (self.source / "LICENSE.txt").unlink()
        with self.assertRaises(FileNotFoundError):
            subject.package(artifact, self.root)
        self.assertFalse((self.output / "licenses").exists())

    def test_unrecorded_runtime_svg_is_rejected(self):
        artifact = self.output / "game.exe"
        artifact.write_bytes(b"executable")
        (self.source / "solid/new-icon.svg").write_bytes(b"unrecorded icon")
        with self.assertRaisesRegex(ValueError, "list each runtime SVG exactly once"):
            subject.package(artifact, self.root)
        self.assertFalse((self.output / "licenses").exists())


if __name__ == "__main__":
    unittest.main()
