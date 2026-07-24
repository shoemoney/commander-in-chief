#!/usr/bin/env python3
"""Procedurally generate the remaining encumbered entity sprites.

This is the last licence blocker for an open-source release: 94 images across
assets/art/{decor,p2,mil2,cast2}, the 7 loose sprites at assets/art/ top level,
and the 9 in assets/soldiers/ (a SECOND purchased pack, no licence file). See
OPEN_SOURCE_CHECKLIST.md sections 1, 1b.

WHY PROCEDURAL RATHER THAN GENERATIVE-AI
tools/regen_entities.py drives an image model with the old sprite as reference.
It works for vehicles, but its own header records that the CHARACTER category is
not ship-ready: across three prompt revisions the model kept returning a 3/4
STANDING figure instead of a true 90-degree overhead one, the installed pilot
graded C+/B- against the bakes it replaced, and it was reverted.

Drawing the figure analytically sidesteps that failure entirely -- the camera
angle is not something the model has to be talked into, it is just the geometry
I choose. It also suits the actual pixel budget: these sprites are TINY on
screen (item_bullet 10px, ammobox 16px, weapon pickups 12-22px, soldiers 64px,
the largest vehicle 75px), so the outer silhouette carries the whole read and
interior detail is wasted. That is the same argument that cleared assets/art/fx
and the ui/hud/icons chrome, and the same house style.

CONVENTIONS
  * every figure faces NORTH (up), matching the packs these replace, so
    art.gd's rotation math is unchanged.
  * SIZES is the manifest -- one entry per file this tool owns.
  * each sprite keeps its ORIGINAL canvas size, so Art.SCALE and every draw
    site are untouched.

    python3 tools/gen_entities.py --family human
    python3 tools/gen_entities.py --outdir /tmp/x --only cast2/hero1
"""
from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen_ui_icons  # noqa: E402
from gen_ui_icons import Pad, mask_out  # noqa: E402  (proven canvas + ink keyline)


def _pad(n: int, m: int | None = None) -> Pad:
    """Pad with a canvas-appropriate supersample.

    gen_ui_icons draws at SS=3, which is right for a 128px icon and ruinous for
    a 1024px one: 3072x3072 with a 60px morphological keyline filter takes
    minutes per sprite. These canvases are already large enough to carry the
    shapes, and the .import size_limit knocks most of them back to 128 anyway,
    so scale the supersample down as the canvas grows.
    """
    gen_ui_icons.SS = 1 if n >= 512 else (2 if n >= 240 else 3)
    pad = Pad(n, m if m is not None else n)
    # centre/half-extent rounded rect -- every figure below is laid out from a
    # centreline, and corner coords make that unreadable.
    pad.rrect_c = lambda cx, cy, hw, hh, r, fill: pad.rect(
        cx - hw, cy - hh, cx + hw, cy + hh, fill, r=r)
    return pad

PROJECT_ROOT = Path(__file__).resolve().parent.parent
ART = PROJECT_ROOT / "assets/art"
SOLDIERS = PROJECT_ROOT / "assets/soldiers"

# --- palettes ----------------------------------------------------------------
# art.gd multiplies most of these by an olive Art.tint at draw time, so the
# source stays fairly neutral and leans on VALUE contrast rather than hue.
class P:
    SKIN = (176, 132, 96)
    HELM_A = (108, 116, 78)      # allied olive
    HELM_A_D = (72, 78, 50)
    HELM_E = (128, 68, 58)       # enemy crimson (red-faction convention)
    HELM_E_D = (86, 42, 36)
    HELM_C = (118, 112, 96)      # civilian / contractor tan
    HELM_C_D = (80, 76, 62)
    CLOTH = (96, 104, 70)
    CLOTH_D = (62, 68, 44)
    GUN = (44, 46, 42)
    GUN_HI = (86, 90, 84)
    BOOT = (52, 44, 36)
    STEEL = (140, 146, 140)
    STEEL_D = (86, 92, 86)
    SAND = (196, 172, 120)
    SAND_D = (140, 118, 76)
    RUST = (128, 78, 46)
    CHAR = (38, 36, 34)          # burnt / charred
    CHAR_HI = (74, 70, 64)
    OLIVE = (104, 118, 62)
    OLIVE_D = (68, 78, 40)
    BLOOD = (118, 38, 32)
    WATER = (58, 82, 92)


# --- the overhead figure -----------------------------------------------------
def person(p: Pad, *, helm=P.HELM_A, helm_d=P.HELM_A_D, cloth=P.CLOTH,
           cloth_d=P.CLOTH_D, weapon="rifle", prone=False, pack=None,
           shield=False, arms_out=False, scale=1.0, keyline=0.020):
    """A soldier seen from a CEILING camera, facing north.

    Drawn back-to-front the way the camera stacks it: boots, then the torso,
    then the pack, then the arms as SEPARATE limbs reaching forward onto the
    weapon, then the weapon, and the helmet crown last because from directly
    above it occludes everything. Keeping the arms a distinct value from the
    torso is what stops the whole thing reading as one domed blob.
    """
    cx, cy = 0.5, 0.50
    s = scale
    hi = tuple(min(255, int(c * 1.34)) for c in cloth)

    if prone:
        # lying flat: a long narrow body along the north axis, ragged if ghillie
        p.rrect_c(cx, cy + 0.06 * s, 0.150 * s, 0.300 * s, 0.10, cloth)
        p.rrect_c(cx, cy + 0.19 * s, 0.130 * s, 0.150 * s, 0.09, cloth_d)
        _weapon_overhead(p, cx, cy - 0.06 * s, s, weapon)
        p.ell(cx, cy - 0.20 * s, 0.100 * s, 0.092 * s, fill=helm)
        p.ell(cx, cy - 0.215 * s, 0.078 * s, 0.072 * s, fill=helm_d)
        p.keyline(keyline)
        return

    # boots -- two dark toe caps peeking south of the torso
    for sx in (-1, 1):
        p.rrect_c(cx + sx * 0.085 * s, cy + 0.215 * s, 0.052 * s, 0.055 * s, 0.02, P.BOOT)

    # torso: WIDE and SHORT. A tall ellipse reads as a beetle from above.
    p.rrect_c(cx, cy + 0.045 * s, 0.205 * s, 0.135 * s, 0.075, cloth)
    p.rrect_c(cx, cy + 0.115 * s, 0.205 * s, 0.065 * s, 0.055, cloth_d)   # shadowed back

    if pack:
        p.rrect_c(cx, cy + 0.150 * s, 0.115 * s, 0.075 * s, 0.03, pack)

    # arms: distinct limbs, lighter than the torso, reaching FORWARD to the grip
    grip_x, grip_y = cx + 0.105 * s, cy - 0.120 * s
    spread = 0.275 if arms_out else 0.235
    for sx in (-1, 1):
        p.line([(cx + sx * spread * s, cy + 0.010 * s),
                (grip_x - sx * 0.010 * s, grip_y + 0.030 * s)], hi, 0.072 * s)
        p.ell(cx + sx * spread * s, cy + 0.010 * s, 0.042 * s, 0.042 * s, fill=hi)

    if weapon:
        _weapon_overhead(p, cx, cy, s, weapon)

    if shield:
        p.rrect_c(cx, cy - 0.150 * s, 0.255 * s, 0.145 * s, 0.04, P.STEEL)
        p.rrect_c(cx, cy - 0.095 * s, 0.255 * s, 0.090 * s, 0.04, P.STEEL_D)

    # helmet crown last: from directly overhead nothing sits above it
    p.ell(cx - 0.020 * s, cy - 0.035 * s, 0.100 * s, 0.096 * s, fill=helm)
    p.ell(cx - 0.020 * s, cy - 0.044 * s, 0.082 * s, 0.078 * s, fill=helm_d)
    p.ell(cx - 0.044 * s, cy - 0.072 * s, 0.032 * s, 0.026 * s, fill=helm)
    p.keyline(keyline)


def _weapon_overhead(p: Pad, cx, cy, s, kind: str):
    """The gun from above: a receiver block with a barrel running north.

    Offset to the firing side so it reads as HELD, not as an antenna sprouting
    from the middle of the head.
    """
    x = cx + 0.105 * s
    spec = {              # (barrel len, barrel half-width, receiver len, stock)
        "rifle":    (0.255, 0.045, 0.140, True),
        "smg":      (0.175, 0.045, 0.115, True),
        "lmg":      (0.280, 0.058, 0.175, True),
        "sniper":   (0.335, 0.038, 0.150, True),
        "shotgun":  (0.235, 0.052, 0.135, True),
        "pistol":   (0.100, 0.040, 0.070, False),
        "speargun": (0.300, 0.040, 0.120, False),
        "rpg":      (0.280, 0.070, 0.160, False),
    }.get(kind)
    if spec is None:
        return
    blen, bw, rlen, stock = spec
    top = cy - 0.055 * s - blen * s
    p.rrect_c(x, cy - 0.055 * s - blen * s / 2, bw * s, blen * s / 2, 0.012, P.GUN)
    p.rrect_c(x, cy - 0.020 * s, 0.052 * s, rlen * s / 2, 0.018, P.GUN)
    p.rrect_c(x - 0.014 * s, cy - 0.020 * s, 0.020 * s, rlen * s / 2.4, 0.012, P.GUN_HI)
    if stock:
        p.rrect_c(x, cy + 0.055 * s, 0.040 * s, 0.052 * s, 0.015, P.GUN)
    if kind == "lmg":     # box magazine slung under the receiver
        p.rrect_c(x + 0.055 * s, cy + 0.010 * s, 0.040 * s, 0.055 * s, 0.012, P.GUN_HI)
    if kind == "sniper":  # scope
        p.rrect_c(x, cy - 0.120 * s, 0.026 * s, 0.055 * s, 0.012, P.GUN_HI)
    if kind == "speargun":
        p.poly([(x, top - 0.055 * s), (x + 0.045 * s, top),
                (x - 0.045 * s, top)], P.STEEL)
    if kind == "rpg":
        p.poly([(x, top - 0.070 * s), (x + 0.070 * s, top),
                (x - 0.070 * s, top)], P.RUST)


# --- the manifest ------------------------------------------------------------
# key -> (family, canvas, kwargs). Canvas comes from the sprite being replaced.
HUMANS: dict[str, dict] = {
    # --- assets/soldiers/ : the purchased-pack replacements (most-seen art) ---
    "SOL:soldier_assault_rifle": dict(canvas=1024, weapon="rifle",
                                      helm=P.HELM_A, helm_d=P.HELM_A_D),
    "SOL:enemy/enemy_assault_rifle": dict(canvas=1024, weapon="rifle",
                                          helm=P.HELM_E, helm_d=P.HELM_E_D),
    "SOL:enemy/enemy_smg": dict(canvas=1024, weapon="smg",
                                helm=P.HELM_E, helm_d=P.HELM_E_D),
    "SOL:enemy/enemy_shotgun": dict(canvas=1024, weapon="shotgun",
                                    helm=P.HELM_E, helm_d=P.HELM_E_D),
    "SOL:enemy/enemy_lmg": dict(canvas=1024, weapon="lmg", arms_out=True,
                                helm=P.HELM_E, helm_d=P.HELM_E_D),
    "SOL:enemy/enemy_sniper": dict(canvas=1024, weapon="sniper",
                                   helm=P.HELM_E, helm_d=P.HELM_E_D),
    "SOL:frogman_rifle": dict(canvas=1024, weapon="rifle", helm=(52, 68, 74),
                              helm_d=(34, 46, 52), cloth=(46, 62, 68),
                              cloth_d=(30, 42, 48)),
    "SOL:frogman_speargun": dict(canvas=1024, weapon="speargun", helm=(52, 68, 74),
                                 helm_d=(34, 46, 52), cloth=(46, 62, 68),
                                 cloth_d=(30, 42, 48)),
    # --- cast2 / p2 / mil2 humans -------------------------------------------
    "cast2/hero1": dict(canvas=300, weapon="rifle"),
    "cast2/hero2": dict(canvas=300, weapon="smg"),
    "cast2/insurgent1": dict(canvas=300, weapon="rifle",
                             helm=P.HELM_E, helm_d=P.HELM_E_D),
    "cast2/insurgent2": dict(canvas=300, weapon="lmg", arms_out=True,
                             helm=P.HELM_E, helm_d=P.HELM_E_D),
    "cast2/observer2": dict(canvas=300, weapon="pistol", helm=P.HELM_C,
                            helm_d=P.HELM_C_D, pack=(78, 84, 62)),
    "mil2/soldier2": dict(canvas=1024, weapon="rifle", arms_out=True,
                          helm=P.HELM_E, helm_d=P.HELM_E_D),
    "mil2/insurgent3": dict(canvas=64, weapon="rifle",
                            helm=P.HELM_E, helm_d=P.HELM_E_D),
    "mil2/insurgent4": dict(canvas=64, weapon="smg",
                            helm=P.HELM_E, helm_d=P.HELM_E_D),
    "mil2/insurgent5": dict(canvas=64, weapon="shotgun",
                            helm=P.HELM_E, helm_d=P.HELM_E_D),
    "mil2/contractor2": dict(canvas=64, weapon="rifle", helm=P.HELM_C,
                             helm_d=P.HELM_C_D),
    "mil2/pilot": dict(canvas=56, weapon="pistol", helm=(150, 154, 148),
                       helm_d=(96, 100, 96), scale=0.92),
    "mil2/bombsuit": dict(canvas=1024, weapon=None, scale=1.14,
                          helm=(122, 126, 112), helm_d=(84, 88, 76),
                          cloth=(126, 130, 114), cloth_d=(82, 86, 74)),
    "p2/sapper": dict(canvas=1024, weapon="smg", pack=(84, 74, 52),
                      helm=P.HELM_E, helm_d=P.HELM_E_D),
    "p2/ghillie": dict(canvas=1024, weapon="sniper", prone=True,
                       cloth=(96, 100, 62), cloth_d=(64, 70, 40)),
    "p2/courier": dict(canvas=64, weapon="pistol", pack=(96, 76, 48),
                       helm=P.HELM_C, helm_d=P.HELM_C_D),
    # the older 56px frogman, kept alongside the soldiers/ pair it predates
    "frogman": dict(canvas=56, weapon="rifle", helm=(52, 68, 74), helm_d=(34, 46, 52),
                    cloth=(46, 62, 68), cloth_d=(30, 42, 48)),
    "p2/riot_shield": dict(canvas=64, weapon=None, shield=True,
                           helm=P.HELM_E, helm_d=P.HELM_E_D),
}


def _corpse(p: Pad, *, cloth, cloth_d, helm, helm_d, blood=True):
    """A body sprawled face-down -- arms and legs splayed, not a tidy figure."""
    cx, cy = 0.5, 0.52
    if blood:
        p.ell(cx, cy + 0.05, 0.29, 0.24, fill=(62, 30, 26))
    for a, ln in ((-0.9, 0.30), (-2.3, 0.28), (0.85, 0.31), (2.35, 0.27)):
        p.line([(cx, cy), (cx + math.cos(a) * ln, cy + math.sin(a) * ln)],
               cloth_d, 0.075)
    p.ell(cx, cy + 0.02, 0.17, 0.20, fill=cloth)
    p.d.chord([(cx - 0.17) * p.W, (cy - 0.18) * p.H,
               (cx + 0.17) * p.W, (cy + 0.22) * p.H], 0, 180, fill=cloth_d)
    p.ell(cx - 0.02, cy - 0.19, 0.105, 0.100, fill=helm)
    p.ell(cx - 0.02, cy - 0.205, 0.085, 0.080, fill=helm_d)
    p.keyline(0.020)


CORPSES = {
    "p2/corpse_soldier1": dict(canvas=140, cloth=P.CLOTH, cloth_d=P.CLOTH_D,
                               helm=P.HELM_E, helm_d=P.HELM_E_D),
    "p2/corpse_soldier2": dict(canvas=140, cloth=(88, 82, 62), cloth_d=(58, 54, 40),
                               helm=P.HELM_C, helm_d=P.HELM_C_D),
    "decor/fallen_merc": dict(canvas=180, cloth=(82, 88, 68), cloth_d=(54, 58, 44),
                              helm=P.HELM_C, helm_d=P.HELM_C_D),
}


# =============================================================================
# OBJECTS -- vehicles, structures, props, terrain, weapons, pickups, FX.
# All drawn from directly overhead like the figures above. These are the easy
# half: they are geometry, and most land at 10-75px on screen where the outer
# silhouette is the entire read.
# =============================================================================
def _tracks(p, cx, cy, hw, hh, col=(46, 48, 44)):
    """Two dark track runs flanking a hull -- the tracked-vehicle tell."""
    for sx in (-1, 1):
        p.rrect_c(cx + sx * hw, cy, hw * 0.30, hh, 0.02, col)
        for i in range(7):
            y = cy - hh + (i + 0.5) * (2 * hh / 7)
            p.line([(cx + sx * hw - hw * 0.30, y), (cx + sx * hw + hw * 0.30, y)],
                   (78, 80, 74), 0.012)


def _wheels(p, cx, cy, hw, hh, n=3, col=(40, 42, 38)):
    for sx in (-1, 1):
        for i in range(n):
            y = cy - hh * 0.72 + i * (1.44 * hh / max(1, n - 1))
            p.rrect_c(cx + sx * hw, y, hw * 0.26, hh * 0.20, 0.02, col)


def _burnt(p, cx, cy, hw, hh):
    """Scorch + a blown-open hole: what makes a hull read as a WRECK."""
    p.ell(cx, cy, hw * 0.95, hh * 0.85, fill=(30, 28, 26))
    p.ell(cx + hw * 0.12, cy - hh * 0.10, hw * 0.42, hh * 0.34, fill=(16, 15, 14))
    p.ell(cx - hw * 0.30, cy + hh * 0.30, hw * 0.26, hh * 0.20, fill=(20, 19, 18))


def o_technical(p):        # live militia pickup -- the MG is the hero feature
    p.rrect_c(0.5, 0.52, 0.24, 0.40, 0.06, P.OLIVE)
    p.rrect_c(0.5, 0.30, 0.20, 0.16, 0.05, P.OLIVE_D)          # cab roof
    p.rrect_c(0.5, 0.66, 0.235, 0.24, 0.04, (58, 66, 40))      # cargo bed
    _wheels(p, 0.5, 0.52, 0.245, 0.36, 2)
    p.ell(0.5, 0.66, 0.155, 0.150, fill=(38, 40, 36))          # turret ring, oversized
    p.ell(0.5, 0.66, 0.105, 0.100, fill=(64, 68, 60))
    p.rrect_c(0.5, 0.40, 0.038, 0.22, 0.01, (26, 28, 24))      # MG barrel overhanging
    p.keyline(0.018)


def o_apc(p):
    p.rrect_c(0.5, 0.50, 0.26, 0.42, 0.07, (62, 66, 58))
    _tracks(p, 0.5, 0.50, 0.265, 0.40)
    _burnt(p, 0.5, 0.50, 0.24, 0.38)
    p.keyline(0.018)


def o_light_tank(p):
    p.rrect_c(0.5, 0.54, 0.24, 0.36, 0.06, (60, 64, 56))
    _tracks(p, 0.5, 0.54, 0.245, 0.34)
    p.ell(0.5, 0.50, 0.175, 0.170, fill=(46, 50, 44))          # turret, askew
    p.rrect_c(0.60, 0.24, 0.040, 0.20, 0.01, (34, 36, 32))     # barrel, broken angle
    _burnt(p, 0.5, 0.54, 0.20, 0.30)
    p.keyline(0.018)


def o_radar_tank(p):
    p.rrect_c(0.5, 0.54, 0.24, 0.38, 0.06, P.OLIVE_D)
    _tracks(p, 0.5, 0.54, 0.245, 0.36)
    p.ell(0.5, 0.48, 0.315, 0.300, fill=(52, 58, 44))          # dish dominates
    p.ell(0.5, 0.48, 0.235, 0.225, fill=(150, 156, 142))
    p.ell(0.5, 0.48, 0.120, 0.115, fill=(64, 70, 58))
    p.ell(0.5, 0.48, 0.040, 0.038, fill=(214, 210, 190))
    p.keyline(0.018)


def o_rocket_truck(p):
    p.rrect_c(0.5, 0.60, 0.23, 0.34, 0.05, P.OLIVE)
    p.rrect_c(0.5, 0.26, 0.19, 0.14, 0.04, P.OLIVE_D)
    _wheels(p, 0.5, 0.58, 0.24, 0.32, 3)
    p.rrect_c(0.5, 0.58, 0.205, 0.235, 0.03, (44, 48, 40))     # tube block
    for r in range(4):
        for c in range(4):
            p.ell(0.5 + (c - 1.5) * 0.093, 0.58 + (r - 1.5) * 0.105,
                  0.036, 0.036, fill=(20, 22, 18))
    p.keyline(0.018)


def o_heli(p, attack: bool):
    if attack:
        p.poly([(0.5, 0.06), (0.585, 0.40), (0.565, 0.86), (0.435, 0.86),
                (0.415, 0.40)], (60, 68, 50))
        p.rrect_c(0.5, 0.44, 0.245, 0.045, 0.02, (48, 54, 40))     # stub wings
        for sx in (-1, 1):
            p.rrect_c(0.5 + sx * 0.205, 0.44, 0.055, 0.070, 0.02, (34, 38, 30))
    else:
        p.rrect_c(0.5, 0.50, 0.215, 0.360, 0.16, (66, 72, 56))     # fat cargo hull
        p.ell(0.5, 0.24, 0.185, 0.130, fill=(52, 58, 44))
    p.rrect_c(0.5, 0.90, 0.030, 0.090, 0.01, (44, 48, 40))         # tail boom
    for a in (0.30, 1.87, -1.27):                                   # rotor bars
        p.line([(0.5 - math.cos(a) * 0.47, 0.46 - math.sin(a) * 0.47),
                (0.5 + math.cos(a) * 0.47, 0.46 + math.sin(a) * 0.47)],
               (34, 36, 32), 0.036)
    p.ell(0.5, 0.46, 0.052, 0.052, fill=(24, 26, 22))
    p.keyline(0.016)


def o_jet(p):
    p.poly([(0.5, 0.03), (0.565, 0.30), (0.545, 0.80), (0.455, 0.80),
            (0.435, 0.30)], (118, 124, 116))
    p.poly([(0.545, 0.40), (0.96, 0.74), (0.96, 0.82), (0.535, 0.66)], (96, 102, 94))
    p.poly([(0.455, 0.40), (0.04, 0.74), (0.04, 0.82), (0.465, 0.66)], (96, 102, 94))
    p.poly([(0.535, 0.80), (0.74, 0.96), (0.50, 0.94)], (86, 92, 84))
    p.poly([(0.465, 0.80), (0.26, 0.96), (0.50, 0.94)], (86, 92, 84))
    p.ell(0.5, 0.26, 0.052, 0.090, fill=(52, 66, 74))
    p.keyline(0.014)


def o_drone(p):
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.line([(0.5, 0.5), (0.5 + sx * 0.33, 0.5 + sy * 0.33)], (44, 46, 42), 0.075)
            p.ell(0.5 + sx * 0.35, 0.5 + sy * 0.35, 0.150, 0.150, fill=(30, 32, 28))
    p.rrect_c(0.5, 0.5, 0.135, 0.135, 0.05, (64, 70, 58))
    p.ell(0.5, 0.5, 0.055, 0.055, fill=(38, 52, 62))
    p.keyline(0.018)


def o_tank_hulk(p):
    p.rrect_c(0.5, 0.52, 0.25, 0.38, 0.06, (54, 52, 48))
    _tracks(p, 0.5, 0.52, 0.255, 0.36)
    p.ell(0.5, 0.46, 0.180, 0.175, fill=(42, 40, 38))
    p.rrect_c(0.5, 0.20, 0.042, 0.16, 0.01, (30, 30, 28))
    _burnt(p, 0.5, 0.52, 0.21, 0.32)
    p.keyline(0.018)


def o_wreck(p):
    p.rrect_c(0.5, 0.52, 0.26, 0.34, 0.08, (52, 48, 44))
    _burnt(p, 0.5, 0.52, 0.25, 0.32)
    p.keyline(0.020)


def o_wreck_halftrack(p):
    p.rrect_c(0.5, 0.50, 0.23, 0.38, 0.05, (52, 50, 46))
    _tracks(p, 0.5, 0.62, 0.235, 0.24)
    _wheels(p, 0.5, 0.26, 0.235, 0.12, 2)
    _burnt(p, 0.5, 0.50, 0.20, 0.34)
    p.keyline(0.018)


# --- structures --------------------------------------------------------------
def o_bunker(p):
    p.rrect_c(0.5, 0.52, 0.40, 0.34, 0.05, (170, 162, 138))
    p.rrect_c(0.5, 0.64, 0.40, 0.22, 0.05, (74, 70, 60))
    p.rrect_c(0.5, 0.34, 0.32, 0.085, 0.01, (18, 18, 16))       # firing slit, oversized
    for sx in (-1, 1):
        p.rrect_c(0.5 + sx * 0.315, 0.52, 0.075, 0.320, 0.03, (108, 102, 86))
    p.keyline(0.026)


def o_watchtower(p):
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.line([(0.5, 0.5), (0.5 + sx * 0.40, 0.5 + sy * 0.40)], (78, 62, 40), 0.055)
    p.rrect_c(0.5, 0.5, 0.245, 0.245, 0.04, (136, 108, 68))
    p.rrect_c(0.5, 0.5, 0.185, 0.185, 0.03, (92, 72, 46))
    p.keyline(0.016)


def o_radio_tower(p):
    p.poly([(0.5, 0.06), (0.94, 0.88), (0.06, 0.88)], None, outline=(96, 100, 92),
           width=0.045)
    p.line([(0.5, 0.06), (0.5, 0.88)], (86, 90, 82), 0.030)
    p.ell(0.5, 0.50, 0.090, 0.090, fill=(176, 180, 168))
    p.keyline(0.016)


def o_tent(p):
    p.poly([(0.10, 0.86), (0.30, 0.14), (0.70, 0.14), (0.90, 0.86)], (104, 112, 74))
    p.poly([(0.5, 0.14), (0.90, 0.86), (0.5, 0.86)], (70, 78, 48))
    p.line([(0.5, 0.14), (0.5, 0.86)], (150, 156, 118), 0.022)
    p.keyline(0.016)


def o_mg_stand(p):
    p.rrect_c(0.5, 0.62, 0.235, 0.150, 0.04, (150, 130, 92))     # sandbag nest
    for a in (0.9, 2.24, -1.57):
        p.line([(0.5, 0.52), (0.5 + math.cos(a) * 0.30, 0.52 + math.sin(a) * 0.30)],
               (54, 56, 50), 0.048)
    p.rrect_c(0.5, 0.30, 0.040, 0.240, 0.01, (34, 36, 32))
    p.ell(0.5, 0.52, 0.090, 0.090, fill=(46, 48, 44))
    p.keyline(0.018)


def o_mg_tripod(p):
    for a in (0.9, 2.24, -1.57):
        p.line([(0.5, 0.55), (0.5 + math.cos(a) * 0.34, 0.55 + math.sin(a) * 0.34)],
               (58, 60, 54), 0.055)
    p.rrect_c(0.5, 0.30, 0.042, 0.250, 0.01, (34, 36, 32))
    p.ell(0.5, 0.55, 0.095, 0.095, fill=(46, 48, 44))
    p.keyline(0.020)


def o_flak_gun(p):
    p.ell(0.5, 0.62, 0.230, 0.220, fill=(78, 84, 62))
    p.ell(0.5, 0.62, 0.150, 0.145, fill=(54, 60, 44))
    for sx in (-1, 1):
        p.rrect_c(0.5 + sx * 0.070, 0.28, 0.036, 0.260, 0.01, (36, 38, 34))
    _wheels(p, 0.5, 0.66, 0.235, 0.10, 1)
    p.keyline(0.018)


def o_wall_sandbag(p, end: bool):
    n = 3 if end else 6
    for r in range(2):
        for i in range(n):
            x = (i + 0.5) / n
            p.ell(x, 0.40 + r * 0.22, 0.5 / n * 0.92, 0.115,
                  fill=(190, 166, 116) if r == 0 else (146, 124, 82))
    p.keyline(0.016)


# --- terrain -----------------------------------------------------------------
def _crater(p, cx, cy, r, depth=(48, 40, 30)):
    p.ell(cx, cy, r, r * 0.88, fill=(198, 174, 122))     # thrown-sand rim
    p.ell(cx, cy, r * 0.70, r * 0.60, fill=depth)


def o_crater(p):
    _crater(p, 0.5, 0.5, 0.46)
    p.keyline(0.012)


def o_crater_field(p):
    for cx, cy, r in ((0.30, 0.34, 0.26), (0.68, 0.30, 0.18),
                      (0.56, 0.70, 0.29), (0.22, 0.74, 0.15)):
        _crater(p, cx, cy, r)
    p.keyline(0.010)


def o_crater_water(p):
    p.ell(0.5, 0.5, 0.46, 0.42, fill=(198, 174, 122))
    p.ell(0.5, 0.5, 0.33, 0.29, fill=P.WATER)
    p.ell(0.44, 0.44, 0.13, 0.09, fill=(86, 116, 126))
    p.keyline(0.012)


def o_trench(p):
    p.rrect_c(0.5, 0.30, 0.50, 0.115, 0.02, (186, 162, 112))   # spoil bank
    p.rrect_c(0.5, 0.70, 0.50, 0.115, 0.02, (186, 162, 112))
    p.rect(0.0, 0.40, 1.0, 0.60, (42, 36, 28))                 # the channel
    p.keyline(0.010)


def o_bridge(p, ramp: bool):
    if ramp:
        p.poly([(0.14, 0.02), (0.86, 0.02), (0.94, 0.98), (0.06, 0.98)], (128, 106, 72))
    else:
        p.rect(0.06, 0.02, 0.94, 0.98, (128, 106, 72))
    for i in range(9):
        y = 0.06 + i * 0.105
        p.line([(0.08, y), (0.92, y)], (92, 74, 48), 0.016)
    p.rect(0.06, 0.02, 0.13, 0.98, (74, 60, 40))
    p.rect(0.87, 0.02, 0.94, 0.98, (74, 60, 40))
    p.keyline(0.012)


def o_skyline_chimney(p):
    p.ell(0.5, 0.5, 0.44, 0.44, fill=(120, 84, 66))
    p.ell(0.5, 0.5, 0.30, 0.30, fill=(88, 62, 48))
    p.ell(0.5, 0.5, 0.19, 0.19, fill=(24, 22, 20))
    p.keyline(0.016)


def o_skyline_mast(p):
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.line([(0.5, 0.5), (0.5 + sx * 0.44, 0.5 + sy * 0.44)], (92, 96, 88), 0.026)
    p.rrect_c(0.5, 0.5, 0.115, 0.115, 0.03, (76, 80, 72))
    p.ell(0.5, 0.5, 0.055, 0.055, fill=(186, 92, 72))
    p.keyline(0.016)


# --- props -------------------------------------------------------------------
def o_ammobox(p):
    p.rrect_c(0.5, 0.54, 0.34, 0.26, 0.04, (52, 60, 36))
    p.rrect_c(0.5, 0.46, 0.34, 0.18, 0.04, (116, 128, 84))
    p.rrect_c(0.5, 0.44, 0.155, 0.050, 0.02, (44, 48, 38))     # carry handle
    p.keyline(0.024)


def o_barrel(p):
    p.ell(0.5, 0.52, 0.40, 0.40, fill=(56, 46, 30))
    p.ell(0.5, 0.50, 0.40, 0.40, fill=(140, 116, 70))
    p.ell(0.5, 0.50, 0.28, 0.28, fill=(112, 92, 56))
    p.ell(0.5, 0.50, 0.10, 0.10, fill=(70, 58, 36))
    p.keyline(0.026)


def o_barricade(p):
    p.rrect_c(0.5, 0.58, 0.44, 0.16, 0.03, (140, 118, 78))
    p.rrect_c(0.5, 0.44, 0.44, 0.13, 0.03, (190, 166, 116))
    for i in range(4):
        x = 0.18 + i * 0.215
        p.rrect_c(x, 0.52, 0.030, 0.230, 0.01, (92, 72, 46))
    p.keyline(0.022)


def o_barrier(p):
    p.poly([(0.14, 0.72), (0.24, 0.30), (0.76, 0.30), (0.86, 0.72)], (186, 182, 170))
    p.poly([(0.14, 0.72), (0.86, 0.72), (0.80, 0.84), (0.20, 0.84)], (68, 66, 60))
    p.keyline(0.022)


def o_crate_stack(p):
    p.rrect_c(0.42, 0.60, 0.30, 0.28, 0.03, (78, 60, 38))
    p.rrect_c(0.62, 0.40, 0.26, 0.24, 0.03, (150, 120, 76))
    p.rrect_c(0.36, 0.34, 0.22, 0.20, 0.03, (168, 138, 90))
    p.keyline(0.022)


def o_rock(p, big: bool):
    # rocks sit ON the tan ground, so a tan rock disappears -- go grey-brown and
    # keep a hard dark shadow half.
    r = 0.44 if big else 0.38
    pts = []
    for i in range(7):
        a = i * 2 * math.pi / 7
        rr = r * (0.78 + 0.22 * ((i * 5) % 3) / 2.0)
        pts.append((0.5 + math.cos(a) * rr, 0.52 + math.sin(a) * rr * 0.92))
    p.poly(pts, (104, 96, 84))
    p.poly([(x, y + 0.10) for x, y in pts[3:]] + [pts[3]], (54, 50, 44))
    p.poly([(0.5 + (x - 0.5) * 0.52, 0.46 + (y - 0.52) * 0.52) for x, y in pts],
           (156, 146, 126))
    p.keyline(0.024)


def o_tank_trap(p):
    for a in (0.52, 1.57 + 0.52, -0.52):
        p.line([(0.5 - math.cos(a) * 0.44, 0.5 - math.sin(a) * 0.44),
                (0.5 + math.cos(a) * 0.44, 0.5 + math.sin(a) * 0.44)],
               (120, 124, 116), 0.075)
    p.ell(0.5, 0.5, 0.075, 0.075, fill=(76, 80, 72))
    p.keyline(0.022)


def o_barbedwire(p):
    for sx in (0.10, 0.90):
        p.rrect_c(sx, 0.5, 0.045, 0.30, 0.02, (72, 58, 40))
    xs = [0.10 + i * 0.10 for i in range(9)]
    pts = [(x, 0.5 + (0.20 if i % 2 else -0.20)) for i, x in enumerate(xs)]
    p.line(pts, (150, 154, 146), 0.024)
    for x, y in pts:
        p.ell(x, y, 0.030, 0.030, fill=(186, 190, 182))
    p.keyline(0.020)


def o_landmine(p):
    p.ell(0.5, 0.5, 0.42, 0.40, fill=(112, 100, 74))
    p.ell(0.5, 0.5, 0.31, 0.29, fill=(66, 60, 46))
    p.ell(0.5, 0.5, 0.19, 0.18, fill=(140, 126, 92))
    p.ell(0.5, 0.5, 0.075, 0.070, fill=(40, 36, 28))
    p.keyline(0.016)


def o_dropped_shield(p):
    p.rrect_c(0.5, 0.52, 0.30, 0.42, 0.08, (62, 66, 62))
    p.rrect_c(0.5, 0.46, 0.30, 0.34, 0.08, (156, 162, 154))
    p.rrect_c(0.5, 0.52, 0.19, 0.055, 0.02, (48, 50, 46))
    p.keyline(0.026)


def o_flag_marker(p):
    p.rrect_c(0.34, 0.50, 0.035, 0.44, 0.01, (72, 62, 44))
    p.poly([(0.36, 0.14), (0.84, 0.30), (0.36, 0.46)], (196, 84, 62))
    p.keyline(0.022)


def o_sandbag(p):
    for r in range(2):
        for i in range(3):
            p.ell((i + 0.5) / 3, 0.38 + r * 0.24, 0.155, 0.125,
                  fill=(194, 170, 120) if r == 0 else (150, 128, 86))
    p.keyline(0.020)


def o_tree(p, big: bool):
    r = 0.44 if big else 0.40
    for i, (dx, dy, rr, c) in enumerate((
            (-0.13, 0.10, 0.78, (54, 74, 42)), (0.14, 0.12, 0.70, (62, 84, 48)),
            (0.02, -0.14, 0.86, (78, 102, 56)), (-0.05, 0.0, 0.60, (96, 122, 66)))):
        p.ell(0.5 + dx * r, 0.52 + dy * r, r * rr, r * rr * 0.94, fill=c)
    p.keyline(0.018)


# --- pickups -----------------------------------------------------------------
def o_crate(p, kind: str):
    body = {"ammo": (150, 122, 74), "grenade": (96, 110, 66),
            "airstrike": (140, 116, 78)}[kind]
    dark = tuple(int(c * 0.66) for c in body)
    p.rrect_c(0.5, 0.54, 0.38, 0.34, 0.05, dark)
    p.rrect_c(0.5, 0.46, 0.38, 0.28, 0.05, body)
    mark = {"ammo": (198, 160, 70), "grenade": (60, 70, 44), "airstrike": (188, 76, 58)}[kind]
    if kind == "ammo":
        for i in range(3):
            p.rrect_c(0.36 + i * 0.14, 0.46, 0.040, 0.115, 0.02, mark)
    elif kind == "grenade":
        p.ell(0.5, 0.46, 0.115, 0.115, fill=mark)
    else:
        p.poly([(0.5, 0.30), (0.66, 0.58), (0.34, 0.58)], mark)
    p.keyline(0.026)


def o_pickup_vest(p):
    p.poly([(0.20, 0.26), (0.38, 0.20), (0.5, 0.30), (0.62, 0.20), (0.80, 0.26),
            (0.84, 0.84), (0.16, 0.84)], (104, 114, 124))
    p.rect(0.16, 0.58, 0.84, 0.84, (72, 80, 90))
    p.rrect_c(0.5, 0.62, 0.085, 0.085, 0.02, (150, 158, 166))
    p.keyline(0.026)


def o_trophy(p):
    p.poly([(0.28, 0.16), (0.72, 0.16), (0.66, 0.56), (0.34, 0.56)], (214, 176, 66))
    p.poly([(0.50, 0.16), (0.72, 0.16), (0.66, 0.56), (0.50, 0.56)], (150, 116, 34))
    for sx in (-1, 1):
        p.arc(0.5 + sx * 0.29, 0.30, 0.135, 0.125, 0, 360, (150, 116, 34), 0.050)
    p.rrect_c(0.5, 0.64, 0.060, 0.085, 0.02, (150, 116, 34))
    p.rrect_c(0.5, 0.78, 0.220, 0.060, 0.02, (128, 96, 58))
    p.rrect_c(0.5, 0.88, 0.280, 0.050, 0.02, (96, 70, 42))
    p.keyline(0.016)


# --- weapon + item pickups (tiny: 10-22px on screen) -------------------------
def w_gun(p, kind: str):
    """Weapon pickups are 12-22px on screen -- one bold bar plus one tell."""
    p.rrect_c(0.5, 0.50, 0.085, 0.400, 0.03, P.GUN)             # barrel/body
    p.rrect_c(0.5, 0.70, 0.150, 0.140, 0.04, P.GUN_HI)          # receiver block
    if kind == "rifle":
        p.rrect_c(0.5, 0.86, 0.075, 0.110, 0.02, (110, 82, 48))
    elif kind == "shotgun":
        p.rrect_c(0.5, 0.50, 0.130, 0.180, 0.04, (120, 90, 54))
    elif kind == "mg":
        p.rrect_c(0.5, 0.66, 0.210, 0.110, 0.03, P.GUN)
        p.rrect_c(0.5, 0.22, 0.130, 0.075, 0.02, P.GUN_HI)
    elif kind == "pistol":
        p.rrect_c(0.5, 0.42, 0.085, 0.230, 0.03, P.GUN)
        p.rrect_c(0.5, 0.68, 0.130, 0.180, 0.04, P.GUN_HI)
    elif kind == "rpg":
        p.rrect_c(0.5, 0.50, 0.130, 0.400, 0.05, P.GUN)
        p.poly([(0.5, 0.06), (0.72, 0.30), (0.28, 0.30)], P.RUST)
    p.keyline(0.030)


def w_grenade(p, kind: str):
    body = {"grenade": (62, 78, 40), "flashbang": (196, 200, 194),
            "smoke": (70, 78, 66), "claymore": (58, 70, 38)}[kind]
    if kind == "claymore":
        p.poly([(0.18, 0.34), (0.82, 0.34), (0.76, 0.66), (0.24, 0.66)], body)
        p.poly([(0.18, 0.34), (0.82, 0.34), (0.80, 0.44), (0.20, 0.44)],
               tuple(int(c * 1.3) for c in body))
        for fx in (0.32, 0.68):
            p.line([(fx, 0.66), (fx - 0.06, 0.90)], (54, 58, 48), 0.045)
    else:
        p.ell(0.5, 0.58, 0.290, 0.310, fill=body)
        p.ell(0.44, 0.50, 0.130, 0.120, fill=tuple(min(255, int(c * 1.3)) for c in body))
        p.rrect_c(0.5, 0.22, 0.100, 0.120, 0.03, (72, 76, 68))
        p.arc(0.66, 0.26, 0.150, 0.130, 150, 380, (168, 172, 164), 0.045)
    p.keyline(0.030)


def i_binoculars(p):
    for sx in (-1, 1):
        p.rrect_c(0.5 + sx * 0.185, 0.50, 0.160, 0.330, 0.06, (34, 38, 32))
        p.ell(0.5 + sx * 0.185, 0.26, 0.135, 0.100, fill=(70, 96, 110))
    p.rrect_c(0.5, 0.54, 0.110, 0.130, 0.03, (40, 44, 38))
    p.keyline(0.032)


def i_bullet(p, shotgun: bool):
    if shotgun:
        p.rrect_c(0.5, 0.58, 0.190, 0.340, 0.05, (176, 62, 52))
        p.rrect_c(0.5, 0.84, 0.190, 0.110, 0.04, (196, 164, 82))
    else:
        p.poly([(0.31, 0.34), (0.5, 0.08), (0.69, 0.34)], (168, 96, 52))
        p.rrect_c(0.5, 0.62, 0.190, 0.300, 0.05, (198, 156, 62))
        p.rrect_c(0.5, 0.86, 0.190, 0.075, 0.03, (134, 100, 34))
    p.keyline(0.036)


def o_tank_shell(p):
    p.poly([(0.30, 0.40), (0.5, 0.04), (0.70, 0.40)], (150, 88, 48))
    p.rrect_c(0.5, 0.66, 0.200, 0.300, 0.05, (198, 156, 62))
    p.rrect_c(0.5, 0.90, 0.200, 0.080, 0.03, (134, 100, 34))
    p.keyline(0.040)


# --- FX ----------------------------------------------------------------------
def fx_flame(p):
    for r, c in ((0.44, (168, 62, 30)), (0.33, (214, 122, 40)),
                 (0.21, (240, 190, 80)), (0.11, (250, 236, 190))):
        pts = []
        for i in range(9):
            a = i * 2 * math.pi / 9
            rr = r * (0.72 + 0.28 * ((i * 4) % 3) / 2.0)
            pts.append((0.5 + math.cos(a) * rr, 0.54 + math.sin(a) * rr * 1.10))
        p.poly(pts, c)
    return p.out(blur=1.2)


def fx_muzzle(p):
    """Additive crack-pop card: a hot star with a transparent-ish core."""
    for i in range(14):
        a = i * 2 * math.pi / 14
        ln = 0.46 if i % 2 == 0 else 0.26
        p.poly([(0.5 + math.cos(a) * ln, 0.5 + math.sin(a) * ln),
                (0.5 + math.cos(a + 0.22) * 0.10, 0.5 + math.sin(a + 0.22) * 0.10),
                (0.5 + math.cos(a - 0.22) * 0.10, 0.5 + math.sin(a - 0.22) * 0.10)],
               (255, 246, 214))
    p.ell(0.5, 0.5, 0.16, 0.16, fill=(255, 252, 240))
    return p.out(blur=1.0)


def o_flag_iran(p):
    """Same three-band design as the sprite it replaces, drawn from scratch so
    the LICENCE question is cleared. The reputational call the checklist parks
    is a separate decision and is deliberately left untouched."""
    p.rect(0.14, 0.02, 0.22, 1.00, (74, 62, 44))            # pole
    for i, c in enumerate(((44, 122, 62), (238, 238, 232), (196, 62, 52))):
        p.rect(0.22, 0.06 + i * 0.176, 0.98, 0.06 + (i + 1) * 0.176, c)
    p.keyline(0.010)


OBJECTS = {
    # key: (canvas, draw)   canvas is (w, h) when the sprite is not square
    "mil2/technical": (96, o_technical),
    "mil2/apc": (104, o_apc),
    "mil2/light_tank": (96, o_light_tank),
    "mil2/radar_tank": (104, o_radar_tank),
    "mil2/rocket_truck": (104, o_rocket_truck),
    "mil2/heli_attack2": (112, lambda p: o_heli(p, True)),
    "mil2/heli_transport": (112, lambda p: o_heli(p, False)),
    "mil2/jet": (128, o_jet),
    "mil2/drone": (48, o_drone),
    "p2/tank_hulk": (104, o_tank_hulk),
    "decor/wreck": (220, o_wreck),
    "decor/wreck_halftrack": (240, o_wreck_halftrack),
    "cast2/bunker": (440, o_bunker),
    "p2/bunker2": (440, o_bunker),
    "decor/watchtower": (260, o_watchtower),
    "decor/radio_tower": (220, o_radio_tower),
    "decor/tent": (260, o_tent),
    "mil2/mg_stand": (160, o_mg_stand),
    "decor/mg_tripod": (160, o_mg_tripod),
    "decor/flak_gun": (220, o_flak_gun),
    "p2/wall_sandbag": (240, lambda p: o_wall_sandbag(p, False)),
    "p2/wall_sandbag_end": (120, lambda p: o_wall_sandbag(p, True)),
    "decor/crater": (160, o_crater),
    "decor/crater_field": (240, o_crater_field),
    "decor/crater_water": (240, o_crater_water),
    "decor/trench": (260, o_trench),
    "decor/bridge_mid": (220, lambda p: o_bridge(p, False)),
    "decor/bridge_ramp": (220, lambda p: o_bridge(p, True)),
    "decor/skyline_chimney": (160, o_skyline_chimney),
    "decor/skyline_mast": (200, o_skyline_mast),
    "decor/ammobox": (160, o_ammobox),
    "decor/barrel": (160, o_barrel),
    "decor/barricade": (200, o_barricade),
    "decor/barrier": (220, o_barrier),
    "decor/crate_stack": (220, o_crate_stack),
    "decor/rock1": (220, lambda p: o_rock(p, False)),
    "decor/rock2": (260, lambda p: o_rock(p, True)),
    "decor/tank_trap": (200, o_tank_trap),
    "decor/barbedwire": (220, o_barbedwire),
    "decor/landmine": (160, o_landmine),
    "decor/dropped_shield": (140, o_dropped_shield),
    "decor/flag_marker": (200, o_flag_marker),
    "sandbag": (80, o_sandbag),
    "tree_large": (120, lambda p: o_tree(p, True)),
    "tree_small": (96, lambda p: o_tree(p, False)),
    "crate_ammo": (56, lambda p: o_crate(p, "ammo")),
    "crate_grenade": (56, lambda p: o_crate(p, "grenade")),
    "crate_airstrike": (56, lambda p: o_crate(p, "airstrike")),
    "p2/pickup_vest": (56, o_pickup_vest),
    "cast2/trophy": (256, o_trophy),
    "mil2/wep_rifle": (56, lambda p: w_gun(p, "rifle")),
    "mil2/wep_shotgun": (56, lambda p: w_gun(p, "shotgun")),
    "mil2/wep_mg": (56, lambda p: w_gun(p, "mg")),
    "mil2/wep_pistol": (40, lambda p: w_gun(p, "pistol")),
    "mil2/wep_rpg": (64, lambda p: w_gun(p, "rpg")),
    "mil2/wep_grenade": (40, lambda p: w_grenade(p, "grenade")),
    "mil2/wep_flashbang": (40, lambda p: w_grenade(p, "flashbang")),
    "mil2/wep_smoke": (40, lambda p: w_grenade(p, "smoke")),
    "mil2/wep_claymore": (40, lambda p: w_grenade(p, "claymore")),
    "mil2/item_binoculars": (40, i_binoculars),
    "mil2/item_bullet": (32, lambda p: i_bullet(p, False)),
    "mil2/item_bullet_shotgun": (32, lambda p: i_bullet(p, True)),
    "p2/tank_shell": (32, o_tank_shell),
    "p2/fx_flame": (200, fx_flame),
    "SOL:fx/muzzleflash_small": (1024, fx_muzzle),
    "decor/flag_iran": ((306, 600), o_flag_iran),
}


def recenter(im: Image.Image) -> Image.Image:
    """Shift the art so its ALPHA-MASS centroid lands on the canvas centre.

    tests/test_assets.gd pins this to 1%: these sprites rotate about the canvas
    centre, so an off-centre mass makes a unit wobble as it turns. A figure whose
    weapon projects north and whose boots hang south is naturally off-centre, so
    correct it here rather than hand-tuning every pose.
    """
    a = im.getchannel("A")
    px = a.load()
    w, h = im.size
    tot = sx = sy = 0.0
    for y in range(h):
        for x in range(w):
            v = px[x, y]
            if v:
                tot += v
                sx += x * v
                sy += y * v
    if tot == 0:
        return im
    dx = int(round((w - 1) / 2.0 - sx / tot))
    dy = int(round((h - 1) / 2.0 - sy / tot))
    if dx == 0 and dy == 0:
        return im
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.paste(im, (dx, dy))
    return out


def build(key: str) -> Image.Image:
    if key in HUMANS:
        cfg = dict(HUMANS[key])
        n = cfg.pop("canvas")
        p = _pad(n)
        person(p, **cfg)
        return recenter(p.out())
    if key in CORPSES:
        cfg = dict(CORPSES[key])
        n = cfg.pop("canvas")
        p = _pad(n)
        _corpse(p, **cfg)
        return recenter(p.out())
    if key in OBJECTS:
        canvas, fn = OBJECTS[key]
        w, h = canvas if isinstance(canvas, tuple) else (canvas, canvas)
        p = _pad(w, h)
        got = fn(p)
        return got if got is not None else p.out()
    raise KeyError(key)


def dest_for(key: str, outdir: Path) -> Path:
    if key.startswith("SOL:"):
        return outdir / "soldiers" / (key[4:] + ".png")
    return outdir / "art" / (key + ".png")


SIZES: dict[str, tuple[int, int]] = {}
for _k, _v in {**HUMANS, **CORPSES}.items():
    SIZES[_k] = (_v["canvas"], _v["canvas"])
for _k, (_c, _f) in OBJECTS.items():
    SIZES[_k] = _c if isinstance(_c, tuple) else (_c, _c)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--outdir", type=Path, default=PROJECT_ROOT / "assets")
    ap.add_argument("--only")
    ap.add_argument("--family", default="all")
    args = ap.parse_args()

    keys = [args.only] if args.only else sorted(SIZES)
    for key in keys:
        im = build(key)
        n = SIZES[key]
        if im.size != n:
            raise ValueError(f"{key}: got {im.size}, expected {n}")
        if im.getchannel("A").getbbox() is None:
            raise ValueError(f"{key}: fully transparent")
        d = dest_for(key, args.outdir)
        d.parent.mkdir(parents=True, exist_ok=True)
        im.save(d)
        print(f"  ok   {key}: {n[0]}x{n[1]}")
    print(f"\n{len(keys)} sprite(s) -> {args.outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
