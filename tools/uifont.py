#!/usr/bin/env python3
"""A tiny stroke-drawn letterform set for the generated UI chrome.

Why not a TTF: the button captions ("B", "LB", "R2", "ZR") are drawn at 100-250
canvas pixels, where the game's 8px PixelOperator face falls apart, and pulling
in a display font would re-introduce exactly the third-party-licence question
the chrome swap exists to close. Ten letters and two digits drawn as strokes on
a unit box cost less than either and stay crisp at any size.

Glyphs are defined in a 0..1 box (y down). Each entry is a list of polylines;
they are stroked with round caps and joins so the weight reads evenly.
"""
from __future__ import annotations

import math

from PIL import ImageDraw

# Bowls (the round part of B, R, D...) are approximated by dense polylines so a
# single stroke call handles them -- PIL has no thick-arc-with-round-caps.
def _arc(cx, cy, rx, ry, a0, a1, n=14):
    return [(cx + math.cos(math.radians(a0 + (a1 - a0) * i / n)) * rx,
             cy + math.sin(math.radians(a0 + (a1 - a0) * i / n)) * ry)
            for i in range(n + 1)]


GLYPHS: dict[str, list[list[tuple[float, float]]]] = {
    "A": [[(0.04, 1.0), (0.5, 0.0), (0.96, 1.0)], [(0.22, 0.66), (0.78, 0.66)]],
    "B": [[(0.12, 0.0), (0.12, 1.0)],
          [(0.12, 0.0), (0.52, 0.0)] + _arc(0.52, 0.25, 0.36, 0.25, -90, 90) + [(0.12, 0.5)],
          [(0.12, 0.5), (0.56, 0.5)] + _arc(0.56, 0.75, 0.38, 0.25, -90, 90) + [(0.12, 1.0)]],
    "L": [[(0.16, 0.0), (0.16, 1.0), (0.92, 1.0)]],
    "R": [[(0.12, 0.0), (0.12, 1.0)],
          [(0.12, 0.0), (0.54, 0.0)] + _arc(0.54, 0.27, 0.38, 0.27, -90, 90) + [(0.12, 0.54)],
          [(0.46, 0.54), (0.94, 1.0)]],
    "T": [[(0.04, 0.02), (0.96, 0.02)], [(0.5, 0.02), (0.5, 1.0)]],
    "X": [[(0.06, 0.0), (0.94, 1.0)], [(0.94, 0.0), (0.06, 1.0)]],
    "Y": [[(0.06, 0.0), (0.5, 0.52)], [(0.94, 0.0), (0.5, 0.52)], [(0.5, 0.52), (0.5, 1.0)]],
    "Z": [[(0.08, 0.02), (0.92, 0.02), (0.08, 0.98), (0.92, 0.98)]],
    "1": [[(0.22, 0.22), (0.54, 0.0), (0.54, 1.0)], [(0.18, 1.0), (0.92, 1.0)]],
    "2": [_arc(0.5, 0.3, 0.42, 0.3, 180, 360) + [(0.08, 1.0), (0.94, 1.0)]],
    "3": [_arc(0.5, 0.25, 0.38, 0.25, 180, 450)[:11],
          _arc(0.5, 0.74, 0.40, 0.26, 270, 540)[:12]],
    "4": [[(0.72, 0.0), (0.10, 0.68), (0.94, 0.68)], [(0.72, 0.36), (0.72, 1.0)]],
    "5": [[(0.86, 0.02), (0.20, 0.02), (0.16, 0.44)] + _arc(0.50, 0.70, 0.40, 0.30, 250, 430)],
    "-": [[(0.12, 0.5), (0.88, 0.5)]],
    "+": [[(0.5, 0.06), (0.5, 0.94)], [(0.06, 0.5), (0.94, 0.5)]],
}

# Per-glyph advance width in units of `size`. Narrow marks get less room.
ADVANCE = {"1": 0.72, "-": 0.80, "+": 0.86}


def text_width(s: str, size: float, tracking: float = 0.14) -> float:
    if not s:
        return 0.0
    w = sum(ADVANCE.get(c, 0.86) * size for c in s)
    return w + tracking * size * (len(s) - 1)


def draw_text(d: ImageDraw.ImageDraw, cx: float, cy: float, s: str, size: float,
              fill, weight: float = 0.20, tracking: float = 0.14) -> None:
    """Draw `s` centred on (cx, cy). `size` is the cap height in pixels."""
    total = text_width(s, size, tracking)
    x = cx - total / 2
    y = cy - size / 2
    w = max(1, int(size * weight))
    for ch in s:
        adv = ADVANCE.get(ch, 0.86) * size
        for poly in GLYPHS[ch]:
            pts = [(x + px * adv, y + py * size) for px, py in poly]
            if len(pts) == 1:
                continue
            d.line(pts, fill=fill, width=w, joint="curve")
            # round caps: PIL's line has none, so stamp the endpoints
            for ex, ey in (pts[0], pts[-1]):
                d.ellipse([ex - w / 2, ey - w / 2, ex + w / 2, ey + w / 2], fill=fill)
        x += adv + tracking * size
