"""Negative controls for the package gate; no Godot or real saves touched."""
from pathlib import Path
import re
import tempfile
import unittest
import zipfile

from verify_export_content import (MANIFEST, MUSIC_MANIFEST, ROOT, check_archive, check_fontawesome,
                                   check_music, fontawesome_icons, music_contract)


def check_music_empty() -> bool:
    """An empty contract must be reported, never read as 'nothing to check'."""
    import io
    import zipfile as z
    buffer = io.BytesIO()
    with z.ZipFile(buffer, "w") as archive:
        archive.writestr(MUSIC_MANIFEST, b"{}")
    with z.ZipFile(buffer) as archive:
        return bool(check_music(archive, (b"{}", [])))


class ExportContentTests(unittest.TestCase):
    def setUp(self):
        self.icons = fontawesome_icons()
        self.resource = next(iter(self.icons))
        self.texture = ".godot/imported/fixture-" + Path(self.resource).stem + ".ctex"
        self.music = (b'{"fixture": true}', ["assets/music/fixture_combat.ogg", "assets/music/sting_fixture.ogg"])

    def check(self, changes):
        files = {MANIFEST: b"actions", "project.binary": b"settings",
                 "src/main.tscn.remap": b"scene", MUSIC_MANIFEST: self.music[0]}
        for stem in self.music[1]:
            files[stem + ".import"] = b"[remap]\n"
        for resource in self.icons:
            texture = ".godot/imported/fixture-" + Path(resource).stem + ".ctex"
            files[resource + ".import"] = ('[remap]\npath="res://' + texture + '"\n').encode()
            files[texture] = b"fixture texture bytes; load acceptance remains a runtime check"
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
            return check_archive(path, b"actions", self.icons, self.music)

    def test_valid_pack(self):
        self.assertEqual(self.check({}), [])

    def test_missing_or_wrong_manifest(self):
        for data in (None, b"stale"):
            with self.subTest(data=data):
                self.assertTrue(self.check({MANIFEST: data}))

    def test_missing_or_stale_music_manifest_rejected(self):
        for data in (None, b"stale"):
            with self.subTest(data=data):
                self.assertTrue(self.check({MUSIC_MANIFEST: data}))

    def test_missing_music_stem_rejected(self):
        for stem in self.music[1]:
            with self.subTest(stem=stem):
                self.assertTrue(self.check({stem + ".import": None}))

    def test_empty_music_contract_cannot_bypass_validation(self):
        self.assertTrue(self.check({}) == [] and check_music_empty())

    def test_shipped_music_contract_names_every_stem_on_disk(self):
        data, stems = music_contract()
        self.assertGreaterEqual(len(stems), 24)
        for stem in stems:
            self.assertTrue((ROOT / stem).is_file(), stem)
            self.assertTrue((ROOT / (stem + ".import")).is_file(), stem + ".import")

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

    def test_svg_source_can_be_replaced_by_godot_imported_representation(self):
        self.assertEqual(self.check({}), [])
        self.assertEqual(self.check({self.resource: (ROOT / self.resource).read_bytes()}), [])

    def test_missing_svg_import_rejected(self):
        self.assertTrue(self.check({self.resource + ".import": None}))

    def test_missing_or_empty_imported_texture_rejected(self):
        for data in (None, b""):
            with self.subTest(data=data):
                self.assertTrue(self.check({self.texture: data}))

    def test_stale_raw_svg_rejected(self):
        self.assertTrue(self.check({self.resource: b"different image"}))

    def test_empty_icon_contract_cannot_bypass_validation(self):
        self.assertTrue(check_fontawesome(None, {}))

    def test_missing_ambiguous_or_unsafe_remap_rejected(self):
        for target in (b"[remap]\n", b'path="res://../outside.ctex"\n',
                       b'path="res://.godot/imported/../outside.ctex"\n',
                       b'path="res://.godot/imported/a.ctex"\npath="res://.godot/imported/b.ctex"\n'):
            with self.subTest(target=target):
                self.assertTrue(self.check({self.resource + ".import": target}))

    def test_external_load_probes_cover_every_manifest_icon(self):
        expected = {Path(resource).stem for resource in self.icons}
        for name in ("native_export_smoke.gd", "verify_export_runtime.gd"):
            with self.subTest(name=name):
                script = (ROOT / "tools" / name).read_text()
                declaration = re.search(r'const FONT_AWESOME_ICONS := \[(.*?)\]', script, re.DOTALL)
                self.assertIsNotNone(declaration)
                self.assertEqual(set(re.findall(r'"([a-z-]+)"', declaration.group(1))), expected)


if __name__ == "__main__":
    unittest.main()
