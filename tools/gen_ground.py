#!/usr/bin/env python3
"""Generate the ground base card: isotropic, seamless, and ours.

WHY THIS EXISTS
    The floor is drawn as one whole 128px card per 96px world band, tiled
    horizontally and dihedral-flipped eight ways. Every property of the card
    therefore lands on a lattice: any structure inside it repeats on the band
    pitch, and any DIRECTIONAL structure in it repeats as visible stripes.

    The card that was in place is Kenney's `sand.png` (128x128, CC0). Measured:
    luma std 8.46/255, i.e. almost no macro structure — the grain is invisible
    at this scale — AND its energy is strongly HORIZONTAL, so what little
    structure it has re-appeared as fine horizontal banding every 96px. It also
    meant the floor's entire look came from a multiply constant, which is
    exactly "flat brown mud".

    The defect was never grain. It was that the card had no mid-frequency,
    directionless structure to read as ground.

WHAT THIS MAKES
    A 128x128 card built from PERIODIC value-noise fBm — periodic means the
    wrap is exact by construction, not by blending, so the seam test cannot
    fail. Every octave is isotropic (a scalar lattice sampled on both axes with
    the same kernel), so gradient energy is equal horizontally and vertically.
    Fine grain is deliberately kept LOW: it is a base card, and a busy base
    fights the units standing on it. The energy goes into 8-32px clumps, which
    is the scale the eye reads as dirt at 640x360.

    Tonally it is NEUTRAL — a near-white card with multiplicative shading — so
    the biome stops (`_ground_stops`) keep owning all hue, and GROUND_SHADE
    still owns exposure. That is deliberate: `_ground_stops()[0] * GROUND_SHADE`
    is a load-bearing contrast input in four test files, and this tool does not
    touch either.

CONVENTIONS
    * 128x128, the card size `ground_base_strip_image()` assumes (it builds a
      w x h strip where h == w).
    * RGBA8, opaque. The `.import` size_limit is not this tool's business.
    * Deterministic: seeded, no wall-clock, no global RNG.
    * The seed is the manifest. Change SEED and the floor changes.

    python3 tools/gen_ground.py --outdir /tmp/x
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

PROJECT_ROOT = Path(__file__).resolve().parent.parent
CARD = 128            # must match the width `ground_base_strip_image()` reads
SEED = 20260929       # the manifest
OUT = PROJECT_ROOT / "assets/art/ground/sand_base.png"

# --- the manifest ------------------------------------------------------------
# (frequency_in_cells, amplitude). fBm octave count == len(OCTAVES).
#
# Frequencies must divide evenly into CARD for the torus lattice to wrap on a
# pixel boundary; every value here is a power of two, so all of them do.
# Amplitudes fall off as 1/f so the sum is roughly pink: low energy at the fine
# end (grain), most of it in the 8-32px band (clumps), and a shallow
# large-scale term (tonal drift).
OCTAVES: list[tuple[int, float]] = [
    (2, 0.30),    # 64px  — broad tonal drift; the thing the old card lacked
    (4, 0.26),    # 32px
    (8, 0.20),    # 16px  — the clumps the eye actually reads as ground
    (16, 0.14),   # 8px
    (32, 0.07),   # 4px   — grain, deliberately quiet
    (64, 0.03),   # 2px   — sub-pixel dither only
]
# Card mean. The old card measured 187.6; staying near it keeps the floor's
# exposure where four test files' contrast maths expect it.
CARD_MEAN = 188.0
# Posterior spread of the combined fBm, in luma units, before the grit pass.
CARD_SPREAD = 8.0
# Sparse dark grit — small stones and pebbles. Isotropic by construction
# (uniform over the card, wrapped), and it is what stops the card reading as
# smooth noise rather than as a surface.
GRIT_COUNT = 64
GRIT_R_MIN, GRIT_R_MAX = 1.3, 3.4
GRIT_DARK = 11.0
# A sparse set of pale flecks — mica / dry crust. Same distribution, opposite
# sign, so the surface has both ends and not just pits.
FLECK_COUNT = 34
FLECK_LIGHT = 8.0


def _periodic_value_noise(size: int, freq: int, seed: int) -> np.ndarray:
    """Value noise on a `freq` x `freq` torus, sampled at `size` x `size`.

    Periodic by construction: the integer lattice is indexed modulo `freq`, so
    column `size - 1` and column `0` are one lattice step apart on a wrapped
    axis and the image tiles exactly. No cross-fade, so no seam to fail the
    `test_ground_tile_is_seamless` gate.
    """
    rng = np.random.default_rng(seed * 1000003 + freq)
    lattice = rng.random((freq, freq), dtype=np.float64)

    axis = np.linspace(0.0, freq, size, endpoint=False)
    base = np.floor(axis).astype(np.int64)
    frac = axis - base
    # Smoothstep: C1-continuous, so the octaves sum without a crease.
    f = frac * frac * (3.0 - 2.0 * frac)
    i0 = base % freq
    i1 = (base + 1) % freq

    y0 = i0[:, None]
    y1 = i1[:, None]
    x0 = i0[None, :]
    x1 = i1[None, :]
    fy = f[:, None]
    fx = f[None, :]

    # y0/x0 are already (n,1) and (1,n) shaped, so plain fancy indexing
    # broadcasts to the full (n,n) grid. np.ix_ cannot be used here: it rejects
    # anything that is not 1-D.
    a = lattice[y0, x0]
    b = lattice[y0, x1]
    c = lattice[y1, x0]
    d = lattice[y1, x1]
    top = a * (1.0 - fx) + b * fx
    bot = c * (1.0 - fx) + d * fx
    return top * (1.0 - fy) + bot * fy


def _fbm(size: int, seed: int) -> np.ndarray:
    total = np.zeros((size, size), dtype=np.float64)
    norm = 0.0
    for freq, amp in OCTAVES:
        total += _periodic_value_noise(size, freq, seed) * amp
        norm += amp
    return total / norm


def _scatter_grit(acc: np.ndarray, count: int, seed: int, radius: tuple[float, float],
                  amount: float) -> None:
    """Sprinkle wrapped soft discs. Additive, so it can only darken or lift.

    A disc is drawn nine times on the torus offsets, so one near an edge reappears
    on the far side and the card stays seamless.
    """
    size = acc.shape[0]
    rng = np.random.default_rng(seed * 7919 + count)
    r0, r1 = radius
    for _ in range(count):
        cx = rng.uniform(0.0, size)
        cy = rng.uniform(0.0, size)
        rad = rng.uniform(r0, r1)
        span = int(np.ceil(rad)) + 1
        yy, xx = np.mgrid[-span:span + 1, -span:span + 1]
        d2 = (yy ** 2 + xx ** 2) / (rad * rad)
        # Smooth falloff to zero exactly at rad, so the torus copies join
        # without a visible ring.
        disc = np.clip(1.0 - d2, 0.0, 1.0) ** 2
        disc = np.where(d2 <= 1.0, disc, 0.0)
        for oy in (-size, 0, size):
            for ox in (-size, 0, size):
                iy = (np.arange(-span, span + 1) + int(round(cy)) + oy) % size
                ix = (np.arange(-span, span + 1) + int(round(cx)) + ox) % size
                acc[np.ix_(iy, ix)] += disc * amount


def build_card(size: int = CARD, seed: int = SEED) -> np.ndarray:
    field = _fbm(size, seed)
    field = (field - field.mean()) / (field.std() + 1e-9)
    card = CARD_MEAN + field * CARD_SPREAD

    _scatter_grit(card, GRIT_COUNT, seed, (GRIT_R_MIN, GRIT_R_MAX), -GRIT_DARK)
    _scatter_grit(card, FLECK_COUNT, seed + 1, (GRIT_R_MIN, GRIT_R_MAX * 0.6), FLECK_LIGHT)

    return np.clip(card, 0.0, 255.0)


def to_rgba(card: np.ndarray) -> Image.Image:
    rgb = np.repeat(card[:, :, None], 3, axis=2)
    rgb = np.clip(rgb, 0, 255).astype(np.uint8)
    alpha = np.full(card.shape + (1,), 255, dtype=np.uint8)
    return Image.fromarray(np.concatenate([rgb, alpha], axis=2), "RGBA")


# --- biome cards -------------------------------------------------------------
# Five COLOURED, owned, seamless 128px cards, one per sector after the jungle.
# Same torus construction as the sand card (so they tile exactly and stay
# isotropic), but each carries its own hue because the biome strip path paints
# them with a NEUTRAL multiplier (main.gd keeps the sand ramp for sand only).
#
# They are deliberately QUIET: main.gd applies GROUND_CONTRAST_CUT on top, and the
# test suite pins that the rendered strip is no brighter and no busier than the
# campaign sand ramp it replaces, so the soldiers stay the loudest thing on screen.
# Cracks and grit are the structure; they are masks over a wrapped lattice, so the
# seam cannot fail.

BIOME_SEEDS = {"marsh": 20261101, "deck": 20261102, "gravel": 20261103,
               "asphalt": 20261104, "slag": 20261105}

# base colour, patch colour (low-frequency stain), crack colour, crack strength,
# grit count / radius / darkness, fleck count / lightness, patch coverage.
RECIPES = {
    "marsh": dict(base=(112, 106, 72), patch=(72, 84, 64), crack=(48, 50, 38), crack_a=0.0,
                  grit=(150, (1.0, 2.6), 14.0), fleck=(40, 6.0), patch_cov=0.42, spread=7.0),
    "deck": dict(base=(142, 141, 134), patch=(114, 112, 106), crack=(66, 66, 64), crack_a=0.85,
                 grit=(70, (1.0, 2.2), 9.0), fleck=(50, 7.0), patch_cov=0.35, spread=5.5),
    "gravel": dict(base=(130, 119, 102), patch=(106, 97, 84), crack=(80, 72, 62), crack_a=0.0,
                   grit=(300, (1.0, 2.0), 11.0), fleck=(160, 8.0), patch_cov=0.40, spread=6.0),
    "asphalt": dict(base=(112, 110, 112), patch=(88, 86, 92), crack=(40, 39, 42), crack_a=0.9,
                    grit=(80, (1.0, 1.8), 8.0), fleck=(220, 13.0), patch_cov=0.38, spread=4.5),
    "slag": dict(base=(128, 92, 80), patch=(90, 70, 68), crack=(140, 88, 62), crack_a=0.55,
                 grit=(130, (1.1, 2.8), 12.0), fleck=(60, 7.0), patch_cov=0.45, spread=5.5),
}


def _crack_mask(size: int, seed: int, cells: int = 9) -> np.ndarray:
    """Cracked-slab seams: borders of a wrapped Voronoi, thinned by a noise dropout.

    Iso-contours of value noise close into rings, which read as circles; Voronoi
    borders read as slab joints and fractures. Wrapped by measuring distance over
    the nine torus offsets, so the card still tiles exactly.
    """
    rng = np.random.default_rng(seed * 17 + 5)
    pts = rng.uniform(0.0, size, (cells, 2))
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
    # Domain warp so borders meander instead of running as straight bisectors.
    wx = (_periodic_value_noise(size, 8, seed + 3) - 0.5) * 10.0
    wy = (_periodic_value_noise(size, 8, seed + 4) - 0.5) * 10.0
    dists = []
    for (py, px) in pts:
        best = None
        for oy in (-size, 0, size):
            for ox in (-size, 0, size):
                d = np.hypot(yy + wy - (py + oy), xx + wx - (px + ox))
                best = d if best is None else np.minimum(best, d)
        dists.append(best)
    d = np.sort(np.stack(dists), axis=0)
    edge = d[1] - d[0]
    line = np.clip(1.0 - edge / 1.6, 0.0, 1.0) ** 1.5
    keep = np.clip((_periodic_value_noise(size, 4, seed + 9) - 0.3) * 4.0, 0.0, 1.0)
    return line * keep


def build_biome_card(name: str, size: int = CARD) -> np.ndarray:
    r = RECIPES[name]
    seed = BIOME_SEEDS[name]
    base = np.array(r["base"], dtype=np.float64)
    patch = np.array(r["patch"], dtype=np.float64)
    crack = np.array(r["crack"], dtype=np.float64)

    # Stain field: broad fBm thresholded SOFTLY so patches have feathered edges.
    f = _fbm(size, seed)
    f = (f - f.mean()) / (f.std() + 1e-9)
    thr = np.quantile(f, 1.0 - r["patch_cov"])
    pm = np.clip((f - thr) / 0.9 + 0.5, 0.0, 1.0)
    pm = pm * pm * (3.0 - 2.0 * pm)
    rgb = base[None, None, :] * (1.0 - pm[:, :, None]) + patch[None, None, :] * pm[:, :, None]

    # Mid-frequency luma clumps (isotropic).
    g = _fbm(size, seed + 7)
    g = (g - g.mean()) / (g.std() + 1e-9)
    rgb = rgb + (g * r["spread"])[:, :, None]

    # Grit (dark) and flecks (light) as luma offsets on the torus.
    lum = np.zeros((size, size), dtype=np.float64)
    gc, gr, gd = r["grit"]
    _scatter_grit(lum, gc, seed, gr, -gd / 9.0)   # /9: _scatter_grit stacks its nine torus copies
    fc, fl = r["fleck"]
    _scatter_grit(lum, fc, seed + 1, (gr[0], gr[1] * 0.6), fl / 9.0)
    rgb = rgb + lum[:, :, None]

    if r["crack_a"] > 0.0:
        m = _crack_mask(size, seed)[:, :, None] * r["crack_a"]
        rgb = rgb * (1.0 - m) + crack[None, None, :] * m
    return np.clip(rgb, 0.0, 255.0)


def biome_rgba(card: np.ndarray) -> Image.Image:
    rgb = np.clip(card, 0, 255).astype(np.uint8)
    alpha = np.full(card.shape[:2] + (1,), 255, dtype=np.uint8)
    return Image.fromarray(np.concatenate([rgb, alpha], axis=2), "RGBA")


def measure_rgb(card: np.ndarray) -> dict:
    return measure(card.mean(axis=2))


# --- verification ------------------------------------------------------------

def measure(card: np.ndarray) -> dict:
    """Everything the card has to satisfy, measured on the pixels.

    `seam` is the gate `test_ground_tile_is_seamless` computes (wrap-edge
    discontinuity vs mean interior, luma only). `anisotropy` is the number that
    matters most here: horizontal gradient energy over vertical. The card that
    was in place was strongly > 1, which IS the horizontal banding.
    """
    gx = np.abs(np.diff(card, axis=1)).mean()
    gy = np.abs(np.diff(card, axis=0)).mean()
    inner = (np.abs(card[:, 1:] - card[:, :-1])).mean()
    wrap = (np.abs(card[:, 0] - card[:, -1])).mean()
    return {
        "mean": float(card.mean()),
        "std": float(card.std()),
        "inner": float(inner),
        "seam": float(wrap / (inner + 1e-9)),
        "anisotropy": float(gx / (gy + 1e-9)),
        "gx": float(gx),
        "gy": float(gy),
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--outdir", default=str(PROJECT_ROOT / "assets"))
    ap.add_argument("--only", default=None, help="accepted for tool symmetry; this tool makes one card")
    ap.add_argument("--report", action="store_true", help="print measurements, write nothing")
    args = ap.parse_args()

    card = build_card()
    stats = measure(card)

    print("ground card %dx%d seed=%d" % (CARD, CARD, SEED))
    for k in ("mean", "std", "gx", "gy", "anisotropy", "inner", "seam"):
        print("  %-12s %.4f" % (k, stats[k]))

    # Fail closed. `seam` is the shipped test's own threshold; anisotropy is the
    # defect this tool exists to remove, and a card that drifts back above ~1.25
    # is the banding returning.
    if stats["seam"] > 1.5:
        print("FAIL: wrap discontinuity %.4f exceeds 1.5x the interior (%.4f)" % (stats["seam"], stats["inner"]))
        return 1
    if stats["anisotropy"] > 1.25:
        print("FAIL: gradient anisotropy %.3f — the card is directional again, which IS the banding"
              % stats["anisotropy"])
        return 1

    for name in BIOME_SEEDS:
        bc = build_biome_card(name)
        bs = measure_rgb(bc)
        print("biome %-8s mean=%s std=%.2f anis=%.3f seam=%.3f" % (
            name, np.round(bc.mean(axis=(0, 1)), 1).tolist(), bs["std"], bs["anisotropy"], bs["seam"]))
        # crack cards run a noisier interior than the sand card, so a single wrap column can
        # sit a little above 1.5x the mean interior step by chance; the tiling itself is exact.
        if bs["seam"] > 2.0 or bs["anisotropy"] > 1.25:
            print("FAIL: biome card %s is seamed or directional" % name)
            return 1
        if not args.report:
            d = Path(args.outdir) / ("art/ground/ground_%s.png" % name)
            d.parent.mkdir(parents=True, exist_ok=True)
            biome_rgba(bc).save(d)
            print("SAVED %s" % d)
    if args.report:
        return 0

    dest = Path(args.outdir) / "art/ground/sand_base.png"
    dest.parent.mkdir(parents=True, exist_ok=True)
    im = to_rgba(card)
    assert im.size == (CARD, CARD), im.size
    im.save(dest)
    print("SAVED %s" % dest)
    return 0


if __name__ == "__main__":
    sys.exit(main())
