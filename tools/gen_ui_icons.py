#!/usr/bin/env python3
"""Procedurally generate the assets/art/ui/menuicons/ and assets/art/icons/ symbols.

Bucket 2 of the chrome swap: pickup icons, capability pips, medals and the menu
symbol set. Same reasoning as tools/gen_ui_chrome.py -- no CC0 drop-in exists
(OPEN_SOURCE_CHECKLIST.md), so these are drawn analytically rather than sourced.

House style: flat two-tone props (a lit face plus a shaded lower band) with an
ink keyline, so a 24px pickup pip and a 96px menu symbol read the same. The
capability strips and a few menu symbols are WHITE ALPHA MASKS -- the view tints
them, so only the silhouette matters there.

  * SIZES is the manifest -- one entry per file this tool owns.
  * each sprite keeps its ORIGINAL canvas size.

    python3 tools/gen_ui_icons.py
    python3 tools/gen_ui_icons.py --outdir /tmp/x --only icons/icon_ammo
"""
from __future__ import annotations

import argparse
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

from uifont import draw_text

PROJECT_ROOT = Path(__file__).resolve().parent.parent
ART = PROJECT_ROOT / "assets/art"

SS = 3

INK = (12, 14, 10)
STEEL = (150, 155, 148)
STEEL_D = (92, 97, 92)
OLIVE = (104, 118, 62)
OLIVE_D = (68, 78, 40)
BRASS = (198, 156, 62)
BRASS_D = (134, 100, 34)
RED = (176, 62, 52)
RED_D = (118, 38, 32)
GOLD = (214, 176, 66)
GOLD_D = (150, 116, 34)
SILVER = (196, 200, 196)
SILVER_D = (132, 137, 132)
BRONZE = (170, 116, 66)
BRONZE_D = (114, 74, 40)
WOOD = (128, 96, 58)
BLOOD = (150, 44, 38)

SIZES = {
    # --- menu symbol set -----------------------------------------------------
    "ui/menuicons/book": (512, 512),
    "ui/menuicons/controller": (512, 512),
    "ui/menuicons/keyboard": (512, 512),
    "ui/menuicons/mi_arrow": (256, 256),
    "ui/menuicons/mi_back": (256, 256),
    "ui/menuicons/mi_camera": (256, 256),
    "ui/menuicons/mi_cancel": (256, 256),
    "ui/menuicons/mi_combat": (256, 256),
    "ui/menuicons/mi_controller": (256, 256),
    "ui/menuicons/mi_home": (256, 256),
    "ui/menuicons/mi_medal_1": (256, 256),
    "ui/menuicons/mi_medal_2": (256, 256),
    "ui/menuicons/mi_medal_3": (256, 256),
    "ui/menuicons/mi_medal_4": (256, 256),
    "ui/menuicons/mi_medal_5": (256, 256),
    "ui/menuicons/mi_reload": (256, 256),
    "ui/menuicons/mi_settings": (256, 256),
    "ui/menuicons/mi_timer": (256, 256),
    "ui/menuicons/mus_off": (512, 512),
    "ui/menuicons/mus_on": (512, 512),
    "ui/menuicons/play": (512, 512),
    "ui/menuicons/snd_off": (512, 512),
    "ui/menuicons/snd_on": (512, 512),
    "ui/menuicons/trophy": (512, 512),
    # --- pickup / capability icons -------------------------------------------
    "icons/cap_claymore": (1024, 1024),
    "icons/cap_flash": (1024, 1024),
    "icons/cap_pierce": (512, 256),
    "icons/cap_rend": (512, 256),
    "icons/cap_smoke": (1024, 1024),
    "icons/cap_spread": (512, 256),
    "icons/cap_triple": (512, 256),
    "icons/icon_airstrike": (128, 128),
    "icons/icon_ammo": (128, 128),
    "icons/icon_coin": (128, 128),
    "icons/icon_fuel": (128, 128),
    "icons/icon_grenade": (128, 128),
    "icons/icon_medal": (128, 128),
    "icons/icon_rend": (64, 64),
    "icons/icon_skull": (128, 128),
    "icons/icon_vest": (128, 128),
}


# --- canvas helpers ----------------------------------------------------------
class Pad:
    """RGBA scratch canvas in supersampled space, drawn in 0..1 unit coords."""

    def __init__(self, w: int, h: int):
        self.w, self.h = w, h
        self.W, self.H = w * SS, h * SS
        self.im = Image.new("RGBA", (self.W, self.H), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.im)

    def _p(self, pts):
        return [(x * self.W, y * self.H) for x, y in pts]

    def poly(self, pts, fill, outline=None, width=0.0):
        self.d.polygon(self._p(pts), fill=fill, outline=outline,
                       width=max(1, int(width * self.W)) if width else 1)

    def rect(self, x0, y0, x1, y1, fill, r=0.0):
        box = [x0 * self.W, y0 * self.H, x1 * self.W, y1 * self.H]
        if r:
            self.d.rounded_rectangle(box, radius=max(1, int(r * self.W)), fill=fill)
        else:
            self.d.rectangle(box, fill=fill)

    def ell(self, cx, cy, rx, ry, fill=None, outline=None, width=0.0):
        box = [(cx - rx) * self.W, (cy - ry) * self.H,
               (cx + rx) * self.W, (cy + ry) * self.H]
        self.d.ellipse(box, fill=fill, outline=outline,
                       width=max(1, int(width * self.W)) if width else 1)

    def line(self, pts, fill, width):
        self.d.line(self._p(pts), fill=fill, width=max(1, int(width * self.W)),
                    joint="curve")

    def arc(self, cx, cy, rx, ry, a0, a1, fill, width):
        self.d.arc([(cx - rx) * self.W, (cy - ry) * self.H,
                    (cx + rx) * self.W, (cy + ry) * self.H], a0, a1,
                   fill=fill, width=max(1, int(width * self.W)))

    def text(self, cx, cy, s, size, fill, weight=0.20):
        draw_text(self.d, cx * self.W, cy * self.H, s, size * self.W, fill, weight)

    def keyline(self, strength: float = 0.024):
        """Ink rim around whatever is already drawn -- keeps icons readable on
        both the sand ground and the dark menu plate."""
        a = self.im.getchannel("A")
        grown = a.filter(ImageFilter.MaxFilter(max(3, int(self.W * strength) | 1)))
        rim = Image.new("RGBA", (self.W, self.H), INK + (0,))
        rim.putalpha(grown)
        rim.alpha_composite(self.im)
        self.im = rim
        self.d = ImageDraw.Draw(self.im)

    def out(self, blur: float = 0.4) -> Image.Image:
        im = self.im
        if blur:
            im = im.filter(ImageFilter.GaussianBlur(blur * SS * 0.5))
        return im.resize((self.w, self.h), Image.LANCZOS)


def mask_out(p: Pad, blur: float = 0.4) -> Image.Image:
    """Collapse a Pad to a pure white alpha mask (for the tinted sprites)."""
    im = p.out(blur)
    white = Image.new("RGBA", im.size, (255, 255, 255, 0))
    white.putalpha(im.getchannel("A"))
    return white


# --- menu symbols ------------------------------------------------------------
def i_book(p):
    p.poly([(0.06, 0.22), (0.48, 0.30), (0.48, 0.88), (0.06, 0.80)], WOOD)
    p.poly([(0.94, 0.22), (0.52, 0.30), (0.52, 0.88), (0.94, 0.80)], (150, 116, 72))
    p.poly([(0.10, 0.26), (0.46, 0.335), (0.46, 0.83), (0.10, 0.755)], (232, 226, 208))
    p.poly([(0.90, 0.26), (0.54, 0.335), (0.54, 0.83), (0.90, 0.755)], (244, 240, 226))
    p.rect(0.475, 0.29, 0.525, 0.885, (92, 68, 40))
    for i in range(4):
        y = 0.42 + i * 0.11
        p.line([(0.14, y), (0.42, y + 0.055)], (168, 160, 140), 0.014)
        p.line([(0.58, y + 0.055), (0.86, y)], (168, 160, 140), 0.014)
    p.keyline()


def _gamepad(p, body, body_d, buttons=True):
    p.rect(0.10, 0.34, 0.90, 0.72, body, r=0.19)
    p.ell(0.245, 0.53, 0.175, 0.20, fill=body)
    p.ell(0.755, 0.53, 0.175, 0.20, fill=body)
    p.poly([(0.10, 0.58), (0.90, 0.58), (0.90, 0.66), (0.10, 0.66)], body_d)
    # dpad
    p.rect(0.175, 0.485, 0.325, 0.545, (44, 46, 42), r=0.012)
    p.rect(0.220, 0.440, 0.280, 0.590, (44, 46, 42), r=0.012)
    if buttons:
        for dx, dy, c in ((0.0, -0.052, (196, 76, 66)), (0.052, 0.0, (86, 150, 196)),
                          (-0.052, 0.0, (206, 176, 70)), (0.0, 0.052, (110, 168, 86))):
            p.ell(0.755 + dx, 0.515 + dy, 0.031, 0.031, fill=c)
    else:
        for dx, dy in ((0.0, -0.052), (0.052, 0.0), (-0.052, 0.0), (0.0, 0.052)):
            p.ell(0.755 + dx, 0.515 + dy, 0.031, 0.031, fill=(44, 46, 42))
    p.rect(0.20, 0.285, 0.34, 0.345, body_d, r=0.03)   # shoulders
    p.rect(0.66, 0.285, 0.80, 0.345, body_d, r=0.03)


def i_controller(p):
    _gamepad(p, (58, 62, 58), (38, 41, 38))
    p.keyline()


def i_mi_controller(p):
    _gamepad(p, (255, 255, 255), (255, 255, 255), buttons=False)
    # white-on-white erased the detail, so punch the controls out of the alpha
    hole = (0, 0, 0, 0)
    p.d.rectangle([0.175 * p.W, 0.485 * p.H, 0.325 * p.W, 0.545 * p.H], fill=hole)
    p.d.rectangle([0.220 * p.W, 0.440 * p.H, 0.280 * p.W, 0.590 * p.H], fill=hole)
    for dx, dy in ((0.0, -0.052), (0.052, 0.0), (-0.052, 0.0), (0.0, 0.052)):
        cx, cy = 0.755 + dx, 0.515 + dy
        p.d.ellipse([(cx - 0.031) * p.W, (cy - 0.031) * p.H,
                     (cx + 0.031) * p.W, (cy + 0.031) * p.H], fill=hole)


def i_keyboard(p):
    p.rect(0.05, 0.30, 0.95, 0.74, STEEL_D, r=0.045)
    p.rect(0.07, 0.32, 0.93, 0.70, (206, 210, 202), r=0.035)
    for row in range(4):
        y = 0.355 + row * 0.085
        x = 0.095 + (0.022 * row)
        while x < 0.88:
            wkey = 0.055 if row < 3 else (0.30 if x > 0.30 else 0.055)
            p.rect(x, y, x + wkey, y + 0.062, (86, 90, 84), r=0.010)
            x += wkey + 0.014
    p.keyline()


def i_mi_arrow(p):
    for off, c in ((0.16, (170, 175, 168)), (0.0, (232, 236, 228))):
        p.poly([(0.14 + off, 0.14), (0.52 + off, 0.50), (0.14 + off, 0.86),
                (0.30 + off, 0.86), (0.68 + off, 0.50), (0.30 + off, 0.14)], c)
    p.keyline()


def i_mi_back(p):
    p.poly([(0.86, 0.14), (0.48, 0.50), (0.86, 0.86), (0.70, 0.86),
            (0.32, 0.50), (0.70, 0.14)], (206, 186, 96))
    p.poly([(0.60, 0.14), (0.22, 0.50), (0.60, 0.86), (0.44, 0.86),
            (0.06, 0.50), (0.44, 0.14)], (162, 142, 66))
    p.keyline()


def i_mi_camera(p):
    p.rect(0.06, 0.30, 0.94, 0.80, OLIVE, r=0.07)
    p.rect(0.06, 0.30, 0.94, 0.44, OLIVE_D, r=0.07)
    p.rect(0.30, 0.20, 0.52, 0.32, OLIVE_D, r=0.03)
    p.ell(0.50, 0.56, 0.20, 0.20, fill=(46, 50, 46))
    p.ell(0.50, 0.56, 0.145, 0.145, fill=(64, 96, 116))
    p.ell(0.455, 0.515, 0.045, 0.045, fill=(198, 214, 224))
    p.ell(0.80, 0.38, 0.038, 0.038, fill=(214, 96, 72))
    p.keyline()


def i_mi_cancel(p):
    p.ell(0.5, 0.5, 0.44, 0.44, fill=None, outline=(186, 76, 66), width=0.105)
    p.line([(0.235, 0.235), (0.765, 0.765)], (186, 76, 66), 0.105)
    p.keyline()


def i_mi_combat(p):
    for flip in (1, -1):
        x0 = 0.5 - flip * 0.34
        x1 = 0.5 + flip * 0.30
        p.line([(x0, 0.86), (x1, 0.16)], (198, 202, 194), 0.070)   # blade
        p.line([(x1 - flip * 0.05, 0.24), (x1, 0.16)], (238, 240, 232), 0.050)
        p.line([(x0 - flip * 0.06, 0.72), (x0 + flip * 0.10, 0.80)], BRASS, 0.058)
        p.ell(x0 + flip * 0.015, 0.885, 0.045, 0.045, fill=BRASS_D)
    p.keyline()


def i_mi_home(p):
    p.poly([(0.5, 0.14), (0.94, 0.50), (0.06, 0.50)], (150, 62, 52))
    p.rect(0.16, 0.48, 0.84, 0.88, OLIVE)
    p.poly([(0.16, 0.48), (0.84, 0.48), (0.84, 0.58), (0.16, 0.58)], OLIVE_D)
    p.rect(0.40, 0.62, 0.60, 0.88, (54, 44, 34), r=0.02)
    p.keyline()


def i_medal(p, tier: int):
    face, shade = ((GOLD, GOLD_D), (SILVER, SILVER_D), (BRONZE, BRONZE_D),
                   (SILVER, SILVER_D), (GOLD, GOLD_D))[tier - 1]
    p.poly([(0.34, 0.06), (0.46, 0.06), (0.54, 0.40), (0.40, 0.40)], (70, 96, 150))
    p.poly([(0.54, 0.06), (0.66, 0.06), (0.60, 0.40), (0.46, 0.40)], (176, 68, 60))
    pts = 4 + tier * 2
    if tier >= 3:  # higher tiers wear a star burst behind the disc
        star = []
        for i in range(pts * 2):
            r = 0.40 if i % 2 == 0 else 0.26
            a = -math.pi / 2 + i * math.pi / pts
            star.append((0.5 + math.cos(a) * r, 0.60 + math.sin(a) * r))
        p.poly(star, shade)
    p.ell(0.5, 0.60, 0.27, 0.27, fill=face)
    p.ell(0.5, 0.60, 0.20, 0.20, fill=shade)
    p.text(0.5, 0.60, str(tier), 0.20, face, weight=0.22)
    p.keyline()


def i_mi_reload(p):
    p.arc(0.5, 0.5, 0.36, 0.36, 300, 210, OLIVE, 0.115)
    # arc ends at 210deg; drop the head there, pointing along the tangent
    a = math.radians(210)
    tx, ty = 0.5 + math.cos(a) * 0.36, 0.5 + math.sin(a) * 0.36
    p.poly([(tx - 0.19, ty - 0.02), (tx + 0.05, ty - 0.17), (tx + 0.07, ty + 0.13)], BRASS)
    p.keyline()


def i_mi_settings(p):
    teeth = 9
    pts = []
    for i in range(teeth):
        a0 = i * 2 * math.pi / teeth
        for da, r in ((-0.13, 0.34), (-0.09, 0.47), (0.09, 0.47), (0.13, 0.34)):
            pts.append((0.5 + math.cos(a0 + da) * r, 0.5 + math.sin(a0 + da) * r))
    p.poly(pts, OLIVE)
    p.ell(0.5, 0.5, 0.30, 0.30, fill=OLIVE_D)
    p.ell(0.5, 0.5, 0.17, 0.17, fill=(38, 40, 36))
    p.keyline()


def i_mi_timer(p):
    p.rect(0.42, 0.06, 0.58, 0.17, STEEL_D, r=0.03)
    p.ell(0.5, 0.58, 0.40, 0.40, fill=BRASS_D)
    p.ell(0.5, 0.58, 0.335, 0.335, fill=(238, 232, 210))
    for i in range(12):
        a = i * math.pi / 6
        p.line([(0.5 + math.cos(a) * 0.285, 0.58 + math.sin(a) * 0.285),
                (0.5 + math.cos(a) * 0.245, 0.58 + math.sin(a) * 0.245)], (90, 84, 70), 0.016)
    p.line([(0.5, 0.58), (0.5, 0.36)], (54, 50, 42), 0.026)
    p.line([(0.5, 0.58), (0.66, 0.66)], (54, 50, 42), 0.026)
    p.ell(0.5, 0.58, 0.030, 0.030, fill=(150, 44, 38))
    p.keyline()


def _note(p, c, c_d):
    p.ell(0.30, 0.78, 0.145, 0.115, fill=c)
    p.ell(0.72, 0.68, 0.145, 0.115, fill=c)
    p.rect(0.415, 0.16, 0.465, 0.79, c)
    p.rect(0.835, 0.06, 0.885, 0.69, c)
    p.poly([(0.415, 0.16), (0.885, 0.06), (0.885, 0.21), (0.415, 0.31)], c_d)


def i_mus_on(p):
    _note(p, (214, 218, 210), (162, 166, 158))
    p.keyline()


def i_mus_off(p):
    _note(p, (150, 154, 148), (108, 112, 106))
    p.line([(0.10, 0.10), (0.90, 0.90)], (196, 76, 66), 0.075)
    p.keyline()


def i_play(p):
    p.poly([(0.26, 0.12), (0.86, 0.50), (0.26, 0.88)], (214, 220, 212))
    p.poly([(0.26, 0.50), (0.86, 0.50), (0.26, 0.88)], (166, 172, 164))
    p.keyline()


def _speaker(p, c, c_d):
    p.poly([(0.10, 0.38), (0.26, 0.38), (0.46, 0.16), (0.46, 0.84),
            (0.26, 0.62), (0.10, 0.62)], c)
    p.poly([(0.10, 0.50), (0.46, 0.50), (0.46, 0.84), (0.26, 0.62), (0.10, 0.62)], c_d)


def i_snd_on(p):
    _speaker(p, (214, 220, 212), (166, 172, 164))
    for i, r in enumerate((0.14, 0.24, 0.34)):
        p.arc(0.52, 0.50, r, r, -58, 58, (214, 220, 212), 0.042 - i * 0.006)
    p.keyline()


def i_snd_off(p):
    _speaker(p, (150, 154, 148), (108, 112, 106))
    p.line([(0.58, 0.34), (0.90, 0.66)], (196, 76, 66), 0.070)
    p.line([(0.90, 0.34), (0.58, 0.66)], (196, 76, 66), 0.070)
    p.keyline()


def i_trophy(p):
    p.poly([(0.26, 0.14), (0.74, 0.14), (0.68, 0.58), (0.32, 0.58)], GOLD)
    p.poly([(0.50, 0.14), (0.74, 0.14), (0.68, 0.58), (0.50, 0.58)], GOLD_D)
    for flip in (1, -1):
        cx = 0.5 + flip * 0.30
        p.arc(cx, 0.30, 0.14, 0.13, 0, 360, GOLD_D, 0.055)
    p.rect(0.44, 0.56, 0.56, 0.72, GOLD_D)
    p.rect(0.28, 0.72, 0.72, 0.84, WOOD, r=0.02)
    p.rect(0.22, 0.84, 0.78, 0.94, (96, 70, 42), r=0.02)
    star = []
    for i in range(10):
        r = 0.15 if i % 2 == 0 else 0.065
        a = -math.pi / 2 + i * math.pi / 5
        star.append((0.5 + math.cos(a) * r, 0.34 + math.sin(a) * r * 1.0))
    p.poly(star, (246, 226, 150))
    p.keyline()


# --- pickup / capability icons -----------------------------------------------
def _gun(p, kind: str):
    """Side-view weapon silhouettes for the capability strips (white masks).
    Canvas is 2:1, so everything is laid out along x."""
    W = (255, 255, 255)
    p.rect(0.06, 0.44, 0.60, 0.56, W, r=0.02)          # receiver
    p.poly([(0.04, 0.44), (0.04, 0.80), (0.22, 0.64), (0.22, 0.44)], W)   # stock
    if kind == "pierce":       # bolt-action: long thin barrel + scope
        p.rect(0.58, 0.47, 0.97, 0.525, W, r=0.01)
        p.rect(0.34, 0.28, 0.62, 0.39, W, r=0.02)      # scope
        p.rect(0.395, 0.36, 0.435, 0.46, W)            # front mount
        p.rect(0.535, 0.36, 0.575, 0.46, W)            # rear mount
        p.rect(0.44, 0.56, 0.52, 0.72, W, r=0.01)      # grip
    elif kind == "rend":       # carbine + straight mag
        p.rect(0.58, 0.46, 0.92, 0.54, W, r=0.01)
        p.rect(0.44, 0.56, 0.53, 0.82, W, r=0.015)
        p.rect(0.30, 0.56, 0.40, 0.74, W, r=0.015)
        p.rect(0.62, 0.38, 0.68, 0.46, W)
    elif kind == "spread":     # shotgun: fat barrel + pump
        p.rect(0.58, 0.44, 0.96, 0.545, W, r=0.02)
        p.rect(0.66, 0.56, 0.86, 0.65, W, r=0.02)      # pump
        p.rect(0.42, 0.56, 0.51, 0.78, W, r=0.015)
    else:                      # "triple": rifle with a banana mag
        p.rect(0.58, 0.46, 0.94, 0.54, W, r=0.01)
        p.poly([(0.40, 0.56), (0.52, 0.56), (0.58, 0.86), (0.44, 0.88)], W)
        p.rect(0.26, 0.56, 0.35, 0.72, W, r=0.015)
        p.rect(0.60, 0.37, 0.66, 0.46, W)


def i_cap_claymore(p):
    p.poly([(0.16, 0.34), (0.84, 0.34), (0.78, 0.70), (0.22, 0.70)], (86, 96, 64))
    p.poly([(0.16, 0.34), (0.84, 0.34), (0.82, 0.44), (0.18, 0.44)], (120, 132, 88))
    p.poly([(0.22, 0.70), (0.78, 0.70), (0.76, 0.76), (0.24, 0.76)], (58, 66, 42))
    for fx in (0.30, 0.70):
        p.line([(fx, 0.72), (fx - 0.06, 0.92)], (54, 58, 48), 0.030)
        p.line([(fx, 0.72), (fx + 0.06, 0.92)], (54, 58, 48), 0.030)
    p.text(0.5, 0.52, "-", 0.30, (216, 210, 180), weight=0.16)
    p.keyline(0.014)


def i_cap_flash(p):
    p.rect(0.36, 0.30, 0.64, 0.80, (198, 200, 196), r=0.06)
    p.rect(0.36, 0.42, 0.64, 0.50, (150, 154, 148))
    p.rect(0.36, 0.58, 0.64, 0.66, (150, 154, 148))
    p.rect(0.42, 0.20, 0.58, 0.32, (120, 124, 118), r=0.03)
    p.poly([(0.58, 0.21), (0.74, 0.16), (0.74, 0.25), (0.58, 0.28)], (188, 160, 60))
    for i in range(8):
        a = i * math.pi / 4
        p.line([(0.5 + math.cos(a) * 0.16, 0.24 + math.sin(a) * 0.16),
                (0.5 + math.cos(a) * 0.30, 0.24 + math.sin(a) * 0.30)],
               (250, 244, 196), 0.024)
    p.keyline(0.014)


def i_cap_smoke(p):
    p.rect(0.38, 0.34, 0.62, 0.84, (78, 86, 66), r=0.05)
    p.rect(0.38, 0.46, 0.62, 0.53, (52, 58, 44))
    p.rect(0.38, 0.62, 0.62, 0.69, (52, 58, 44))
    p.rect(0.44, 0.26, 0.56, 0.36, (104, 110, 98), r=0.02)
    for cx, cy, r in ((0.30, 0.20, 0.13), (0.50, 0.11, 0.15), (0.70, 0.20, 0.12),
                      (0.40, 0.15, 0.10), (0.62, 0.16, 0.10)):
        p.ell(cx, cy, r, r * 0.86, fill=(198, 202, 198))
    p.keyline(0.014)


def i_icon_ammo(p):
    for i, (x, ytop) in enumerate(((0.16, 0.28), (0.40, 0.20), (0.64, 0.30))):
        w = 0.20
        p.poly([(x, ytop + 0.10), (x + w / 2, ytop), (x + w, ytop + 0.10)], (168, 96, 52))
        p.rect(x, ytop + 0.09, x + w, 0.86, BRASS, r=0.02)
        p.rect(x, ytop + 0.09, x + w * 0.42, 0.86, (222, 186, 96), r=0.02)
        p.rect(x, 0.76, x + w, 0.86, BRASS_D, r=0.02)
    p.keyline(0.018)


def i_icon_grenade(p):
    p.ell(0.50, 0.62, 0.32, 0.30, fill=OLIVE)
    p.ell(0.42, 0.54, 0.16, 0.14, fill=(132, 148, 84))
    for i in range(3):
        y = 0.46 + i * 0.16
        p.line([(0.19, y), (0.81, y)], OLIVE_D, 0.030)
    for i in range(2):
        x = 0.36 + i * 0.28
        p.line([(x, 0.34), (x, 0.90)], OLIVE_D, 0.030)
    p.rect(0.42, 0.20, 0.58, 0.36, (86, 92, 82), r=0.03)
    p.arc(0.66, 0.26, 0.16, 0.13, 150, 380, (176, 180, 172), 0.040)
    p.keyline(0.018)


def i_icon_coin(p):
    p.ell(0.50, 0.54, 0.42, 0.42, fill=(158, 108, 40))
    p.ell(0.50, 0.50, 0.42, 0.42, fill=(214, 154, 58))
    p.ell(0.50, 0.50, 0.33, 0.33, fill=(238, 190, 92))
    p.text(0.50, 0.50, "5", 0.36, (150, 100, 34), weight=0.20)
    p.keyline(0.018)


def i_icon_fuel(p):
    p.rect(0.18, 0.26, 0.74, 0.90, (170, 58, 48), r=0.06)
    p.rect(0.18, 0.26, 0.34, 0.90, (200, 78, 64), r=0.06)
    p.rect(0.30, 0.18, 0.50, 0.30, (140, 44, 38), r=0.03)
    p.arc(0.74, 0.36, 0.20, 0.16, 200, 340, (54, 56, 52), 0.055)
    p.rect(0.86, 0.34, 0.94, 0.44, (54, 56, 52), r=0.02)
    p.line([(0.30, 0.44), (0.62, 0.76)], (238, 226, 210), 0.055)
    p.line([(0.62, 0.44), (0.30, 0.76)], (238, 226, 210), 0.055)
    p.keyline(0.018)


def i_icon_airstrike(p):
    # side-view bomb, nose right: body capsule + tail fins + nose cone
    p.rect(0.24, 0.36, 0.74, 0.64, OLIVE, r=0.14)
    p.rect(0.24, 0.50, 0.74, 0.64, OLIVE_D, r=0.14)
    p.poly([(0.72, 0.36), (0.94, 0.50), (0.72, 0.64)], (132, 148, 84))
    p.poly([(0.30, 0.38), (0.10, 0.20), (0.10, 0.44), (0.26, 0.46)], (132, 148, 84))
    p.poly([(0.30, 0.62), (0.10, 0.80), (0.10, 0.56), (0.26, 0.54)], (86, 98, 56))
    p.rect(0.16, 0.44, 0.30, 0.56, (70, 80, 46), r=0.04)
    p.line([(0.36, 0.44), (0.36, 0.56)], (70, 80, 46), 0.028)
    p.keyline(0.018)


def i_icon_medal(p):
    i_medal(p, 1)


def i_icon_skull(p):
    p.ell(0.50, 0.44, 0.36, 0.34, fill=(226, 224, 212))
    p.rect(0.32, 0.62, 0.68, 0.86, (226, 224, 212), r=0.07)
    p.rect(0.32, 0.72, 0.68, 0.80, (196, 192, 178))
    for fx in (0.36, 0.64):
        p.ell(fx, 0.46, 0.115, 0.125, fill=(38, 38, 34))
    p.poly([(0.50, 0.54), (0.57, 0.68), (0.43, 0.68)], (38, 38, 34))
    for fx in (0.41, 0.50, 0.59):
        p.rect(fx - 0.018, 0.78, fx + 0.018, 0.90, (150, 148, 138))
    p.keyline(0.018)


def i_icon_vest(p):
    p.poly([(0.16, 0.26), (0.36, 0.20), (0.50, 0.32), (0.64, 0.20),
            (0.84, 0.26), (0.88, 0.86), (0.12, 0.86)], (108, 118, 128))
    p.poly([(0.12, 0.60), (0.88, 0.60), (0.88, 0.86), (0.12, 0.86)], (76, 84, 94))
    p.poly([(0.36, 0.20), (0.50, 0.32), (0.64, 0.20), (0.58, 0.44), (0.42, 0.44)],
           (58, 64, 72))
    p.line([(0.20, 0.40), (0.80, 0.52)], (120, 84, 52), 0.045)
    p.line([(0.80, 0.40), (0.20, 0.52)], (120, 84, 52), 0.045)
    p.rect(0.44, 0.56, 0.56, 0.70, (150, 158, 166), r=0.02)
    p.keyline(0.018)


def i_icon_rend(p):
    """64px sibling of the 128px pickups -- one cartridge, drawn fatter so it
    survives the smaller canvas."""
    p.poly([(0.32, 0.24), (0.50, 0.08), (0.68, 0.24)], (168, 96, 52))
    p.rect(0.32, 0.22, 0.68, 0.92, BRASS, r=0.05)
    p.rect(0.32, 0.22, 0.46, 0.92, (222, 186, 96), r=0.05)
    p.rect(0.32, 0.78, 0.68, 0.92, BRASS_D, r=0.05)
    p.keyline(0.030)


MENU = {
    "book": i_book, "controller": i_controller, "keyboard": i_keyboard,
    "mi_arrow": i_mi_arrow, "mi_back": i_mi_back, "mi_camera": i_mi_camera,
    "mi_cancel": i_mi_cancel, "mi_combat": i_mi_combat, "mi_home": i_mi_home,
    "mi_reload": i_mi_reload, "mi_settings": i_mi_settings, "mi_timer": i_mi_timer,
    "mus_off": i_mus_off, "mus_on": i_mus_on, "play": i_play,
    "snd_off": i_snd_off, "snd_on": i_snd_on, "trophy": i_trophy,
}
PICK = {
    "cap_claymore": i_cap_claymore, "cap_flash": i_cap_flash, "cap_smoke": i_cap_smoke,
    "icon_ammo": i_icon_ammo, "icon_grenade": i_icon_grenade, "icon_coin": i_icon_coin,
    "icon_fuel": i_icon_fuel, "icon_airstrike": i_icon_airstrike,
    "icon_medal": i_icon_medal, "icon_skull": i_icon_skull, "icon_vest": i_icon_vest,
    "icon_rend": i_icon_rend,
}


def build(key: str, w: int, h: int) -> Image.Image:
    stem = key.rsplit("/", 1)[1]
    p = Pad(w, h)
    if stem == "mi_controller":            # white mask
        i_mi_controller(p)
        return mask_out(p)
    if stem.startswith("cap_") and stem[4:] in ("pierce", "rend", "spread", "triple"):
        _gun(p, stem[4:])
        return mask_out(p)
    if stem.startswith("mi_medal_"):
        i_medal(p, int(stem[-1]))
        return p.out()
    if stem in MENU:
        MENU[stem](p)
        return p.out()
    if stem in PICK:
        PICK[stem](p)
        return p.out()
    raise KeyError(key)


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
