"""Negative controls for the package gate; no Godot or real saves touched."""
from pathlib import Path
import tempfile
import unittest
import zipfile

from verify_export_content import MANIFEST, check_archive


class ExportContentTests(unittest.TestCase):
    def check(self, changes):
        files = {MANIFEST: b"actions", "project.binary": b"settings",
                 "src/main.tscn.remap": b"scene"}
        for name, data in changes.items():
            if data is None:
                files.pop(name, None)
            else:
                files[name] = data
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "pack.zip"
            with zipfile.ZipFile(path, "w") as archive:
                for name, data in files.items():
                    archive.writestr(name, data)
            return check_archive(path, b"actions")

    def test_valid_pack(self):
        self.assertEqual(self.check({}), [])

    def test_missing_or_wrong_manifest(self):
        for data in (None, b"stale"):
            with self.subTest(data=data):
                self.assertTrue(self.check({MANIFEST: data}))

    def test_missing_main_or_settings(self):
        for name in ("project.binary", "src/main.tscn.remap"):
            with self.subTest(name=name):
                self.assertTrue(self.check({name: None}))

    def test_development_files(self):
        for name in ("addons/godot_mcp/commands/exec_commands.gdc",
                     "tmp/probe.gdc", "tmp_probe.gdc", "tools/probe.gd.remap",
                     "reviews/cycle-4/consensus.json", "skills/goals/assets/goal.example.json"):
            with self.subTest(name=name):
                self.assertTrue(self.check({name: b"development code"}))

    def test_stale_class_cache(self):
        self.assertTrue(self.check({".godot/global_script_class_cache.cfg":
                                   b'"path": "res://addons/godot_mcp/plugin.gd"'}))

    def test_runtime_addons_are_not_blanket_banned(self):
        self.assertEqual(self.check({"addons/godotsteam/steam.gdextension": b"runtime"}), [])


if __name__ == "__main__":
    unittest.main()
