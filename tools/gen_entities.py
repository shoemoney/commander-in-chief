#!/usr/bin/env python3
"""Procedurally generate the remaining encumbered entity sprites.

This is the last licence blocker for an open-source release: 94 images across
assets/art/{decor,p2,mil2,cast2}, the 7 loose sprites at assets/art/ top level,
and the 9 in assets/troops/ (the owned infantry set). See
ASSETS.md sections 1, 1b.

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

    # legs: short thigh stubs plus boots. Without them the silhouette is a
    # rounded slab and reads as a beetle rather than a person.
    for sx in (-1, 1):
        p.rrect_c(cx + sx * 0.082 * s, cy + 0.170 * s, 0.055 * s, 0.075 * s, 0.02,
                  cloth_d)
        p.rrect_c(cx + sx * 0.085 * s, cy + 0.232 * s, 0.050 * s, 0.048 * s, 0.02,
                  P.BOOT)

    # torso: WIDE and SHORT. A tall ellipse reads as a beetle from above.
    p.rrect_c(cx, cy + 0.045 * s, 0.205 * s, 0.135 * s, 0.075, cloth)
    p.rrect_c(cx, cy + 0.115 * s, 0.205 * s, 0.065 * s, 0.055, cloth_d)   # shadowed back
    # chest rig: one bright horizontal band. At 32-64px this single stripe does
    # more to say "soldier" than any amount of interior detail.
    p.rrect_c(cx, cy - 0.010 * s, 0.150 * s, 0.032 * s, 0.012,
              tuple(int(c * 0.62) for c in cloth))
    # shoulder pads -- break the torso outline so the figure has real shoulders
    for sx in (-1, 1):
        p.ell(cx + sx * 0.185 * s, cy - 0.020 * s, 0.075 * s, 0.068 * s,
              fill=tuple(min(255, int(c * 1.12)) for c in cloth))

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
    p.ell(cx - 0.020 * s, cy - 0.035 * s, 0.104 * s, 0.100 * s,
          fill=tuple(min(255, int(c * 1.25)) for c in helm))      # lit crown rim
    p.ell(cx - 0.020 * s, cy - 0.040 * s, 0.086 * s, 0.082 * s, fill=helm)
    p.ell(cx - 0.020 * s, cy - 0.046 * s, 0.062 * s, 0.058 * s, fill=helm_d)
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
    if kind in ("rifle", "smg", "shotgun", "sniper", "lmg"):   # foregrip
        p.rrect_c(x, cy - 0.055 * s - blen * s * 0.55, 0.072 * s, 0.030 * s,
                  0.012, P.GUN_HI)
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
    # --- assets/troops/ : the purchased-pack replacements (most-seen art) ---
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


def _torso(p, cx, cy, rx, ry, base, hi, lo):
    """The mass of a body on the ground, carrying the same north-lit ramp the
    hulls do: dark contact skirt, mid body, lit crown. A body drawn in one flat
    fill loses the torso/arm separation that is the only thing saying "human"
    once the sprite is 19px across."""
    p.ell(cx, cy + ry * 0.16, rx * 1.10, ry * 1.10, fill=lo)
    p.ell(cx, cy, rx, ry, fill=base)
    p.ell(cx - rx * 0.14, cy - ry * 0.30, rx * 0.72, ry * 0.56, fill=hi)


def _head(p, cx, cy, helm, helm_d):
    p.ell(cx, cy, 0.108, 0.102, fill=helm)
    p.ell(cx - 0.014, cy - 0.016, 0.086, 0.080, fill=helm_d)
    p.ell(cx - 0.020, cy - 0.030, 0.052, 0.048,
          fill=tuple(min(255, int(c * 1.26)) for c in helm))


def _corpse(p, *, cloth, cloth_d, helm, helm_d, blood=True, pose="splayed"):
    """A body on the ground -- THREE POSES, not one pose in three palettes.

    The three corpses were previously a single stamp recoloured (measured alpha
    IoU 1.00 and 0.95), so a battlefield strewn with them read as one shape
    repeated at three litter slots. They now differ in PLAN SILHOUETTE first and
    palette second:

      splayed  -- face-down, limbs thrown wide; the widest of the three
      curled   -- on its side, knees up, arm folded across the chest; compact
      together-- face-down, legs straight and parallel, arms tucked; a slab

    Those three plans are near-orthogonal when bbox-normalised, which is what
    actually separates them at 18-22px -- a different palette at the same
    silhouette is invisible on a dark ground.
    """
    cx, cy = 0.5, 0.50
    mid, lo = cloth, _mul(cloth, 0.56)
    hi = _mul(cloth, 1.28)

    if blood:
        # a separate, offset, DARKER pool: soaked ground, not part of the
        # silhouette -- so it is kept clear of the body's own bbox on the slab
        # pose, where a centred disc would erase the plan entirely
        pool = {"splayed": (cx + 0.02, cy + 0.14, 0.30, 0.24),
                "curled": (cx + 0.05, cy + 0.15, 0.23, 0.19),
                "together": (cx + 0.09, cy + 0.17, 0.145, 0.135)}[pose]
        p.ell(pool[0], pool[1], pool[2], pool[3], fill=(58, 27, 24))
        p.ell(pool[0] - pool[2] * 0.42, pool[1] + pool[3] * 0.34,
              pool[2] * 0.52, pool[3] * 0.40, fill=(80, 35, 31))

    if pose == "splayed":
        for a, ln in ((-0.70, 0.335), (-2.44, 0.315), (0.64, 0.345), (2.48, 0.305)):
            p.line([(cx, cy), (cx + math.cos(a) * ln, cy + math.sin(a) * ln)],
                   lo, 0.080)
            p.line([(cx + math.cos(a) * ln * 0.55,
                     cy + math.sin(a) * ln * 0.55),
                    (cx + math.cos(a) * ln, cy + math.sin(a) * ln)],
                   hi, 0.034)                       # lit upper edge per limb
        _torso(p, cx, cy + 0.020, 0.170, 0.205, mid, hi, lo)
        _head(p, cx - 0.020, cy - 0.205, helm, helm_d)
    elif pose == "curled":
        p.ell(cx + 0.030, cy + 0.075, 0.235, 0.200, fill=lo)
        p.line([(cx - 0.020, cy + 0.105), (cx - 0.235, cy - 0.020)], lo, 0.086)
        p.line([(cx - 0.235, cy - 0.020), (cx - 0.185, cy - 0.190)], lo, 0.082)
        p.line([(cx + 0.045, cy + 0.020), (cx - 0.140, cy - 0.125)], hi, 0.078)
        _torso(p, cx + 0.030, cy + 0.010, 0.185, 0.170, mid, hi, lo)
        _head(p, cx - 0.160, cy - 0.205, helm, helm_d)
    else:   # "together"
        for sx in (-1, 1):
            p.line([(cx + sx * 0.050, cy + 0.150), (cx + sx * 0.058, cy + 0.360)],
                   lo, 0.084)
            p.line([(cx + sx * 0.050, cy + 0.180), (cx + sx * 0.055, cy + 0.350)],
                   hi, 0.030)
            p.ell(cx + sx * 0.062, cy + 0.395, 0.052, 0.046,
                  fill=_mul(cloth_d, 0.80))         # boots
        _torso(p, cx, cy - 0.055, 0.150, 0.205, mid, hi, lo)
        for sx in (-1, 1):                          # arms tucked hard in
            p.line([(cx + sx * 0.118, cy - 0.115), (cx + sx * 0.052, cy + 0.070)],
                   lo, 0.070)
        _head(p, cx, cy - 0.245, helm, helm_d)
    p.keyline(0.020)


CORPSES = {
    "p2/corpse_soldier1": dict(canvas=140, cloth=P.CLOTH, cloth_d=P.CLOTH_D,
                               helm=P.HELM_E, helm_d=P.HELM_E_D, pose="splayed"),
    "p2/corpse_soldier2": dict(canvas=140, cloth=(88, 82, 62), cloth_d=(58, 54, 40),
                               helm=P.HELM_C, helm_d=P.HELM_C_D, pose="curled"),
    "decor/fallen_merc": dict(canvas=180, cloth=(82, 88, 68), cloth_d=(54, 58, 44),
                              helm=P.HELM_C, helm_d=P.HELM_C_D, pose="together"),
}


# =============================================================================
# OBJECTS -- vehicles, structures, props, terrain, weapons, pickups, FX.
# All drawn from directly overhead like the figures above. These are the easy
# half: they are geometry, and most land at 10-75px on screen where the outer
# silhouette is the entire read.
# =============================================================================
def _mul(c, k):
    """Scale an RGB triple, clamped. Every value ramp in this file is
    multiply-by-factor off one base, which is the _bag() vocabulary."""
    return tuple(max(0, min(255, int(v * k))) for v in c)


def _hull(p, pts, base, lift=0.022, skirt=0.024, hi=1.30, lo=0.70):
    """A RAISED, north-lit hull face -- the _bag() crown convention generalised
    from an ellipse to an arbitrary hull polygon.

    Draws a dark skirt that shows along the SOUTH edge, the mid body, a mid-light
    band and a bright top face that show along the NORTH edge: four value steps
    off one base colour. The wreck family used to be ONE flat fill plus three
    dark ellipses, and at 18-32px on screen the ink keyline is sub-pixel, so the
    whole hull collapsed to a single sticker value. `lift` is in unit coords --
    keep it under ~0.03 or the top face slides off the hull on a short sprite.
    """
    p.poly([(x, y + skirt) for x, y in pts], _mul(base, lo))
    p.poly(pts, base)
    p.poly([(x, y - lift * 0.5) for x, y in pts], _mul(base, 1.0 + (hi - 1.0) * 0.58))
    p.poly([(x, y - lift) for x, y in pts], _mul(base, hi))


def _tracks(p, cx, cy, hw, hh, col=(46, 48, 44), sides=(-1, 1)):
    """Dark track runs flanking a hull -- the tracked-vehicle tell. `sides` drops
    one run for the half-tracked / broken-vehicle plans."""
    for sx in sides:
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


def _burnt(p, hx, hy, hrx, hry):
    """The blown-open hole that makes a hull read as a WRECK, and -- the part that
    was missing -- its lit torn lip.

    A hole is a value with nothing above it, not a step in the value range: the
    old burn stamped three near-black ellipses and the sprite measured flatter
    the more of it there was. A blown plate edge catches the same north light as
    the hull crown, so the lip goes in as a THIN crescent on the hole's north
    side -- the hole's own shape offset north, then the hole drawn over it. The
    first pass drew the lip as a bright ellipse PARKED ON TOP of the hole, which
    at these sizes is a white saucer balanced on the wreck.

    The opening is an angular 7-gon, not a circle: a round hole reads as a
    porthole. Still kept SMALL -- an earlier version covered ~95% of the hull in
    near-black, which made apc / light_tank / technical / wreck all collapse into
    the same dark blob at their real 26-37px.
    """
    torn = [(hx - hrx * 1.00, hy - hry * 0.10), (hx - hrx * 0.60, hy - hry * 0.74),
            (hx + hrx * 0.20, hy - hry * 0.92), (hx + hrx * 0.98, hy - hry * 0.30),
            (hx + hrx * 0.72, hy + hry * 0.68), (hx - hrx * 0.12, hy + hry * 0.98),
            (hx - hrx * 0.82, hy + hry * 0.50)]
    p.ell(hx - hrx * 0.24, hy + hry * 0.34, hrx * 0.90, hry * 0.64, fill=(94, 86, 74))
    p.poly([(x, y - hry * 0.32) for x, y in torn], (146, 138, 122))   # torn lip
    p.poly(torn, (54, 50, 46))                                        # the opening
    p.poly([(hx + (x - hx) * 0.68, hy + (y - hy) * 0.68) for x, y in torn],
           (33, 31, 29))                                              # its depth
    p.poly([(hx + (x - hx) * 0.32, hy + (y - hy) * 0.32) for x, y in torn],
           (23, 22, 21))


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
    """The LOW, LONG, TURRETLESS one, and the family's most NON-CONVEX plan: a
    wide armoured nose section that STEPS IN over the rear third to a narrow hull,
    with the tracks running the front two-thirds. The bevelled nose is the sloped
    glacis read from overhead; the step is what makes the normalised silhouette
    nothing like the halftrack's L-shaped cargo, the light tank's barrel spout or
    the hulk's single-track kidney. The step sits low in the plan on purpose --
    put it at the midpoint and the thing reads as a mushroom, not a hull.
    """
    body = (94, 98, 88)
    _tracks(p, 0.5, 0.355, 0.258, 0.265, col=(42, 44, 40))
    hull = [(0.290, 0.090), (0.710, 0.090), (0.710, 0.600), (0.605, 0.665),
            (0.605, 0.885), (0.395, 0.885), (0.395, 0.665), (0.290, 0.600)]
    _hull(p, hull, body, lift=0.026, skirt=0.024)
    # the glacis: the most light-catching face on the vehicle
    p.poly([(0.295, 0.093), (0.705, 0.093), (0.705, 0.196), (0.295, 0.196)],
           _mul(body, 1.24))
    p.poly([(0.325, 0.104), (0.675, 0.104), (0.675, 0.172), (0.325, 0.172)],
           _mul(body, 1.38))
    for i in range(3):                       # road wheels reading through the skirt
        p.ell(0.5, 0.265 + i * 0.120, 0.155, 0.038, fill=_mul(body, 0.82))
    p.poly([(0.395, 0.672), (0.605, 0.672), (0.605, 0.716), (0.395, 0.716)],
           _mul(body, 0.76))                 # the step's shaded riser
    p.rrect_c(0.5, 0.800, 0.105, 0.060, 0.012, _mul(body, 0.86))   # rear hatch
    _burnt(p, 0.375, 0.500, 0.098, 0.082)
    p.keyline(0.018)


def o_light_tank(p):
    """The one with a SPOUT. A compact hull, a small turret offset EAST of centre,
    and a long thin barrel running most of the sprite's length to the north --
    the only protrusion in the family, so this is the silhouette that separates
    from all four siblings at a glance. A snapped barrel is also the reason a
    tank is a wreck, so the value work goes into the mantlet and the deck.
    """
    body = (90, 94, 84)
    _tracks(p, 0.5, 0.575, 0.272, 0.245, col=(40, 42, 38))
    # the hull's south-east corner is blown away, so the plan is a bitten wedge
    # rather than the rounded slab its three siblings were
    hull = [(0.315, 0.290), (0.685, 0.290), (0.715, 0.375), (0.715, 0.640),
            (0.600, 0.780), (0.500, 0.845), (0.355, 0.845), (0.285, 0.740),
            (0.285, 0.375)]
    _hull(p, hull, body, lift=0.022, skirt=0.020)
    p.poly([(0.315, 0.290), (0.685, 0.290), (0.668, 0.360), (0.332, 0.360)],
           _mul(body, 1.22))                          # lit engine deck
    for i in range(4):                               # louvres
        p.line([(0.36 + i * 0.028, 0.300), (0.36 + i * 0.028, 0.348)],
               _mul(body, 0.80), 0.014)
    # turret: a small CAST turret, so a hexagon -- four concentric ellipses
    # read as a bullseye at 20px, which is the one thing a tank must not do
    ring = _epoly(0.540, 0.520, 0.170, 0.160, 0.20, n=6)
    p.poly([(x, y + 0.016) for x, y in ring], _mul(body, 0.70))
    p.poly(ring, body)
    p.poly([(x, y - 0.022) for x, y in ring], _mul(body, 1.26))
    p.rrect_c(0.540, 0.505, 0.082, 0.062, 0.014, (30, 29, 27))   # open hatch
    p.rrect_c(0.540, 0.498, 0.062, 0.030, 0.010, (54, 52, 48))
    p.ell(0.525, 0.476, 0.044, 0.040, fill=(26, 26, 24))          # mantlet
    # the spout: long, thin, kinked off the mantlet, lit down its west face
    p.poly([(0.503, 0.460), (0.548, 0.460), (0.528, 0.030), (0.492, 0.030)],
           (48, 48, 44))
    p.poly([(0.503, 0.460), (0.520, 0.460), (0.506, 0.030), (0.492, 0.030)],
           (112, 112, 106))
    p.ell(0.510, 0.048, 0.040, 0.026, fill=(74, 74, 70))          # muzzle brake
    _burnt(p, 0.380, 0.720, 0.090, 0.068)
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
    """The BROKEN one, and the only lopsided member of the family. The hull sits
    crooked, the whole east track run is gone (thrown clear, leaving bare road
    wheels and an empty track bed), and the turret is a blown-off stub ring.
    Every sibling is symmetric about its long axis, so dropping one flank and
    rotating the body is a silhouette differentiator nothing else in the litter
    can match -- and it is also the honest read for a parked hulk the sim burns
    smoke off.
    """
    body = (82, 76, 70)
    _tracks(p, 0.5, 0.560, 0.258, 0.310, col=(38, 36, 34), sides=(-1,))
    p.ell(0.5 + 0.192, 0.560, 0.058, 0.288, fill=(30, 29, 27))   # empty track bed
    p.ell(0.5 + 0.192, 0.300, 0.052, 0.030, fill=(96, 90, 80))   # its lit north lip
    for i in range(4):                       # bare road wheels, standing in the bed
        p.ell(0.5 + 0.196 - i * 0.008, 0.350 + i * 0.145, 0.050, 0.056,
              fill=(64, 60, 56))
        p.ell(0.5 + 0.196 - i * 0.008, 0.342 + i * 0.145, 0.030, 0.032,
              fill=(112, 106, 96))
    # the hull is rotated AND has its north-east quarter torn away, so the plan
    # is a crooked wedge -- no sibling has anything but a rounded outline
    hull = _epoly(0.462, 0.560, 0.232, 0.345, 0.145, n=7)
    _hull(p, hull, body, lift=0.024, skirt=0.022)
    for a, b in ((0.330, 0.760), (0.395, 0.330)):   # panel seams, so the hull
        p.line([(a, b), (0.612, b + 0.055)], _mul(body, 0.68), 0.016)  # is not one field
    p.rrect_c(0.560, 0.330, 0.075, 0.055, 0.012, _mul(body, 0.80))    # engine deck
    ring = _epoly(0.462, 0.518, 0.132, 0.126, -0.25, n=6)
    p.poly([(x, y + 0.014) for x, y in ring], _mul(body, 0.74))   # turret ring
    p.poly(ring, _mul(body, 1.10))
    p.poly([(x + (0.462 - x) * 0.26, y + (0.518 - y) * 0.26) for x, y in ring],
           (34, 32, 30))                                          # blown off
    for i in range(3):                       # the barrel, snapped to a stub
        p.poly([(0.442 + i * 0.016, 0.485), (0.454 + i * 0.016, 0.485),
                (0.457 + i * 0.016, 0.345 - i * 0.030),
                (0.445 + i * 0.016, 0.345 - i * 0.030)], (52, 50, 46))
    p.poly([(0.560, 0.360), (0.690, 0.430), (0.610, 0.640), (0.520, 0.560)],
           (32, 30, 28))                     # the torn-open flank
    p.poly([(0.560, 0.360), (0.690, 0.430), (0.662, 0.470), (0.552, 0.412)],
           (144, 136, 120))                  # its lit peeled lip
    _burnt(p, 0.575, 0.760, 0.105, 0.082)
    p.keyline(0.018)


def o_wreck(p):
    """The GENERIC burnt shell: nothing recognisable survives, and that is the
    job -- it is the litter the other four read against. A torn-open top edge, a
    jagged plan with a bitten west flank, and two peeled-back plate flaps give
    it an outline no tracked hull can share.
    """
    body = (86, 80, 72)
    hull = [(0.320, 0.270), (0.470, 0.190), (0.640, 0.235), (0.710, 0.385),
            (0.775, 0.490), (0.725, 0.620), (0.765, 0.755), (0.605, 0.810),
            (0.450, 0.780), (0.365, 0.850), (0.285, 0.720), (0.400, 0.640),
            (0.250, 0.560), (0.330, 0.470), (0.235, 0.400), (0.285, 0.330)]
    _hull(p, hull, body, lift=0.028, skirt=0.030)
    p.poly([(0.235, 0.400), (0.205, 0.275), (0.335, 0.420)],
           _mul(body, 1.26))                      # plate flap, bent up
    p.poly([(0.765, 0.755), (0.795, 0.615), (0.660, 0.795)],
           _mul(body, 0.72))                      # and its shadowed twin
    _burnt(p, 0.505, 0.540, 0.132, 0.112)
    p.poly([(0.320, 0.270), (0.470, 0.190), (0.640, 0.235), (0.665, 0.330),
            (0.335, 0.368)], (32, 29, 27))        # the torn-open top
    p.poly([(0.320, 0.270), (0.470, 0.190), (0.505, 0.215), (0.340, 0.305)],
           (130, 121, 105))                       # its lit peeled lip
    p.keyline(0.020)


def o_wreck_halftrack(p):
    """The hero hardpoint wreck and the largest litter sprite on screen, so it
    carries the family's loudest read: a WIDE tracked nose under a big BOXY rear
    cargo block. The cargo is a separate raised box with its own lit lid, that
    hard value break is what keeps this one off the rounded blobs its four
    siblings used to be -- and the cargo's blown-out WEST corner plus the flatbed
    tail hanging off its EAST gives the plan a hard L/T notch nothing else in the
    family shares.

    The alpha bbox is deliberately held near the ~0.67 x 0.78 canvas fraction
    the main.gd rock-cover pin was measured against: at call scale 1.1 it draws
    ~53x61 over a 64x48 blocker, so growing the footprint would re-open the
    art-vs-collision gap that pin closed.
    """
    body = (90, 84, 74)
    _tracks(p, 0.5, 0.345, 0.245, 0.200, col=(40, 38, 36))
    front = [(0.300, 0.165), (0.700, 0.165), (0.712, 0.300), (0.700, 0.535),
             (0.300, 0.535), (0.288, 0.300)]
    _hull(p, front, body, lift=0.024, skirt=0.022)
    for i in range(3):                           # engine-deck ribs
        p.line([(0.340, 0.215 + i * 0.070), (0.660, 0.215 + i * 0.070)],
               _mul(body, 0.70), 0.018)
    p.poly([(0.300, 0.165), (0.700, 0.165), (0.690, 0.232), (0.310, 0.232)],
           _mul(body, 1.30))
    p.poly([(0.300, 0.500), (0.700, 0.500), (0.700, 0.560), (0.300, 0.560)],
           (30, 28, 26))                         # the seam between hull and box
    # the boxy rear cargo, a clear value step LIGHTER than the nose, with its
    # blown-out west corner cutting an L out of the plan
    box = _mul(body, 1.22)
    cargo = [(0.250, 0.560), (0.790, 0.560), (0.790, 0.905), (0.400, 0.905),
             (0.400, 0.720), (0.250, 0.720)]
    p.poly([(x, y + 0.020) for x, y in cargo], _mul(body, 0.60))
    p.poly(cargo, box)
    p.poly([(x, y - 0.030) for x, y in cargo], _mul(box, 1.22))
    p.poly([(0.258, 0.582), (0.782, 0.582), (0.782, 0.638), (0.258, 0.638)],
           _mul(box, 1.30))                     # lit crate-lid edge
    for cxp in (0.480, 0.625, 0.750):            # plank seams
        p.line([(cxp, 0.652), (cxp, 0.892)], _mul(box, 0.70), 0.018)
    p.poly([(0.250, 0.720), (0.400, 0.720), (0.400, 0.905), (0.250, 0.905)],
           (30, 28, 26))                         # the torn-out corner, in shadow
    p.poly([(0.250, 0.720), (0.400, 0.720), (0.400, 0.762), (0.250, 0.762)],
           _mul(box, 0.92))                      # and its lit inner lip
    _burnt(p, 0.640, 0.790, 0.088, 0.064)       # punched through the lit lid
    p.poly([(0.790, 0.700), (0.840, 0.726), (0.840, 0.868), (0.790, 0.842)],
           _mul(body, 0.80))                     # flatbed tail, off the east
    p.poly([(0.790, 0.700), (0.840, 0.726), (0.840, 0.762), (0.790, 0.744)],
           _mul(body, 1.16))
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
    """A tripod-mounted gun, and the thinnest read in the litter: it lands ~11x16
    on screen. (main.gd's _tiny_decor_no_rim tests the full 160px canvas, not the
    alpha bbox, so at SCALE 0.12 it measures 19.2 and KEEPS its 1.1px draw rim
    rather than dropping it -- either way the baked ink keyline is the only
    structure here, so the sprite has to carry itself.)

    The previous version was three near-black legs on a near-black hub: a black
    cross. Lighter legs with a lit outer face and bright feet, a BRIGHT top-face
    hub, a mid-value receiver and a bright ammo box give five value steps, and
    the wider splay keeps the three legs separable at 11px instead of merging
    into one stub.
    """
    leg, leg_hi = (94, 96, 86), (146, 148, 136)
    for a in (0.86, 2.28, -1.57):
        ex, ey = 0.5 + math.cos(a) * 0.40, 0.585 + math.sin(a) * 0.335
        ox, oy = -math.sin(a) * 0.013, math.cos(a) * 0.013
        p.line([(0.5, 0.585), (ex, ey)], leg, 0.062)
        p.line([(0.5 + math.cos(a) * 0.12, 0.585 + math.sin(a) * 0.12),
                (ex + ox, ey + oy)], leg_hi, 0.026)      # lit outer face
        p.ell(ex, ey, 0.042, 0.040, fill=leg_hi)          # foot
    p.ell(0.5, 0.585, 0.138, 0.122, fill=(70, 72, 64))   # pintle collar
    p.ell(0.5, 0.566, 0.110, 0.096, fill=(114, 116, 106))
    p.ell(0.5, 0.548, 0.062, 0.054, fill=(156, 158, 148))
    p.rrect_c(0.5, 0.290, 0.054, 0.235, 0.01, (56, 56, 50))   # barrel shroud
    p.poly([(0.500, 0.070), (0.530, 0.110), (0.518, 0.400), (0.500, 0.400)],
           (124, 126, 118))                                # lit barrel edge
    p.rrect_c(0.5, 0.470, 0.138, 0.092, 0.02, (86, 88, 80))   # receiver
    p.rrect_c(0.5, 0.444, 0.118, 0.046, 0.015, (132, 134, 124))
    p.rrect_c(0.5, 0.578, 0.152, 0.062, 0.015, (162, 158, 122))  # ammo box
    p.keyline(0.020)


def o_flak_gun(p):
    p.ell(0.5, 0.62, 0.230, 0.220, fill=(78, 84, 62))
    p.ell(0.5, 0.62, 0.150, 0.145, fill=(54, 60, 44))
    for sx in (-1, 1):
        p.rrect_c(0.5 + sx * 0.070, 0.28, 0.036, 0.260, 0.01, (36, 38, 34))
    _wheels(p, 0.5, 0.66, 0.235, 0.10, 1)
    p.keyline(0.018)


def _j(seed: int, i: int, k: int) -> float:
    """Deterministic 0..1 jitter (Art.cell_hash's mixer). No `random` -- a re-run
    must reproduce the committed PNG byte-for-byte."""
    h = (seed * 374761393 + i * 668265263 + k * 2654435761) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0


def _rot_pt(cx, cy, dx, dy, tilt):
    ct, st = math.cos(tilt), math.sin(tilt)
    return (cx + dx * ct - dy * st, cy + dx * st + dy * ct)


def _epoly(cx, cy, rx, ry, tilt, n=14):
    return [_rot_pt(cx, cy, rx * math.cos(2 * math.pi * k / n),
                     ry * math.sin(2 * math.pi * k / n), tilt) for k in range(n)]


def _bag(p, cx, cy, hw, hh, tilt, base):
    """One burlap sandbag, camera-overhead: dark contact shadow, mid body, a
    crown lit to the NORTH (matches ROCK_TOP_LIGHT's overhead-light convention,
    main.gd:6530), and a seam line -- a stamped oval has none of the three."""
    dark = tuple(max(0, int(c * 0.60)) for c in base)
    lit = tuple(min(255, int(c * 1.24)) for c in base)
    p.poly(_epoly(cx, cy + hh * 0.14, hw * 1.03, hh * 0.94, tilt), dark)
    p.poly(_epoly(cx, cy, hw, hh, tilt), base)
    p.poly(_epoly(cx, cy - hh * 0.28, hw * 0.60, hh * 0.40, tilt), lit)
    p.line([_rot_pt(cx, cy, -hw * 0.55, -hh * 0.08, tilt),
            _rot_pt(cx, cy, 0.0, hh * 0.10, tilt),
            _rot_pt(cx, cy, hw * 0.55, -hh * 0.08, tilt)], dark, hh * 0.09)


# Dark burlap rim for the wall kit instead of the icons' near-black INK: a
# gate wall tiles these segments end-to-end, and the ink keyline is what made
# the run read as identical stickers with stark black outlines. Keeps edge
# readability over scorched ground without the sticker border.
WALL_RIM = (64, 54, 36)


def _sandbag_wall(p, n: int, seed: int, y_top: float, y_bot: float,
                  chipped: int = -1, spill: bool = False, rim=WALL_RIM) -> None:
    """Brick-staggered two-course sandbag run: a shaded back course (n-1 bags,
    half-pitch offset) drawn first, a lit front course (n bags) on top. Every
    bag gets its own hashed width/height/tilt/dy/shade off (seed, i) -- no two
    bags in the run are identical, and the brick offset kills the ruled grid.
    A hashed spoil-berm skirt along the bottom blends the run into the ground.
    `chipped` squashes front bag i into a torn, settled remnant (a worn
    segment); `spill` bursts two lone bags off the foot inside the berm band
    (a shelled segment). Both stay inside the y in [64,181] alpha footprint
    test_sandbag_bakes_are_not_a_mechanical_grid pins.
    """
    front_pitch = 1.0 / n
    back_n = max(1, n - 1)
    back_pitch = 1.0 / back_n
    course_h = y_bot - y_top
    for i in range(back_n):
        x = (i + 0.5) * back_pitch
        w = front_pitch * 0.5 * (0.80 + _j(seed, i, 1) * 0.22)
        h = course_h * 0.48 * (0.86 + _j(seed, i, 2) * 0.30)
        tilt = (_j(seed, i, 3) - 0.5) * 0.24
        dy = (_j(seed, i, 4) - 0.5) * course_h * 0.14
        shade = 0.80 * (0.93 + _j(seed, i, 5) * 0.15)
        base = tuple(max(0, min(255, int(c * shade))) for c in (146, 124, 82))
        _bag(p, x, y_top + dy, w, h, tilt, base)
    for i in range(n):
        x = (i + 0.5) * front_pitch
        w = front_pitch * 0.5 * (0.80 + _j(seed, i, 6) * 0.22)
        h = course_h * 0.36 * (0.86 + _j(seed, i, 7) * 0.30)
        tilt = (_j(seed, i, 8) - 0.5) * 0.24
        dy = (_j(seed, i, 9) - 0.5) * course_h * 0.4
        shade = 0.93 + _j(seed, i, 10) * 0.15
        if i == chipped:
            # a torn, settled bag: most of it is GONE — a real gap in the
            # front course, not a slightly smaller stamp — with the remnant
            # squashed flat and sunk into the berm
            w *= 0.38
            h *= 0.30
            dy += course_h * 0.24
            tilt += 0.14
        base = tuple(max(0, min(255, int(c * shade))) for c in (190, 166, 116))
        _bag(p, x, y_bot + dy, w, h, tilt, base)
    for i in range(n + 1):
        bx = (i + 0.3 + _j(seed, i, 11) * 0.4) / (n + 1)
        by = y_bot + course_h * 0.14 + _j(seed, i, 12) * course_h * 0.06
        br = front_pitch * (0.20 + _j(seed, i, 13) * 0.10)
        p.ell(bx, by, br, br * 0.36, fill=(150, 128, 86))
    if spill:
        # shelled segment: two lone bags burst wide off the foot, kept inside
        # the berm band so the run's committed footprint does not grow.
        for k in range(2):
            sx = 0.24 + 0.30 * k + (_j(seed, 20 + k, 1) - 0.5) * 0.06
            sy = y_bot + course_h * 0.16 + (_j(seed, 20 + k, 2) - 0.5) * course_h * 0.05
            sw = front_pitch * (0.34 + _j(seed, 20 + k, 3) * 0.10)
            sh = course_h * (0.16 + _j(seed, 20 + k, 4) * 0.05)
            stilt = (0.30 + _j(seed, 20 + k, 5) * 0.25) * (1 if k == 0 else -1)
            sshade = 0.86 + _j(seed, 20 + k, 6) * 0.10
            sbase = tuple(max(0, min(255, int(c * sshade))) for c in (170, 148, 102))
            _bag(p, sx, sy, sw, sh, stilt, sbase)
    p.keyline(0.016, rim)


def o_wall_sandbag(p, end: bool, seed: int = 0):
    if end:
        _sandbag_wall(p, 2, seed, 0.40, 0.62)
    elif seed == 1:
        # worn segment: a THINNED 3+2 course with one front bag torn flat —
        # a genuinely different silhouette, not the same stamp re-jittered
        _sandbag_wall(p, 3, seed, 0.40, 0.62, chipped=1)
    elif seed == 2:
        _sandbag_wall(p, 5, seed, 0.40, 0.62, spill=True)  # shelled segment
    else:
        _sandbag_wall(p, 4, seed, 0.40, 0.62)


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


def o_rock_slab(p):
    """rock2 is NOT rock1 at a wider radius. That pairing measured 0.98 alpha
    IoU -- one polygon, two sizes -- so a boulder field drew as a repeated
    stamp. rock1 keeps its domed 7-gon; this is a FLAT TILTED SLAB with two
    smaller angular chunks piled on its north-west end: a low, skewed, wedge
    plan against rock1's symmetric dome, and a different bbox aspect to boot.

    The slab keeps a lit north face and a hard dark lee, so it still reads as
    RAISED cover under main.gd's ROCK_TOP_LIGHT overhead-light convention rather
    than as a ground decal -- the brief's "convex-ish" requirement.
    """
    base = (112, 104, 90)
    slab = [(0.140, 0.400), (0.300, 0.160), (0.660, 0.140), (0.880, 0.340),
            (0.855, 0.605), (0.560, 0.760), (0.215, 0.720)]
    p.poly([(x, y + 0.055) for x, y in slab], _mul(base, 0.46))     # lee shadow
    p.poly(slab, base)
    p.poly([(0.190, 0.395), (0.315, 0.205), (0.640, 0.190), (0.660, 0.370),
            (0.300, 0.470)], _mul(base, 1.20))                      # lit top plane
    # the top plane is split into three facets rather than left as one flat
    # field -- a single quad this size is 36% of the sprite in one colour, which
    # is the exact defect the wreck family was rebuilt for
    p.poly([(0.330, 0.300), (0.560, 0.195), (0.620, 0.330), (0.395, 0.420)],
           _mul(base, 1.34))
    p.poly([(0.300, 0.470), (0.660, 0.370), (0.640, 0.560), (0.330, 0.640)],
           _mul(base, 0.92))
    p.poly([(0.300, 0.225), (0.560, 0.205), (0.585, 0.310), (0.330, 0.335)],
           _mul(base, 1.46))                                       # north crown
    # angular chunks piled on the slab's north-west end
    for cx0, cy0, r0, k in ((0.305, 0.300, 0.150, 1.04), (0.470, 0.238, 0.112, 0.78)):
        pts = [(cx0 + math.cos(i * 2 * math.pi / 5 + 0.4) * r0,
                cy0 + math.sin(i * 2 * math.pi / 5 + 0.4) * r0 * 0.86)
               for i in range(5)]
        p.poly([(x, y + 0.030) for x, y in pts], _mul(_mul(base, 0.54), k))
        p.poly(pts, _mul(base, k))
        p.poly([(cx0 + (x - cx0) * 0.56, cy0 - r0 * 0.26 + (y - cy0) * 0.56)
                for x, y in pts], _mul(_mul(base, 1.34), k))
    for fx, fy, gx, gy, k in ((0.400, 0.320, 0.520, 0.640, 0.54),
                              (0.660, 0.350, 0.735, 0.610, 0.62),
                              (0.245, 0.430, 0.330, 0.690, 0.48),
                              (0.520, 0.290, 0.575, 0.470, 0.70)):
        p.line([(fx, fy), (gx, gy)], _mul(base, k), 0.019)        # fractures
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
    # the lone mound keeps the INK rim: it is never tiled end-to-end, so the
    # sticker-outline tell does not apply — and its committed PNG stays
    # byte-identical on a full regeneration.
    _sandbag_wall(p, 3, 10, 0.38, 0.62, rim=gen_ui_icons.INK)


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
    "p2/wall_sandbag": (240, lambda p: o_wall_sandbag(p, False, 0)),
    "p2/wall_sandbag_b": (240, lambda p: o_wall_sandbag(p, False, 1)),
    "p2/wall_sandbag_c": (240, lambda p: o_wall_sandbag(p, False, 2)),
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
    "decor/rock2": (260, o_rock_slab),
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
        return outdir / "troops" / (key[4:] + ".png")
    return outdir / "art" / (key + ".png")


SIZES: dict[str, tuple[int, int]] = {}
for _k, _v in {**HUMANS, **CORPSES}.items():
    SIZES[_k] = (_v["canvas"], _v["canvas"])
for _k, (_c, _f) in OBJECTS.items():
    SIZES[_k] = _c if isinstance(_c, tuple) else (_c, _c)

# Generative-AI replacements (ASSETS.md: "do not regenerate them through
# tools/gen_entities.py") -- excluded from the default sweep, still reachable
# via --only.
SUPERSEDED = frozenset({
    "SOL:soldier_assault_rifle",
    "SOL:enemy/enemy_assault_rifle",
    "SOL:enemy/enemy_smg",
    "SOL:enemy/enemy_shotgun",
    "SOL:enemy/enemy_lmg",
    "SOL:enemy/enemy_sniper",
})


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--outdir", type=Path, default=PROJECT_ROOT / "assets")
    ap.add_argument("--only")
    args = ap.parse_args()

    keys = [args.only] if args.only else [k for k in sorted(SIZES) if k not in SUPERSEDED]
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
