#!/usr/bin/env python3
"""Inspect an actual Godot export, not the source tree's apparent contents.

Exports a ZIP main pack using each selected production preset (no executable
templates required). This tests packaging, not native boot or real Steam Input.
The ZIP/PCK exporters use the same preset resource selection. No archive is
extracted, and development files on disk are never removed.
"""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile
import zipfile


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = "assets/input/actions.vdf"
DEV_PREFIXES = ("tests/", "docs/", "tools/", "addons/godot_mcp/", "tmp/",
                "tmp_", "assets_src/", "art_candidates/", "build/", "reviews/", "skills/")
ERRORS = re.compile(r"SCRIPT ERROR|Parse Error|Compile Error|^ERROR:", re.MULTILINE)


def check_archive(path: Path, manifest: bytes) -> list[str]:
    problems = []
    with zipfile.ZipFile(path) as archive:
        names = set(archive.namelist())
        if MANIFEST not in names:
            problems.append("Steam Input manifest is missing")
        elif archive.read(MANIFEST) != manifest:
            problems.append("Steam Input manifest differs from the source bytes")
        if "project.binary" not in names:
            problems.append("exported project settings are missing")
        if not {"src/main.tscn", "src/main.tscn.remap"} & names:
            problems.append("main scene is missing")
        leaked = sorted(n for n in names if n.startswith(DEV_PREFIXES))
        if leaked:
            problems.append("development files bundled: " + ", ".join(leaked))
        # An exported class cache must not retain references to removed tools.
        cache = ".godot/global_script_class_cache.cfg"
        if cache in names:
            paths = re.findall(r'res://([^"\n]+)', archive.read(cache).decode("utf-8"))
            stale = sorted(p for p in paths if p.startswith(DEV_PREFIXES))
            if stale:
                problems.append("development classes in export cache: " + ", ".join(stale))
        damaged = archive.testzip()
        if damaged:
            problems.append("archive checksum failed: " + damaged)
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--preset", action="append", help="Repeat to select presets; default: all")
    parser.add_argument("--archive", type=Path, help="Inspect an existing ZIP pack instead of exporting")
    args = parser.parse_args()
    manifest = (ROOT / MANIFEST).read_bytes()
    if args.archive:
        problems = check_archive(args.archive, manifest)
        for problem in problems:
            print("FAIL: " + problem)
        if not problems:
            print("EXPORT CONTENT PASS: " + str(args.archive))
        return int(bool(problems))

    presets = args.preset or re.findall(r'^name="([^"]+)"',
                                       (ROOT / "export_presets.cfg").read_text(), re.MULTILINE)
    if not presets:
        parser.error("no export presets found")
    with tempfile.TemporaryDirectory(prefix="cic-export-content-") as temporary:
        for index, preset in enumerate(presets):
            archive = Path(temporary) / f"pack-{index}.zip"
            result = subprocess.run([args.godot, "--headless", "--path", str(ROOT),
                                     "--export-pack", preset, str(archive)],
                                    capture_output=True, text=True, timeout=300)
            output = result.stdout + result.stderr
            if result.returncode or ERRORS.search(output) or not archive.is_file():
                print(output)
                print("FAIL: export did not complete cleanly: " + preset)
                return 1
            problems = check_archive(archive, manifest)
            if problems:
                for problem in problems:
                    print("FAIL: " + preset + ": " + problem)
                return 1
            print("EXPORT CONTENT PASS: " + preset, flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
