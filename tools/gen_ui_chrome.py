#!/usr/bin/env python3
"""Procedurally generate the assets/art/ui/ and assets/art/hud/ chrome sprites.

Bucket 1 of the chrome swap: plates, frames, bezels, reticles, map pips and the
screen-space HUD cards. Every one of these is pure geometry -- a rounded plate,
a bevelled ring, a stencil silhouette -- so drawing them analytically clears the
legacy art licence for the bucket outright instead of trading one third-party pack
for another. See OPEN_SOURCE_CHECKLIST.md: no CC0 drop-in exists.

Same contract as tools/gen_fx_cards.py:
  * SIZES is the manifest -- one entry per file this tool owns.
  * each sprite keeps its ORIGINAL canvas size, so Art.SCALE and every draw
    site are untouched.
  * drawn at SSx then LANCZOS'd down, which beats a downscaled 3D render.

Button captions are stroked from tools/uifont.py rather than a TTF -- see that
module for why; it keeps the output reproducible on any checkout with no font
dependency at all.

    python3 tools/gen_ui_chrome.py                 # write in place
    python3 tools/gen_ui_chrome.py --outdir /tmp/x # preview
    python3 tools/gen_ui_chrome.py --only ui/panel
"""
from __future__ import annotations

import argparse
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

from uifont import draw_text

PROJECT_ROOT = Path(__file__).resolve().parent.parent
ART = PROJECT_ROOT / "assets/art"

SS = 3  # supersample factor

# --- house palette -----------------------------------------------------------
# Desert-military chrome: brushed steel plate, stencil ink, amber accent. Picked
# to sit with Art.PLATE_STEEL / Art.PRINT_INK rather than the blue-grey legacy art kit.
INK = (13, 15, 10)
STEEL = (128, 133, 128)
STEEL_HI = (198, 202, 194)
STEEL_LO = (68, 72, 68)
AMBER = (214, 164, 62)
PANEL_DARK = (18, 19, 17)

# path (relative to assets/art) -> (w, h). This dict IS the manifest.
SIZES = {
    "ui/bar_frame": (512, 128),
    "ui/cursor": (64, 64),
    "ui/dial_fuel": (600, 600),
    "ui/key_blank": (256, 256),
    "ui/menu_button": (512, 512),
    "ui/menu_button_sel": (512, 512),
    "ui/pad_b": (256, 256),
    "ui/pad_back": (256, 256),
    "ui/pad_x": (256, 256),
    "ui/pad_y": (256, 256),
    "ui/panel": (256, 256),
    "ui/plate_metal_c": (190, 230),
    "ui/plate_metal_l": (190, 230),
    "ui/plate_metal_r": (190, 230),
    "ui/reticle": (64, 64),
    "ui/vignette": (1024, 1024),
    "ui/wheel_socket": (512, 512),
    "hud/ICON_Map_Fire": (256, 256),
    "hud/ICON_Map_Flag": (256, 256),
    "hud/ICON_Map_GunShop": (256, 256),
    "hud/ICON_Map_Lightning": (256, 256),
    "hud/ICON_Map_Radiation": (256, 256),
    "hud/ICON_Map_Skull": (256, 256),
    "hud/ICON_Map_Star": (256, 256),
    "hud/ICON_Map_Target": (256, 256),
    "hud/ICON_Map_Vehicle": (256, 256),
    "hud/SPR_Apocalypse_WeaponWheel": (2048, 1024),
    "hud/SPR_HUD_Frame_Lrg": (256, 256),
    "hud/SPR_HUD_Frame_Lrg_Underlay": (256, 256),
    "hud/SPR_HUD_Reticle_Bracket_Shotgun": (128, 256),
    "hud/SPR_HUD_Reticle_Circle_Med": (256, 256),
    "hud/SPR_HUD_Tooltip": (256, 256),
    "hud/hudfx_blood": (2048, 2048),
    "hud/hudfx_dmgdir": (512, 512),
    "hud/hudfx_dmgvig": (1024, 1024),
    "hud/hudfx_glow": (1024, 1024),
    "hud/hudfx_hitlines": (256, 256),
}


# --- primitives --------------------------------------------------------------
def _mask(w: int, h: int) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    im = Image.new("L", (w * SS, h * SS), 0)
    return im, ImageDraw.Draw(im)


def _rgb(w: int, h: int, fill=(0, 0, 0)) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    im = Image.new("RGB", (w * SS, h * SS), fill)
    return im, ImageDraw.Draw(im)


def _down(mask: Image.Image, w: int, h: int, blur: float = 0.0,
          rgb: tuple[int, int, int] | Image.Image = (255, 255, 255)) -> Image.Image:
    if blur:
        mask = mask.filter(ImageFilter.GaussianBlur(blur * SS))
    mask = mask.resize((w, h), Image.LANCZOS)
    base = Image.new("RGB", (w, h), rgb) if isinstance(rgb, tuple) else rgb.resize((w, h), Image.LANCZOS)
    out = base.convert("RGBA")
    out.putalpha(mask)
    return out


def _text(d: ImageDraw.ImageDraw, cx: float, cy: float, s: str, px: int, fill) -> None:
    draw_text(d, cx, cy, s, px, fill)


def _bevel(w: int, h: int, light=STEEL_HI, mid=STEEL, dark=STEEL_LO) -> Image.Image:
    """Top-lit vertical steel gradient used by every plate."""
    im, d = _rgb(w, h)
    H = h * SS
    for y in range(H):
        t = y / max(1, H - 1)
        if t < 0.5:
            k = t / 0.5
            c = tuple(int(light[i] + (mid[i] - light[i]) * k) for i in range(3))
        else:
            k = (t - 0.5) / 0.5
            c = tuple(int(mid[i] + (dark[i] - mid[i]) * k) for i in range(3))
        d.line([(0, y), (w * SS, y)], fill=c)
    return im


def _rounded(d: ImageDraw.ImageDraw, box, r: float, **kw) -> None:
    d.rounded_rectangle(box, radius=max(1, int(r)), **kw)


def _ngon(cx, cy, r, n, rot=0.0):
    return [(cx + math.cos(rot + i * 2 * math.pi / n) * r,
             cy + math.sin(rot + i * 2 * math.pi / n) * r) for i in range(n)]


# --- ui/ ---------------------------------------------------------------------
def bar_frame(w, h):
    """Hollow capsule frame; the bar fill is drawn inside it by the HUD."""
    m, d = _mask(w, h)
    W, H = w * SS, h * SS
    pad = H * 0.10
    _rounded(d, [pad * 0.5, pad, W - pad * 0.5, H - pad], H * 0.16, fill=255)
    # knock the interior out so the frame reads as a frame, not a slab
    inset = H * 0.26
    _rounded(d, [pad * 0.5 + inset, pad + inset * 0.62,
                 W - pad * 0.5 - inset, H - pad - inset * 0.62], H * 0.08, fill=0)
    # end caps + rivets
    for fx in (0.045, 0.955):
        d.ellipse([W * fx - H * 0.075, H * 0.5 - H * 0.075,
                   W * fx + H * 0.075, H * 0.5 + H * 0.075], fill=255)
    return _down(m, w, h, blur=0.25, rgb=_bevel(w, h))


def cursor(w, h):
    m, d = _mask(w, h)
    S = w * SS
    pts = [(0.16, 0.06), (0.16, 0.82), (0.36, 0.64), (0.50, 0.94),
           (0.63, 0.87), (0.49, 0.59), (0.74, 0.56)]
    d.polygon([(x * S, y * S) for x, y in pts], fill=255)
    body = m.copy()
    # ink outline: dilate the silhouette, then colour the ring dark
    ring = body.filter(ImageFilter.MaxFilter(int(S * 0.05) | 1))
    col, cd = _rgb(w, h, INK)
    fill = body.resize((w, h), Image.LANCZOS)
    out = _down(ring, w, h, rgb=INK)
    white = Image.new("RGBA", (w, h), (245, 245, 240, 0))
    white.putalpha(fill)
    out.alpha_composite(white)
    return out


def dial_fuel(w, h):
    """Segmented gauge bezel -- 12 notches around a hollow ring."""
    m, d = _mask(w, h)
    S = w * SS
    c = S / 2
    d.polygon(_ngon(c, c, c * 0.97, 12, math.pi / 12), fill=255)
    d.polygon(_ngon(c, c, c * 0.63, 12, math.pi / 12), fill=0)
    grad = _bevel(w, h)
    gd = ImageDraw.Draw(grad)
    for i in range(12):
        a = i * 2 * math.pi / 12
        gd.line([(c + math.cos(a) * c * 0.64, c + math.sin(a) * c * 0.64),
                 (c + math.cos(a) * c * 0.97, c + math.sin(a) * c * 0.97)],
                fill=STEEL_LO, width=max(2, int(S * 0.018)))
    gd.polygon(_ngon(c, c, c * 0.72, 12, math.pi / 12), outline=AMBER,
               width=max(2, int(S * 0.022)))
    return _down(m, w, h, blur=0.3, rgb=grad)


def key_blank(w, h):
    """White alpha mask -- the view tints it, so only the plate shape matters."""
    m, d = _mask(w, h)
    S = w * SS
    _rounded(d, [S * 0.06, S * 0.06, S * 0.94, S * 0.94], S * 0.17, fill=255)
    _rounded(d, [S * 0.13, S * 0.13, S * 0.87, S * 0.87], S * 0.12, fill=190)
    return _down(m, w, h, blur=0.4)


def menu_button(w, h, selected: bool):
    m, d = _mask(w, h)
    S = w * SS
    c = S / 2
    d.polygon(_ngon(c, c, c * 0.94, 8, math.pi / 8), fill=255)
    if selected:
        base = _bevel(w, h, (232, 236, 228), (186, 190, 182), (128, 132, 126))
    else:
        base = _bevel(w, h, (176, 180, 172), (126, 131, 126), (72, 76, 72))
    bd = ImageDraw.Draw(base)
    bd.polygon(_ngon(c, c, c * 0.94, 8, math.pi / 8),
               outline=AMBER if selected else STEEL_LO, width=max(2, int(S * 0.022)))
    bd.polygon(_ngon(c, c, c * 0.80, 8, math.pi / 8),
               outline=(238, 240, 232) if selected else (150, 154, 148),
               width=max(1, int(S * 0.010)))
    return _down(m, w, h, blur=0.35, rgb=base)


def pad_face(w, h, letter: str, disc: tuple[int, int, int]):
    m, d = _mask(w, h)
    S = w * SS
    d.ellipse([S * 0.04, S * 0.04, S * 0.96, S * 0.96], fill=255)
    base, bd = _rgb(w, h, disc)
    bd.ellipse([S * 0.04, S * 0.04, S * 0.96, S * 0.96],
               outline=tuple(int(v * 0.62) for v in disc), width=max(2, int(S * 0.035)))
    _text(bd, S / 2, S / 2 - S * 0.02, letter, int(S * 0.52), INK)
    return _down(m, w, h, blur=0.3, rgb=base)


def pad_back(w, h):
    """White mask: pill plate with a 'return' chevron knocked out."""
    m, d = _mask(w, h)
    S = w * SS
    _rounded(d, [S * 0.04, S * 0.30, S * 0.96, S * 0.70], S * 0.20, fill=255)
    cx, cy = S * 0.5, S * 0.5
    a = S * 0.115
    d.polygon([(cx - a, cy), (cx + a * 0.30, cy - a), (cx + a * 0.30, cy + a)], fill=0)
    d.rectangle([cx + a * 0.20, cy - a * 0.33, cx + a * 1.15, cy + a * 0.33], fill=0)
    return _down(m, w, h, blur=0.35)


def panel(w, h):
    """Near-black backing plate for menu/tooltip bodies."""
    m, d = _mask(w, h)
    S = w * SS
    _rounded(d, [0, 0, S - 1, S - 1], S * 0.09, fill=246)
    base = _bevel(w, h, (30, 32, 28), PANEL_DARK, (10, 11, 9))
    bd = ImageDraw.Draw(base)
    bd.rounded_rectangle([1, 1, S - 2, S - 2], radius=int(S * 0.09),
                         outline=(62, 66, 58), width=max(2, int(S * 0.012)))
    return _down(m, w, h, blur=0.3, rgb=base)


def plate_metal(w, h, side: str):
    """Framed plate: top rail + hollow body. l/r add an outboard edge rail."""
    m, d = _mask(w, h)
    W, H = w * SS, h * SS
    d.rectangle([W * 0.06, H * 0.02, W * 0.94, H * 0.15], fill=255)   # top rail
    _rounded(d, [W * 0.06, H * 0.17, W * 0.94, H * 0.97], W * 0.05, fill=255)
    _rounded(d, [W * 0.14, H * 0.25, W * 0.86, H * 0.89], W * 0.03, fill=0)
    base = _bevel(w, h)
    bd = ImageDraw.Draw(base)
    bd.rectangle([0, 0, W, H * 0.15], fill=(208, 212, 204))
    if side in ("l", "r"):
        x0, x1 = (W * 0.06, W * 0.14) if side == "l" else (W * 0.86, W * 0.94)
        bd.rectangle([x0, H * 0.17, x1, H * 0.97], fill=(150, 116, 108))
    return _down(m, w, h, blur=0.3, rgb=base)


def reticle(w, h):
    """Single chevron bracket -- the HUD draws four of these, rotated."""
    m, d = _mask(w, h)
    S = w * SS
    d.line([(S * 0.62, S * 0.18), (S * 0.34, S * 0.50), (S * 0.62, S * 0.82)],
           fill=255, width=max(2, int(S * 0.10)), joint="curve")
    return _down(m, w, h, blur=0.3, rgb=(242, 244, 236))


def vignette(w, h):
    """Bright at the border, transparent toward the middle (screen-edge frame)."""
    m = Image.new("L", (w, h), 0)
    px = m.load()
    for y in range(h):
        fy = min(y, h - 1 - y) / (h / 2)
        for x in range(w):
            fx = min(x, w - 1 - x) / (w / 2)
            t = min(fx, fy)               # 0 at the border, 1 at the centre
            v = max(0.0, 1.0 - t / 0.42)
            px[x, y] = int(255 * v ** 1.7)
    m = m.filter(ImageFilter.GaussianBlur(w * 0.012))
    out = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    out.putalpha(m)
    return out


def wheel_socket(w, h):
    m, d = _mask(w, h)
    S = w * SS
    c = S / 2
    d.polygon(_ngon(c, c, c * 0.95, 9, math.pi / 9), fill=255)
    base = _bevel(w, h, (150, 154, 146), (96, 100, 95), (54, 58, 54))
    bd = ImageDraw.Draw(base)
    bd.polygon(_ngon(c, c, c * 0.78, 9, math.pi / 9), fill=(22, 24, 21))
    bd.polygon(_ngon(c, c, c * 0.78, 9, math.pi / 9), outline=(158, 162, 152),
               width=max(2, int(S * 0.016)))
    return _down(m, w, h, blur=0.35, rgb=base)


# --- hud/ map pips (white alpha stencils) ------------------------------------
def pip_fire(S, d):
    outer = [(0.50, 0.03), (0.60, 0.24), (0.67, 0.20), (0.71, 0.36), (0.81, 0.48),
             (0.84, 0.64), (0.75, 0.83), (0.57, 0.95), (0.41, 0.95), (0.25, 0.84),
             (0.17, 0.65), (0.24, 0.47), (0.33, 0.34), (0.36, 0.21), (0.44, 0.25)]
    d.polygon([(x * S, y * S) for x, y in outer], fill=255)
    inner = [(0.50, 0.45), (0.63, 0.64), (0.60, 0.82), (0.50, 0.89),
             (0.40, 0.82), (0.37, 0.64)]
    d.polygon([(x * S, y * S) for x, y in inner], fill=0)


def pip_flag(S, d):
    d.rectangle([S * 0.22, S * 0.06, S * 0.30, S * 0.94], fill=255)
    d.polygon([(S * 0.30, S * 0.10), (S * 0.86, S * 0.26), (S * 0.30, S * 0.46)], fill=255)


def pip_gunshop(S, d):
    d.rounded_rectangle([S * 0.08, S * 0.30, S * 0.90, S * 0.50], radius=S * 0.045, fill=255)
    d.rectangle([S * 0.80, S * 0.24, S * 0.87, S * 0.32], fill=255)      # front sight
    d.polygon([(S * 0.20, S * 0.48), (S * 0.44, S * 0.48), (S * 0.36, S * 0.88),
               (S * 0.14, S * 0.88)], fill=255)                          # grip
    d.rectangle([S * 0.44, S * 0.48, S * 0.62, S * 0.56], fill=255)      # frame
    d.arc([S * 0.36, S * 0.50, S * 0.66, S * 0.80], 0, 180,
          fill=255, width=max(2, int(S * 0.035)))                        # trigger guard


def pip_lightning(S, d):
    d.polygon([(S * 0.60, S * 0.04), (S * 0.22, S * 0.56), (S * 0.46, S * 0.56),
               (S * 0.36, S * 0.96), (S * 0.80, S * 0.40), (S * 0.54, S * 0.40)], fill=255)


def pip_radiation(S, d):
    c = S / 2
    for i in range(3):
        a0 = -90 + i * 120 - 28
        d.pieslice([S * 0.06, S * 0.06, S * 0.94, S * 0.94], a0, a0 + 56, fill=255)
    d.ellipse([c - S * 0.15, c - S * 0.15, c + S * 0.15, c + S * 0.15], fill=0)
    d.ellipse([c - S * 0.09, c - S * 0.09, c + S * 0.09, c + S * 0.09], fill=255)


def pip_skull(S, d):
    d.ellipse([S * 0.14, S * 0.08, S * 0.86, S * 0.74], fill=255)
    d.rounded_rectangle([S * 0.32, S * 0.62, S * 0.68, S * 0.94], radius=S * 0.07, fill=255)
    for fx in (0.34, 0.66):
        d.ellipse([S * fx - S * 0.13, S * 0.30, S * fx + S * 0.13, S * 0.56], fill=0)
    d.polygon([(S * 0.5, S * 0.54), (S * 0.57, S * 0.68), (S * 0.43, S * 0.68)], fill=0)
    for fx in (0.42, 0.5, 0.58):
        d.rectangle([S * fx - S * 0.022, S * 0.76, S * fx + S * 0.022, S * 0.94], fill=0)


def pip_star(S, d):
    c = S / 2
    pts = []
    for i in range(10):
        r = c * (0.96 if i % 2 == 0 else 0.42)
        a = -math.pi / 2 + i * math.pi / 5
        pts.append((c + math.cos(a) * r, c + math.sin(a) * r))
    d.polygon(pts, fill=255)


def pip_target(S, d):
    c = S / 2
    w = max(2, int(S * 0.055))
    d.ellipse([S * 0.20, S * 0.20, S * 0.80, S * 0.80], outline=255, width=w)
    d.polygon(_ngon(c, c, c * 0.44, 8), outline=255, width=w)
    for a in (0, math.pi / 2, math.pi, 3 * math.pi / 2):
        d.line([(c + math.cos(a) * c * 0.30, c + math.sin(a) * c * 0.30),
                (c + math.cos(a) * c * 0.95, c + math.sin(a) * c * 0.95)], fill=255, width=w)
    d.ellipse([c - S * 0.05, c - S * 0.05, c + S * 0.05, c + S * 0.05], fill=255)


def pip_vehicle(S, d):
    d.polygon([(S * 0.10, S * 0.62), (S * 0.24, S * 0.36), (S * 0.62, S * 0.36),
               (S * 0.74, S * 0.50), (S * 0.92, S * 0.52), (S * 0.92, S * 0.66),
               (S * 0.10, S * 0.66)], fill=255)
    d.rectangle([S * 0.30, S * 0.40, S * 0.56, S * 0.54], fill=0)
    for fx in (0.28, 0.74):
        d.ellipse([S * fx - S * 0.13, S * 0.60, S * fx + S * 0.13, S * 0.86], fill=255)
        d.ellipse([S * fx - S * 0.055, S * 0.685, S * fx + S * 0.055, S * 0.795], fill=0)


PIPS = {
    "Fire": pip_fire, "Flag": pip_flag, "GunShop": pip_gunshop,
    "Lightning": pip_lightning, "Radiation": pip_radiation, "Skull": pip_skull,
    "Star": pip_star, "Target": pip_target, "Vehicle": pip_vehicle,
}


# --- hud/ frames, reticles, screen cards -------------------------------------
def weapon_wheel(w, h):
    """Eight dark sockets, 4x2 -- the radial weapon picker backing."""
    m, d = _mask(w, h)
    W, H = w * SS, h * SS
    r = H * 0.20
    base, bd = _rgb(w, h, (0, 0, 0))
    for row in range(2):
        for col in range(4):
            cx = W * (0.145 + col * 0.237)
            cy = H * (0.29 + row * 0.42)
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
            bd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(26, 28, 25))
            bd.ellipse([cx - r, cy - r, cx + r, cy + r], outline=STEEL,
                       width=max(2, int(H * 0.014)))
            bd.ellipse([cx - r * 0.82, cy - r * 0.82, cx + r * 0.82, cy + r * 0.82],
                       outline=(70, 74, 68), width=max(1, int(H * 0.006)))
    return _down(m, w, h, blur=0.3, rgb=base)


def frame_lrg(w, h):
    m, d = _mask(w, h)
    S = w * SS
    d.rectangle([S * 0.06, S * 0.06, S * 0.94, S * 0.94], outline=255,
                width=max(2, int(S * 0.022)))
    return _down(m, w, h, blur=0.25)


def frame_underlay(w, h):
    """Same square, corners broken out -- reads as a bracket set behind the frame."""
    m, d = _mask(w, h)
    S = w * SS
    d.rectangle([S * 0.05, S * 0.05, S * 0.95, S * 0.95], outline=255,
                width=max(3, int(S * 0.035)))
    g = S * 0.13
    for cx, cy in ((S * 0.5, S * 0.05), (S * 0.5, S * 0.95),
                   (S * 0.05, S * 0.5), (S * 0.95, S * 0.5)):
        d.rectangle([cx - g, cy - g, cx + g, cy + g], fill=0)
    return _down(m, w, h, blur=0.25, rgb=(238, 240, 232))


def reticle_bracket(w, h):
    m, d = _mask(w, h)
    W, H = w * SS, h * SS
    d.arc([W * 0.20, H * 0.06, W * 1.55, H * 0.94], 118, 242,
          fill=255, width=max(2, int(W * 0.10)))
    return _down(m, w, h, blur=0.3, rgb=(242, 244, 236))


def reticle_circle(w, h):
    m, d = _mask(w, h)
    S = w * SS
    c = S / 2
    d.polygon(_ngon(c, c, c * 0.86, 9, -math.pi / 2), outline=255,
              width=max(2, int(S * 0.045)))
    return _down(m, w, h, blur=0.3, rgb=(242, 244, 236))


def tooltip(w, h):
    """Circled '!' alert stencil (white mask)."""
    m, d = _mask(w, h)
    S = w * SS
    c = S / 2
    d.polygon(_ngon(c, c, c * 0.92, 11, -math.pi / 2), fill=255)
    d.polygon(_ngon(c, c, c * 0.74, 11, -math.pi / 2), fill=0)
    d.polygon([(c - S * 0.055, S * 0.24), (c + S * 0.055, S * 0.24),
               (c + S * 0.038, S * 0.60), (c - S * 0.038, S * 0.60)], fill=255)
    d.ellipse([c - S * 0.055, S * 0.66, c + S * 0.055, S * 0.77], fill=255)
    return _down(m, w, h, blur=0.3)


def blood(w, h):
    """Screen-space impact spatter: a few clusters of droplets."""
    m, d = _mask(w, h)
    S = w * SS
    rng = random.Random(41)
    for _ in range(9):
        bx, by = rng.uniform(0.12, 0.88) * S, rng.uniform(0.10, 0.86) * S
        for _ in range(rng.randint(30, 60)):
            a = rng.uniform(0, 2 * math.pi)
            dist = abs(rng.gauss(0, 1)) * S * 0.075
            r = S * rng.uniform(0.004, 0.028) * (1.0 - min(dist / (S * 0.20), 0.75))
            x, y = bx + math.cos(a) * dist, by + math.sin(a) * dist
            d.ellipse([x - r, y - r, x + r, y + r], fill=rng.randint(170, 255))
        r = S * rng.uniform(0.022, 0.045)
        d.ellipse([bx - r, by - r, bx + r, by + r], fill=255)
    return _down(m, w, h, blur=0.6)


def dmgdir(w, h):
    """Directional damage arc -- a tapered crescent that points at the hit."""
    m, d = _mask(w, h)
    S = w * SS
    for k, alpha in ((0.0, 255), (0.055, 150), (0.10, 70)):
        r = S * (0.46 - k)
        d.arc([S * 0.5 - r, S * 0.5 - r, S * 0.5 + r, S * 0.5 + r], -46, 46,
              fill=alpha, width=max(2, int(S * (0.040 - k * 0.25))))
    return _down(m, w, h, blur=1.6)


def dmgvig(w, h):
    m = vignette(w, h).getchannel("A")
    m = m.point(lambda v: int(255 * (v / 255) ** 0.75))
    out = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    out.putalpha(m.filter(ImageFilter.GaussianBlur(w * 0.02)))
    return out


def glow(w, h):
    m = Image.new("L", (w, h), 0)
    px = m.load()
    c = w / 2
    for y in range(h):
        dy = y - c
        for x in range(w):
            dd = math.hypot(x - c, dy) / c
            px[x, y] = 0 if dd >= 1.0 else int(255 * (1.0 - dd) ** 2.1)
    out = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    out.putalpha(m.filter(ImageFilter.GaussianBlur(w * 0.01)))
    return out


def hitlines(w, h):
    """Additive lens streak: a thin horizontal flare through the hit point."""
    m = Image.new("L", (w, h), 0)
    px = m.load()
    cy, cx = h / 2, w / 2
    for y in range(h):
        fy = abs(y - cy) / (h * 0.030)
        if fy > 4.0:
            continue
        for x in range(w):
            fx = abs(x - cx) / (w * 0.46)
            if fx > 1.0:
                continue
            v = math.exp(-fy * fy) * (1.0 - fx) ** 1.6
            px[x, y] = int(255 * v)
    out = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    out.putalpha(m.filter(ImageFilter.GaussianBlur(w * 0.004)))
    return out


# --- dispatch ----------------------------------------------------------------
def build(key: str, w: int, h: int) -> Image.Image:
    if key.startswith("hud/ICON_Map_"):
        m, d = _mask(w, h)
        PIPS[key.rsplit("_", 1)[1]](w * SS, d)
        return _down(m, w, h, blur=0.3)
    simple = {
        "ui/bar_frame": bar_frame, "ui/cursor": cursor, "ui/dial_fuel": dial_fuel,
        "ui/key_blank": key_blank, "ui/panel": panel, "ui/reticle": reticle,
        "ui/vignette": vignette, "ui/wheel_socket": wheel_socket,
        "ui/pad_back": pad_back,
        "hud/SPR_Apocalypse_WeaponWheel": weapon_wheel,
        "hud/SPR_HUD_Frame_Lrg": frame_lrg,
        "hud/SPR_HUD_Frame_Lrg_Underlay": frame_underlay,
        "hud/SPR_HUD_Reticle_Bracket_Shotgun": reticle_bracket,
        "hud/SPR_HUD_Reticle_Circle_Med": reticle_circle,
        "hud/SPR_HUD_Tooltip": tooltip, "hud/hudfx_blood": blood,
        "hud/hudfx_dmgdir": dmgdir, "hud/hudfx_dmgvig": dmgvig,
        "hud/hudfx_glow": glow, "hud/hudfx_hitlines": hitlines,
    }
    if key in simple:
        return simple[key](w, h)
    if key == "ui/menu_button":
        return menu_button(w, h, False)
    if key == "ui/menu_button_sel":
        return menu_button(w, h, True)
    if key.startswith("ui/plate_metal_"):
        return plate_metal(w, h, key[-1])
    faces = {"ui/pad_b": ("B", (196, 66, 58)), "ui/pad_x": ("X", (62, 150, 198)),
             "ui/pad_y": ("Y", (214, 186, 62))}
    if key in faces:
        return pad_face(w, h, *faces[key])
    raise KeyError(key)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--outdir", type=Path, default=ART)
    ap.add_argument("--only", help="generate a single sprite, e.g. ui/panel")
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
