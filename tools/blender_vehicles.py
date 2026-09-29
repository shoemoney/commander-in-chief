#!/usr/bin/env python3
"""Blender 5.x procedural vehicle + boss sprite pipeline (Blender-runnable).

Replaces six generative-AI bakes that had NO recorded pipeline with geometry
that is 100% authored here: every vertex is computed in this file, there is no
image input, no HDRI, no downloaded model, and nothing under assets/ is read
except the six files being replaced (for the before/after table only).

    blender -b --factory-startup --python tools/blender_vehicles.py
    blender -b --factory-startup --python tools/blender_vehicles.py -- --only tank_body
    blender -b --factory-startup --python tools/blender_vehicles.py -- --outdir /tmp/v --samples 48

WHY BLENDER AT ALL -- the sprites this replaces were measured flat
    colossus_body  143x143px drawn, 4 significant value steps, luma stddev 22.8
    gunship_body    98px drawn, 21.7% top-1 quantised colour
and read as bakes of a bake. This script models real volumes and LIGHTS them,
so the value structure is a consequence of form (a bevelled north-west edge
catches the key; a south-east bevel falls into fill) rather than paint.

CANVAS CONTRACT -- never changes. Art.SCALE (src/view/art.gd) and the
VEHICLE_CONTACT call_scale (src/main.gd) multiply these canvases, so a new
canvas size silently re-scales the thing on screen:
    tank_body      104 x 104   0.72 x 0.62 ->  46.4px drawn
    tank_barrel     72 x  72   0.69 x 0.62 ->  30.8px drawn
    gunship_body   112 x 112   0.67 x 1.30 ->  97.6px drawn
    gunship_barrel  48 x  48   0.50 x 1.30 ->  31.2px drawn
    colossus_body  128 x 128   0.59 x 1.90 -> 143.5px drawn  (drawn BIGGER than
                                 the canvas -- the finale boss is upscaled)
    colossus_barrel 72 x  72   0.60 x 1.30 ->  56.2px drawn
Every quality gate below is measured at the DRAWN size, because a 104px
canvas drawn at 46px and a 128px canvas drawn at 143px are two different
pictures and only one of them is what the player sees.

ORIENTATION -- muzzle NORTH (+Y world = up in the PNG). main.gd rotates these
with `PI` (bosses, so their guns point down-screen at the players) and
`barrel_angle + PI/2` (tank turret), which is the same +PI/2 that
Art.facing_rotation applies to troops whose art is authored muzzle-up.
DRAWN-WITH-PI MEANS THE AUTHORED ART MUST FACE +Y, not -Y: a 180-degree error
here is invisible in isolation and drives every vehicle backwards in play.

ALPHA -- straight (unpremultiplied), RGBA8, film_transparent. The box
downsample runs in premultiplied space and un-premultiplies afterwards, which
is the only order that does not bleed the transparent-black background into
every edge pixel.

NO PIL / NO NUMPY-FREE ASSUMPTIONS: this runs inside Blender's Python, which
has numpy but no Pillow, so PNG encode and decode are both local.
"""
from __future__ import annotations

import argparse
import math
import struct
import sys
import zlib
from pathlib import Path

import numpy as np

import bmesh
import bpy
from mathutils import Vector

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUTDIR = PROJECT_ROOT / "assets/art/vehicles"
BEFORE_DIR = PROJECT_ROOT / "assets/art"

# --- canvas contract ---------------------------------------------------------
CANVAS = {
    "tank_body": (104, 104),
    "tank_barrel": (72, 72),
    "gunship_body": (112, 112),
    "gunship_barrel": (48, 48),
    "colossus_body": (128, 128),
    "colossus_barrel": (72, 72),
}
# Art.SCALE (src/view/art.gd) x VEHICLE_CONTACT[...].call_scale (src/main.gd).
DRAW = {
    "tank_body": 0.72 * 0.62,
    "tank_barrel": 0.69 * 0.62,
    "gunship_body": 0.67 * 1.30,
    "gunship_barrel": 0.50 * 1.30,
    "colossus_body": 0.59 * 1.90,
    "colossus_barrel": 0.60 * 1.30,
}
BODIES = ("tank_body", "gunship_body", "colossus_body")

# --- quality gates (measured at DRAWN size) ----------------------------------
MIN_VALUE_STEPS = 5      # luma buckets holding >=2% of the opaque area
MAX_TOP1 = 0.25          # largest share of any 8x8x8 RGB quantised bin
MIN_STDDEV = 30.0        # luma standard deviation over the opaque area
MIN_COVER = 0.06         # a sprite that is basically nothing
MAX_COVER = 0.90
MIN_EDGE_MARGIN = 2      # px of clear canvas on EVERY side (muzzle side included)
MIN_INK_SOUTH = 0.49     # ink centroid, as a fraction of bbox height from NORTH
IOU_BAR = 0.75           # pairwise alpha IoU between the three bodies

# --- lighting (see docs/blender-pipeline.md for the reasoning) ---------------
# Key travels toward +X, -Y, -Z: it therefore COMES FROM the north-west and
# above. A 45-degree north-west bevel (normal 0,0.71,0.71) then reads 0.96
# where a flat top face reads 0.85 and a south-east bevel reads ~0.0 -- so the
# bright edge lands on the north-west of every raised element for free, which
# is the _bag() "RAISED crown lit to the NORTH" convention in tools/
# gen_entities.py, produced by lighting instead of by hand-painting three
# stacked polygons.
KEY_DIR = Vector((0.38, -0.60, -1.0)).normalized()
KEY_ENERGY = 8.5
KEY_ANGLE = 0.030        # radians of sun softness -- crisp contact shadows
# Cool bounce from the south-east, low and wide: keeps shadow sides readable
# and tinted rather than black, which is what stops a 46px tank from turning
# into a silhouette. Direction is where the light TRAVELS, so it comes FROM
# (-X, +Y) = south-east.
FILL_DIR = Vector((-0.52, 0.70, -0.55)).normalized()
FILL_ENERGY = 7.0
WORLD_COLOUR = (0.02, 0.02, 0.0250)
RENDER_SEED = 20260929


# ===========================================================================
# PNG encode / decode (no Pillow inside Blender)
# ===========================================================================
def _srgb_to_linear(c: float) -> float:
    """`c` is a 0..255 sRGB component; Blender's Base Color wants linear 0..1."""
    c /= 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _linear_to_srgb(c: float) -> float:
    c = max(0.0, min(1.0, c))
    return c * 12.92 if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055


def _png_write(path: Path, rgba: np.ndarray) -> None:
    """Write straight-alpha RGBA8. rgba is (h, w, 4) uint8 with row 0 = TOP."""
    h, w, _ = rgba.shape
    raw = bytearray()
    flat = rgba.reshape(h, w * 4)
    for y in range(h):
        raw.append(0)
        raw += flat[y].tobytes()

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    body = (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
            + chunk(b"IEND", b""))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(body)


def _png_decode(data: bytes) -> np.ndarray:
    """Decode 8-bit RGB/RGBA (non-interlaced) to (h, w, 4) uint8, row 0 = TOP."""
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    pos, idat = 8, bytearray()
    w = h = ct = None
    while pos + 8 <= len(data):
        (ln,) = struct.unpack(">I", data[pos:pos + 4])
        tag = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + ln]
        pos += 12 + ln
        if tag == b"IHDR":
            w, h, bd, ct, _c, _f, il = struct.unpack(">IIBBBBB", body)
            if bd != 8 or ct not in (2, 6) or il != 0:
                raise ValueError(f"unsupported PNG: depth {bd} colour {ct} interlace {il}")
        elif tag == b"IDAT":
            idat += body
        elif tag == b"IEND":
            break
    nch = 3 if ct == 2 else 4
    stride = w * nch
    raw = zlib.decompress(bytes(idat))
    out = np.zeros((h, stride), dtype=np.uint8)
    prev = np.zeros(stride, dtype=np.int32)
    p = 0
    for y in range(h):
        f = raw[p]
        p += 1
        line = np.frombuffer(raw, dtype=np.uint8, count=stride, offset=p).astype(np.int32)
        p += stride
        if f == 0:
            cur = line
        elif f == 1:
            cur = line.copy()
            for i in range(nch, stride):
                cur[i] = (cur[i] + cur[i - nch]) & 255
        elif f == 2:
            cur = (line + prev) & 255
        elif f == 3:
            cur = line.copy()
            for i in range(stride):
                a = cur[i - nch] if i >= nch else 0
                cur[i] = (cur[i] + ((a + prev[i]) >> 1)) & 255
        else:
            cur = line.copy()
            for i in range(stride):
                a = cur[i - nch] if i >= nch else 0
                b = prev[i]
                c = prev[i - nch] if i >= nch else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                cur[i] = (cur[i] + pr) & 255
        out[y] = cur.astype(np.uint8)
        prev = cur
    img = out.reshape(h, w, nch)
    if nch == 3:
        img = np.dstack([img, np.full((h, w, 1), 255, np.uint8)])
    return img


def _read_png(path: Path) -> np.ndarray:
    return _png_decode(Path(path).read_bytes())


def _resize_lanczos(arr: np.ndarray, w: int, h: int) -> np.ndarray:
    """Small, dependency-free area-average resample. Only ever used on ALREADY
    downsampled sprites (128px -> 143px is the worst case) so the mild kernel
    softness is invisible next to the Lanczos noise it would import."""
    src = arr.astype(np.float32)
    sh, sw, _ = src.shape
    ys = (np.arange(h) + 0.5) * sh / h - 0.5
    xs = (np.arange(w) + 0.5) * sw / w - 0.5
    y0 = np.floor(ys).astype(int)
    x0 = np.floor(xs).astype(int)
    wy = ys - y0
    wx = xs - x0
    acc = np.zeros((h, w, 4), np.float32)
    for dy in (0, 1):
        for dx in (0, 1):
            yy = np.clip(y0 + dy, 0, sh - 1)
            xx = np.clip(x0 + dx, 0, sw - 1)
            wgt = ((1 - wy) if dy == 0 else wy)[:, None] * ((1 - wx) if dx == 0 else wx)[None, :]
            acc += src[np.ix_(yy, xx)] * wgt[:, :, None]
    return np.clip(acc + 0.5, 0, 255).astype(np.uint8)


# ===========================================================================
# measurement -- the same code grades the before and the after
# ===========================================================================
def _alpha_mask(arr: np.ndarray) -> np.ndarray:
    return arr[..., 3] > 38


def _draw_size(arr: np.ndarray, drawn_scale: float) -> np.ndarray:
    h, w, _ = arr.shape
    dw = max(1, int(round(w * drawn_scale)))
    dh = max(1, int(round(h * drawn_scale)))
    return _resize_lanczos(arr, dw, dh) if (dw, dh) != (w, h) else arr


def measure(arr: np.ndarray, drawn_scale: float) -> dict:
    a = _draw_size(arr, drawn_scale)
    mask = _alpha_mask(a)
    n = int(mask.sum())
    if n == 0:
        return dict(size=(a.shape[1], a.shape[0]), cover=0.0, steps=0, top1=1.0,
                    std=0.0, bins=0, margin=(0, 0, 0, 0), opaque=0, ink=0.5)
    px = a[mask][:, :3].astype(np.float64)
    luma = 0.2126 * px[:, 0] + 0.7152 * px[:, 1] + 0.0722 * px[:, 2]
    q = np.clip(np.round(luma / 255.0 * 8).astype(int), 0, 7)
    hist = np.bincount(q, minlength=8) / n
    steps = int((hist >= 0.02).sum())
    key = (px[:, 0].astype(int) // 32) * 64 + (px[:, 1].astype(int) // 32) * 8 \
        + (px[:, 2].astype(int) // 32)
    uk, cnt = np.unique(key, return_counts=True)
    top1 = float(cnt.max() / n)
    ys, xs = np.nonzero(mask)
    h, w = mask.shape
    margin = (int(xs.min()), int(w - xs.max() - 1), int(ys.min()), int(h - ys.max() - 1))
    span = max(1, int(ys.max() - ys.min()))
    # Ink centroid as a fraction of the alpha bbox height, measured from the
    # NORTH edge. A muzzle-north vehicle is all mass BEHIND its muzzle, so this
    # must be >= 0.5; flip the geometry 180 degrees and it inverts. This is the
    # one gate that catches the failure mode with no visible symptom until play:
    # every vehicle drives backwards and nothing else in the file complains.
    ink = float((ys.mean() - ys.min()) / span)
    return dict(size=(w, h), cover=float(mask.mean()), steps=steps, top1=top1,
                std=float(luma.std()), bins=int(uk.size), margin=margin, opaque=n,
                ink=ink)


def _iou(a: np.ndarray, b: np.ndarray) -> float:
    """Alpha IoU at drawn size, on a common grid -- the two bodies are different
    sizes (46px tank vs 143px colossus), so both are centred into the larger
    frame exactly the way main.gd centres a sprite on its position."""
    w = max(a.shape[1], b.shape[1])
    h = max(a.shape[0], b.shape[0])
    out = []
    for arr in (a, b):
        m = np.zeros((h, w), bool)
        y0 = (h - arr.shape[0]) // 2
        x0 = (w - arr.shape[1]) // 2
        m[y0:y0 + arr.shape[0], x0:x0 + arr.shape[1]] = _alpha_mask(arr)
        out.append(m)
    union = int((out[0] | out[1]).sum())
    return float((out[0] & out[1]).sum()) / union if union else 1.0


# ===========================================================================
# scene construction helpers
# ===========================================================================
_COLL = None


def _reset_scene() -> None:
    global _COLL
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.name = "vehicles"
    _COLL = bpy.data.collections.new("vehicles")
    scene.collection.children.link(_COLL)
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (*WORLD_COLOUR, 1.0)
    bg.inputs[1].default_value = 1.0
    scene.world = world


def _mat(name: str, srgb: tuple, rough: float, metal: float = 0.0,
         emit: tuple | None = None, emit_strength: float = 0.0) -> bpy.types.Material:
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*[_srgb_to_linear(c) for c in srgb], 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    b.inputs["Specular IOR Level"].default_value = 0.35
    if emit is not None:
        b.inputs["Emission Color"].default_value = (*[_srgb_to_linear(c) for c in emit], 1.0)
        b.inputs["Emission Strength"].default_value = emit_strength
    return m


def _mesh(name: str, verts: list, faces: list, mat, bevel: float = 0.0,
          segments: int = 2) -> bpy.types.Object:
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    if bevel > 0.0:
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        thick = min(
            max(v[0] for v in verts) - min(v[0] for v in verts),
            max(v[1] for v in verts) - min(v[1] for v in verts),
            max(v[2] for v in verts) - min(v[2] for v in verts),
        )
        off = min(bevel, thick * 0.28)
        if off > 1e-4:
            bmesh.ops.bevel(bm, geom=list(bm.edges), offset=off, offset_type="OFFSET",
                            segments=segments, affect="EDGES", profile=0.5,
                            clamp_overlap=True, material=-1)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me)
        bm.free()
    me.update()
    ob = bpy.data.objects.new(name, me)
    ob.data.materials.append(mat)
    _COLL.objects.link(ob)
    return ob


def _prism(name: str, poly: list, z0: float, z1: float, mat, bevel: float = 0.0,
           segments: int = 2) -> bpy.types.Object:
    n = len(poly)
    verts = [(x, y, z0) for x, y in poly] + [(x, y, z1) for x, y in poly]
    faces = [list(range(n - 1, -1, -1)), list(range(n, 2 * n))]
    faces += [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    return _mesh(name, verts, faces, mat, bevel, segments)


def _rect(cx, cy, hw, hh) -> list:
    return [(cx - hw, cy - hh), (cx + hw, cy - hh), (cx + hw, cy + hh), (cx - hw, cy + hh)]


def _rrect(cx, cy, hw, hh, r, n=4) -> list:
    """Rounded rectangle as a polygon -- the track-run silhouette."""
    r = min(r, hw * 0.98, hh * 0.98)
    pts = []
    corners = ((cx + hw - r, cy + hh - r, 0.0), (cx - hw + r, cy + hh - r, math.pi / 2),
               (cx - hw + r, cy - hh + r, math.pi), (cx + hw - r, cy - hh + r, 3 * math.pi / 2))
    for px, py, a0 in corners:
        for i in range(n + 1):
            a = a0 + (math.pi / 2) * i / n
            pts.append((px + r * math.cos(a), py + r * math.sin(a)))
    return pts


def _ngon(cx, cy, r, n, phase=0.0) -> list:
    return [(cx + r * math.cos(phase + 2 * math.pi * i / n),
             cy + r * math.sin(phase + 2 * math.pi * i / n)) for i in range(n)]


def _taper(y0, y1, w0, w1, x=0.0) -> list:
    """CCW quad with a different width at each end -- barrels and strakes."""
    return [(x - w0, y0), (x + w0, y0), (x + w1, y1), (x - w1, y1)]


def _j(seed: int, i: int, k: int) -> float:
    """Deterministic 0..1 jitter (Art.cell_hash's mixer). No `random` -- a re-run
    must reproduce the committed PNG byte for byte."""
    h = (seed * 374761393 + i * 668265263 + k * 2654435761) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0


# --- shared materials --------------------------------------------------------
def build_tank_mats() -> dict:
    return {
        "hull": _mat("tank_hull", (108, 116, 78), 0.72, 0.05),
        "hull_lit": _mat("tank_hull_lit", (146, 152, 112), 0.66, 0.05),
        "deck": _mat("tank_deck", (88, 96, 64), 0.78, 0.05),
        "turret": _mat("tank_turret", (126, 134, 96), 0.68, 0.08),
        "track": _mat("tank_track", (54, 58, 50), 0.92, 0.0),
        "link": _mat("tank_link", (82, 88, 76), 0.86, 0.0),
        "dark": _mat("tank_dark", (36, 40, 34), 0.80, 0.10),
        "steel": _mat("tank_steel", (150, 156, 148), 0.44, 0.30),
        "gun": _mat("tank_gun", (96, 104, 96), 0.44, 0.28),
    }


def build_gunship_mats() -> dict:
    return {
        "hull": _mat("gs_hull", (116, 122, 128), 0.64, 0.10),
        "hull_lit": _mat("gs_hull_lit", (150, 156, 164), 0.56, 0.12),
        "panel": _mat("gs_panel", (76, 82, 90), 0.70, 0.10),
        "dark": _mat("gs_dark", (44, 48, 56), 0.68, 0.12),
        "trim": _mat("gs_trim", (168, 62, 48), 0.60, 0.10),
        "glass": _mat("gs_glass", (58, 88, 108), 0.30, 0.25),
        "rotor": _mat("gs_rotor", (112, 120, 132), 0.46, 0.12),
        # Dedicated wing tones. The wings originally shared the fuselage base
        # colour, so fuselage + wing tops landed in ONE quantised bin and the
        # whole sprite measured 35.3% top-1 -- a value step the geometry was
        # never going to produce, because there was no step in it.
        "wing": _mat("gs_wing", (46, 52, 60), 0.68, 0.10),
        "wing_mid": _mat("gs_wing_mid", (92, 98, 106), 0.64, 0.10),
        "wing_lit": _mat("gs_wing_lit", (156, 162, 170), 0.60, 0.12),
        "steel": _mat("gs_steel", (158, 164, 172), 0.40, 0.30),
        "gun": _mat("gs_gun", (86, 90, 98), 0.46, 0.22),
    }


def build_colossus_mats() -> dict:
    return {
        "skirt": _mat("col_skirt", (58, 64, 74), 0.78, 0.20),
        "deck": _mat("col_deck", (98, 106, 118), 0.70, 0.10),
        "deck_lit": _mat("col_deck_lit", (138, 146, 158), 0.64, 0.12),
        "steel": _mat("col_steel", (172, 178, 186), 0.40, 0.30),
        "dark": _mat("col_dark", (40, 44, 52), 0.70, 0.14),
        "track": _mat("col_track", (48, 52, 58), 0.92, 0.0),
        "link": _mat("col_link", (76, 82, 90), 0.84, 0.10),
        "trim": _mat("col_trim", (176, 96, 44), 0.58, 0.15),
        # Emission tuned so the core is an ORANGE with a hot centre rather than a
        # clipped pale-yellow disc: at 2.6 every core pixel saturated to
        # (255,255,190) and the focal point became a flat sticker.
        "core": _mat("col_core", (255, 150, 64), 0.50, 0.0,
                     emit=(255, 96, 24), emit_strength=0.70),
        "gun": _mat("col_gun", (98, 104, 112), 0.46, 0.22),
    }


# ===========================================================================
# TANK -- 104px canvas, 46px drawn. Tracked hull, faceted turret.
#
# The value ladder is deliberate and is the same on all three vehicles:
#   tier 5  bright top faces (glacis, turret roof, track-link crowns)
#   tier 4  lit upper hull
#   tier 3  mid hull / side walls
#   tier 2  dark recess (turret ring gap, panel grooves, louvre slots)
#   tier 1  near-black skirt + track rubber
# so the sprite holds five steps even after the 0.44 downscale to 46px.
# ===========================================================================
def build_tank() -> None:
    m = build_tank_mats()
    # --- track runs (the tracked-vehicle tell) ---
    for sx in (-1, 1):
        cx = sx * 0.272
        _prism("track", _rrect(cx, 0.0, 0.074, 0.302, 0.064), 0.004, 0.050,
               m["track"], 0.010)
        for i in range(8):
            y = -0.302 + (i + 0.5) * (0.604 / 8)
            _prism("link", _rect(cx, y, 0.062, 0.020), 0.048, 0.062, m["link"], 0.005, 1)
        for sy in (-1, 1):
            _prism("roller", _ngon(cx, sy * 0.258, 0.046, 10), 0.050, 0.070,
                   m["deck"], 0.006, 1)

    # --- hull: tapered, pointed glacis to the north ---
    hull = [(-0.198, -0.270), (0.198, -0.270), (0.198, -0.214), (0.212, -0.180),
            (0.212, 0.092), (0.170, 0.196), (0.092, 0.300), (-0.092, 0.300),
            (-0.170, 0.196), (-0.212, 0.092), (-0.212, -0.180), (-0.198, -0.214)]
    _prism("hull", hull, 0.026, 0.104, m["hull"], 0.016)
    # glacis: a raised wedge plate -- the brightest big block, and the thing
    # that says "this vehicle points north" once the turret is smaller.
    _prism("glacis", [(-0.086, 0.292), (0.086, 0.292), (0.168, 0.196),
                      (0.206, 0.092), (0.206, 0.048), (0.130, 0.150),
                      (-0.130, 0.150), (-0.206, 0.048), (-0.206, 0.092),
                      (-0.168, 0.196)], 0.102, 0.128, m["hull_lit"], 0.010)
    _prism("spare_track", _rect(0.0, 0.208, 0.116, 0.016), 0.126, 0.138,
           m["track"], 0.005, 1)
    # engine deck to the south with louvre slats sunk into a dark recess
    _prism("engine", _rect(0.0, -0.168, 0.180, 0.088), 0.102, 0.118, m["dark"], 0.007)
    for i in range(5):
        y = -0.228 + i * 0.030
        _prism("louvre", _rect(0.0, y, 0.152, 0.007), 0.116, 0.126, m["deck"], 0.003, 1)
    # stowage bins down both flanks
    for sx in (-1, 1):
        _prism("stow", _rrect(sx * 0.164, -0.020, 0.038, 0.086, 0.020), 0.102, 0.140,
               m["deck"], 0.008)
        _prism("stow_band", _rect(sx * 0.164, -0.020, 0.030, 0.006), 0.138, 0.144,
               m["hull_lit"], 0.002, 1)
    # driver's hatch + commander's cupola ahead of the turret
    _prism("hatch", _rect(0.056, 0.128, 0.036, 0.040), 0.102, 0.126, m["deck"], 0.008)
    _prism("cupola", _ngon(-0.062, 0.118, 0.038, 8), 0.102, 0.142, m["turret"], 0.008)

    # --- turret: small and faceted, so the glacis still reads at 46px ---
    _prism("ring", _ngon(0.0, 0.010, 0.128, 16), 0.102, 0.118, m["dark"], 0.006, 1)
    _prism("turret", _ngon(0.0, 0.010, 0.112, 8, math.pi / 8), 0.116, 0.176,
           m["turret"], 0.014)
    # roof plate only on the rear half: a smaller bright face keeps the value
    # ladder from collapsing into one pale disc
    _prism("turret_roof", _ngon(0.0, -0.030, 0.072, 8, math.pi / 8), 0.174, 0.184,
           m["hull_lit"], 0.006, 1)
    # mantlet + barrel stub: the turret points NORTH
    _prism("mantlet", _rect(0.0, 0.130, 0.044, 0.028), 0.128, 0.168, m["hull"], 0.009)
    _prism("stub", _taper(0.142, 0.248, 0.023, 0.018), 0.146, 0.168, m["gun"], 0.005)
    _prism("stub_lit", _rect(0.0, 0.196, 0.010, 0.044), 0.166, 0.172,
           m["hull_lit"], 0.002, 1)
    # commander's hatch + whip antenna on the turret roof
    _prism("cmd", _ngon(-0.044, -0.052, 0.030, 8), 0.182, 0.196, m["deck"], 0.006, 1)
    _prism("cmd_visor", _rect(-0.044, -0.032, 0.022, 0.006), 0.194, 0.200,
           m["steel"], 0.002, 1)
    _prism("antenna", _rect(-0.024, -0.150, 0.006, 0.060), 0.182, 0.188, m["steel"], 0.002, 1)


def build_tank_barrel() -> None:
    m = build_tank_mats()
    # A gun this sprite has to carry the whole tank: at 31px drawn it is four
    # or five pixels wide, so the silhouette does all the work and the value
    # ladder (black breech -> lit collar -> mid tube -> bright brake) is what
    # keeps it from reading as one grey stick.
    _prism("breech", _rrect(0.0, -0.300, 0.120, 0.062, 0.032), -0.030, 0.070,
           m["deck"], 0.014)
    _prism("breech_dark", _rect(0.0, -0.330, 0.104, 0.020), 0.066, 0.080,
           m["dark"], 0.004, 1)
    _prism("collar", _rect(0.0, -0.222, 0.082, 0.020), 0.062, 0.090, m["steel"], 0.006, 1)
    _prism("tube", _taper(-0.226, 0.244, 0.062, 0.046), 0.016, 0.066, m["gun"], 0.010)
    _prism("tube_lit", _taper(-0.190, 0.230, 0.026, 0.018), 0.062, 0.070,
           m["hull_lit"], 0.004, 1)
    _prism("fume", _rect(0.0, 0.010, 0.066, 0.046), 0.010, 0.072, m["gun"], 0.012)
    _prism("fume_dark", _rect(0.0, -0.038, 0.056, 0.008), 0.068, 0.076,
           m["dark"], 0.003, 1)
    _prism("brake", _taper(0.238, 0.336, 0.062, 0.058), 0.012, 0.074, m["steel"], 0.010)
    for y in (0.262, 0.306):
        _prism("brake_slot", _rect(0.0, y, 0.064, 0.010), 0.070, 0.078,
               m["dark"], 0.002, 1)
    _prism("muzzle", _rect(0.0, 0.332, 0.038, 0.007), -0.008, 0.040, m["dark"], 0.002, 1)


# ===========================================================================
# GUNSHIP -- 112px canvas, 98px drawn. Tilt-rotor gunship.
#
# Distinctness is the whole job here: the tank is a rectangle-plus-circle and
# the colossus is a wide square, so the gunship has to be the only one of the
# three whose silhouette is a CROSS -- long thin north-south fuselage, wide
# east-west wings, two rotor discs. The alpha IoU gate enforces it.
# ===========================================================================
def build_gunship() -> None:
    m = build_gunship_mats()
    # --- wings first, so the nacelles read as sitting ON them ---
    for sx in (-1, 1):
        wing = [(sx * 0.062, 0.126), (sx * 0.220, 0.014), (sx * 0.418, -0.112),
                (sx * 0.442, -0.176), (sx * 0.434, -0.220), (sx * 0.290, -0.220),
                (sx * 0.150, -0.142), (sx * 0.062, -0.118)]
        _prism("wing", wing if sx > 0 else wing[::-1], 0.058, 0.098, m["wing"], 0.012)
        # Wing panels. An undissected wing slab measured 26.9-35.3% of the sprite
        # in one quantised colour: three separated tones (mid inboard, dark
        # spar bay, bright outboard) is what actually splits that bin.
        _prism("wing_inner", [(sx * 0.066, 0.120), (sx * 0.184, 0.036),
                              (sx * 0.190, -0.156), (sx * 0.066, -0.120)],
               0.096, 0.106, m["wing_mid"], 0.004, 1)
        _prism("wing_outer", [(sx * 0.252, -0.020), (sx * 0.424, -0.128),
                              (sx * 0.426, -0.206), (sx * 0.256, -0.206)],
               0.096, 0.104, m["wing_lit"], 0.004, 1)
        # three chordwise ribs: the detail that survives the 0.87 downscale
        for fx, fy in ((0.196, 0.010), (0.252, -0.028), (0.336, -0.104)):
            _prism("rib", _rect(sx * fx, fy, 0.006, 0.070), 0.098, 0.110,
                   m["dark"], 0.002, 1)
        # red leading-edge trim: the gunship's colour identity vs the olive tank
        _prism("trim", [(sx * 0.072, 0.124), (sx * 0.220, 0.012), (sx * 0.416, -0.116),
                        (sx * 0.418, -0.140), (sx * 0.222, 0.034), (sx * 0.072, 0.146)],
               0.094, 0.108, m["trim"], 0.005, 1)
        # wingtip rocket pod
        _prism("tip_pod", _rrect(sx * 0.372, -0.030, 0.038, 0.090, 0.028), 0.018, 0.060,
               m["panel"], 0.008)
        _prism("tip_tip", _ngon(sx * 0.372, -0.118, 0.034, 8), 0.022, 0.056,
               m["dark"], 0.006, 1)
        # canted tail fin off the trailing edge
        _prism("fin", [(sx * 0.250 - 0.014, -0.192), (sx * 0.250 + 0.014, -0.192),
                       (sx * 0.250 + 0.046, -0.316), (sx * 0.250 + 0.018, -0.316)],
               0.096, 0.130, m["panel"], 0.005)
        # --- nacelle + rotor disc ---
        _prism("nacelle", _rrect(sx * 0.242, -0.026, 0.056, 0.132, 0.046), 0.082, 0.158,
               m["hull_lit"], 0.014)
        _prism("nac_band", _rect(sx * 0.242, -0.026, 0.050, 0.012), 0.154, 0.164,
               m["panel"], 0.003, 1)
        _prism("intake", _rect(sx * 0.242, 0.062, 0.038, 0.026), 0.154, 0.166,
               m["dark"], 0.005, 1)
        # rotor: a thin disc plus four blades. Small on purpose -- an oversized
        # disc reads as an eye, not as a rotor.
        _prism("rotor", _ngon(sx * 0.242, -0.026, 0.092, 20), 0.156, 0.164,
               m["rotor"], 0.004, 1)
        _prism("hub", _ngon(sx * 0.242, -0.026, 0.024, 10), 0.162, 0.174, m["dark"], 0.005, 1)
        for k in range(4):
            a = math.pi / 4 + k * math.pi / 2
            dx, dy = 0.086 * math.cos(a), 0.086 * math.sin(a)
            _prism("blade", [(sx * 0.242 - dy * 0.12, -0.026 + dx * 0.12),
                             (sx * 0.242 + dy * 0.12, -0.026 - dx * 0.12),
                             (sx * 0.242 + dy * 0.12 + dx, -0.026 - dx + dy),
                             (sx * 0.242 - dy * 0.12 + dx, -0.026 + dx + dy)],
                   0.164, 0.170, m["panel"], 0.002, 1)

    # --- fuselage: hexagonal section, nose north ---
    fuse = [(0.0, 0.380), (0.044, 0.344), (0.076, 0.244), (0.086, 0.070),
            (0.076, -0.120), (0.046, -0.244), (0.0, -0.276),
            (-0.046, -0.244), (-0.076, -0.120), (-0.086, 0.070),
            (-0.076, 0.244), (-0.044, 0.344)]
    _prism("fuse", fuse, 0.050, 0.146, m["hull"], 0.014)
    # spine deck: mid value, with a narrower bright cap so the biggest single
    # face on the sprite is not one flat tone
    _prism("spine", [(-0.052, 0.216), (0.052, 0.216), (0.058, -0.150),
                     (0.0, -0.198), (-0.058, -0.150)], 0.144, 0.156, m["panel"], 0.008)
    _prism("spine_cap", [(-0.030, 0.180), (0.030, 0.180), (0.034, -0.120),
                         (0.0, -0.162), (-0.034, -0.120)], 0.154, 0.164,
           m["hull"], 0.006, 1)
    for sx in (-1, 1):
        _prism("spine_seam", _rect(sx * 0.042, -0.010, 0.005, 0.118), 0.154, 0.160,
               m["dark"], 0.002, 1)
    # canopy: the one dark-glass shape, immediately says "aircraft"
    _prism("canopy", [(0.0, 0.336), (0.038, 0.300), (0.050, 0.222),
                      (0.0, 0.194), (-0.050, 0.222), (-0.038, 0.300)],
           0.146, 0.164, m["glass"], 0.007)
    # tailplane across the back
    _prism("tail", [(0.0, -0.196), (0.148, -0.238), (0.162, -0.282),
                    (0.0, -0.300), (-0.162, -0.282), (-0.148, -0.238),
                    (0.0, -0.196)], 0.082, 0.100, m["panel"], 0.006)
    # chin turret -- the separate gunship_barrel sprite lands here
    _prism("chin", _rect(0.0, 0.192, 0.058, 0.046), 0.028, 0.084, m["dark"], 0.010)


def build_gunship_barrel() -> None:
    m = build_gunship_mats()
    # Compact chin cannon at 31px drawn. The mount is deliberately SMALL: an
    # earlier pass gave it the whole lower half in one flat tone and that single
    # face measured 44.6% of the sprite -- the value budget has to live in the
    # tube and the brake, not in the base.
    _prism("mount", _rrect(0.0, -0.320, 0.116, 0.082, 0.042), -0.030, 0.050,
           m["panel"], 0.014)
    _prism("mount_dark", _rect(0.0, -0.356, 0.086, 0.030), 0.046, 0.058,
           m["dark"], 0.005, 1)
    _prism("mantlet", _rect(0.0, -0.198, 0.116, 0.058), 0.044, 0.116, m["hull"], 0.016)
    _prism("mantlet_band", _rect(0.0, -0.216, 0.120, 0.012), 0.112, 0.122,
           m["panel"], 0.004, 1)
    _prism("shroud", _taper(-0.150, 0.242, 0.100, 0.080), 0.010, 0.104, m["gun"], 0.016)
    _prism("shroud_cap", _taper(-0.120, 0.230, 0.062, 0.048), 0.100, 0.112,
           m["rotor"], 0.005, 1)
    _prism("shroud_band", _rect(0.0, -0.020, 0.092, 0.012), 0.100, 0.112,
           m["dark"], 0.004, 1)
    for sx in (-1, 1):
        _prism("port", _rect(sx * 0.056, 0.070, 0.028, 0.140), 0.014, 0.092,
               m["dark"], 0.008, 1)
    _prism("brake", _rect(0.0, 0.294, 0.108, 0.080), 0.004, 0.116, m["steel"], 0.012)
    for y in (0.252, 0.336):
        _prism("slot", _rect(0.0, y, 0.112, 0.018), 0.112, 0.122, m["dark"], 0.003, 1)
    _prism("muzzle", _rect(0.0, 0.358, 0.066, 0.010), -0.006, 0.048, m["dark"], 0.003, 1)


# ===========================================================================
# COLOSSUS -- 128px canvas, 143px drawn (UPSCALED). Fortress-crawler.
# ===========================================================================
def build_colossus() -> None:
    m = build_colossus_mats()
    # --- four track pods ---
    for sx in (-1, 1):
        for sy in (-1, 1):
            cx, cy = sx * 0.300, sy * 0.250
            _prism("pod", _rrect(cx, cy, 0.086, 0.130, 0.056), 0.004, 0.078,
                   m["track"], 0.014)
            for i in range(5):
                y = cy - 0.130 + (i + 0.5) * (0.260 / 5)
                _prism("pod_link", _rect(cx, y, 0.072, 0.014), 0.076, 0.090,
                       m["link"], 0.004, 1)
            _prism("pod_armour", _rect(cx, cy, 0.058, 0.104), 0.088, 0.104,
                   m["skirt"], 0.007)

    # --- armour skirt: EIGHT separate plates over a dark base ---
    # As one continuous octagonal ring this face rendered at a single flat
    # value and measured 26.7% of the sprite on its own -- the top-1 gate was
    # failing on one polygon. Segmented into plates (with the dark base showing
    # in the gaps) it breaks the bin AND gains the panel-line detail the 143px
    # drawn size can actually carry.
    outer = [(-0.150, -0.360), (0.150, -0.360), (0.268, -0.286), (0.268, 0.244),
             (0.176, 0.352), (0.0, 0.386), (-0.176, 0.352), (-0.268, 0.244),
             (-0.268, -0.286)]
    _prism("skirt_base", outer, 0.018, 0.074, m["dark"], 0.014)
    cx_o = sum(p[0] for p in outer) / len(outer)
    cy_o = sum(p[1] for p in outer) / len(outer)
    for i, (ax, ay) in enumerate(outer):
        bx, by = outer[(i + 1) % len(outer)]

        def _in(pt, f):
            return (pt[0] + (cx_o - pt[0]) * f, pt[1] + (cy_o - pt[1]) * f)
        plate = [_in((ax, ay), 0.09), _in((ax, ay), 0.26),
                 _in((bx, by), 0.26), _in((bx, by), 0.09)]
        _prism("skirt_plate", plate, 0.072, 0.100, m["skirt"], 0.009)
        # a bolt on every second plate: 3px at 143px drawn, and it stops the
        # plates reading as eight identical stamps
        if i % 2 == 0:
            mx = (plate[0][0] + plate[2][0]) * 0.5
            my = (plate[0][1] + plate[2][1]) * 0.5
            _prism("plate_bolt", _ngon(mx, my, 0.013, 6), 0.098, 0.108,
                   m["steel"], 0.003, 1)

    deck = [(-0.118, -0.306), (0.118, -0.306), (0.222, -0.240), (0.222, 0.204),
            (0.140, 0.294), (0.0, 0.324), (-0.140, 0.294), (-0.222, 0.204),
            (-0.222, -0.240)]
    _prism("deck", deck, 0.096, 0.158, m["deck"], 0.018)
    # Side armour panels, stepped a tier above the deck. Without them the whole
    # middle of the sprite is one tone -- an earlier pass measured 26.5% of the
    # colossus in a single quantised colour bin, which is the flatness this
    # pipeline exists to fix.
    for sx in (-1, 1):
        _prism("side_panel", [(sx * 0.098, -0.256), (sx * 0.200, -0.212),
                              (sx * 0.204, 0.176), (sx * 0.128, 0.252),
                              (sx * 0.098, 0.212)],
               0.156, 0.176, m["deck_lit"], 0.010)
        _prism("side_recess", [(sx * 0.112, -0.212), (sx * 0.186, -0.180),
                               (sx * 0.188, 0.144), (sx * 0.130, 0.206),
                               (sx * 0.112, 0.174)],
               0.174, 0.182, m["dark"], 0.005, 1)
        _prism("tracer", _rect(sx * 0.156, -0.020, 0.052, 0.010), 0.174, 0.182,
               m["trim"], 0.003, 1)

    # prow: the heaviest, brightest block, pointing north
    _prism("prow", [(-0.104, 0.230), (0.104, 0.230), (0.132, 0.282), (0.0, 0.318),
                    (-0.132, 0.282)], 0.156, 0.224, m["deck_lit"], 0.016)
    _prism("prow_ramp", [(-0.058, 0.244), (0.058, 0.244), (0.070, 0.284), (-0.070, 0.284)],
           0.222, 0.238, m["steel"], 0.006, 1)
    # bolt heads around the deck rim -- 2-3px at 143px drawn, so they survive
    for i in range(14):
        t = i / 14.0 * math.tau
        bx = 0.196 * math.cos(t)
        by = 0.262 * math.sin(t)
        if by > 0.250:
            bx *= 0.62
            by = 0.250 + (by - 0.250) * 0.55
        _prism("bolt", _ngon(bx, by, 0.014, 6), 0.156, 0.168, m["steel"], 0.003, 1)

    # rear deck: louvre banks + grille ribs
    for sx in (-1, 1):
        for i in range(4):
            y = -0.286 + i * 0.032
            _prism("grille", _rect(sx * 0.082, y, 0.054, 0.009), 0.156, 0.166,
                   m["dark"], 0.003, 1)
    for i in range(3):
        x = -0.056 + i * 0.056
        _prism("rib", _rect(x, -0.086, 0.010, 0.118), 0.156, 0.168, m["deck_lit"], 0.005, 1)

    # core housing: the warm focal point, and the sim's CORE-EXPOSED anchor
    _prism("core_ring", _ngon(0.0, 0.052, 0.104, 12), 0.156, 0.190, m["dark"], 0.010)
    _prism("core_housing", _ngon(0.0, 0.052, 0.080, 8, math.pi / 8), 0.188, 0.232,
           m["deck_lit"], 0.012)
    _prism("core", _ngon(0.0, 0.052, 0.044, 12), 0.228, 0.242, m["core"], 0.006, 1)

    # side sponsons -- the two colossus_barrel sprites mount out here
    for sx in (-1, 1):
        _prism("sponson", _rrect(sx * 0.262, -0.010, 0.052, 0.118, 0.030), 0.086, 0.150,
               m["skirt"], 0.012)
        _prism("sponson_top", _rect(sx * 0.262, -0.010, 0.038, 0.096), 0.148, 0.162,
               m["deck"], 0.008, 1)
        _prism("sponson_seam", _rect(sx * 0.262, 0.040, 0.042, 0.008), 0.160, 0.168,
               m["steel"], 0.003, 1)


def build_colossus_barrel() -> None:
    m = build_colossus_mats()
    # Twin siege tubes: unmistakably NOT the tank's single thin barrel. Two
    # tubes plus a lit cross-brace give four values in a 30x56px footprint,
    # where the previous all-one-tone base measured 29.1% top-1.
    _prism("mount", _rrect(0.0, -0.330, 0.190, 0.070, 0.038), -0.040, 0.062,
           m["skirt"], 0.016)
    _prism("mount_lit", _rect(0.0, -0.296, 0.166, 0.030), 0.058, 0.072,
           m["deck"], 0.005, 1)
    _prism("mantlet", _rect(0.0, -0.226, 0.178, 0.052), 0.056, 0.142, m["deck"], 0.016)
    _prism("mantlet_lit", _rect(0.0, -0.234, 0.150, 0.024), 0.138, 0.152,
           m["deck_lit"], 0.006, 1)
    for sx in (-1, 1):
        _prism("tube", _taper(-0.180, 0.208, 0.058, 0.048, sx * 0.084), 0.026, 0.104,
               m["gun"], 0.012)
        _prism("tube_cap", _taper(-0.140, 0.190, 0.026, 0.020, sx * 0.084), 0.100, 0.112,
               m["steel"], 0.004, 1)
        _prism("sleeve", _rect(sx * 0.084, -0.076, 0.064, 0.048), 0.020, 0.110,
               m["gun"], 0.012)
        _prism("sleeve_band", _rect(sx * 0.084, -0.076, 0.068, 0.008), 0.106, 0.114,
               m["dark"], 0.003, 1)
    _prism("brace", _rect(0.0, -0.020, 0.180, 0.024), 0.096, 0.118, m["dark"], 0.006, 1)
    for sx in (-1, 1):
        _prism("brake", _rect(sx * 0.084, 0.264, 0.074, 0.060), 0.016, 0.114,
               m["steel"], 0.012)
        for y in (0.226, 0.300):
            _prism("slot", _rect(sx * 0.084, y, 0.078, 0.014), 0.110, 0.118,
                   m["dark"], 0.003, 1)


BUILDERS = {
    "tank_body": build_tank,
    "tank_barrel": build_tank_barrel,
    "gunship_body": build_gunship,
    "gunship_barrel": build_gunship_barrel,
    "colossus_body": build_colossus,
    "colossus_barrel": build_colossus_barrel,
}


# ===========================================================================
# camera + lights + render settings
# ===========================================================================
def _aim(obj, direction: Vector) -> None:
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def _setup_scene(canvas: int, ss: int, samples: int) -> bpy.types.Scene:
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"          # GPU kernels differ between machines; CPU keeps
                                     # the byte output reproducible anywhere.
    sc.cycles.samples = samples
    sc.cycles.use_adaptive_sampling = True
    sc.cycles.adaptive_threshold = 0.012
    sc.cycles.use_denoising = True
    sc.cycles.denoiser = "OPENIMAGEDENOISE"
    sc.cycles.seed = RENDER_SEED
    sc.cycles.use_animated_seed = False
    sc.cycles.max_bounces = 4
    sc.cycles.diffuse_bounces = 3
    sc.cycles.glossy_bounces = 2
    sc.cycles.transmission_bounces = 0
    sc.cycles.volume_bounces = 0
    sc.cycles.transparent_max_bounces = 2
    sc.cycles.caustics_reflective = False
    sc.cycles.caustics_refractive = False
    sc.cycles.filter_width = 1.10      # slightly sharpened AA: we downsample 4x after
    sc.cycles.blur_glossy = 1.0
    sc.render.film_transparent = True
    sc.render.use_motion_blur = False
    sc.render.dither_intensity = 0.0  # dithering is a seeded noise source
    sc.render.resolution_x = canvas * ss
    sc.render.resolution_y = canvas * ss
    sc.render.resolution_percentage = 100
    sc.render.pixel_aspect_x = 1.0
    sc.render.pixel_aspect_y = 1.0
    sc.render.filter_size = 1.0
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.image_settings.color_depth = "8"
    sc.render.image_settings.compression = 15
    sc.view_settings.view_transform = "Standard"   # no filmic toe: a value-step
    sc.view_settings.look = "None"                 # budget must survive to the PNG
    sc.view_settings.exposure = 0.0
    sc.view_settings.gamma = 1.0
    sc.view_settings.use_curve_mapping = False

    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 1.0          # the world box is exactly one canvas wide
    cam_data.clip_start = 0.05
    cam_data.clip_end = 20.0
    cam = bpy.data.objects.new("cam", cam_data)
    cam.location = (0.0, 0.0, 8.0)
    # Zero rotation: the camera looks down -Z with local +Y = world +Y, so world
    # +Y lands at the TOP of the PNG. Muzzle north, with no transform fudge.
    cam.rotation_euler = (0.0, 0.0, 0.0)
    _COLL.objects.link(cam)
    sc.camera = cam

    key = bpy.data.lights.new("key", "SUN")
    key.energy = KEY_ENERGY
    key.angle = KEY_ANGLE
    key.color = (1.0, 0.972, 0.930)
    key_obj = bpy.data.objects.new("key", key)
    key_obj.location = (0.0, 0.0, 4.0)
    _aim(key_obj, KEY_DIR)
    _COLL.objects.link(key_obj)

    fill = bpy.data.lights.new("fill", "AREA")
    fill.energy = FILL_ENERGY
    fill.size = 2.4
    fill.shape = "SQUARE"
    fill.color = (0.52, 0.66, 1.0)
    fill_obj = bpy.data.objects.new("fill", fill)
    # Position DERIVED from the direction. A lamp placed by hand and aimed by
    # hand drifts: this fill shipped aimed 130 degrees away from the subject and
    # contributed exactly nothing to any render, which is invisible in the
    # image and only shows up as a shadow side that never lifts.
    fill_obj.location = -FILL_DIR * 2.2
    _aim(fill_obj, FILL_DIR)
    _COLL.objects.link(fill_obj)
    return sc


# ===========================================================================
# render + box downsample
# ===========================================================================
def render_sprite(name: str, outdir: Path, ss: int, samples: int) -> Path:
    canvas = CANVAS[name][0]
    _reset_scene()
    BUILDERS[name]()
    sc = _setup_scene(canvas, ss, samples)
    sc.render.filepath = str(outdir / f".{name}_ss.png")
    bpy.ops.render.render(write_still=True)
    big = _read_png(Path(sc.render.filepath))
    Path(sc.render.filepath).unlink()
    h, w, _ = big.shape
    if (w, h) != (canvas * ss, canvas * ss):
        raise ValueError(f"{name}: rendered {w}x{h}, expected {canvas * ss} square")

    # Premultiply -> average each ss x ss block -> un-premultiply. Averaging in
    # premultiplied space is what keeps the transparent background from smearing
    # black into every edge pixel; doing it the other way round is the classic
    # way a render comes out with a dark 1px outline. The premultiplied buffer
    # holds RGB in 0..255 and alpha in 0..1, so the un-premultiply divides by a
    # unit alpha -- mixing those two scales is a 255x brightness bug that renders
    # a perfectly lit vehicle as solid black.
    src = big.astype(np.float32)
    alpha = src[..., 3:4] / 255.0
    premul = np.concatenate([src[..., :3] * alpha, alpha], axis=2)
    blocks = premul.reshape(canvas, ss, canvas, ss, 4).mean(axis=(1, 3))
    out_a = blocks[..., 3:4]
    rgb = np.where(out_a > 1e-4, blocks[..., :3] / np.maximum(out_a, 1e-4), 0.0)
    out = np.clip(np.floor(np.concatenate([rgb, out_a * 255.0], axis=2) + 0.5),
                  0, 255).astype(np.uint8)
    # NO row flip: the intermediate PNG is decoded back in file order (row 0 =
    # top of the image = world +Y = north), which is already the order we want.
    # Blender's *internal* buffer is bottom-up, but `save_render` un-flips it on
    # the way to disk, so a second flip here turns the vehicle around.

    path = outdir / f"{name}.png"
    _png_write(path, out)
    return path


# ===========================================================================
# verification
# ===========================================================================
def _fail(msgs: list, ok: bool, text: str) -> None:
    if not ok:
        msgs.append(text)


def verify(paths: dict) -> tuple[bool, list, dict]:
    problems: list[str] = []
    after: dict = {}
    for name in sorted(paths):
        arr = _read_png(paths[name])
        m = measure(arr, DRAW[name])
        after[name] = m
        want = CANVAS[name]
        got = (arr.shape[1], arr.shape[0])
        _fail(problems, got == want,
              f"{name}: canvas is {got[0]}x{got[1]}, contract says {want[0]}x{want[1]}")
        _fail(problems, m["opaque"] > 0, f"{name}: fully transparent")
        _fail(problems, MIN_COVER <= m["cover"] <= MAX_COVER,
              f"{name}: opaque coverage {m['cover']:.3f} outside "
              f"[{MIN_COVER}, {MAX_COVER}] — the silhouette is the whole read")
        _fail(problems, m["steps"] >= MIN_VALUE_STEPS,
              f"{name}: only {m['steps']} value step(s) holding >=2% of the area "
              f"(need {MIN_VALUE_STEPS}) — at {DRAW[name] * CANVAS[name][0]:.0f}px drawn "
              f"this reads as one flat sticker")
        _fail(problems, m["top1"] <= MAX_TOP1,
              f"{name}: top-1 quantised colour is {m['top1'] * 100:.1f}% "
              f"(need <= {MAX_TOP1 * 100:.0f}%)")
        _fail(problems, m["std"] >= MIN_STDDEV,
              f"{name}: luma stddev {m['std']:.1f} < {MIN_STDDEV} — no contrast to "
              f"separate the raised forms")
        west, east, north, south = m["margin"]
        _fail(problems, min(m["margin"]) >= MIN_EDGE_MARGIN,
              f"{name}: alpha bbox touches the canvas on margin W/E/N/S = "
              f"{west}/{east}/{north}/{south}px, need >= {MIN_EDGE_MARGIN}px clear on "
              f"every side (the muzzle side especially: a barrel that runs off the "
              f"canvas is clipped in-engine)")
        _fail(problems, m["ink"] >= MIN_INK_SOUTH,
              f"{name}: ink centroid sits at {m['ink']:.3f} of the alpha bbox height "
              f"measured from the NORTH edge (need >= {MIN_INK_SOUTH}) — the sprite is "
              f"authored muzzle-up; a 180-degree error here is invisible in isolation "
              f"and makes every vehicle drive backwards in play")
    # cross-sprite distinctness at drawn size
    body_arr = {n: _draw_size(_read_png(paths[n]), DRAW[n]) for n in BODIES if n in paths}
    for i, a in enumerate(BODIES):
        for b in BODIES[i + 1:]:
            if a in body_arr and b in body_arr:
                v = _iou(body_arr[a], body_arr[b])
                after.setdefault("_iou", {})[f"{a}|{b}"] = v
                _fail(problems, v <= IOU_BAR,
                      f"{a} vs {b}: alpha IoU {v:.3f} > {IOU_BAR} — they occupy the "
                      f"same ground at drawn size and cannot be told apart at a glance")
    return (not problems), problems, after


def before_table() -> dict:
    out = {}
    for name in sorted(CANVAS):
        p = BEFORE_DIR / f"{name}.png"
        if p.exists():
            out[name] = measure(_read_png(p), DRAW[name])
    return out


# ===========================================================================
def main(argv: list) -> int:
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--outdir", type=Path, default=DEFAULT_OUTDIR,
                    help="where the flat <name>.png files are written "
                         f"(default {DEFAULT_OUTDIR.relative_to(PROJECT_ROOT)})")
    ap.add_argument("--only", action="append", default=None,
                    help="render one sprite (repeatable); default is all six")
    ap.add_argument("--samples", type=int, default=96,
                    help="Cycles samples (default 96; 48 is fine for a look pass)")
    ap.add_argument("--ss", type=int, default=4,
                    help="supersample factor; output is canvas px regardless "
                         "(default 4, minimum 2)")
    args = ap.parse_args(argv)

    if args.ss < 2:
        print("--ss must be >= 2 (the render is downsampled onto the fixed canvas)")
        return 2
    names = args.only if args.only else list(CANVAS)
    unknown = [n for n in names if n not in CANVAS]
    if unknown:
        print(f"unknown sprite(s): {', '.join(unknown)}; known: {', '.join(CANVAS)}")
        return 2

    outdir = args.outdir
    outdir.mkdir(parents=True, exist_ok=True)

    written = {}
    for name in names:
        print(f"  render {name:16s} {CANVAS[name][0]}x{CANVAS[name][1]} "
              f"(ss{args.ss}, {args.samples} samples) ...", flush=True)
        written[name] = render_sprite(name, outdir, args.ss, args.samples)

    ok, problems, after = verify(written)

    before = before_table()
    hdr = (f"{'sprite':16s} {'canvas':>9s} {'drawn':>7s} | "
           f"{'steps':>17s} {'top1':>19s} {'luma sd':>15s} {'ink':>7s}")
    print("\n" + hdr)
    print("-" * len(hdr))
    for name in sorted(CANVAS):
        c = CANVAS[name][0]
        d = c * DRAW[name]
        b = before.get(name)
        a = after.get(name) if name in written else None

        def cell(m):
            if m is None:
                return "      n/a         "
            return (f"{m['steps']:>4d} {m['top1'] * 100:6.1f}% {m['std']:6.1f} "
                    f"{m['ink']:5.3f}")

        mark = "" if name in written else "  (not rendered this run)"
        print(f"{name:16s} {c:>4d}x{c:<4d} {d:6.1f}px | "
              f"{cell(b)}  ->  {cell(a)}{mark}")
    print("  (before = the generative-AI bakes in assets/art/, after = this run; "
          "\n   steps = luma buckets holding >=2% of the opaque area, top1 = largest "
          "\n   8x8x8 RGB quantised bin, ink = ink centroid from the NORTH edge)")
    ious = after.get("_iou", {})
    for k, v in sorted(ious.items()):
        print(f"  alpha IoU {k.replace('|', ' vs '):46s} {v:.3f}  (bar {IOU_BAR})")

    if problems:
        print(f"\nFAIL — {len(problems)} gate(s):")
        for p in problems:
            print(f"  * {p}")
        return 1
    print(f"\nOK — {len(written)} sprite(s) written to {outdir}; "
          f"every gate passed at drawn size.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []))
