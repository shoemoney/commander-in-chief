#!/usr/bin/env python3
"""Minimal self-check for sprite_chroma_key.py -- run directly:

    python3 tools/test_sprite_chroma_key.py

  1. chroma_key erases a flat magenta backdrop but keeps an opaque,
     unrelated-hue subject block fully intact (alpha and color untouched).
  2. chroma_key's spill de-tint reduces (does not fully erase) a subject
     pixel that was GI-tinted toward the backdrop hue but sits far too dark
     to trip the value gate.
  3. resize_premultiplied does not bleed a transparent pixel's arbitrary
     leftover color into a neighboring opaque pixel (the plain-RGBA-resize
     bug it exists to avoid).
  4. key_crop_pad_resize returns exactly the requested output size and
     drops the keyed-out backdrop area from the final alpha.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sprite_chroma_key import chroma_key, key_crop_pad_resize, resize_premultiplied

FAILURES = []


def check(name, cond):
    print(f"{'ok' if cond else 'FAIL'}  {name}")
    if not cond:
        FAILURES.append(name)


def test_chroma_key_erases_backdrop_keeps_subject():
    arr = np.full((20, 20, 4), 255, dtype=np.uint8)
    arr[:, :, 0] = 197
    arr[:, :, 1] = 71
    arr[:, :, 2] = 138  # flat magenta backdrop everywhere
    arr[5:15, 5:15] = [40, 120, 60, 255]  # opaque green subject block, far from magenta hue
    img = Image.fromarray(arr, "RGBA")
    out = np.asarray(chroma_key(img))
    check("backdrop pixel keyed to alpha 0", out[0, 0, 3] == 0)
    check("subject alpha stays opaque", out[10, 10, 3] == 255)
    check("subject color untouched", tuple(out[10, 10, :3]) == (40, 120, 60))


def test_spill_detint_reduces_not_erases():
    arr = np.full((10, 10, 4), 255, dtype=np.uint8)
    arr[:, :, 0] = 197
    arr[:, :, 1] = 71
    arr[:, :, 2] = 138
    # dark subject pixel tinted toward the magenta key hue (R,B > G) but far
    # too dim to trip the value gate -- should be de-tinted, not erased.
    arr[5, 5] = [60, 20, 55, 255]
    img = Image.fromarray(arr, "RGBA")
    out = np.asarray(chroma_key(img))
    check("dark GI-tinted pixel stays opaque", out[5, 5, 3] == 255)
    check("dark GI-tinted pixel loses its R/B spill excess",
          int(out[5, 5, 0]) < 60 or int(out[5, 5, 2]) < 55)


def test_resize_premultiplied_no_color_bleed():
    arr = np.zeros((4, 4, 4), dtype=np.uint8)
    arr[0:2, :, :] = [255, 0, 0, 255]  # opaque red top half
    arr[2:4, :, :] = [0, 255, 0, 0]  # fully transparent bottom half, garbage green leftover
    img = Image.fromarray(arr, "RGBA")
    out = np.asarray(resize_premultiplied(img, (4, 4)))
    check("opaque region keeps its color after resize", tuple(out[0, 0, :3]) == (255, 0, 0))


def test_key_crop_pad_resize_output_shape():
    arr = np.full((30, 50, 4), 255, dtype=np.uint8)
    arr[:, :, 0], arr[:, :, 1], arr[:, :, 2] = 197, 71, 138
    arr[10:20, 15:35] = [40, 120, 60, 255]
    img = Image.fromarray(arr, "RGBA")
    out = key_crop_pad_resize(img, (64, 64))
    check("output canvas matches requested size", out.size == (64, 64))
    arr_out = np.asarray(out)
    check("some pixels keyed fully transparent", (arr_out[:, :, 3] == 0).any())
    check("some pixels stayed opaque", (arr_out[:, :, 3] == 255).any())


if __name__ == "__main__":
    test_chroma_key_erases_backdrop_keeps_subject()
    test_spill_detint_reduces_not_erases()
    test_resize_premultiplied_no_color_bleed()
    test_key_crop_pad_resize_output_shape()
    if FAILURES:
        print(f"\n{len(FAILURES)} check(s) FAILED: {FAILURES}")
        sys.exit(1)
    print("\nall checks passed")
