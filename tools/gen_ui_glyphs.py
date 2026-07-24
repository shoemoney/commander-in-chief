#!/usr/bin/env python3
"""Procedurally generate the assets/art/ui/glyphs/ input prompts.

Bucket 3 of the chrome swap, and the one with an extra constraint. The sprites
being replaced are console button art, and the licence problem does NOT get
solved by drawing a closer lookalike -- copying a platform holder's face-button
iconography trades a copyright question for a trademark one.

So this set is deliberately a HOUSE ABSTRACTION rather than a reproduction:

  * one plate for every platform -- an off-white rounded key cap with an ink
    keyline, the same plate as ui/key_blank.
  * the caption is a letter or a basic geometric mark stroked from
    tools/uifont.py: "A", "LB", "R2", "ZR", "+", "-", a cross, a ring, a square,
    a triangle. Geometric primitives and letters carry the meaning a player
    needs to find the right button; none of them is anyone's badge.
  * no vendor colour coding is reproduced.

The per-platform filenames stay, so the input layer keeps picking the right set
per device and no draw site moves.

  * SIZES is the manifest -- one entry per file this tool owns.
  * each sprite keeps its ORIGINAL canvas size.

    python3 tools/gen_ui_glyphs.py
    python3 tools/gen_ui_glyphs.py --outdir /tmp/x --only ui/glyphs/pad_a
"""
from __future__ import annotations

import argparse
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

from uifont import draw_text, text_width

PROJECT_ROOT = Path(__file__).resolve().parent.parent
ART = PROJECT_ROOT / "assets/art"

SS = 3

PLATE = (246, 244, 238)
PLATE_D = (206, 204, 196)
INK = (34, 36, 32)

SIZES = {
    "ui/glyphs/dpad_lr": (256, 256),
    "ui/glyphs/key_enter": (256, 256),
    "ui/glyphs/key_space": (360, 256),
    "ui/glyphs/key_wide": (512, 512),
    "ui/glyphs/mouse_l": (256, 256),
    "ui/glyphs/mouse_r": (256, 256),
    "ui/glyphs/pad_a": (256, 256),
    "ui/glyphs/pad_lb": (256, 256),
    "ui/glyphs/pad_rt": (256, 256),
    "ui/glyphs/pad_start": (256, 256),
    "ui/glyphs/ps_a": (256, 256),
    "ui/glyphs/ps_b": (256, 256),
    "ui/glyphs/ps_back": (256, 256),
    "ui/glyphs/ps_dpad_lr": (256, 256),
    "ui/glyphs/ps_lb": (256, 256),
    "ui/glyphs/ps_rt": (256, 256),
    "ui/glyphs/ps_start": (256, 256),
    "ui/glyphs/ps_x": (256, 256),
    "ui/glyphs/ps_y": (256, 256),
    "ui/glyphs/stick_l": (256, 256),
    "ui/glyphs/stick_r": (256, 256),
    "ui/glyphs/sw_a": (256, 256),
    "ui/glyphs/sw_b": (256, 256),
    "ui/glyphs/sw_back": (256, 256),
    "ui/glyphs/sw_dpad_lr": (256, 256),
    "ui/glyphs/sw_lb": (256, 256),
    "ui/glyphs/sw_rt": (256, 256),
    "ui/glyphs/sw_start": (256, 256),
    "ui/glyphs/sw_x": (256, 256),
    "ui/glyphs/sw_y": (256, 256),
}


class Pad:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.W, self.H = w * SS, h * SS
        self.im = Image.new("RGBA", (self.W, self.H), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.im)

    def rrect(self, x0, y0, x1, y1, r, fill):
        self.d.rounded_rectangle([x0 * self.W, y0 * self.H, x1 * self.W, y1 * self.H],
                                 radius=max(1, int(r * min(self.W, self.H))), fill=fill)

    def ell(self, cx, cy, rx, ry, fill=None, outline=None, width=0.0):
        self.d.ellipse([(cx - rx) * self.W, (cy - ry) * self.H,
                        (cx + rx) * self.W, (cy + ry) * self.H],
                       fill=fill, outline=outline,
                       width=max(1, int(width * self.W)) if width else 1)

    def poly(self, pts, fill=None, outline=None, width=0.0):
        self.d.polygon([(x * self.W, y * self.H) for x, y in pts], fill=fill,
                       outline=outline, width=max(1, int(width * self.W)) if width else 1)

    def line(self, pts, fill, width):
        self.d.line([(x * self.W, y * self.H) for x, y in pts], fill=fill,
                    width=max(1, int(width * self.W)), joint="curve")

    def text(self, cx, cy, s, size, fill=INK, weight=0.19):
        draw_text(self.d, cx * self.W, cy * self.H, s, size * self.W, fill, weight)

    def keyline(self, strength=0.022):
        a = self.im.getchannel("A")
        grown = a.filter(ImageFilter.MaxFilter(max(3, int(self.W * strength) | 1)))
        rim = Image.new("RGBA", (self.W, self.H), INK + (0,))
        rim.putalpha(grown)
        rim.alpha_composite(self.im)
        self.im = rim
        self.d = ImageDraw.Draw(self.im)

    def out(self, blur=0.35):
        im = self.im.filter(ImageFilter.GaussianBlur(blur * SS * 0.5)) if blur else self.im
        return im.resize((self.w, self.h), Image.LANCZOS)


# --- plates ------------------------------------------------------------------
def round_plate(p):
    p.ell(0.5, 0.5, 0.45, 0.45, fill=PLATE_D)
    p.ell(0.5, 0.475, 0.45, 0.45, fill=PLATE)


def cap_plate(p, x0=0.06, x1=0.94, y0=0.14, y1=0.86, r=0.15):
    p.rrect(x0, y0 + 0.03, x1, y1, r, PLATE_D)
    p.rrect(x0, y0, x1, y1 - 0.03, r, PLATE)


def _fit(s: str, box: float) -> float:
    """Shrink the caption until it fits `box` of plate width."""
    size = 0.40
    while text_width(s, size) > box and size > 0.10:
        size -= 0.01
    return size


# --- captions ----------------------------------------------------------------
def cap_round(p, s):
    round_plate(p)
    p.text(0.5, 0.475, s, _fit(s, 0.62), INK)
    p.keyline()


def cap_key(p, s):
    cap_plate(p)
    p.text(0.5, 0.48, s, _fit(s, 0.66), INK)
    p.keyline()


def mark_cross(p):
    round_plate(p)
    p.line([(0.34, 0.32), (0.66, 0.63)], INK, 0.075)
    p.line([(0.66, 0.32), (0.34, 0.63)], INK, 0.075)
    p.keyline()


def mark_ring(p):
    round_plate(p)
    p.ell(0.5, 0.475, 0.17, 0.17, outline=INK, width=0.072)
    p.keyline()


def mark_square(p):
    round_plate(p)
    p.d.rectangle([0.33 * p.W, 0.305 * p.H, 0.67 * p.W, 0.645 * p.H],
                  outline=INK, width=max(1, int(0.072 * p.W)))
    p.keyline()


def mark_triangle(p):
    round_plate(p)
    p.poly([(0.5, 0.29), (0.69, 0.63), (0.31, 0.63)], outline=INK, width=0.072)
    p.keyline()


def mark_bars(p):
    """Generic 'menu' mark -- three stacked bars."""
    round_plate(p)
    for i in range(3):
        y = 0.36 + i * 0.115
        p.line([(0.33, y), (0.67, y)], INK, 0.062)
    p.keyline()


def mark_plate_outline(p):
    """Generic 'select' mark -- an empty plate outline."""
    round_plate(p)
    p.d.rounded_rectangle([0.31 * p.W, 0.345 * p.H, 0.69 * p.W, 0.605 * p.H],
                          radius=int(0.06 * p.W), outline=INK,
                          width=max(1, int(0.060 * p.W)))
    p.keyline()


# --- devices -----------------------------------------------------------------
def dpad_lr(p):
    """Horizontal d-pad: the left/right arms called out, the cross implied."""
    a = 0.115
    p.rrect(0.5 - a, 0.10, 0.5 + a, 0.90, 0.05, PLATE_D)
    p.rrect(0.10, 0.5 - a, 0.90, 0.5 + a, 0.05, PLATE_D)
    p.rrect(0.5 - a, 0.085, 0.5 + a, 0.885, 0.05, PLATE)
    p.rrect(0.10, 0.485 - a, 0.90, 0.485 + a, 0.05, PLATE)
    for sx in (-1, 1):
        cx = 0.5 + sx * 0.30
        p.poly([(cx + sx * 0.085, 0.485), (cx - sx * 0.045, 0.485 - 0.075),
                (cx - sx * 0.045, 0.485 + 0.075)], fill=INK)
    p.keyline()


def stick(p, side: str):
    p.ell(0.5, 0.53, 0.34, 0.34, fill=PLATE_D)      # base
    p.ell(0.5, 0.50, 0.34, 0.34, fill=PLATE)
    p.ell(0.5, 0.50, 0.20, 0.20, fill=PLATE_D)      # thumb dish
    p.text(0.5, 0.50, side, 0.24, INK)
    p.keyline()


def mouse(p, button: str):
    p.rrect(0.20, 0.10, 0.80, 0.92, 0.30, PLATE_D)
    p.rrect(0.20, 0.07, 0.80, 0.89, 0.30, PLATE)
    # split the two front buttons; fill the pressed one
    p.line([(0.5, 0.09), (0.5, 0.44)], PLATE_D, 0.030)
    p.line([(0.22, 0.44), (0.78, 0.44)], PLATE_D, 0.030)
    # Fill the pressed button on its own layer and clip it to the body silhouette --
    # an unclipped pieslice spills past the shell and reads as a pie chart.
    body = p.im.getchannel("A")
    lay = Image.new("RGBA", (p.W, p.H), (0, 0, 0, 0))
    ld = ImageDraw.Draw(lay)
    # centred on the button split (0.5, 0.44) and deliberately OVERSIZED so the
    # wedge overshoots the shell on every side; the clip below trims it exactly.
    box = [-0.10 * p.W, (0.44 - 0.60) * p.H, 1.10 * p.W, (0.44 + 0.60) * p.H]
    ld.pieslice(box, 180, 270, fill=INK) if button == "l" else \
        ld.pieslice(box, 270, 360, fill=INK)
    lay.putalpha(ImageChops.darker(lay.getchannel("A"), body))
    p.im.alpha_composite(lay)
    p.d = ImageDraw.Draw(p.im)
    p.keyline()


def key_enter(p):
    cap_plate(p)
    # return arrow: down the riser, then left into the head
    p.line([(0.70, 0.30), (0.70, 0.56), (0.34, 0.56)], INK, 0.060)
    p.poly([(0.24, 0.56), (0.42, 0.45), (0.42, 0.67)], fill=INK)
    p.keyline()


def key_blank_wide(p):
    cap_plate(p, x0=0.04, x1=0.96, y0=0.20, y1=0.80, r=0.09)
    p.keyline()


def key_space(p):
    """The widest cap in the set, left unlettered -- a bare space bar."""
    cap_plate(p, x0=0.03, x1=0.97, y0=0.28, y1=0.72, r=0.10)
    p.line([(0.22, 0.60), (0.78, 0.60)], PLATE_D, 0.020)
    p.keyline()


CAPTIONS = {
    "pad_a": "A", "pad_lb": "LB", "pad_rt": "RT",
    "ps_lb": "L1", "ps_rt": "R2",
    "sw_a": "A", "sw_b": "B", "sw_x": "X", "sw_y": "Y",
    "sw_lb": "L", "sw_rt": "ZR", "sw_start": "+", "sw_back": "-",
}
MARKS = {
    "ps_a": mark_cross, "ps_b": mark_ring, "ps_x": mark_square, "ps_y": mark_triangle,
    "pad_start": mark_bars, "ps_start": mark_bars, "ps_back": mark_plate_outline,
}


def build(key: str, w: int, h: int) -> Image.Image:
    stem = key.rsplit("/", 1)[1]
    p = Pad(w, h)
    if stem in CAPTIONS:
        cap_round(p, CAPTIONS[stem])
    elif stem in MARKS:
        MARKS[stem](p)
    elif stem.endswith("dpad_lr"):
        dpad_lr(p)
    elif stem == "stick_l":
        stick(p, "L")
    elif stem == "stick_r":
        stick(p, "R")
    elif stem == "mouse_l":
        mouse(p, "l")
    elif stem == "mouse_r":
        mouse(p, "r")
    elif stem == "key_enter":
        key_enter(p)
    elif stem == "key_space":
        key_space(p)
    elif stem == "key_wide":
        key_blank_wide(p)
    else:
        raise KeyError(key)
    return p.out()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--outdir", type=Path, default=ART)
    ap.add_argument("--only")
    args = ap.parse_args()

    keys = [args.only] if args.only else sorted(SIZES)
    for key in keys:
        w, h = SIZES[key]
        im = build(key, w, h)
        if im.size != (w, h):
            raise ValueError(f"{key}: got {im.size}, expected {(w, h)}")
        if im.getchannel("A").getbbox() is None:
            raise ValueError(f"{key}: generated sprite is fully transparent")
        dest = args.outdir / f"{key}.png"
        dest.parent.mkdir(parents=True, exist_ok=True)
        im.save(dest)
        print(f"  ok   {key}: {w}x{h}")
    print(f"\n{len(keys)} sprite(s) -> {args.outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
