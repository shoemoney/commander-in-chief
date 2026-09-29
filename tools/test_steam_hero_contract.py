"""Run inside Blender with -- --input /path/to/library_hero.blend."""
import argparse
from pathlib import Path
import sys
import unittest

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
from verify_steam_media import hero_contract


class HeroContractTests(unittest.TestCase):
    def setUp(self):
        bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
        bpy.context.view_layer.update()
        self.scene = bpy.context.scene

    def issues(self):
        bpy.context.view_layer.update()
        found = []
        hero_contract(self.scene, found)
        return found

    def test_authored_mapping_passes(self):
        self.assertEqual(self.issues(), [])

    def test_camera_shift_is_rejected(self):
        self.scene.camera.location.x += 4
        self.assertIn("critical face/hair content escapes the protected center", self.issues())

    def test_nonuniform_scale_is_rejected(self):
        self.scene.objects["CIC_Background"].scale.x = 1.5
        self.assertIn("hero character is stretched instead of uniformly scaled", self.issues())

    def test_changed_source_is_rejected(self):
        self.scene["hero_source_sha256"] = "0" * 64
        self.assertIn("hero packed illustration differs from the inspected source", self.issues())

    def test_missing_annotations_are_rejected(self):
        del self.scene["hero_face_source_box"]
        self.assertIn("hero lacks source-bound critical-content annotations", self.issues())


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    SOURCE = Path(args.input).resolve()
    result = unittest.main(argv=[__file__], exit=False, verbosity=2).result
    if not result.wasSuccessful():
        raise RuntimeError("Steam hero contract tests failed")
