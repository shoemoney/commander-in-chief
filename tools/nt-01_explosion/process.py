#!/usr/bin/env python3
"""nt-01-explosion-vfx-replacement pipeline record.

Regenerates assets/kenney/explosion0..3.png from the winning fal.ai render.
Kept here (tracked) so the pipeline is reproducible/reviewable even though
its raw inputs/outputs live under the gitignored art_candidates/ scratch
dir. Run from the repo root: `python3 tools/nt-01_explosion/process.py`.

How the winning source was generated (fal.ai nano-banana, default model of
~/.claude/skills/image-toolkit/scripts/generate.py):
    A 2x2 grid sprite sheet of 4 sequential frames of a single top-down
    video game explosion animation, each frame isolated on a solid flat
    pure magenta background for chroma-key removal, thin gap between grid
    cells. Frame 1 top-left: small bright white-yellow flash burst just
    igniting. Frame 2 top-right: expanding orange-red fireball with dark
    smoke starting to billow. Frame 3 bottom-left: large intense fireball,
    red-orange-yellow core, black smoke plumes, a few flying debris specks,
    biggest frame of the sequence. Frame 4 bottom-right: fireball
    collapsing into a dissipating grey-brown smoke cloud with dying embers,
    smaller and fading. Modern stylized semi-realistic top-down military
    shooter VFX art, painterly rendering, vivid warm colors, no text, no
    watermark, no grid lines, no drop shadow, centered explosion in each
    cell.

Picked over 3 other candidates (2x fal.ai, 1x Replicate flux-schnell, all
generated with the same/a close variant of the prompt above) because: a
clean single-hairline grid (one Replicate candidate baked an extra inner
rectangle into every cell that would have left a border after cropping),
correct size progression across the 4 cells matching how _draw_fx already
animates spr_scale over the FX lifetime (both Replicate candidates had
same-sized or inconsistently-positioned frames), and the best small-size
silhouette read (single blob shape with a hot core, matching what the old
Kenney frames did well) while adding real shading/smoke/debris the Kenney
frames never had.

Split the 2x2 grid into 4 explosion frames, chroma-key the magenta
background to transparent, crop to content bbox, resize to a shared square
canvas so the sim's spr_scale progression (not raw pixel size) controls the
growth animation, and install the result over assets/kenney/explosion0..3.png
— the same 4 files this pipeline produced for the committed sprites."""
import hashlib
import sys
from pathlib import Path

import numpy as np
from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[2]

# Pillow 9.1 moved the resample-filter constants to Image.Resampling and
# deprecated the old top-level Image.BOX/.LANCZOS/etc (removed outright in
# some later line); resolve via getattr so this keeps working whichever
# Pillow the caller has installed.
_BOX = getattr(getattr(Image, "Resampling", Image), "BOX")

# SHA-256 of each installed frame's DECODED pixel data (Image.tobytes(), not
# the PNG file bytes, so re-encoding doesn't change it), recorded the last
# time this pipeline was run end-to-end and the result was reviewed. main()
# re-checks against these after every run and prints a mismatch instead of
# silently drifting if a future edit to the algorithm above changes the
# output — a reviewer can trust "it ran clean" without re-diffing pixels by
# hand. Update these (and re-review the frames!) whenever you deliberately
# change the pipeline.
EXPECTED_SHA256 = {
    0: "51f255ae1b755cb249a43393212dbe403bd4eacf460d9f43a195c38eda9ebdb3",
    1: "4679d60414b9e41525becd9b2feb0c6aaf59700c19baaf682fb6c993b82b6b59",
    2: "ec4b6a808976f8677663286c1476f613933e0443257ee72926aa9e352aaed081",
    3: "64a4dfde77eb1a110a94d47f62e4bf6d6fb081513a96885cc1cd46c3867b8d5d",
}


def resize_premultiplied(im: Image.Image, size: tuple[int, int]) -> Image.Image:
    """PIL's RGBA resize interpolates RGB and A independently, so a fully
    transparent pixel's leftover (arbitrary, post-chroma-key) color bleeds
    into semi-transparent neighbors during filtering. Premultiply by alpha
    before resizing and un-premultiply after so invisible pixels can't tint
    the visible edge. Uses BOX (a non-negative-kernel filter, no ringing) —
    LANCZOS's negative side-lobes overshoot at the hard alpha edges these
    chroma-keyed cutouts have, and dividing an overshot premultiplied color
    back out by its (also overshot but still small) alpha blows up to a
    solid white halo right at the silhouette edge."""
    arr = np.asarray(im.convert("RGBA")).astype(np.float32)
    a = arr[:, :, 3:4] / 255.0
    premul = arr.copy()
    premul[:, :, :3] *= a
    premul_img = Image.fromarray(premul.astype(np.uint8), "RGBA")
    resized = premul_img.resize(size, _BOX)
    rarr = np.asarray(resized).astype(np.float32)
    ra = np.clip(rarr[:, :, 3:4], 1, 255) / 255.0
    rarr[:, :, :3] = np.clip(rarr[:, :, :3] / ra, 0, 255)
    return Image.fromarray(rarr.astype(np.uint8), "RGBA")

# Winning fal.ai render (regenerate via the prompt in the module docstring
# if this scratch file is gone) and where the split/keyed frames land.
SRC = REPO_ROOT / "art_candidates" / "nt-01-explosion" / "fal_a.png"
SCRATCH_OUT = REPO_ROOT / "art_candidates" / "nt-01-explosion"
INSTALL_DIR = REPO_ROOT / "assets" / "kenney"   # committed sprite location
OUT_SIZE = 128  # shared square canvas for all 4 frames

KEY = (219, 29, 128)  # magenta background, sampled from fal_a.png corners
TOL = 90      # hard-cut radius: fully inside this distance -> transparent
FEATHER = 40  # antialias band right at the silhouette edge
# How far out (past TOL+FEATHER) an opaque pixel can still carry a magenta
# color spill even though it's already far enough to stay fully opaque.
# Measured directly off a keyed frame: fringe pixels sat at distance
# ~130-150 from KEY, all just past TOL+FEATHER (130) — so a 40px margin
# covers the measured halo with room to spare.
SPILL_MARGIN = 40


def chroma_key(cell: Image.Image) -> Image.Image:
    cell = cell.convert("RGBA")
    px = cell.load()
    cw, ch = cell.size
    for y in range(ch):
        for x in range(cw):
            r, g, b, a = px[x, y]
            dr, dg, db = r - KEY[0], g - KEY[1], b - KEY[2]
            dist = (dr * dr + dg * dg + db * db) ** 0.5
            if dist < TOL:
                px[x, y] = (r, g, b, 0)
            elif dist < TOL + FEATHER + SPILL_MARGIN:
                # Magenta-spill de-tint, scoped to the near-key zone (the
                # alpha-feather band PLUS the measured spill halo just past
                # it — see SPILL_MARGIN above), not applied unconditionally
                # to the whole frame: the source render antialiases its own
                # edges INTO the magenta key (R and B both pulled above G),
                # which a plain alpha feather leaves as a purple rim on any
                # other bg. Real fire/smoke color never has R and B both
                # exceeding G at once (orange fire has low B; grey smoke has
                # R~=G~=B) so subtracting the shared R/B excess over G only
                # ever cancels genuine spill — but bounding WHERE it runs
                # means it can't quietly reshade real artwork deep inside
                # the frame on a future regeneration with a different
                # palette, even though the formula happens to be a no-op
                # there for this one.
                spill = max(0, min(r, b) - g)
                r -= spill
                b -= spill
                if dist < TOL + FEATHER:
                    fa = int(a * (dist - TOL) / FEATHER)
                    a = min(a, fa)
                px[x, y] = (r, g, b, a)
            else:
                px[x, y] = (r, g, b, a)
    return cell

def find_grid_line_bands(arr: np.ndarray) -> tuple[list[tuple[int, int]], list[tuple[int, int]]]:
    """Auto-detect the source grid's near-white/light-grey divider lines
    (the center "+" cross AND the subtler outer picture-frame rectangle —
    see the erase-step comment in main()) instead of trusting hardcoded
    pixel bands tuned for one specific 1024px render. A "line" row/column is
    one where most of the interior (excluding the outer 10% margin, where
    real explosion content legitimately reaches) is near-white/grey and
    low-saturation — a color no chroma-keyed fire/smoke/spark pixel in this
    palette produces. Returns (row_bands, col_bands), each a list of
    (lo, hi) index ranges to blank out with the key color; either list is
    empty if nothing matched, which main() treats as a hard error rather
    than silently mis-cropping."""
    rgb = arr[:, :, :3].astype(np.int32)
    mn = rgb.min(axis=-1)
    mx = rgb.max(axis=-1)
    line_mask = (mn > 150) & ((mx - mn) < 60)
    h, w = line_mask.shape
    margin_x, margin_y = w // 10, h // 10
    row_hits = line_mask[:, margin_x: w - margin_x].sum(axis=1)
    col_hits = line_mask[margin_y: h - margin_y, :].sum(axis=0)
    row_thresh = (w - 2 * margin_x) * 0.5
    col_thresh = (h - 2 * margin_y) * 0.5

    def to_bands(hits: np.ndarray, thresh: float) -> list[tuple[int, int]]:
        idx = np.where(hits > thresh)[0]
        if len(idx) == 0:
            return []
        bands, start, prev = [], idx[0], idx[0]
        for v in idx[1:]:
            if v - prev > 4:
                bands.append((start, prev + 1))
                start = v
            prev = v
        bands.append((start, prev + 1))
        pad = 8  # cover each line's antialiased halo
        return [(max(0, lo - pad), hi + pad) for lo, hi in bands]

    return to_bands(row_hits, row_thresh), to_bands(col_hits, col_thresh)


def assert_frame_is_clean(square: Image.Image, frame_idx: int) -> None:
    """Runnable self-check (not just eyeballing a composite once): assert
    the installed frame has real content and no surviving magenta fringe.
    Raises AssertionError with a specific reason on failure — meant to
    catch the exact 2 regressions this pipeline actually hit during
    development (an emptied-out frame, and a chroma-key fringe) without a
    human re-diffing a composited screenshot every run."""
    arr = np.asarray(square.convert("RGBA")).astype(np.int32)
    a = arr[:, :, 3]
    visible = a > 40
    coverage = visible.sum() / visible.size
    assert coverage > 0.05, (
        f"frame {frame_idx}: only {coverage:.1%} of pixels have visible "
        "alpha — looks like an empty/near-empty frame")

    rgb = arr[:, :, :3]
    dr = rgb[:, :, 0] - KEY[0]
    dg = rgb[:, :, 1] - KEY[1]
    db = rgb[:, :, 2] - KEY[2]
    dist = np.sqrt(dr * dr + dg * dg + db * db)
    closest = dist[visible].min()
    assert closest > 60, (
        f"frame {frame_idx}: a visible pixel sits only {closest:.0f} units "
        "from the magenta key color — looks like a chroma-key fringe "
        "survived")


def main() -> int:
    if not SRC.exists():
        print(f"error: source render not found: {SRC}\n"
              "It lives in the gitignored art_candidates/ scratch dir and "
              "isn't committed — regenerate it with the fal.ai prompt in "
              "this module's docstring before running this script.",
              file=sys.stderr)
        return 1

    img = Image.open(SRC).convert("RGBA")
    w, h = img.size
    hw, hh = w // 2, h // 2

    # The source grid has TWO thin white lines to erase before splitting
    # into quadrants, or they survive chroma-keying (near-white, nowhere
    # near the magenta key) as a straight border bleed: a center "+" divider
    # between the 4 cells, AND a subtler outer picture-frame rectangle
    # inset from the true canvas edges that a corner-only sample missed on
    # the first pass — every cell's bbox reached out to touch it, which is
    # what a "border" on 2 sides of each cropped/resized frame turned out
    # to be. Auto-detected (not hardcoded to this one 1024px render) via
    # find_grid_line_bands(); abort loudly instead of silently mis-cropping
    # a differently-sized or differently-styled regeneration.
    arr = np.asarray(img).copy()
    row_bands, col_bands = find_grid_line_bands(arr)
    if not row_bands or not col_bands:
        print("error: could not find the expected near-white grid-divider "
              f"lines in {SRC} (found {len(row_bands)} row band(s), "
              f"{len(col_bands)} col band(s) — need at least 1 of each). "
              "Refusing to guess; the source render's grid style must have "
              "changed, so re-check it visually before adjusting the "
              "detection thresholds in find_grid_line_bands().",
              file=sys.stderr)
        return 1
    for lo, hi in row_bands:
        arr[lo:hi, :, :] = (*KEY, 255)
    for lo, hi in col_bands:
        arr[:, lo:hi, :] = (*KEY, 255)
    img = Image.fromarray(arr, "RGBA")

    # 2x2 quadrants in reading order -> explosion0..3 (flash, fireball,
    # big fireball, smoke)
    boxes = [
        (0, 0, hw, hh),
        (hw, 0, w, hh),
        (0, hh, hw, h),
        (hw, hh, w, h),
    ]

    SCRATCH_OUT.mkdir(parents=True, exist_ok=True)
    mismatches: list[int] = []
    for i, box in enumerate(boxes):
        cell = img.crop(box)
        cell = chroma_key(cell)
        bbox = cell.getbbox()
        if bbox:
            cell = cell.crop(bbox)
        # pad to square, centered, then resize to OUT_SIZE
        cw, ch = cell.size
        side = max(cw, ch)
        square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        square.paste(cell, ((side - cw) // 2, (side - ch) // 2), cell)
        square = resize_premultiplied(square, (OUT_SIZE, OUT_SIZE))
        assert_frame_is_clean(square, i)

        scratch_path = SCRATCH_OUT / f"frame{i}.png"
        square.save(scratch_path)
        install_path = INSTALL_DIR / f"explosion{i}.png"
        square.save(install_path)

        digest = hashlib.sha256(square.convert("RGBA").tobytes()).hexdigest()
        expected = EXPECTED_SHA256.get(i)
        status = "OK" if digest == expected else "MISMATCH"
        if status == "MISMATCH":
            mismatches.append(i)
        print(f"{scratch_path} -> {install_path}  {square.size}  "
              f"sha256={digest} [{status}]")

    if mismatches:
        print(f"\nerror: frame(s) {mismatches} don't match EXPECTED_SHA256 "
              "at the top of this script. If this is an intentional "
              "pipeline change, re-review the frames (composited over a "
              "real background, not just an isolated checkerboard preview "
              "— see the spec for why that matters) and update "
              "EXPECTED_SHA256 to match.", file=sys.stderr)
        return 1

    print("\nAll 4 frames match the reviewed EXPECTED_SHA256 pixel hashes.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
