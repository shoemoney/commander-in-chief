#!/usr/bin/env python3
"""Checks the baked infantry PNGs: hard alpha, bounded palette, keyline ring.

Run:  python3 tools/test_bake_sprites.py
Also proves the checks can fail: a deliberately soft copy must be rejected.
"""
import glob
import os
import sys
import unittest

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BAKED = os.path.join(ROOT, "assets", "baked")
INK = np.array([13, 15, 10])
MAX_COLORS = 48          # shared palette (<=40) + the ink keyline


def files():
    return sorted(glob.glob(os.path.join(BAKED, "*", "*.png")))


def hard_alpha_ratio(a):
    return float(np.mean((a == 0) | (a == 255)))


def palette_size(arr):
    solid = arr[..., 3] > 0
    return len({tuple(p) for p in arr[..., :3][solid]})


def keyline_ratio(arr):
    """Share of the silhouette's outermost ring that is the ink colour."""
    solid = arr[..., 3] > 0
    inner = solid.copy()
    inner[1:, :] &= solid[:-1, :]
    inner[:-1, :] &= solid[1:, :]
    inner[:, 1:] &= solid[:, :-1]
    inner[:, :-1] &= solid[:, 1:]
    inner[0, :] = inner[-1, :] = False
    inner[:, 0] = inner[:, -1] = False
    ring = solid & ~inner
    if not ring.any():
        return 0.0
    ink = (arr[..., :3] == INK).all(axis=-1)
    return float((ring & ink).sum() / ring.sum())


class Baked(unittest.TestCase):
    def test_there_are_baked_files(self):
        self.assertGreaterEqual(len(files()), 69)

    def test_hard_alpha_edge(self):
        for f in files():
            a = np.asarray(Image.open(f).convert("RGBA"))[..., 3]
            self.assertGreaterEqual(hard_alpha_ratio(a), 0.99, f)

    def test_bounded_colour_count(self):
        for f in files():
            arr = np.asarray(Image.open(f).convert("RGBA"))
            self.assertLessEqual(palette_size(arr), MAX_COLORS, f)

    def test_keyline_ring(self):
        for f in files():
            arr = np.asarray(Image.open(f).convert("RGBA"))
            self.assertGreaterEqual(keyline_ratio(arr), 0.99, f)

    def test_screen_sized(self):
        for f in files():
            w, h = Image.open(f).size
            self.assertLessEqual(max(w, h), 48, f)


class Controls(unittest.TestCase):
    """The checks above must be able to fail."""

    def test_a_blurred_sprite_is_rejected(self):
        src = Image.open(os.path.join(BAKED, "hero", "idle.png")).convert("RGBA")
        soft = np.asarray(src.filter(ImageFilter.GaussianBlur(1.2)))
        self.assertLess(hard_alpha_ratio(soft[..., 3]), 0.99)
        self.assertGreater(palette_size(soft), MAX_COLORS)

    def test_a_ringless_sprite_is_rejected(self):
        arr = np.asarray(Image.open(os.path.join(BAKED, "hero", "idle.png")).convert("RGBA")).copy()
        arr[..., :3][(arr[..., :3] == INK).all(axis=-1)] = (200, 200, 200)
        self.assertLess(keyline_ratio(arr), 0.5)


if __name__ == "__main__":
    sys.exit(unittest.main(verbosity=1))
