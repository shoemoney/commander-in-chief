"""Read-only integrity/pixel check for actual gameplay capture receipts.

This checks recorded replay-verification results; it does not run Godot or
certify Steam acceptance, image suitability, licensing or gameplay quality.
"""
import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def local_file(root, name):
    path = (root / name).resolve()
    if not path.is_relative_to(root.resolve()) or not path.is_file():
        raise ValueError(f"Missing or out-of-folder artifact: {name}")
    return path


def check_pair(raw_path, display_path):
    with Image.open(raw_path) as raw, Image.open(display_path) as display:
        if raw.size != (640, 360) or display.size != (1920, 1080):
            raise ValueError("Unexpected source or presentation dimensions")
        expected = raw.convert("RGBA").resize(display.size, Image.Resampling.NEAREST)
        if display.convert("RGBA").tobytes() != expected.tobytes():
            raise ValueError("Presentation pixels differ from exact nearest 3x")


def verify(root):
    data = json.loads((root / "capture.json").read_text())
    for field in ("replay_score_verified", "replay_frames_verified", "sources_unchanged"):
        if data.get(field) is not True:
            raise ValueError(f"Missing successful capture check: {field}")
    if data.get("staged_entities") is not False or not data.get("source_files"):
        raise ValueError("Missing unstaged capture declaration or source fingerprints")
    replay = local_file(root, data["replay"])
    if digest(replay) != data["replay_sha256"]:
        raise ValueError("Replay checksum mismatch")
    frames = data["frames"]
    if not frames:
        raise ValueError("Capture has no frames")
    seen = set()
    previous = -1
    eligible = []
    for frame in frames:
        if frame.get("god_mode") is not False:
            raise ValueError("God mode or missing god-mode state")
        index = frame["replay_frame"]
        if index < 1 or index < previous or "sim_checksum" not in frame:
            raise ValueError("Invalid recorded frame order/checksum")
        previous = index
        paths = []
        for field, hash_field in (("raw_file", "raw_sha256"), ("file", "sha256")):
            path = local_file(root, frame[field])
            if path in seen or digest(path) != frame[hash_field]:
                raise ValueError(f"Duplicate file or checksum mismatch: {path.name}")
            seen.add(path)
            paths.append(path)
        check_pair(*paths)
        if (frame.get("alive") is True and frame.get("menu_visible") is False
                and frame.get("wiped") is False and frame.get("debrief") is False):
            eligible.append(frame["file"])
    return {"directory": str(root), "verified_frames": len(frames),
            "active_candidates": eligible,
            "scope": "file integrity, exact presentation pixels and capture receipts; visual review still required"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("takes", type=Path, nargs="+")
    args = parser.parse_args()
    try:
        print(json.dumps([verify(path) for path in args.takes], indent=2))
    except (ValueError, KeyError, OSError, TypeError) as error:
        parser.exit(1, f"Gameplay capture verification failed: {error}\n")


if __name__ == "__main__":
    main()
