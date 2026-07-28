#!/usr/bin/env python3
"""Composite ALL 8 shipped desert-reskin winners onto the game's real
sand ground tile (assets/cc0/sand.png), tiled and labeled, into one
PNG for winners.md.

This is a compositing preview, NOT an in-engine screenshot -- this
sandbox has no GPU/display context (running `--headless` under Godot
here falls back to the dummy rendering driver: `get_image()` returns
null, confirmed while trying tools/biome_capture.gd). It exists so the 8
winners can be eyeballed together against their real ground texture
without hand-waving "trust the individual contact sheets". A real
in-engine capture -- `SHOT_DIR=... godot --path . --rendering-method
gl_compatibility -s res://tools/biome_capture.gd` (needs an actual
GPU/X/Xvfb session) -- should replace this when run from a machine that
has one; see the note in winners.md.

Usage:
    python3 tools/build_desert_preview.py

tools/test_build_desert_preview.py drives main() with all four path
arguments pointed at a scratch tree (a tiny manifest + fake sprites + a
fake sand tile), so the composite logic is smoke-tested against fresh
input every run, not just trusted from the committed output PNG.
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate_desert_assets import Image, ImageDraw  # noqa: E402

PROJECT_ROOT = Path(__file__).resolve().parent.parent
MANIFEST = PROJECT_ROOT / "art_candidates" / "desert_reskin" / "manifest.json"
OUT = PROJECT_ROOT / "art_reviews" / "desert_reskin" / "contact_sheets" / "composite_preview.png"
SAND_TILE = PROJECT_ROOT / "assets" / "kenney" / "sand.png"

CELL = 240
COLS = 4


def main(manifest_path: Path = None, project_root: Path = None,
         out_path: Path = None, sand_tile_path: Path = None) -> int:
    # Defaults resolved from the module globals inside the body (not as
    # `= MANIFEST` parameter defaults) -- see verify_desert_winners.py's
    # write_into_winners_md() docstring for why a def-time-bound default
    # here would silently ignore a test pointing these at a scratch tree.
    manifest_path = manifest_path or MANIFEST
    project_root = project_root or PROJECT_ROOT
    out_path = out_path or OUT
    sand_tile_path = sand_tile_path or SAND_TILE

    manifest = json.loads(manifest_path.read_text())
    names = [n for n in manifest if n != "backend_legend"]
    rows = (len(names) + COLS - 1) // COLS

    sand = Image.open(sand_tile_path).convert("RGB")
    canvas = Image.new("RGB", (CELL * COLS, CELL * rows))
    for y in range(0, canvas.height, sand.height):
        for x in range(0, canvas.width, sand.width):
            canvas.paste(sand, (x, y))

    draw = ImageDraw.Draw(canvas)
    for i, name in enumerate(names):
        entry = manifest[name]
        winner = entry["winner"]
        if winner is None:
            continue
        sprite_path = project_root / entry["replaces"]
        sprite = Image.open(sprite_path).convert("RGBA")
        cx, cy = (i % COLS) * CELL, (i // COLS) * CELL
        # center the sprite in its cell, leaving room for the label
        sx = cx + (CELL - sprite.width) // 2
        sy = cy + (CELL - sprite.height) // 2 - 12
        canvas.paste(sprite, (sx, sy), sprite)
        label = f"{name} (v{winner})"
        draw.rectangle([cx, cy + CELL - 20, cx + CELL, cy + CELL], fill=(0, 0, 0))
        draw.text((cx + 4, cy + CELL - 18), label, fill=(255, 255, 0))

    out_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out_path)
    print(f"wrote {out_path} ({canvas.width}x{canvas.height}, {len(names)} winners on the real sand tile)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
