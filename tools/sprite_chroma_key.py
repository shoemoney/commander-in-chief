#!/usr/bin/env python3
"""Reusable chroma-key + resize helpers for turning a flat-color-backdrop
render into a clean transparent sprite at a target canvas size. Generic and
asset-agnostic -- no prompts, no per-asset rationale, no fixed key color:
the key color is sampled from the image's own corners, not hardcoded, so the
same two functions work for any solid-backdrop render regardless of subject
or backdrop hue.

    python3 tools/test_sprite_chroma_key.py   # self-check
"""
import numpy as np
from PIL import Image


def resize_premultiplied(im: Image.Image, size: tuple[int, int]) -> Image.Image:
    """PIL's RGBA resize interpolates RGB and A independently, so a fully
    transparent pixel's leftover (arbitrary, post-chroma-key) color bleeds
    into semi-transparent neighbors during filtering. Premultiply by alpha
    before resizing and un-premultiply after so invisible pixels can't tint
    the visible edge. Uses BOX (a non-negative-kernel filter, no ringing) --
    LANCZOS's negative side-lobes overshoot at the hard alpha edges a
    chroma-keyed cutout has, and dividing an overshot premultiplied color
    back out by its (also overshot but still small) alpha blows up to a
    solid white halo right at the silhouette edge."""
    arr = np.asarray(im.convert("RGBA")).astype(np.float32)
    a = arr[:, :, 3:4] / 255.0
    premul = arr.copy()
    premul[:, :, :3] *= a
    premul_img = Image.fromarray(premul.astype(np.uint8), "RGBA")
    resized = premul_img.resize(size, Image.BOX)
    rarr = np.asarray(resized).astype(np.float32)
    ra = np.clip(rarr[:, :, 3:4], 1, 255) / 255.0
    rarr[:, :, :3] = np.clip(rarr[:, :, :3] / ra, 0, 255)
    return Image.fromarray(rarr.astype(np.uint8), "RGBA")


def _rgb_to_hsv(r, g, b):
    """Vectorized RGB[0..255] -> HSV (H in degrees, S/V in [0,1])."""
    r, g, b = r / 255.0, g / 255.0, b / 255.0
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    d = mx - mn
    safe_d = np.where(d == 0, 1.0, d)
    rc = np.where(mx == r, ((g - b) / safe_d) % 6, 0.0)
    gc = np.where(mx == g, (b - r) / safe_d + 2.0, 0.0)
    bc = np.where(mx == b, (r - g) / safe_d + 4.0, 0.0)
    h = np.where(mx == r, rc, np.where(mx == g, gc, bc)) * 60.0
    h = np.where(d == 0, 0.0, h)
    s = np.where(mx == 0, 0.0, d / np.where(mx == 0, 1.0, mx))
    return h, s, mx


def chroma_key(img: Image.Image, hue_tol: float = 14, hue_feather: float = 14,
               sat_gate: float = 0.12, val_frac: float = 0.72) -> Image.Image:
    """Key a flat-color backdrop to transparent using HSV hue distance rather
    than raw RGB distance -- a subject color can sit deceptively close to the
    backdrop in RGB space (e.g. a warm tan subject vs a magenta backdrop)
    while its hue is 60+ degrees away, which plain-distance keying misses and
    ends up erasing subject pixels instead of just background. The key color
    is auto-sampled from the four image corners (assumed pure backdrop), so
    no caller-supplied key color is needed.

    Gated by saturation AND value so near-black/near-white subject pixels
    (which have undefined/unstable hue) are never mistaken for background,
    and a global magenta/backdrop-hue "spill" de-tint is applied everywhere
    (not just the feathered edge) to mute residual backdrop-color bleed
    (e.g. GI-bounced tint on shadowed subject surfaces) without erasing real
    shading detail."""
    arr = np.asarray(img.convert("RGBA")).astype(np.float32)
    h, w = arr.shape[:2]
    corners = [arr[0, 0, :3], arr[0, w - 1, :3], arr[h - 1, 0, :3], arr[h - 1, w - 1, :3]]
    key = np.mean(corners, axis=0)
    key_h, _, key_v = _rgb_to_hsv(np.array([key[0]]), np.array([key[1]]), np.array([key[2]]))
    key_h, key_v = key_h[0], key_v[0]
    val_gate = key_v * val_frac
    r, g, b, a = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2], arr[:, :, 3]
    ph, ps, pv = _rgb_to_hsv(r, g, b)
    dh = np.abs(ph - key_h)
    dh = np.minimum(dh, 360.0 - dh)
    bg_like = (ps > sat_gate) & (pv > val_gate)
    out_a = a.copy()
    hard = bg_like & (dh < hue_tol)
    soft = bg_like & (dh >= hue_tol) & (dh < hue_tol + hue_feather)
    out_a[hard] = 0
    out_a[soft] = a[soft] * (dh[soft] - hue_tol) / hue_feather
    # backdrop-hue spill de-tint: the two channels the key color is highest
    # in (e.g. R and B for a magenta key) never both legitimately exceed the
    # third on real subject paint, so subtracting their shared excess only
    # ever cancels genuine key-color bleed (e.g. GI-bounced tint on shadowed
    # subject surfaces) without erasing real shading detail.
    order = np.argsort(key)
    lo_ch, hi_a, hi_b = int(order[0]), int(order[1]), int(order[2])
    chans = [r, g, b]
    spill = np.clip(np.minimum(chans[hi_a], chans[hi_b]) - chans[lo_ch], 0, None)
    chans[hi_a] = chans[hi_a] - spill
    chans[hi_b] = chans[hi_b] - spill
    out = np.stack([chans[0], chans[1], chans[2], out_a], axis=-1)
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")


def key_crop_pad_resize(img: Image.Image, size: tuple[int, int], rot_deg: float = 0.0,
                         **key_kwargs) -> Image.Image:
    """Convenience pipeline: chroma-key, optionally rotate (e.g. to land a
    subject "front" at the top of the canvas), crop to content bbox, pad to
    a square, and resize to the target canvas via resize_premultiplied."""
    keyed = chroma_key(img, **key_kwargs)
    if rot_deg:
        keyed = keyed.rotate(rot_deg, expand=True, fillcolor=(0, 0, 0, 0))
    bbox = keyed.getbbox()
    if bbox:
        keyed = keyed.crop(bbox)
    cw, ch = keyed.size
    side = max(cw, ch)
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.paste(keyed, ((side - cw) // 2, (side - ch) // 2), keyed)
    return resize_premultiplied(square, size)
