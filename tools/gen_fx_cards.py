#!/usr/bin/env python3
"""Procedurally generate the assets/art/fx/ particle cards.

Why generate rather than source a replacement: these 21 cards are the single
largest third-party-derived bucket by bytes (~3.8 MB) and 20 of them are pure WHITE
ALPHA MASKS -- the view tints them at draw time (see Art.TINT / the additive
_glow_root pass), so only the alpha shape matters. A gradient or a polygon does
not need a licensed source at all, and drawing it analytically gives a cleaner
falloff than a downscaled 3D render. That clears the licence blocker for this
bucket outright instead of trading one third-party pack for another.

Each card keeps its ORIGINAL canvas size so Art.SCALE and every draw site are
untouched.

    python3 tools/gen_fx_cards.py            # write to assets/art/fx/
    python3 tools/gen_fx_cards.py --outdir /tmp/preview
"""
from __future__ import annotations

import argparse
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

PROJECT_ROOT = Path(__file__).resolve().parent.parent
FX = PROJECT_ROOT / "assets/art/fx"

# name -> canvas size, taken from the sprites being replaced.
SIZES = {
    "bubble1": 512, "bubble2": 512, "fx_bullettrail": 512, "fx_circle_01": 200,
    "fx_circle_02": 500, "fx_fumes4": 1024, "fx_fumes_02": 1024, "fx_groundbreak": 1024,
    "fx_halfcircle": 1024, "fx_impactdark": 200, "fx_lightning_02": 172,
    "fx_muzzle_fan": 512, "fx_ring_02": 512, "fx_shadow": 512, "fx_shell_01": 512,
    "fx_smoke_01": 200, "fx_soft_spot": 512, "fx_sparkle": 512, "fx_swipe2": 2048,
    "fx_swipe_01": 1024, "fx_wind": 512,
}

SS = 2  # supersample factor; everything is drawn big then LANCZOS'd down


def _canvas(n: int) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    im = Image.new("L", (n * SS, n * SS), 0)
    return im, ImageDraw.Draw(im)


def _finish(mask: Image.Image, n: int, blur: float = 0.0,
            rgb: tuple[int, int, int] | Image.Image = (255, 255, 255)) -> Image.Image:
    if blur:
        mask = mask.filter(ImageFilter.GaussianBlur(blur * SS))
    mask = mask.resize((n, n), Image.LANCZOS)
    base = Image.new("RGB", (n, n), rgb) if isinstance(rgb, tuple) else rgb.resize((n, n))
    out = base.convert("RGBA")
    out.putalpha(mask)
    return out


def radial(n: int, inner: float, outer: float, gamma: float = 1.0) -> Image.Image:
    """Soft round falloff -- soft_spot / shadow / smoke puffs."""
    m, _ = _canvas(n)
    px = m.load()
    s = n * SS
    c = s / 2.0
    ri, ro = inner * c, outer * c
    for y in range(s):
        dy = y - c
        for x in range(s):
            d = math.hypot(x - c, dy)
            if d >= ro:
                continue
            t = 1.0 if d <= ri else 1.0 - (d - ri) / (ro - ri)
            px[x, y] = int(255 * (t ** gamma))
    return m


def polygon(n: int, sides: int, r: float, rot: float = 0.0) -> Image.Image:
    m, d = _canvas(n)
    s = n * SS
    c = s / 2.0
    pts = [(c + math.cos(rot + i * 2 * math.pi / sides) * r * c,
            c + math.sin(rot + i * 2 * math.pi / sides) * r * c) for i in range(sides)]
    d.polygon(pts, fill=255)
    return m


def ring(n: int, r: float, w: float) -> Image.Image:
    m, d = _canvas(n)
    s = n * SS
    c = s / 2.0
    rr = r * c
    d.ellipse([c - rr, c - rr, c + rr, c + rr], outline=255, width=max(1, int(w * s)))
    return m


def sphere(n: int) -> Image.Image:
    """Bubble: bright rim, dark centre -- alpha is the rim shading."""
    m, _ = _canvas(n)
    px = m.load()
    s = n * SS
    c = s / 2.0
    for y in range(s):
        dy = y - c
        for x in range(s):
            d = math.hypot(x - c, dy) / c
            if d > 0.96:
                continue
            px[x, y] = int(255 * min(1.0, (d / 0.96) ** 2.2))
    return m


def taper(n: int, tip: float = 0.06) -> Image.Image:
    """Bullet trail: long wedge, fat left, needle right."""
    m, d = _canvas(n)
    s = n * SS
    d.polygon([(0, s * 0.5 - s * 0.10), (s * 0.97, s * 0.5 - s * tip * 0.25),
               (s * 0.97, s * 0.5 + s * tip * 0.25), (0, s * 0.5 + s * 0.10)], fill=255)
    return m


def starburst(n: int, spikes: int = 26) -> Image.Image:
    m, d = _canvas(n)
    s = n * SS
    c = s / 2.0
    rng = random.Random(7)
    for i in range(spikes):
        a = i * 2 * math.pi / spikes + rng.uniform(-0.05, 0.05)
        ln = c * rng.uniform(0.55, 0.98)
        w = 0.022 * rng.uniform(0.6, 1.5)
        d.polygon([(c + math.cos(a) * ln, c + math.sin(a) * ln),
                   (c + math.cos(a + w) * c * 0.13, c + math.sin(a + w) * c * 0.13),
                   (c + math.cos(a - w) * c * 0.13, c + math.sin(a - w) * c * 0.13)], fill=255)
    d.ellipse([c - c * 0.16, c - c * 0.16, c + c * 0.16, c + c * 0.16], fill=255)
    return m


def sparkle(n: int) -> Image.Image:
    """Four-point star with a bright core."""
    m, d = _canvas(n)
    s = n * SS
    c = s / 2.0
    for a in (0.0, math.pi / 2):
        for sign in (1, -1):
            ang = a if sign > 0 else a + math.pi
            d.polygon([(c + math.cos(ang) * c * 0.98, c + math.sin(ang) * c * 0.98),
                       (c + math.cos(ang + math.pi / 2) * c * 0.045,
                        c + math.sin(ang + math.pi / 2) * c * 0.045),
                       (c + math.cos(ang - math.pi / 2) * c * 0.045,
                        c + math.sin(ang - math.pi / 2) * c * 0.045)], fill=255)
    d.ellipse([c - c * 0.10, c - c * 0.10, c + c * 0.10, c + c * 0.10], fill=255)
    return m


def crescent(n: int, count: int = 1) -> Image.Image:
    """Swipe arcs -- a bright band clipped by an offset disc."""
    m, d = _canvas(n)
    s = n * SS
    c = s / 2.0
    rng = random.Random(3)
    for k in range(count):
        r = c * (0.92 - 0.26 * k)
        off = r * 0.30
        arc = Image.new("L", (s, s), 0)
        ad = ImageDraw.Draw(arc)
        ad.ellipse([c - r, c - r, c + r, c + r], fill=255)
        cut = Image.new("L", (s, s), 0)
        cd = ImageDraw.Draw(cut)
        cd.ellipse([c - r + off, c - r - off * 0.4, c + r + off, c + r - off * 0.4], fill=255)
        arc = Image.composite(Image.new("L", (s, s), 0), arc, cut)
        wedge = Image.new("L", (s, s), 0)
        wd = ImageDraw.Draw(wedge)
        a0 = 200 + rng.uniform(-14, 14)
        wd.pieslice([0, 0, s, s], a0, a0 + 118, fill=255)
        arc = Image.composite(arc, Image.new("L", (s, s), 0), wedge)
        m = Image.composite(Image.new("L", (s, s), 255), m, arc)
    return m


def streaks(n: int, vertical: bool, count: int, thick: float, seed: int) -> Image.Image:
    m, d = _canvas(n)
    s = n * SS
    rng = random.Random(seed)
    for _ in range(count):
        p = rng.uniform(0.04, 0.96) * s
        ln = rng.uniform(0.35, 0.95)
        a = int(255 * rng.uniform(0.25, 1.0))
        w = max(1, int(thick * s * rng.uniform(0.5, 1.6)))
        off = (1.0 - ln) / 2 * s
        if vertical:
            d.line([(p, off), (p, s - off)], fill=a, width=w)
        else:
            d.line([(off, p), (s - off, p)], fill=a, width=w)
    return m


def bolt(n: int, seed: int = 5) -> Image.Image:
    m, d = _canvas(n)
    s = n * SS
    rng = random.Random(seed)
    x = s * 0.5
    pts = [(x, 0)]
    y = 0.0
    while y < s:
        y += s * rng.uniform(0.05, 0.12)
        x += s * rng.uniform(-0.09, 0.09)
        pts.append((min(max(x, s * 0.1), s * 0.9), min(y, s)))
    d.line(pts, fill=255, width=max(2, int(s * 0.035)))
    return m


def cracks(n: int, seed: int = 11) -> Image.Image:
    m, d = _canvas(n)
    s = n * SS
    c = s / 2.0
    rng = random.Random(seed)
    for i in range(30):
        a = i * 2 * math.pi / 30 + rng.uniform(-0.3, 0.3)
        x, y = c, c
        w = max(1, int(s * 0.005))
        for _ in range(rng.randint(6, 14)):
            ln = s * rng.uniform(0.04, 0.11)
            a += rng.uniform(-0.5, 0.5)
            nx, ny = x + math.cos(a) * ln, y + math.sin(a) * ln
            d.line([(x, y), (nx, ny)], fill=rng.randint(150, 255), width=w)
            x, y = nx, ny
    return m


def shell(n: int) -> Image.Image:
    """The one COLOURED card: a brass casing with a copper tip."""
    m, d = _canvas(n)
    s = n * SS
    top, bot = s * 0.40, s * 0.60
    d.rounded_rectangle([s * 0.14, top, s * 0.74, bot], radius=int(s * 0.04), fill=255)
    d.polygon([(s * 0.74, top), (s * 0.93, s * 0.5), (s * 0.74, bot)], fill=255)
    grad = Image.new("RGB", (s, s), (150, 110, 45))
    gd = ImageDraw.Draw(grad)
    for y in range(int(top), int(bot)):
        t = abs((y - (top + bot) / 2) / ((bot - top) / 2))
        v = 1.0 - 0.55 * t * t
        gd.line([(0, y), (s, y)], fill=(int(196 * v), int(150 * v), int(62 * v)))
    gd.polygon([(s * 0.74, top), (s * 0.95, s * 0.5), (s * 0.74, bot)], fill=(150, 82, 45))
    gd.rectangle([s * 0.14, top, s * 0.22, bot], fill=(120, 92, 40))
    return _finish(m, n, blur=0.4, rgb=grad)


def build(name: str, n: int) -> Image.Image:
    if name == "fx_soft_spot":
        return _finish(radial(n, 0.02, 0.98, 2.0), n, blur=2.0)
    if name == "fx_shadow":
        # Same falloff as soft_spot but BLACK: _ground_shadow() seats every unit on this
        # card, so a white one would turn every shadow into a glow.
        return _finish(radial(n, 0.02, 0.98, 2.0), n, blur=2.0, rgb=(0, 0, 0))
    if name == "fx_smoke_01":
        return _finish(polygon(n, 8, 0.98, math.pi / 8), n)
    if name == "fx_circle_01":
        return _finish(polygon(n, 8, 0.98, math.pi / 8), n)
    if name == "fx_circle_02":
        return _finish(polygon(n, 8, 0.96, math.pi / 8), n, rgb=(206, 206, 206))
    if name == "fx_impactdark":
        return _finish(polygon(n, 8, 0.98, math.pi / 8), n, rgb=(26, 26, 26))
    if name == "fx_ring_02":
        return _finish(ring(n, 0.90, 0.018), n, blur=1.0)
    if name in ("bubble1", "bubble2"):
        return _finish(sphere(n), n, blur=1.0)
    if name == "fx_bullettrail":
        return _finish(taper(n), n, blur=1.0)
    if name == "fx_muzzle_fan":
        return _finish(starburst(n, 54), n, blur=1.6)
    if name == "fx_sparkle":
        return _finish(sparkle(n), n, blur=1.2)
    if name == "fx_halfcircle":
        return _finish(crescent(n, 1), n, blur=2.0)
    if name == "fx_swipe_01":
        return _finish(crescent(n, 2), n, blur=2.0)
    if name == "fx_swipe2":
        return _finish(crescent(n, 3), n, blur=2.5)
    if name == "fx_fumes4":
        return _finish(streaks(n, True, 420, 0.0022, 21), n, blur=5.0)
    if name == "fx_fumes_02":
        return _finish(streaks(n, True, 700, 0.0035, 22), n, blur=7.0)
    if name == "fx_wind":
        return _finish(streaks(n, False, 130, 0.006, 23), n, blur=6.0)
    if name == "fx_lightning_02":
        return _finish(bolt(n), n, blur=0.8)
    if name == "fx_groundbreak":
        return _finish(cracks(n), n, blur=1.4)
    if name == "fx_shell_01":
        return shell(n)
    raise KeyError(name)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--outdir", type=Path, default=FX)
    ap.add_argument("--only", help="generate a single card")
    args = ap.parse_args()
    args.outdir.mkdir(parents=True, exist_ok=True)

    names = [args.only] if args.only else sorted(SIZES)
    for name in names:
        im = build(name, SIZES[name])
        if im.getchannel("A").getbbox() is None:
            raise ValueError(f"{name}: generated card is fully transparent")
        im.save(args.outdir / f"{name}.png")
        print(f"  ok   {name}: {im.size[0]}px")
    print(f"\n{len(names)} card(s) -> {args.outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
