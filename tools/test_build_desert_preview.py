#!/usr/bin/env python3
"""Smoke test for build_desert_preview.py -- run directly:

    python3 tools/test_build_desert_preview.py

Drives main() against a scratch manifest + fake sprites + a fake sand
tile (all four path args overridden, nothing under the real repo
touched), so the composite path is proven to regenerate cleanly from
fresh input every run, not just trusted from the committed PNG.
"""
import json
import shutil
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_desert_preview as bdp  # noqa: E402
from generate_desert_assets import Image  # noqa: E402


def check_composite_regenerates_from_scratch_input() -> None:
    tmp_root = Path(tempfile.mkdtemp(prefix="build_desert_preview_selftest_"))
    try:
        candidates_root = tmp_root / "candidates"
        (candidates_root / "cactus_large").mkdir(parents=True)
        (candidates_root / "scrub").mkdir(parents=True)

        art_dir = tmp_root / "assets" / "art"
        art_dir.mkdir(parents=True)
        Image.new("RGBA", (32, 32), (10, 120, 40, 255)).save(art_dir / "cactus_large.png")
        Image.new("RGBA", (16, 16), (140, 110, 60, 255)).save(art_dir / "scrub.png")

        sand_tile = tmp_root / "sand.png"
        Image.new("RGB", (8, 8), (200, 170, 110)).save(sand_tile)

        manifest = {
            "cactus_large": {"replaces": "assets/art/cactus_large.png", "winner": 1,
                              "variants": [{"path": "cactus_large/variant_1.png", "backend": "fal"}]},
            "scrub": {"replaces": "assets/art/scrub.png", "winner": None,  # unpicked -- must be skipped, not crash
                      "variants": [{"path": "scrub/variant_1.png", "backend": "fal"}]},
            "backend_legend": {"fa": "fal"},
        }
        manifest_path = candidates_root / "manifest.json"
        manifest_path.write_text(json.dumps(manifest))

        out_path = tmp_root / "out" / "composite_preview.png"
        rc = bdp.main(manifest_path=manifest_path, project_root=tmp_root,
                       out_path=out_path, sand_tile_path=sand_tile)

        assert rc == 0, f"main() should exit 0 for a valid scratch manifest, got {rc}"
        assert out_path.exists(), "main() must write the composite PNG to out_path"
        img = Image.open(out_path).convert("RGB")
        assert img.size == (bdp.CELL * bdp.COLS, bdp.CELL * 1), (
            f"expected a single-row {bdp.CELL * bdp.COLS}x{bdp.CELL} canvas for 2 assets, got {img.size}")

        # Canvas size alone would still pass if the paste loop silently did
        # nothing -- sample actual pixels to prove the sand tile and each
        # shipped sprite's own color really landed where main() computed.

        # Top-left corner is sand-tiled from (0, 0) and far from cactus_large's
        # centered sprite -- must show the raw sand color, not something else.
        assert img.getpixel((0, 0)) == (200, 170, 110), (
            "composite background must be the real sand tile's own pixels, not a blank/wrong canvas")

        # cactus_large (winner=1, solid 32x32 green) is pasted centered in
        # cell 0 at main()'s (cx + (CELL - w)//2, cy + (CELL - h)//2 - 12).
        sx0 = (bdp.CELL - 32) // 2
        sy0 = (bdp.CELL - 32) // 2 - 12
        assert img.getpixel((sx0 + 16, sy0 + 16)) == (10, 120, 40), (
            "cactus_large's own sprite pixels must be present at its composited position, not just a right-sized canvas")

        # scrub's winner is None (unpicked) -- its cell must stay bare sand;
        # its sprite pixels must NOT have been pasted in anyway.
        cx1 = bdp.CELL
        sx1 = cx1 + (bdp.CELL - 16) // 2
        sy1 = (bdp.CELL - 16) // 2 - 12
        assert img.getpixel((sx1 + 8, sy1 + 8)) == (200, 170, 110), (
            "an unpicked (winner=None) asset must not have its sprite pixels pasted into the composite")
    finally:
        shutil.rmtree(tmp_root, ignore_errors=True)

    print("OK: build_desert_preview regenerates a correctly-sized composite from fresh scratch input, "
          "with the real sand tile and each shipped sprite's own pixels actually present where expected "
          "(and skips an unpicked winner's pixels, not just its crash, instead of pasting them anyway)")


def main() -> int:
    check_composite_regenerates_from_scratch_input()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
