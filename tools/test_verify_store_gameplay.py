import json
from pathlib import Path
import tempfile
import unittest

from PIL import Image

from verify_store_gameplay import check_pair, digest, local_file, verify
from assemble_store_gameplay import capture_identity


class GameplayCaptureContract(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        raw = Image.new("RGB", (640, 360), (31, 68, 125))
        raw.putpixel((0, 0), (255, 0, 0))
        raw.save(self.root / "raw.png")
        raw.resize((1920, 1080), Image.Resampling.NEAREST).save(self.root / "display.png")
        (self.root / "take.replay").write_text("test fixture, not a Godot replay")
        self.data = {
            "replay_score_verified": True, "replay_frames_verified": True,
            "sources_unchanged": True, "staged_entities": False,
            "source_files": {"res://fixture.gd": "fixture"},
            "replay": "take.replay", "replay_sha256": digest(self.root / "take.replay"),
            "frames": [{"file": "display.png", "raw_file": "raw.png",
                        "sha256": digest(self.root / "display.png"),
                        "raw_sha256": digest(self.root / "raw.png"),
                        "god_mode": False, "replay_frame": 1, "sim_checksum": 10,
                        "alive": True, "menu_visible": False, "wiped": False,
                        "debrief": False}]}

    def run_check(self):
        (self.root / "capture.json").write_text(json.dumps(self.data))
        return verify(self.root)

    def test_exact_presentation_and_active_candidate(self):
        self.assertEqual(self.run_check()["active_candidates"], ["display.png"])

    def test_modified_pixels_rejected_even_with_updated_file_hash(self):
        with Image.open(self.root / "display.png") as image:
            image.putpixel((1, 0), (0, 0, 0))
            image.save(self.root / "display.png")
        self.data["frames"][0]["sha256"] = digest(self.root / "display.png")
        with self.assertRaisesRegex(ValueError, "Presentation pixels"):
            self.run_check()

    def test_replay_tampering_rejected(self):
        (self.root / "take.replay").write_text("changed")
        with self.assertRaisesRegex(ValueError, "Replay checksum"):
            self.run_check()

    def test_failed_or_missing_attestation_rejected(self):
        for key in ("replay_score_verified", "replay_frames_verified", "sources_unchanged"):
            with self.subTest(key=key):
                self.data[key] = False
                with self.assertRaises(ValueError):
                    self.run_check()
                self.data[key] = True

    def test_god_mode_rejected_and_dead_frames_not_candidates(self):
        frame = self.data["frames"][0]
        frame["god_mode"] = True
        with self.assertRaises(ValueError):
            self.run_check()
        frame["god_mode"] = False
        frame["alive"] = False
        self.assertEqual(self.run_check()["active_candidates"], [])

    def test_path_escape_rejected(self):
        with self.assertRaises(ValueError):
            local_file(self.root, "../outside.png")

    def test_handoff_identity_requires_input_isolation_and_toolchain(self):
        capture = {"source_files": {"res://main.gd": "abc"}, "engine": "test",
                   "renderer": "test", "os_gameplay_input_disabled": True}
        for key in capture:
            missing = dict(capture)
            missing.pop(key)
            with self.subTest(key=key), self.assertRaises(ValueError):
                capture_identity(missing)
        self.assertEqual(capture_identity(capture), capture_identity(dict(capture)))

    def test_handoff_identity_distinguishes_source_and_renderer_changes(self):
        capture = {"source_files": {"res://main.gd": "abc"}, "engine": "test",
                   "renderer": "test", "os_gameplay_input_disabled": True}
        for key, value in (("source_files", {"res://main.gd": "different"}),
                           ("engine", "different"), ("renderer", "different")):
            with self.subTest(key=key):
                changed = dict(capture, **{key: value})
                self.assertNotEqual(capture_identity(capture), capture_identity(changed))


if __name__ == "__main__":
    unittest.main()
