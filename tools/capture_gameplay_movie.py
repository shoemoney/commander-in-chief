"""Record checked gameplay; a zero Godot exit without a complete receipt fails.

The independent wall-clock watchdog owns only its launched process group.
Finished captures may contain deaths; trailer selection still requires live play.
"""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess

from assemble_gameplay_trailer import checked_window


def verify_complete(take, expected_frames):
    take = Path(take)
    receipt = json.loads((take / "movie.json").read_text())
    frames = receipt.get("frames", [])
    if len(frames) != expected_frames or not frames:
        raise ValueError("Capture did not record the requested number of frames")
    start = frames[0]["engine_frame"]
    if type(start) is not int or start < 0:
        raise ValueError("Invalid initial movie index")
    if [f["engine_frame"] for f in frames] != list(range(start, start + expected_frames)):
        raise ValueError("Capture indices are not consecutive")
    return checked_window(take, start, expected_frames, require_live=False)


def capture(output, frames, chapter, mode, seed, timeout):
    root = Path(__file__).resolve().parents[1]
    output = Path(output).resolve()
    # Movie Maker deletes existing same-named PNGs on startup. Refuse that risk.
    if output.exists() and any(output.iterdir()):
        raise ValueError("Capture output must be a new or empty directory")
    output.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update(SHOT_DIR=str(output), TRAILER_FRAMES=str(frames), GIF_CHAPTER=str(chapter),
               GIF_MODE=mode, CAPTURE_SEED=str(seed))
    command = ["bash", str(root / "tools/playtest_newcomer.sh"),
               "--script", "res://tools/capture_gameplay_trailer.gd",
               "--rendering-method", "gl_compatibility", "--fixed-fps", "60",
               "--position", "-10000,-10000", "--write-movie", str(output / "take.png")]
    log_path = output / "stdout.log"
    print(f"Recording to {output}; progress in {log_path}", flush=True)
    with log_path.open("w") as log:
        process = subprocess.Popen(command, cwd=root, env=env, stdout=log,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            status = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            raise RuntimeError(f"Capture exceeded {timeout}s; incomplete output retained") from None
    if status != 0:
        raise RuntimeError(f"Godot exited {status}; see {log_path}")
    log = log_path.read_text()
    errors = ("SCRIPT ERROR", "Parse Error", "Compile Error", "resources still in use at exit",
              "were leaked", "was leaked", "RID allocations")
    if any(error in log for error in errors) or "TRAILER CAPTURE DONE" not in log:
        raise RuntimeError("Capture log is incomplete or reports engine/shutdown errors")
    verify_complete(output, frames)
    receipt = json.loads((output / "movie.json").read_text())
    if receipt.get("os_gameplay_input_disabled") is not True:
        raise RuntimeError("Automated capture did not isolate OS gameplay input")
    print(f"PASS: {frames} consecutive movie frames, PNG pixels, audio timing and replay receipt", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--frames", type=int, default=900, choices=range(60, 3601), metavar="60..3600")
    parser.add_argument("--chapter", type=int, default=0, choices=range(7))
    parser.add_argument("--mode", choices=("campaign", "endless"), default="campaign")
    parser.add_argument("--seed", type=int, default=3)
    parser.add_argument("--timeout", type=int, default=180)
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("timeout must be positive")
    capture(args.output, args.frames, args.chapter, args.mode, args.seed, args.timeout)
