#!/usr/bin/env python3
"""Bake the infantry sprites to their exact on-screen pixel size.

WHY: the authored masters (1024px bases, 256px hero poses, 128px enemy poses)
were shrunk at DRAW time by a 3.8-7.4x factor with NEAREST filtering and no
mipmaps, so the 640x360 frame showed aliased noise instead of soldiers. The
bake does that shrink once, offline, with an area (BOX) filter, then makes
the result crisp: hard alpha, a small shared palette, a 1px dark keyline.
The result is drawn at NET scale 1.0 (Art.SCALE = 1 / call scale).

TWO KINDS OF OUTPUT, and only one of them is still this tool's job:
- Props, vehicles and bosses (PROP_FAMILIES: vehicle, gunship, colossus, bunker, crate,
  cover, rock) are baked here on every run.
- The INFANTRY sets are not. They are designed at native size, top-down, by
  tools/gen_infantry.py; baking the old shrunk masters over them would silently undo
  that, so the infantry sets are SKIPPED unless you pass --legacy-masters (kept as the
  fallback / comparison path).

Usage:  python3 tools/bake_sprites.py                    (props, vehicles, bosses)
        BAKE_ONLY=<family> python3 tools/bake_sprites.py (one prop family)
        python3 tools/bake_sprites.py --legacy-masters   (also overwrites the infantry sets)
Layout: assets/baked/<set>/<pose>.png, plus base.png (from the 1024 master).

The sizes below are the single source of truth for the on-screen footprint;
tools/test_bake_sprites.py and tests/test_sprite_bake.gd read the outputs.
"""
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOL = os.path.join(ROOT, "assets", "troops")
OUT = os.path.join(ROOT, "assets", "baked")

INK = (13, 15, 10)          # Art.PRINT_INK (0.05, 0.06, 0.04) in 8-bit
ALPHA_CUT = 128

HERO_POSES = ["idle", "move_forward_0", "move_forward_1", "move_backward_0",
              "move_backward_1", "crouch", "shoot", "throw", "roll", "downed",
              "interact", "bash"]
ENEMY_POSES = ["idle", "move_0", "move_1", "crouch", "windup", "shoot",
               "stunned", "downed"]

# Growth the fairness suite absorbs WITHOUT moving a band, found by sweeping
# (tests/test_hitbox_fairness.gd): hero x1.15 passes; enemy 1.04+ fails the rusher
# "round 1px inside its silhouette must register" band (sim reach is fixed) and
# the player-bullet-vs-fodder band caps the smg near 1.0, so enemies stay x1.0.
# The win for enemies is crispness, not size.
HERO_GROWTH = float(os.environ.get("BAKE_HERO_GROWTH", 1.15))
ENEMY_GROWTH = float(os.environ.get("BAKE_ENEMY_GROWTH", 1.0))

# The 1024px masters were drawn via their IMPORT size_limit (hero 256, rest 128),
# hence base_factor. Pre-bake draw scale of a master pixel on screen = call scale * Art.SCALE.
# hero:  0.52 * 0.26 ; enemy skins: 0.52 * 0.5 (LIVE_RIFLEMAN_SCALE) ;
# sniper: 0.5 * 0.5 ; elite: 0.62 * 0.5 ; frogman: 0.5 * 0.5.
HERO_T = 0.52 * 0.26
HERO_XSTRETCH = 1.58


def _enemy_set(skin, call, growth=ENEMY_GROWTH, name=None, pose_dir=None):
    pd = pose_dir or skin
    srcs = {p: f"anim/{pd}/{p}.png" for p in ENEMY_POSES}
    srcs["base"] = f"enemy/{skin}.png"
    return {"name": name or skin, "t": call * 0.5 * growth, "xs": 1.0,
            "colors": 28, "src": srcs, "unstretched_base": False,
            "base_factor": 128 / 1024}


def sets():
    hero = {p: f"anim/player/{p}.png" for p in HERO_POSES}
    hero["base"] = "soldier_assault_rifle.png"
    out = [{"name": "hero", "t": HERO_T * HERO_GROWTH, "xs": HERO_XSTRETCH,
            "colors": 40, "src": hero, "unstretched_base": True,
            "base_factor": 256 / 1024}]
    skins = {"enemy_assault": "enemy_assault_rifle", "enemy_smg": "enemy_smg",
             "enemy_shotgun": "enemy_shotgun", "enemy_lmg": "enemy_lmg"}
    for key, master in skins.items():
        s = _enemy_set(master, 0.52, pose_dir=key, name=key)
        s["src"]["base"] = f"enemy/{master}.png"
        out.append(s)
    sn = _enemy_set("enemy_sniper", 0.5, pose_dir="enemy_sniper", name="enemy_sniper")
    sn["src"]["base"] = "enemy/enemy_sniper.png"
    out.append(sn)
    el = _enemy_set("enemy_assault_rifle", 0.62, pose_dir="enemy_assault", name="enemy_elite")
    out.append(el)
    for key, master in (("frogman", "frogman_rifle"), ("frogman_speargun", "frogman_speargun")):
        out.append({"name": key, "t": 0.5 * 0.5, "xs": 1.0, "colors": 24,
                    "src": {"base": f"{master}.png"}, "unstretched_base": False,
                    "base_factor": 128 / 1024})
    return out


def _even(v):
    n = int(round(v))
    return n + (n & 1)


def box_shrink(img, t, xs):
    """Area-average the whole canvas to (N*t*xs, N*t), alpha-premultiplied."""
    n_w, n_h = img.size
    w, h = _even(n_w * t * xs), _even(n_h * t)
    return img.resize((w, h), Image.BOX)   # Pillow premultiplies RGBA for BOX


def crop_symmetric(img, margin=2):
    """Trim empty border but keep the canvas centre (the draw pivot) fixed."""
    a = np.asarray(img)[..., 3]
    ys, xs_ = np.nonzero(a >= ALPHA_CUT)
    if len(ys) == 0:
        return img
    w, h = img.size
    cx, cy = w / 2.0, h / 2.0
    hx = max(cx - xs_.min(), xs_.max() + 1 - cx) + margin
    hy = max(cy - ys.min(), ys.max() + 1 - cy) + margin
    hx, hy = int(np.ceil(hx)), int(np.ceil(hy))
    hx, hy = min(hx, w // 2), min(hy, h // 2)
    out = Image.new("RGBA", (hx * 2, hy * 2), (0, 0, 0, 0))
    out.paste(img.crop((w // 2 - hx, h // 2 - hy, w // 2 + hx, h // 2 + hy)), (0, 0))
    return out


def shared_palette(images, colors):
    px = []
    for im in images:
        a = np.asarray(im)
        m = a[..., 3] >= ALPHA_CUT
        px.append(a[..., :3][m])
    flat = np.concatenate(px, axis=0)
    side = int(np.ceil(np.sqrt(len(flat))))
    pad = np.zeros((side * side, 3), np.uint8)
    pad[:len(flat)] = flat
    pad[len(flat):] = flat[:1]
    strip = Image.fromarray(pad.reshape(side, side, 3), "RGB")
    return strip.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)


def finish(img, pal):
    """Hard alpha + palette snap + 1px inner keyline."""
    a = np.asarray(img).copy()
    solid = a[..., 3] >= ALPHA_CUT
    rgb = Image.fromarray(a[..., :3], "RGB").quantize(
        palette=pal, dither=Image.Dither.NONE).convert("RGB")
    out = np.zeros_like(a)
    out[..., :3] = np.asarray(rgb)
    out[..., 3] = np.where(solid, 255, 0)
    out[~solid, :3] = 0
    # INNER keyline: the outermost ring of solid pixels turns ink. The silhouette
    # (and so every fairness measurement of it) is not inflated by the outline.
    inner = solid.copy()
    inner[1:, :] &= solid[:-1, :]
    inner[:-1, :] &= solid[1:, :]
    inner[:, 1:] &= solid[:, :-1]
    inner[:, :-1] &= solid[:, 1:]
    inner[0, :] = inner[-1, :] = False
    inner[:, 0] = inner[:, -1] = False
    ring = solid & ~inner
    out[ring] = (*INK, 255)
    return Image.fromarray(out, "RGBA")


def pad_for_keyline(img, px=2):
    w, h = img.size
    out = Image.new("RGBA", (w + 2 * px, h + 2 * px), (0, 0, 0, 0))
    out.paste(img, (px, px))
    return out


def bake_set(s):
    shrunk = {}
    for pose, rel in s["src"].items():
        src = Image.open(os.path.join(SOL, rel)).convert("RGBA")
        xs = 1.0 if (pose == "base" and s.get("unstretched_base")) else s["xs"]
        t = s["t"] * s.get("base_factor", 1.0) if pose == "base" else s["t"]
        shrunk[pose] = crop_symmetric(pad_for_keyline(box_shrink(src, t, xs)))
    pal = shared_palette(list(shrunk.values()), s["colors"])
    d = os.path.join(OUT, s["name"])
    os.makedirs(d, exist_ok=True)
    for pose, im in shrunk.items():
        finish(im, pal).save(os.path.join(d, f"{pose}.png"), optimize=True)
    return {p: im.size for p, im in shrunk.items()}


# ---------------------------------------------------------------------------
# NON-INFANTRY families (vehicles, bosses, bunkers, crates, cover, rocks, flora).
# Each key: (source png under assets/, canonical CALL scale of its draw site,
# old Art.SCALE row). The on-screen size is src * call * old_scale; the bake
# is that size exactly and the NEW Art.SCALE row is 1/call (net 1.0). Sizes are
# rounded to even so the canvas centre (the draw pivot) stays on a pixel edge,
# and the canvas is NOT cropped, so the pivot and opaque footprint stay put.
# Output: assets/baked/<family>/<key>.png
# ---------------------------------------------------------------------------
ART = os.path.join(ROOT, "assets", "art")

PROP_FAMILIES = {
    "vehicle": {"colors": 32, "items": {
        "tank_body": ("tank_body.png", 0.62, 0.72),
        "tank_barrel": ("tank_barrel.png", 0.62, 0.69),
        "m_technical": ("mil2/technical.png", 0.55, 0.60),
        "tank_hulk": ("p2/tank_hulk.png", 0.62, 0.72)}},
    "gunship": {"colors": 32, "items": {
        "gunship_body": ("gunship_body.png", 1.3, 0.67),
        "gunship_barrel": ("gunship_barrel.png", 1.3, 0.5)}},
    "colossus": {"colors": 40, "items": {
        "colossus_body": ("colossus_body.png", 1.9, 0.59),
        "colossus_barrel": ("colossus_barrel.png", 1.3, 0.6)}},
    # bunker sources are 440px on disk (the import caps them to 128), so the
    # bake reads the full-resolution master: sharper than the old path.
    "bunker": {"colors": 36, "items": {
        "bunker": ("cast2/bunker.png", 0.78, 0.58, 128),
        "bunker2": ("p2/bunker2.png", 0.78, 0.58, 128)}},
    "crate": {"colors": 28, "items": {
        "crate_ammo": ("crate_ammo.png", 0.55, 0.86),
        "crate_grenade": ("crate_grenade.png", 0.55, 0.86),
        "crate_airstrike": ("crate_airstrike.png", 0.55, 0.86)}},
    "cover": {"colors": 36, "items": {
        "sandbag_beige": ("sandbag.png", 0.484, 0.83),
        "barrel": ("decor/barrel.png", 1.4, 0.11),
        "tank_trap": ("decor/tank_trap.png", 0.9, 0.14),
        "wreck": ("decor/wreck.png", 1.0, 0.17)}},
    "rock": {"colors": 20, "items": {
        "rock1": ("decor/rock1.png", 1.3, 0.13),
        "rock2": ("decor/rock2.png", 1.05, 0.14)}},
}


def bake_prop_family(name, fam):
    shrunk = {}
    for key, spec in fam["items"].items():
        rel, call, old = spec[:3]
        src = Image.open(os.path.join(ART, rel)).convert("RGBA")
        # 4th field: the import size_limit the old path drew through (bunker 128)
        eff = min(max(src.size), spec[3]) if len(spec) > 3 else max(src.size)
        t = call * old * eff / max(src.size)
        w, h = _even(src.size[0] * t), _even(src.size[1] * t)
        shrunk[key] = src.resize((w, h), Image.BOX)
    pal = shared_palette(list(shrunk.values()), fam["colors"])
    d = os.path.join(OUT, name)
    os.makedirs(d, exist_ok=True)
    for key, im in shrunk.items():
        finish(im, pal).save(os.path.join(d, f"{key}.png"), optimize=True)
    return {k: im.size for k, im in shrunk.items()}


def main():
    only = os.environ.get("BAKE_ONLY")
    for name, fam in PROP_FAMILIES.items():
        if only and only != name:
            continue
        sizes = bake_prop_family(name, fam)
        print(f"{name:10s} -> " + ", ".join(f"{k}={w}x{h}" for k, (w, h) in sizes.items()))
    if only:
        return 0
    # Props, vehicles and bosses are still BAKED here from their masters. The infantry is
    # not: those sprites are designed at native size by tools/gen_infantry.py, and baking
    # the old shrunk masters over them would silently undo that. Asking for it by name is
    # the only way to get the old behaviour.
    if "--legacy-masters" not in sys.argv:
        print("infantry sets skipped: they are designed sprites (tools/gen_infantry.py). "
              "Pass --legacy-masters to overwrite them with the old shrunk masters on purpose.")
        return 0
    for s in sets():
        sizes = bake_set(s)
        print(f"{s['name']:18s} t={s['t']:.4f} xs={s['xs']:.2f} -> "
              + ", ".join(f"{p}={w}x{h}" for p, (w, h) in list(sizes.items())[:3]) + " ...")


if __name__ == "__main__":
    sys.exit(main())
