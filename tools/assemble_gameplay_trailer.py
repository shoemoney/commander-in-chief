"""Build a local gameplay-trailer draft from checked Movie Maker frames.

No generated gameplay, time remapping, entity staging or store upload. The
cut list selects ordinary live-play windows. Audio is the synchronized game
mix with short edge fades; voice/asset rights still require owner review.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import wave

from PIL import Image

FPS = 60


def sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def checked_window(take, start, count, *, require_live=True):
    take = Path(take).resolve()
    receipt = json.loads((take / "movie.json").read_text())
    if receipt.get("kind") != "actual gameplay movie" or receipt.get("fps") != FPS:
        raise ValueError("Wrong capture kind or frame rate")
    for field in ("replay_score_verified", "replay_frames_verified", "sources_unchanged"):
        if receipt.get(field) is not True:
            raise ValueError(f"Missing successful capture check: {field}")
    if receipt.get("god_mode") is not False or receipt.get("staged_entities") is not False:
        raise ValueError("God mode or staged entities are forbidden")
    if not receipt.get("source_files"):
        raise ValueError("Missing source fingerprints")
    if receipt.get("replay") != "take.replay" or sha(take / "take.replay") != receipt.get("replay_sha256"):
        raise ValueError("Replay content/path mismatch")
    if type(start) is not int or type(count) is not int or start < 0 or count <= 0:
        raise ValueError("Frame window must use nonnegative start and positive integer count")
    indexed = {frame["engine_frame"]: frame for frame in receipt["frames"]}
    if len(indexed) != len(receipt["frames"]):
        raise ValueError("Duplicate frame evidence")
    selected = []
    for number in range(start, start + count):
        frame = indexed.get(number)
        if frame is None or (require_live and (frame.get("alive") is not True or any(
                frame.get(key) is not False for key in ("wiped", "debrief", "menu_visible")))):
            raise ValueError(f"Frame {number} is missing or is not live gameplay")
        path = take / f"take{number:08d}.png"
        with Image.open(path) as image:
            if image.size != (640, 360):
                raise ValueError("Source must be the unmodified game viewport")
            digest = hashlib.sha256(image.convert("RGBA").tobytes()).hexdigest()
        if digest != frame.get("pixel_sha256"):
            raise ValueError(f"Frame {number} pixels differ from captured state")
        selected.append({**frame, "file_sha256": sha(path)})
    with wave.open(str(take / "take.wav")) as audio:
        if audio.getframerate() != 48000 or audio.getnchannels() != 2:
            raise ValueError("Expected 48kHz stereo Movie Maker audio")
        if audio.getnframes() < (start + count) * 800:
            raise ValueError("Audio does not cover selected frame window")
        movie_frames = list(take.glob("take[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9].png"))
        if audio.getnframes() != len(movie_frames) * 800:
            raise ValueError("Movie audio/video timing is not exactly 60 FPS")
    return {"take": str(take), "start_frame": start, "frame_count": count,
            "movie_receipt_sha256": sha(take / "movie.json"),
            "replay_sha256": receipt["replay_sha256"], "audio_sha256": sha(take / "take.wav"),
            "source_files": receipt["source_files"], "frames": selected}


def run(command):
    subprocess.run(command, check=True)


def encoding():
    return ["-c:v", "libx264", "-preset", "fast", "-b:v", "12M", "-minrate", "12M",
            "-maxrate", "12M", "-bufsize", "24M", "-x264-params", "nal-hrd=cbr:filler=1",
            "-pix_fmt", "yuv420p", "-r", str(FPS), "-c:a", "aac", "-b:a", "192k",
            "-ar", "48000", "-ac", "2", "-movflags", "+faststart"]


def assemble(plan_path, output):
    plan_path, output = Path(plan_path).resolve(), Path(output).resolve()
    plan = json.loads(plan_path.read_text())
    if output.exists():
        raise ValueError("Use a new output directory; existing drafts are preserved")
    checked = [checked_window(item["take"], item["start_frame"], item["frame_count"])
               for item in plan["clips"]]
    if not checked:
        raise ValueError("No gameplay clips")
    # All footage must be from one consistent source/asset snapshot.
    if any(item["source_files"] != checked[0]["source_files"] for item in checked[1:]):
        raise ValueError("Cannot mix footage from different source snapshots")
    logo = Path(plan["logo"]).resolve()
    if sha(logo) != plan["logo_sha256"]:
        raise ValueError("Logo differs from the reviewed render")
    output.mkdir(parents=True)
    shutil.copy2(plan_path, output / "cut-list.json")
    clips = []
    for index, item in enumerate(checked):
        duration = item["frame_count"] / FPS
        target = output / f"clip-{index + 1:02d}.mp4"
        print(f"Encoding gameplay clip {index + 1}", flush=True)
        run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-n", "-framerate", str(FPS),
             "-start_number", str(item["start_frame"]), "-i", str(Path(item["take"]) / "take%08d.png"),
             "-ss", str(item["start_frame"] / FPS), "-i", str(Path(item["take"]) / "take.wav"),
             "-t", str(duration), "-frames:v", str(item["frame_count"]),
             "-vf", "scale=1920:1080:flags=neighbor,setsar=1",
             "-af", f"afade=t=in:d=0.06,afade=t=out:st={duration - .06}:d=0.06",
             *encoding(), str(target)])
        clips.append(target)
    end_card = output / "end-card.mp4"
    run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-n",
         "-f", "lavfi", "-i", "color=c=0x10140f:s=1920x1080:r=60:d=2",
         "-loop", "1", "-i", str(logo), "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo",
         "-filter_complex", "[0:v][1:v]overlay=(W-w)/2:(H-h)/2,format=yuv420p[v]",
         "-map", "[v]", "-map", "2:a", "-t", "2", *encoding(), str(end_card)])
    clips.append(end_card)
    trailer = output / "CommanderInChief-gameplay-draft.mp4"
    lengths = [item["frame_count"] for item in checked] + [120]
    expected = sum(lengths)
    filters, inputs, lanes = [], [], []
    for index, (clip, count) in enumerate(zip(clips, lengths)):
        inputs += ["-i", str(clip)]
        # Reset each decoded stream independently. The concat demuxer otherwise
        # promoted AAC priming timestamps into one extra duplicated video frame.
        filters += [f"[{index}:v]trim=end_frame={count},setpts=N/(60*TB)[v{index}]",
                    f"[{index}:a]atrim=duration={count/FPS},asetpts=PTS-STARTPTS[a{index}]"]
        lanes += [f"[v{index}][a{index}]"]
    filters.append("".join(lanes) + f"concat=n={len(clips)}:v=1:a=1[v][a]")
    run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-n", *inputs,
         "-filter_complex", ";".join(filters), "-map", "[v]", "-map", "[a]",
         "-frames:v", str(expected), "-t", str(expected/FPS), *encoding(), str(trailer)])
    probe = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-show_streams",
                                                "-show_format", "-of", "json", str(trailer)]))
    video = next(s for s in probe["streams"] if s["codec_type"] == "video")
    audio = next(s for s in probe["streams"] if s["codec_type"] == "audio")
    if (video["width"], video["height"], video["avg_frame_rate"], video["codec_name"]) != (1920, 1080, "60/1", "h264"):
        raise ValueError("Final video format mismatch")
    if audio["codec_name"] != "aac" or audio["sample_rate"] != "48000" or audio["channels"] != 2:
        raise ValueError("Final audio format mismatch")
    if int(video["nb_frames"]) != expected:
        raise ValueError("Final frame count differs from the selected source windows")
    if abs(float(probe["format"]["duration"]) - expected / FPS) > .1:
        raise ValueError("Unexpected final duration")
    record = {"status": "local draft; visual and listening review required",
              "fps": FPS, "clips": checked, "logo": str(logo), "logo_sha256": sha(logo),
              "file": trailer.name, "sha256": sha(trailer), "probe": probe,
              "edits": "hard cuts; exact 3x nearest gameplay scale; 60ms audio edge fades; two-second logo end card",
              "limits": "No Steam upload/approval, rights clearance, human playtest or virality claim. Source paths remain project-local."}
    (output / "manifest.json").write_text(json.dumps(record, indent=2) + "\n")
    print(trailer, flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plan", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    assemble(args.plan, args.output)
