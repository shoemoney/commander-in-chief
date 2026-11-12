#!/usr/bin/env python3
"""Designed-at-native-size TOP-DOWN infantry sprites (hero, five weapon classes,
elite, frogman). Deterministic, no RNG, no external assets: every pixel is a
rasterised primitive (ellipse / rect / line) placed on a grid that is the
on-screen size. Owned art.

WHY: tools/bake_sprites.py shrank detailed standing figures to ~16x26 px and
then ROTATED them to the aim angle, so a three-quarter figure spun flat on the
ground and read as a dark blob. These are drawn bird's-eye from the start: a
shoulders ellipse, a round head/helmet with an upper-left highlight, two arms
reaching to a weapon whose barrel protrudes toward the facing direction (the TOP
of the image: Art.facing_rotation adds PI/2), a pack at the rear and boots that
alternate behind the body. Class identity is silhouette first, one accent second.

Colour: every colour below is the FINAL on-screen colour. The game multiplies
each sprite by Art.TINT[key] at draw time, so the file stores final/tint (the
TINT table is mirrored in TINTS and pinned by tools/test_gen_infantry.py against
art.gd). Edges are hard alpha with a 1px ink keyline (test_bake_sprites checks).

Usage:  python3 tools/gen_infantry.py            (writes assets/baked/**)
        python3 tools/gen_infantry.py --sheet OUT.png   (6x tinted contact sheet)
Run `godot --headless --path . --import` afterwards (the .import sidecars exist).
"""
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "baked")
INK = (13, 15, 10)
PAD = 2   # transparent border each side; the canvas centre is the draw pivot

# art.gd TINT rows for the keys these sets are drawn with (the elite draws as
# "enemy_assault"). Mirrored here and checked against art.gd by the python test.
TINTS = {
    "hero": (1.62, 1.64, 1.70),
    "enemy_assault": (1.10, 1.00, 0.90), "enemy_elite": (1.10, 1.00, 0.90),
    "enemy_smg": (1.12, 1.01, 0.90), "enemy_shotgun": (1.08, 0.99, 0.90),
    "enemy_lmg": (1.30, 0.88, 0.72), "enemy_sniper": (1.36, 0.90, 0.78),
    "frogman": (1.35, 1.6, 1.7), "frogman_speargun": (1.35, 1.6, 1.7),
}

# Opaque bbox (w, h) of every file INCLUDING its ink keyline: the footprints the
# fairness suites measure (tests/test_hitbox_fairness.gd bands, test_sprite_bake
# FOOTPRINT). Held fixed on purpose: the redesign changes the drawing, not a band.
BBOX = {
    "hero": {"base": (21, 29), "idle": (26, 30), "move_forward_0": (22, 30),
             "move_forward_1": (22, 30), "move_backward_0": (26, 30),
             "move_backward_1": (26, 30), "crouch": (28, 26), "shoot": (28, 30),
             "throw": (34, 30), "roll": (28, 28), "downed": (25, 30),
             "interact": (30, 30), "bash": (28, 30)},
    "enemy_assault": {"base": (17, 23), "idle": (16, 26), "move_0": (14, 26),
                      "move_1": (16, 26), "crouch": (16, 24), "windup": (14, 26),
                      "shoot": (14, 26), "stunned": (15, 25), "downed": (18, 28)},
    "enemy_smg": {"base": (14, 26), "idle": (14, 26), "move_0": (12, 26),
                  "move_1": (12, 26), "crouch": (16, 24), "windup": (14, 26),
                  "shoot": (12, 26), "stunned": (12, 23), "downed": (12, 28)},
    "enemy_shotgun": {"base": (17, 26), "idle": (16, 26), "move_0": (14, 26),
                      "move_1": (14, 26), "crouch": (18, 24), "windup": (15, 26),
                      "shoot": (14, 26), "stunned": (17, 26), "downed": (16, 28)},
    "enemy_lmg": {"base": (17, 26), "idle": (16, 26), "move_0": (12, 26),
                  "move_1": (14, 26), "crouch": (16, 24), "windup": (16, 26),
                  "shoot": (14, 26), "stunned": (18, 26), "downed": (16, 28)},
    "enemy_sniper": {"base": (13, 24), "idle": (12, 26), "move_0": (10, 24),
                     "move_1": (11, 25), "crouch": (12, 22), "windup": (12, 25),
                     "shoot": (11, 25), "stunned": (13, 25), "downed": (8, 26)},
    "enemy_elite": {"base": (19, 29), "idle": (18, 32), "move_0": (16, 32),
                    "move_1": (18, 31), "crouch": (18, 28), "windup": (16, 32),
                    "shoot": (16, 32), "stunned": (18, 30), "downed": (20, 33)},
    "frogman": {"base": (19, 20)},
    "frogman_speargun": {"base": (19, 23)},
}

# --- palettes (FINAL on-screen colours) ------------------------------------
HOSTILE = {
    "cloth": (150, 84, 56), "shade": (110, 58, 42), "pack": (82, 52, 40),
    "helm": (218, 178, 118), "helm_hi": (246, 222, 168), "helm_lo": (160, 122, 80),
    "skin": (228, 158, 118), "boot": (52, 34, 30), "steel": (98, 92, 94),
    "steel_hi": (214, 206, 196), "flash": (255, 240, 170), "flash2": (255, 190, 80),
    "hair": (70, 44, 34), "band": (222, 196, 98), "brass": (212, 164, 62),
}
# Readability pass: the rusher family (assault/smg/shotgun/lmg skins share one job, so one
# hue) is hot red against every green/sand ground; the sniper is hot magenta, the elite dark maroon
# with gold. Only colours change: geometry, footprints and anchors are untouched.
ROLE_PAL = {
    "enemy_assault": {"cloth": (222, 58, 40), "shade": (150, 30, 30), "pack": (92, 34, 34),
                      "skin": (246, 184, 140), "band": (255, 236, 150)},
    "enemy_smg": {"cloth": (236, 84, 36), "shade": (158, 40, 28), "pack": (92, 34, 34),
                  "skin": (246, 184, 140), "band": (255, 236, 150), "hair": (40, 22, 18)},
    "enemy_shotgun": {"cloth": (208, 44, 56), "shade": (140, 26, 40), "pack": (88, 30, 38),
                      "skin": (246, 184, 140), "band": (255, 226, 120)},
    "enemy_lmg": {"cloth": (200, 48, 36), "shade": (132, 26, 26), "pack": (84, 30, 30),
                  "skin": (246, 184, 140), "band": (255, 226, 120), "steel": (70, 66, 72)},
    "enemy_sniper": {"cloth": (222, 78, 158), "shade": (156, 44, 112), "pack": (98, 34, 72),
                     "helm": (250, 222, 238), "helm_hi": (255, 248, 252), "helm_lo": (196, 140, 170),
                     "skin": (246, 196, 160), "band": (255, 240, 180)},
    "enemy_elite": {"cloth": (104, 34, 30), "shade": (70, 20, 20), "pack": (44, 18, 18),
                    "helm": (252, 206, 70), "helm_hi": (255, 240, 150), "helm_lo": (190, 140, 40),
                    "skin": (246, 184, 140), "band": (255, 60, 50), "steel": (70, 66, 72)},
}
HERO = {
    "cloth": (84, 124, 96), "shade": (58, 92, 76), "pack": (52, 74, 66),
    "helm": (226, 232, 222), "helm_hi": (255, 255, 255), "helm_lo": (160, 176, 176),
    "skin": (244, 200, 164), "boot": (36, 40, 38), "steel": (84, 92, 104),
    "steel_hi": (214, 224, 232), "flash": (255, 244, 190), "flash2": (255, 200, 90),
    "arm": (86, 176, 236), "web": (196, 176, 124), "nade": (60, 96, 64),
}
DIVER = {
    "cloth": (84, 112, 124), "shade": (56, 78, 90), "tank": (150, 160, 156),
    "tank_hi": (200, 208, 204), "lens": (150, 236, 240), "fin": (44, 62, 72),
    "skin": (200, 150, 124), "steel": (62, 66, 70), "steel_hi": (176, 180, 184),
    "hood": (36, 52, 62), "hood_hi": (92, 118, 130),
}


class Cv:
    """A pixel canvas in INTERIOR coordinates (the ink keyline is added last)."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.a = np.zeros((h, w, 4), np.uint8)
        self.ys, self.xs = np.mgrid[0:h, 0:w]

    def px(self, x, y, c):
        x, y = int(x), int(y)
        if 0 <= x < self.w and 0 <= y < self.h:
            self.a[y, x] = (*c, 255)

    def ell(self, cx, cy, rx, ry, c, ring=None):
        if ring is not None:
            self.ell(cx, cy, rx + 0.75, ry + 0.75, ring)
        m = ((self.xs + 0.5 - cx) / rx) ** 2 + ((self.ys + 0.5 - cy) / ry) ** 2 <= 1.0
        self.a[m] = (*c, 255)

    def rect(self, x0, y0, x1, y1, c):
        for y in range(int(round(y0)), int(round(y1)) + 1):
            for x in range(int(round(x0)), int(round(x1)) + 1):
                self.px(x, y, c)

    def line(self, x0, y0, x1, y1, c):
        x0, y0, x1, y1 = (int(round(v)) for v in (x0, y0, x1, y1))
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
        err = dx + dy
        while True:
            self.px(x0, y0, c)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def mirror_px(self, x, y, c):
        self.px(x, y, c)
        self.px(self.w - 1 - x, y, c)


RIM_HOSTILE = (255, 226, 160)   # warm pale rim: lifts the silhouette off dark ground
RIM_HERO = (226, 244, 255)


def rim_light(a, solid, rim, k_lit, k_shade):
    """Lighten the solid pixels that touch the keyline (the inner rim). Edges facing the
    upper-left light get the stronger lift. Footprint and alpha are untouched."""
    h, w = solid.shape
    pad = np.pad(solid, 1)
    up, dn = ~pad[:-2, 1:-1], ~pad[2:, 1:-1]
    lf, rt = ~pad[1:-1, :-2], ~pad[1:-1, 2:]
    edge = solid & (up | dn | lf | rt)
    lit = solid & (up | lf)
    out = a.copy()
    rimc = np.array(rim, float)
    for m, k in ((edge & ~lit, k_shade), (lit, k_lit)):
        c = out[..., :3][m].astype(float)
        out[..., :3][m] = np.clip(np.round(c + (rimc - c) * k), 0, 255).astype(np.uint8)
    return out


def finish(cv, tint, rim=None):
    """Add the 1px ink keyline, centre in a PAD canvas, store final/tint colours."""
    a = cv.a
    solid = a[..., 3] > 0
    if rim is not None:
        a = rim_light(a, solid, rim, 0.5, 0.26)
    grown = solid.copy()
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            sh = np.zeros_like(solid)
            ys0, ys1 = max(dy, 0), cv.h + min(dy, 0)
            xs0, xs1 = max(dx, 0), cv.w + min(dx, 0)
            sh[ys0:ys1, xs0:xs1] = solid[ys0 - dy:ys1 - dy, xs0 - dx:xs1 - dx]
            grown |= sh
    h, w = cv.h + 2 + 2 * PAD, cv.w + 2 + 2 * PAD
    out = np.zeros((h, w, 4), np.uint8)
    # place interior at offset PAD+1; the ring needs the +1 border to exist
    full = np.zeros((h, w), bool)
    fsolid = np.zeros((h, w), bool)
    o = PAD
    fsolid[o + 1:o + 1 + cv.h, o + 1:o + 1 + cv.w] = solid
    fgrown = np.zeros((h, w), bool)
    # dilate on the padded canvas so the keyline can use the border row/col
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            sh = np.zeros_like(fsolid)
            ys0, ys1 = max(dy, 0), h + min(dy, 0)
            xs0, xs1 = max(dx, 0), w + min(dx, 0)
            sh[ys0:ys1, xs0:xs1] = fsolid[ys0 - dy:ys1 - dy, xs0 - dx:xs1 - dx]
            fgrown |= sh
    del full, grown
    out[..., :3][fgrown] = INK
    out[..., 3][fgrown] = 255
    inner = out[o + 1:o + 1 + cv.h, o + 1:o + 1 + cv.w]
    col = np.clip(np.round(a[..., :3].astype(float) / np.array(tint)), 0, 255).astype(np.uint8)
    inner[solid, :3] = col[solid]
    return out


# --- shared figure parts ----------------------------------------------------
def boots(cv, P, y_back, stride, sep, kind="rear"):
    """Two boots behind the body. stride>0: left boot trails, right is forward
    (hidden under the hips), stride<0 mirrors. Walk frames alternate."""
    cx = cv.w / 2.0
    for side, sgn in ((-1, 1), (1, -1)):
        off = stride * sgn
        y1 = y_back + min(0, off) * 0
        by0 = int(round(y_back - 3 + (off if off < 0 else 0) * 0))
        # trailing boot extends to the very back; forward boot tucks up
        y_end = y_back if off >= 0 else y_back - 3
        y_start = y_end - 2
        x = int(round(cx + side * sep - 1))
        cv.rect(x, y_start, x + 1, y_end, P["boot"])


def figure(cv, P, s):
    """Generic bird's-eye soldier from a spec dict `s`; returns nothing."""
    W, H = cv.w, cv.h
    cx = W / 2.0
    hy = s["head_y"]
    # --- rear first (pack, legs), then body, then arms/weapon, then head on top
    for (bx, by0, by1) in s.get("legs", []):
        cv.rect(bx, by0, bx + 1, by1, P["boot"])
    if s.get("pack"):
        px0, py0, px1, py1 = s["pack"]
        cv.rect(px0, py0, px1, py1, P["pack"])
        cv.rect(px0 + 1, py0, px1 - 1, py0, P.get("shade", P["pack"]))
    # hips / torso
    cv.ell(cx, s["torso_y"], s["torso_rx"], s["torso_ry"], P["shade"])
    # shoulders ellipse
    cv.ell(cx, s["sh_y"], s["sh_rx"], s["sh_ry"], P["cloth"])
    if s.get("bandolier"):
        cv.line(cx - s["sh_rx"] + 2, s["sh_y"] - 2, cx + s["sh_rx"] - 3, s["sh_y"] + 2, P["brass"])
        cv.line(cx - s["sh_rx"] + 2, s["sh_y"] - 1, cx + s["sh_rx"] - 3, s["sh_y"] + 3, P["pack"])
    # arms: sleeve lines from the shoulder tips to the hands
    wx = s["wx"]
    lh, rh = s["lhand"], s["rhand"]
    lsh = (cx - s["sh_rx"] + 1.2, s["sh_y"] - 0.5)
    rsh = (cx + s["sh_rx"] - 1.2, s["sh_y"] - 0.5)
    cv.line(*lsh, *lh, P["cloth"])
    cv.line(lsh[0] + 1, lsh[1], lh[0], lh[1] + 1, P["shade"])
    cv.line(*rsh, *rh, P["cloth"])
    cv.line(rsh[0] - 1, rsh[1], rh[0], rh[1] + 1, P["shade"])
    # weapon
    wpn = s["weapon"]
    tip, tail = wpn["tip"], wpn["tail"]
    th = wpn.get("thick", 1)
    for k in range(th):
        cv.rect(wx + k, tip, wx + k, tail, P["steel"])
    if th == 1:
        cv.rect(wx, tip, wx, tip + max(1, (tail - tip) // 3), P["steel_hi"]) if wpn.get("lit") else None
    # receiver / body of the gun, thicker + highlighted
    r0, r1 = wpn["recv"]
    cv.rect(wx - 1 if th == 1 else wx, r0, wx + th, r1, P["steel"])
    cv.px(wx, r0, P["steel_hi"])
    if wpn.get("mag"):
        mx, my0, my1 = wpn["mag"]
        cv.rect(mx, my0, mx, my1, P["steel"])
        cv.px(mx, my0, P["steel_hi"])
    if wpn.get("box"):
        bx0, by0, bx1, by1 = wpn["box"]
        cv.rect(bx0, by0, bx1, by1, P["pack"])
        cv.rect(bx0, by0, bx1, by0, P["brass"])
    if wpn.get("scope"):
        sy0, sy1 = wpn["scope"]
        cv.rect(wx - 1, sy0, wx + th, sy1, P["steel_hi"])
    if wpn.get("bipod"):
        by = wpn["bipod"]
        cv.px(wx - 2, by + 1, P["steel"])
        cv.px(wx - 1, by, P["steel"])
        cv.px(wx + th + 1, by + 1, P["steel"])
        cv.px(wx + th, by, P["steel"])
    cv.px(*lh, P["skin"])
    cv.px(*rh, P["skin"])
    if s.get("flash"):
        fx, fy = wx, tip
        cv.px(fx, fy, P["flash"])
        cv.px(fx - 1, fy + 1, P["flash2"])
        cv.px(fx + 1, fy + 1, P["flash2"])
    # extras drawn before the head
    for e in s.get("extras", []):
        e(cv, P)
    # head
    hx = cx + s.get("head_dx", 0)
    hr = s["head_r"]
    style = s["head"]
    if style == "helmet":
        cv.ell(hx, hy, hr, hr, P["helm"], ring=P["helm_lo"] if False else P["shade"])
        cv.ell(hx, hy + 0.6, hr - 0.8, hr - 1.0, P["helm"])
        cv.rect(hx - 1.5, hy - hr + 0.3, hx + 1.2, hy - hr + 0.3, P["helm_lo"])   # brim shadow = front
        cv.px(hx - 1.5, hy - 1.2, P["helm_hi"])
        cv.px(hx - 0.5, hy - 1.7, P["helm_hi"])
        cv.px(hx - 1.5, hy - 0.2, P["helm_hi"])
    elif style == "bare":
        cv.ell(hx, hy, hr, hr, P["hair"], ring=P["shade"])
        cv.rect(hx - hr + 0.5, hy + 0.6, hx + hr - 1.2, hy + 1.4, P["band"])   # bandana across the rear
        cv.px(hx - 1.5, hy - 1.5, P["steel_hi"] if False else P["helm_lo"])
        cv.px(hx - 0.5, hy - 2.0, P["helm_lo"])
    elif style == "hat":
        cv.ell(hx, hy, hr + 1.3, hr + 1.0, P["helm_lo"], ring=P["shade"])   # wide brim
        cv.ell(hx, hy - 0.2, hr - 0.7, hr - 0.9, P["helm"])
        cv.px(hx - 1.2, hy - 1.4, P["helm_hi"])
        cv.px(hx - 0.2, hy - 1.8, P["helm_hi"])
    elif style == "boonie":
        cv.ell(hx, hy, hr + 0.8, hr + 0.8, P["shade"], ring=P["boot"])
        cv.ell(hx, hy, hr - 0.9, hr - 0.9, P["helm_lo"])
        cv.px(hx - 1, hy - 1, P["helm"])
    elif style == "crest":
        cv.ell(hx, hy, hr, hr + 0.7, P["helm"], ring=P["shade"])
        cv.rect(hx - 0.5, hy - hr - 0.2, hx + 0.5, hy + hr + 0.4, P["band"])   # bone/gold crest stripe
        cv.rect(hx - hr + 1, hy - hr + 0.8, hx + hr - 2, hy - hr + 1.6, P["helm_lo"])   # visor
        cv.px(hx - 2, hy - 0.2, P["helm_hi"])
        cv.px(hx - 2, hy + 0.8, P["helm_hi"])
    elif style == "hero_helm":
        cv.ell(hx, hy, hr, hr, P["helm"], ring=P["shade"])
        cv.rect(hx - hr + 1.2, hy + 0.4, hx + hr - 1.2, hy + 1.3, P["arm"])   # cool headband
        cv.rect(hx - 1.5, hy - hr + 0.4, hx + 1.2, hy - hr + 0.4, P["helm_lo"])
        for (dx, dy) in ((-1.8, -1.5), (-0.8, -2.2), (-2.4, -0.6)):
            cv.px(hx + dx, hy + dy, P["helm_hi"])


def spec_for(kind, bw, bh, pose):
    """Interior spec for one (class, pose). bw/bh = final bbox incl. keyline."""
    W, H = bw - 2, bh - 2
    cx = W / 2.0
    s = {"W": W, "H": H}

    def walk_legs(y_end, sep, stride, thick=2):
        lg = []
        for side, sgn in ((-1, 1), (1, -1)):
            x = int(round(cx + side * sep - 1))
            off = stride * sgn          # >0: this boot trails to the very back
            end = y_end if off >= 0 else y_end - 3
            lg.append((x, end - (4 if off > 0 else 2), end))
        return lg

    stride = {"move_0": 3, "move_1": -3, "move_forward_0": 3, "move_forward_1": -3,
              "move_backward_0": -3, "move_backward_1": 3}.get(pose, 0)
    fire = pose == "shoot"
    aim = pose == "windup"
    crouch = pose == "crouch"
    stun = pose == "stunned"
    down = pose == "downed"
    return s, cx, walk_legs, stride, fire, aim, crouch, stun, down


def build(kind, pose, bw, bh):
    P = HERO if kind == "hero" else (DIVER if kind.startswith("frog") else dict(HOSTILE, **ROLE_PAL.get(kind, {})))
    if kind.startswith("frog"):
        return build_diver(kind, bw, bh)
    s, cx, walk_legs, stride, fire, aim, crouch, stun, down = spec_for(kind, bw, bh, pose)
    W, H = s["W"], s["H"]
    cv = Cv(W, H)
    base = pose == "base"
    if down:
        return build_downed(cv, P, kind, W, H)
    if kind == "hero" and pose == "roll":
        return build_roll(cv, P, W, H)

    # --- per-class geometry (fractions of H keep poses/bases consistent) ------
    f = lambda v: v * H
    if kind in ("enemy_assault", "enemy_lmg", "enemy_shotgun"):
        s.update(head_y=f(0.50), head_r=2.9 if kind != "enemy_shotgun" else 2.7,
                 sh_y=f(0.54), sh_rx=W / 2.0, sh_ry=3.0, torso_y=f(0.66), torso_rx=W / 2.0 - 3.5, torso_ry=f(0.18),
                 pack=(int(cx - 3), int(f(0.66)), int(cx + 2), int(f(0.84))), wx=int(cx + 1.0),
                 head="helmet" if kind != "enemy_shotgun" else "hat")
        s["legs"] = walk_legs(H - 1, 3.0, stride)
        tip = 0 if not fire else 1
        s["weapon"] = {"tip": tip, "tail": int(f(0.54)), "recv": (int(f(0.26)), int(f(0.46))), "lit": True, "mag": None}
        s["lhand"] = (int(cx - 0.8), int(f(0.20)))
        s["rhand"] = (int(cx + 3.0), int(f(0.40)))
        if kind == "enemy_lmg":
            s["weapon"].update(thick=2, bipod=int(f(0.14)), box=(int(cx - 5), int(f(0.34)), int(cx - 3), int(f(0.50))))
            s["wx"] = int(cx)
            s["weapon"]["recv"] = (int(f(0.24)), int(f(0.48)))
            s["lhand"] = (int(cx - 2), int(f(0.26)))
            s["rhand"] = (int(cx + 3), int(f(0.40)))
        if kind == "enemy_shotgun":
            s["bandolier"] = True
            s["weapon"].update(thick=2, tip=0 if not fire else 1)
            s["weapon"]["tail"] = int(f(0.46))
            s["weapon"]["recv"] = (int(f(0.30)), int(f(0.40)))
            s["pack"] = (int(cx - 2), int(f(0.68)), int(cx + 1), int(f(0.82)))
            s["wx"] = int(cx)
    elif kind == "enemy_smg":
        s.update(head_y=f(0.36), head_r=3.0, sh_y=f(0.44), sh_rx=W / 2.0 - 0.5, sh_ry=3.2,
                 torso_y=f(0.60), torso_rx=W / 2.0 - 2.0, torso_ry=f(0.16), pack=None,
                 wx=int(cx + 1), head="bare", head_dx=-0.5)
        s["legs"] = walk_legs(H - 1, 2.6, stride if stride else 2)
        tip = (1 if fire else 0)
        s["weapon"] = {"tip": tip, "tail": int(f(0.46)), "recv": (int(f(0.2)), int(f(0.42))), "lit": True,
                       "mag": (int(cx + 3), int(f(0.26)), int(f(0.36)))}
        s["lhand"] = (int(cx - 0.5), int(f(0.20)))
        s["rhand"] = (int(cx + 2.4), int(f(0.38)))
    elif kind == "enemy_sniper":
        s.update(head_y=f(0.50), head_r=2.6, sh_y=f(0.56), sh_rx=W / 2.0, sh_ry=3.4, torso_y=f(0.68),
                 torso_rx=W / 2.0 - 1.5, torso_ry=f(0.2), pack=(int(cx - 2), int(f(0.70)), int(cx + 1), int(f(0.86))),
                 wx=int(cx + 1), head="boonie")
        s["legs"] = walk_legs(H - 1, 2.2, stride)
        tip = 0 if not fire else 1
        s["weapon"] = {"tip": tip, "tail": int(f(0.62)), "recv": (int(f(0.34)), int(f(0.52))), "lit": True,
                       "scope": (int(f(0.36)), int(f(0.44)))}
        s["lhand"] = (int(cx - 0.6), int(f(0.22)))
        s["rhand"] = (int(cx + 2.2), int(f(0.40)))
        s["extras"] = [lambda c, p, W=W, H=H: ghillie(c, p, W, H)]
    elif kind == "enemy_elite":
        s.update(head_y=f(0.48), head_r=3.1, sh_y=f(0.53), sh_rx=W / 2.0, sh_ry=3.6, torso_y=f(0.66),
                 torso_rx=W / 2.0 - 2.2, torso_ry=f(0.18), pack=(int(cx - 3), int(f(0.66)), int(cx + 2), int(f(0.86))),
                 wx=int(cx + 1), head="crest")
        s["legs"] = walk_legs(H - 1, 3.2, stride)
        tip = 0 if not fire else 1
        s["weapon"] = {"tip": tip, "tail": int(f(0.54)), "recv": (int(f(0.24)), int(f(0.46))), "lit": True,
                       "mag": (int(cx + 3), int(f(0.30)), int(f(0.40)))}
        s["lhand"] = (int(cx - 0.8), int(f(0.20)))
        s["rhand"] = (int(cx + 3.2), int(f(0.38)))
        s["extras"] = [lambda c, p, W=W, H=H, cx=cx, shy=f(0.53): elite_extras(c, p, W, H, cx, shy)]
    elif kind == "hero":
        s.update(head_y=f(0.50), head_r=4.2, sh_y=f(0.55), sh_rx=W / 2.0, sh_ry=3.6, torso_y=f(0.68),
                 torso_rx=W / 2.0 - 6.0, torso_ry=f(0.17), pack=(int(cx - 4), int(f(0.64)), int(cx + 3), int(f(0.84))),
                 wx=int(cx + 1), head="hero_helm")
        s["legs"] = walk_legs(H - 1, 3.6, stride)
        tip = 0 if not fire else 1
        s["weapon"] = {"tip": tip, "tail": int(f(0.56)), "recv": (int(f(0.22)), int(f(0.44))), "lit": True,
                       "mag": (int(cx + 3), int(f(0.30)), int(f(0.38))), "thick": 2}
        s["lhand"] = (int(cx - 0.8), int(f(0.17)))
        s["rhand"] = (int(cx + 4), int(f(0.38)))
        s["extras"] = [lambda c, p, W=W, H=H, cx=cx, shy=f(0.55): hero_extras(c, p, W, H, cx, shy)]
    apply_pose(kind, pose, s, cv, W, H, cx, fire, aim, crouch, stun)
    s["flash"] = fire
    figure(cv, P, s)
    if pose in ("idle", "base"):
        # fairness bands pin these two footprints: widen the shoulders until the
        # opaque bbox (interior + 2px keyline) is exactly the pinned size.
        for _ in range(6):
            xs = np.nonzero(cv.a[..., 3].any(axis=0))[0]
            if xs.max() - xs.min() + 3 >= W + 2:
                break
            s["sh_rx"] += 0.5
            cv.a[:] = 0
            figure(cv, P, s)
    if kind == "hero":
        hero_pose_extras(cv, P, pose, W, H, cx)
    return cv


def apply_pose(kind, pose, s, cv, W, H, cx, fire, aim, crouch, stun):
    if crouch:
        s["head_y"] += 0.0
        s["sh_ry"] += 0.8
        s["legs"] = []
    if aim:
        s["head_y"] -= 1.0
        s["sh_rx"] = max(3.0, s["sh_rx"] - 1.0)
        s["lhand"] = (s["lhand"][0], max(1, s["lhand"][1] - 2))
        s["rhand"] = (s["rhand"][0] - 1, s["rhand"][1] - 2)
    if stun:
        s["head_dx"] = s.get("head_dx", 0) + 1.5
        w = s["weapon"]
        w["tip"] = w["tip"] + 6
        s["lhand"] = (int(cx - s["sh_rx"] + 1), int(s["head_y"] - 1))
        s["rhand"] = (int(cx + s["sh_rx"] - 2), int(s["head_y"] - 1))
    if pose in ("throw", "interact", "bash") and kind == "hero":
        pass


def ghillie(cv, P, W, H):
    """Ragged leaf edge for the sniper: deterministic notches/tufts, no RNG."""
    tufts = [(0, 0.46), (W - 1, 0.50), (1, 0.62), (W - 2, 0.66), (0, 0.74), (W - 1, 0.78),
             (2, 0.84), (W - 3, 0.90), (1, 0.56), (W - 1, 0.58)]
    cols = [P["shade"], P["pack"], P["helm_lo"]]
    for i, (x, fy) in enumerate(tufts):
        y = int(fy * H)
        cv.px(x, y, cols[i % 3])
        cv.px(x + (1 if x < W / 2 else -1), y + 1, cols[(i + 1) % 3])
    for i in range(0, 5):
        cv.px(int(W / 2.0 - 3 + i * 1.4), int(0.78 * H) + (i % 2), cols[i % 3])


def elite_extras(cv, P, W, H, cx, shy):
    # square pauldrons with a gold edge, a whip antenna off the radio pack
    for sgn in (-1, 1):
        x = int(cx + sgn * (W / 2.0 - 2.2))
        cv.rect(x - 1, shy - 2, x + 1, shy + 1, P["shade"])
        cv.px(x - 1 if sgn < 0 else x + 1, shy - 2, P["band"])
    cv.line(cx + 2, H * 0.86, cx + 4, H * 0.62 - 6 + 6, P["steel_hi"])


def hero_extras(cv, P, W, H, cx, shy):
    for sgn in (-1, 1):
        x = int(cx + sgn * (W / 2.0 - 2))
        cv.rect(x - 1, shy - 1, x, shy + 2, P["arm"])   # cool shoulder patches
    cv.line(cx - 5, shy - 2, cx + 3, shy + 4, P["web"])   # chest webbing strap
    cv.line(cx + 5, shy - 2, cx - 3, shy + 4, P["web"])


def hero_pose_extras(cv, P, pose, W, H, cx):
    if pose == "throw":
        cv.line(cx + 3, H * 0.4, cx + W / 2.0 - 1, H * 0.24, P["cloth"])
        cv.ell(cx + W / 2.0 - 1, H * 0.24, 1.5, 1.5, P["nade"], ring=P["boot"])
    elif pose == "bash":
        cv.line(cx - W / 2.0 + 2, H * 0.22, cx + W / 2.0 - 2, H * 0.36, P["steel"])
        cv.line(cx - W / 2.0 + 2, H * 0.23, cx + W / 2.0 - 2, H * 0.37, P["steel_hi"])
    elif pose == "interact":
        cv.px(cx + 4, H * 0.1, P["skin"])
        cv.px(cx + 5, H * 0.1 - 1, P["skin"])


def build_roll(cv, P, W, H):
    cx, cy = W / 2.0, H / 2.0
    cv.ell(cx, cy + 1, W / 2.0 - 1, H / 2.0 - 1, P["cloth"])
    cv.ell(cx, cy + 4, W / 2.0 - 4, 5.5, P["pack"])           # pack arc on the outside of the tuck
    cv.ell(cx, cy - 4, 3.6, 3.6, P["helm"], ring=P["shade"])   # head tucked at the front
    cv.px(cx - 2, cy - 6, P["helm_hi"])
    cv.rect(cx - 3, cy - 3, cx + 2, cy - 2, P["arm"])
    cv.line(cx - 5, cy - 1, cx + 5, cy - 1, P["steel"])        # rifle across the chest
    cv.px(cx - 6, cy + 1, P["boot"])
    cv.px(cx + 5, cy + 1, P["boot"])
    return cv


def build_downed(cv, P, kind, W, H):
    """Face-down, head toward the top (the sprite is spun by the corpse code)."""
    cx = W / 2.0
    dark = {k: tuple(int(v * 0.72) for v in c) for k, c in P.items()}
    P = dark
    cv.rect(cx - 3, H * 0.74, cx - 2, H - 1, P["boot"])
    cv.rect(cx + 1, H * 0.78, cx + 2, H - 1, P["boot"])
    cv.ell(cx, H * 0.55, W / 2.0 - 1.5, H * 0.28, P["cloth"])
    cv.ell(cx, H * 0.62, W / 2.0 - 3.5, H * 0.18, P["pack"])
    cv.line(2, H * 0.40, 1, H * 0.22, P["cloth"])             # arms flung out
    cv.line(W - 3, H * 0.40, W - 2, H * 0.30, P["cloth"])
    cv.px(1, H * 0.2, P["skin"])
    cv.px(W - 2, H * 0.28, P["skin"])
    cv.line(cx + 3, H * 0.14, cx + 3, H * 0.50, P["steel"])   # dropped weapon beside the body
    cv.ell(cx, H * 0.26, 3.0, 3.0, P["helm"], ring=P["shade"])
    return cv


def build_diver(kind, bw, bh):
    P = DIVER
    W, H = bw - 2, bh - 2
    cv = Cv(W, H)
    cx = W / 2.0
    spear = kind == "frogman_speargun"
    # fins: a V of two flippers behind the body (the widest part of the silhouette)
    cv.line(cx - 1, H - 6, 0, H - 1, P["fin"])
    cv.line(cx - 2, H - 6, 1, H - 2, P["fin"])
    cv.line(cx + 1, H - 6, W - 1, H - 1, P["fin"])
    cv.line(cx + 2, H - 6, W - 2, H - 2, P["fin"])
    cv.rect(0, H - 2, 2, H - 1, P["fin"])
    cv.rect(W - 3, H - 2, W - 1, H - 1, P["fin"])
    # air tank along the back
    cv.ell(cx, H * 0.70, 2.2, H * 0.17, P["tank"], ring=P["hood"])
    cv.px(cx - 1, H * 0.62, P["tank_hi"])
    cv.px(cx - 1, H * 0.68, P["tank_hi"])
    # body + shoulders
    cv.ell(cx, H * 0.50, W / 2.0 - 3.5, 3.6, P["cloth"])
    cv.ell(cx, H * 0.58, 3.4, 4.0, P["shade"])
    # arms to the weapon
    wx = int(cx + 1)
    cv.line(cx - 3.5, H * 0.46, wx, H * 0.26, P["cloth"])
    cv.line(cx + 3.5, H * 0.46, wx + 1, H * 0.34, P["cloth"])
    tip = 0 if not spear else 1
    cv.rect(wx, tip, wx, int(H * 0.5), P["steel"])
    if spear:
        cv.px(wx, 0, P["steel_hi"])       # spear tip
        cv.rect(wx - 1, int(H * 0.3), wx + 1, int(H * 0.36), P["steel"])
    else:
        cv.rect(wx - 1, int(H * 0.22), wx + 1, int(H * 0.38), P["steel"])
        cv.px(wx, int(H * 0.22), P["steel_hi"])
    cv.px(wx - 1, int(H * 0.28), P["skin"])
    cv.px(wx + 1, int(H * 0.36), P["skin"])
    # hooded head with goggles
    cv.ell(cx, H * 0.42, 3.2, 3.2, P["hood"], ring=P["shade"])
    cv.rect(cx - 2, H * 0.34, cx + 1, H * 0.34 + 1, P["lens"])
    cv.px(cx - 2, H * 0.36, P["lens"])
    cv.px(cx + 1, H * 0.36, P["lens"])
    cv.px(cx - 1, H * 0.46, P["hood_hi"])
    return cv


# base.png keeps its historic CANVAS and bbox offset: tests/test_view_honesty.gd
# SPRITE_CANVAS pins max(w, h) of the canvas each art.gd SCALE row was tuned on.
BASE_CANVAS = {"hero": (26, 36, 3, 2), "enemy_assault": (22, 28, 3, 2), "enemy_smg": (20, 30, 4, 2),
               "enemy_shotgun": (22, 32, 3, 2), "enemy_lmg": (22, 32, 3, 2),
               "enemy_sniper": (18, 30, 3, 4), "enemy_elite": (24, 36, 3, 2),
               "frogman": (24, 26, 2, 2), "frogman_speargun": (24, 32, 2, 2)}


def to_base_canvas(kind, arr):
    cw, ch, x0, y0 = BASE_CANVAS[kind]
    src = arr[PAD:arr.shape[0] - PAD, PAD:arr.shape[1] - PAD]
    out = np.zeros((ch, cw, 4), np.uint8)
    out[y0:y0 + src.shape[0], x0:x0 + src.shape[1]] = src
    return out


def render_all():
    out = {}
    for kind, poses in BBOX.items():
        for pose, (bw, bh) in poses.items():
            cv = build(kind, pose, bw, bh)
            arr = finish(cv, TINTS[kind], RIM_HERO if kind == "hero" else None)
            if pose == "base":
                arr = to_base_canvas(kind, arr)
            out[(kind, pose)] = arr
    return out


def tinted(arr, tint):
    a = arr.astype(float)
    a[..., :3] = np.clip(a[..., :3] * np.array(tint), 0, 255)
    return a.astype(np.uint8)


def sheet(path, scale=6):
    imgs = render_all()
    rows = []
    for kind, poses in BBOX.items():
        tiles = [Image.fromarray(tinted(imgs[(kind, p)], TINTS[kind]), "RGBA") for p in poses]
        rows.append(tiles)
    cw = max(sum(t.width for t in r) + 3 * len(r) for r in rows)
    ch = sum(max(t.height for t in r) + 3 for r in rows)
    bg = Image.new("RGBA", (cw, ch), (150, 118, 84, 255))
    y = 0
    for r in rows:
        x = 0
        for t in r:
            bg.alpha_composite(t, (x, y))
            x += t.width + 3
        y += max(t.height for t in r) + 3
    bg.resize((cw * scale, ch * scale), Image.NEAREST).save(path)


def main(argv):
    if len(argv) >= 3 and argv[1] == "--sheet":
        sheet(argv[2])
        return 0
    for (kind, pose), arr in render_all().items():
        d = os.path.join(OUT, kind)
        os.makedirs(d, exist_ok=True)
        Image.fromarray(arr, "RGBA").save(os.path.join(d, f"{pose}.png"), optimize=True)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
