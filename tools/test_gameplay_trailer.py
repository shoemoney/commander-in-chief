"""Small positive and tamper fixtures for the trailer source-window gate."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import wave

from PIL import Image
from assemble_gameplay_trailer import checked_window, sha
from capture_gameplay_movie import verify_complete


class TrailerSourceGate(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        frames = []
        for i in range(3):
            image = Image.new("RGBA", (640, 360), (i * 20, 60, 90, 255))
            image.save(self.root / f"take{i:08d}.png")
            frames.append({"engine_frame": i, "pixel_sha256": hashlib.sha256(image.tobytes()).hexdigest(),
                           "alive": True, "wiped": False, "debrief": False, "menu_visible": False})
        (self.root / "take.replay").write_bytes(b"fixture replay, not engine verification")
        with wave.open(str(self.root / "take.wav"), "wb") as audio:
            audio.setparams((2, 4, 48000, 0, "NONE", "not compressed"))
            audio.writeframes(bytes(3 * 800 * 8))
        self.receipt = {"kind": "actual gameplay movie", "fps": 60, "god_mode": False,
                        "staged_entities": False, "replay_score_verified": True,
                        "replay_frames_verified": True, "sources_unchanged": True,
                        "source_files": {"res://source.gd": "fixture hash"}, "replay": "take.replay",
                        "replay_sha256": sha(self.root / "take.replay"), "frames": frames}
        self.save()

    def save(self):
        (self.root / "movie.json").write_text(json.dumps(self.receipt))

    def test_valid_exact_window(self):
        self.assertEqual(len(checked_window(self.root, 1, 2)["frames"]), 2)

    def test_completed_capture_requires_exact_requested_count(self):
        self.assertEqual(len(verify_complete(self.root, 3)["frames"]), 3)
        with self.assertRaises(ValueError):
            verify_complete(self.root, 4)

    def test_completed_capture_can_include_death_but_trailer_cannot(self):
        self.receipt["frames"][1]["alive"] = False
        self.save()
        self.assertEqual(len(verify_complete(self.root, 3)["frames"]), 3)
        with self.assertRaises(ValueError):
            checked_window(self.root, 0, 3)

    def test_missing_or_duplicate_frame_rejected(self):
        self.receipt["frames"][2]["engine_frame"] = 1
        self.save()
        with self.assertRaises(ValueError):
            checked_window(self.root, 1, 2)

    def test_changed_pixels_rejected(self):
        Image.new("RGB", (640, 360), "red").save(self.root / "take00000001.png")
        with self.assertRaises(ValueError):
            checked_window(self.root, 1, 2)

    def test_shifted_movie_counter_rejected(self):
        # A draw counter is not a movie-file counter when automatic rendering
        # is suppressed. Correct pixels attached to the wrong index must fail.
        for frame in self.receipt["frames"]:
            frame["engine_frame"] += 1
        self.save()
        with self.assertRaises(ValueError):
            checked_window(self.root, 1, 2)

    def test_gap_in_movie_counter_rejected(self):
        self.receipt["frames"].pop(1)
        self.save()
        with self.assertRaises(ValueError):
            checked_window(self.root, 0, 3)

    def test_dead_and_menu_frames_rejected(self):
        for key, value in (("alive", False), ("menu_visible", True)):
            with self.subTest(key=key):
                old = self.receipt["frames"][1][key]
                self.receipt["frames"][1][key] = value
                self.save()
                with self.assertRaises(ValueError):
                    checked_window(self.root, 1, 2)
                self.receipt["frames"][1][key] = old

    def test_failed_attestation_rejected(self):
        self.receipt["replay_frames_verified"] = False
        self.save()
        with self.assertRaises(ValueError):
            checked_window(self.root, 1, 2)

    def test_changed_replay_rejected(self):
        (self.root / "take.replay").write_bytes(b"changed")
        with self.assertRaises(ValueError):
            checked_window(self.root, 1, 2)

    def test_wrong_audio_timing_rejected(self):
        with wave.open(str(self.root / "take.wav"), "wb") as audio:
            audio.setparams((2, 4, 48000, 0, "NONE", "not compressed"))
            audio.writeframes(bytes(6 * 800 * 8))
        with self.assertRaises(ValueError):
            checked_window(self.root, 1, 2)


if __name__ == "__main__":
    unittest.main()
