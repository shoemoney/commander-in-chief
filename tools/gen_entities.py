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


def build(key: str) -> Image.Image:
    if key in HUMANS:
        cfg = dict(HUMANS[key])
        n = cfg.pop("canvas")
        p = _pad(n)
        person(p, **cfg)
        return p.out()
    if key in CORPSES:
        cfg = dict(CORPSES[key])
        n = cfg.pop("canvas")
        p = _pad(n)
        _corpse(p, **cfg)
        return p.out()
    raise KeyError(key)


def dest_for(key: str, outdir: Path) -> Path:
    if key.startswith("SOL:"):
        return outdir / "soldiers" / (key[4:] + ".png")
    return outdir / "art" / (key + ".png")


SIZES = {k: v["canvas"] for k, v in {**HUMANS, **CORPSES}.items()}


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
        if im.size != (n, n):
            raise ValueError(f"{key}: got {im.size}, expected {(n, n)}")
        if im.getchannel("A").getbbox() is None:
            raise ValueError(f"{key}: fully transparent")
        d = dest_for(key, args.outdir)
        d.parent.mkdir(parents=True, exist_ok=True)
        im.save(d)
        print(f"  ok   {key}: {n}px")
    print(f"\n{len(keys)} sprite(s) -> {args.outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
