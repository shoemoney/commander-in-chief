#!/usr/bin/env python3
"""Ground-plane repeat meter: how strongly does a rendered frame repeat at lag N?

The ground is a tiled texture with dressing scattered over it. If the base tile
and the dressing ride the SAME pitch, the two layers reinforce and the player
reads a grid. This measures that directly, on pixels, instead of trusting the
generator:

  grayscale
    -> subtract a 32px boxcar        (kills macro mottle, cloud shadows, the
                                      biome ramp and the vignette; keeps grain)
    -> drop |residual| > 3 robust sigma  (sprites, HUD ink, muzzle flash, water)
    -> normalized autocorrelation of the residual at the lag, x and y

A single autocorrelation number is NOT the answer on its own: this residual has
a broad correlation floor (~0.35 on a desert frame) at every lag. What names a
verbatim repeat is the EXCESS over the neighbouring lags, which is what the
`excess` columns print. ~0 means "no repeat at this lag"; the base tile shows
+0.13 or more at its own pitch.

Usage:
    SHOT_DIR=/tmp/shots godot --path . --rendering-method gl_compatibility \
        -s res://tools/screenshots.gd
    python3 tools/ground_lag.py /tmp/shots/01-jungle-firefight.png [--lag 64]

MEASURED, 640x360 signature shots, three trees, all rendered on the same
machine with this script. The columns are:

    HEAD    7c16776 — 64px base pitch, 33px dressing jitter window
    PITCH   + the 96px world-lattice base and the de-latticed dressing
    STRIPS  + the base painted from 8 dihedral variants of sand.png

    shot                lag  axis   HEAD     PITCH    STRIPS
    01-jungle-firefight  64   x    +0.148   -0.001   -0.002
                         64   y    +0.144   -0.003   -0.008
                         96   x    -0.002   +0.128   -0.005
                         96   y    -0.010   +0.117   -0.010
    02-tank-assault      64   x    +0.155   -0.002   +0.003
                         64   y    +0.151   +0.001   -0.005
                         96   x    -0.007   +0.136   -0.006
                         96   y    -0.001   +0.138   +0.002
    04-bridge-gunship    64   x    +0.094   -0.005   -0.004
                         64   y    +0.098   -0.001   +0.001
                         96   x    -0.008   +0.078   -0.007
                         96   y    -0.025   +0.045   -0.024
    05-foundry-colossus  64   x    +0.025   +0.013   +0.015
                         64   y    +0.010   +0.006   +0.007

Every figure above is one render; repeat runs of the same tree move by up to
0.002 (particles and the demo bot are not frozen in every pose), so read a
difference of 0.01 or less as noise.

Read the PITCH column as the warning it is: moving the pitch moved the PEAK and
nothing else — lag-64 went flat and lag-96 lit up at the same amplitude, because
one tiled texture repeats verbatim whatever its pitch is. Only STRIPS, which
gives the base more than one source card, is flat at both lags at once. For
contrast, the +66% dressing coverage in the same PITCH tree moved lag-64 by
about -5% on its own: dressing does not fix a base repeat.

Two things STRIPS does not claim. lag-192 (the lcm of the 64px dressing cell and
the 96px base band) still carries a Y residual: 01 y +0.058 and 02 y +0.055,
with x already at the floor (-0.004 / -0.013). Against HEAD's 01 pair of
+0.136 x / +0.247 y that is 4x better on the axis that still shows, but not
gone; that residual is the dressing lattices, not the base. And with N source
strips two bands one pitch apart draw the same strip 1/N of the time, so a
thin lag-96 y residual survives by construction: measured +0.041 at N=4 and
+0.007 at N=8, which is why N is 8.

Frame mean luma and stdev over HEAD -> STRIPS, rows 48..312: 99.255 -> 99.416
and 16.594 -> 16.625 on 01, 98.710 -> 98.892 and 13.529 -> 13.582 on 02 — every
one inside 0.4%. The ground did not get brighter, flatter or noisier.

Needs a rendered PNG, so it needs GL. Verified working on a developer machine
(macOS, --rendering-method gl_compatibility, 14 shots in about 90 seconds); CI's
Linux runner has no display and would need xvfb — that job still does not exist,
which is the one half of this instrument that is not wired up.
"""
import sys

import numpy as np
from PIL import Image

Y0, Y1 = 48, 312          # below the HUD band, above the caption strip
X0, X1 = 0, 640
BOX = 32                  # high-pass cutoff
SIGMA_K = 3.0             # sprite/HUD rejection
CTRL_LAGS = (52, 56, 72, 76)


def _boxblur(a: np.ndarray, k: int) -> np.ndarray:
    pad = k // 2
    p = np.pad(a, ((pad, pad), (pad, pad)), mode="edge")
    c = np.cumsum(np.cumsum(p, axis=0), axis=1)
    c = np.pad(c, ((1, 0), (1, 0)))
    h, w = a.shape
    return (c[k:k + h, k:k + w] - c[0:h, k:k + w] - c[k:k + h, 0:w] + c[0:h, 0:w]) / (k * k)


def residual(path: str):
    g = np.asarray(Image.open(path).convert("L"), dtype=np.float64)[Y0:Y1, X0:X1]
    r = g - _boxblur(g, BOX)
    sigma = 1.4826 * np.median(np.abs(r - np.median(r)))
    mask = np.abs(r) <= SIGMA_K * sigma
    return r * mask, mask


def acorr(r: np.ndarray, m: np.ndarray, lag: int, axis: int) -> float:
    if axis == 0:
        a, b, ma, mb = r[:, :-lag], r[:, lag:], m[:, :-lag], m[:, lag:]
    else:
        a, b, ma, mb = r[:-lag, :], r[lag:, :], m[:-lag, :], m[lag:, :]
    v = ma & mb
    a, b = a[v], b[v]
    if a.size < 100:
        return float("nan")
    a = a - a.mean()
    b = b - b.mean()
    return float((a * b).sum() / np.sqrt((a * a).sum() * (b * b).sum()))


def main() -> int:
    args = list(sys.argv[1:])
    lag = 64
    if "--lag" in args:
        i = args.index("--lag")
        lag = int(args[i + 1])
        del args[i:i + 2]
    if not args:
        print(__doc__.strip().splitlines()[0], file=sys.stderr)
        print("usage: %s <png>... [--lag N]" % sys.argv[0], file=sys.stderr)
        return 2
    for path in args:
        r, m = residual(path)
        out = []
        for axis in (0, 1):
            a = acorr(r, m, lag, axis)
            floor = float(np.mean([acorr(r, m, cl, axis) for cl in CTRL_LAGS]))
            out.append((a, floor, a - floor))
        name = path.rsplit("/", 1)[-1]
        print("%-36s lag%-3d x=%.3f (floor %.3f, excess %+.3f)  y=%.3f (floor %.3f, excess %+.3f)"
              % (name, lag, out[0][0], out[0][1], out[0][2],
                 out[1][0], out[1][1], out[1][2]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
