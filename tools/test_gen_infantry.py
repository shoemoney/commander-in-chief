#!/usr/bin/env python3
"""Checks tools/gen_infantry.py: deterministic, footprints held, tint table in
sync with art.gd, committed PNGs equal the generator output, walk frames differ.
Run: python3 tools/test_gen_infantry.py"""
import os
import re
import sys
import unittest

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_infantry as g  # noqa: E402


def bbox(arr):
    ys, xs = np.nonzero(arr[..., 3] > 0)
    return int(xs.max() - xs.min() + 1), int(ys.max() - ys.min() + 1)


class Gen(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.out = g.render_all()

    def test_deterministic(self):
        again = g.render_all()
        for k, v in self.out.items():
            self.assertTrue((v == again[k]).all(), k)

    def test_pinned_footprints_idle_and_base(self):
        for (kind, pose), arr in self.out.items():
            if pose in ("idle", "base"):
                self.assertEqual(bbox(arr), g.BBOX[kind][pose], (kind, pose))

    def test_committed_files_match_generator(self):
        for (kind, pose), arr in self.out.items():
            f = os.path.join(g.OUT, kind, pose + ".png")
            with Image.open(f) as im:
                on_disk = np.asarray(im.convert("RGBA"))
            self.assertTrue((on_disk == arr).all(), f)

    def test_tint_table_mirrors_art_gd(self):
        with open(os.path.join(g.ROOT, "src", "view", "art.gd")) as fh:
            src = fh.read()
        for key, want in g.TINTS.items():
            art_key = {"hero": "player1", "enemy_elite": "enemy_assault"}.get(key, key)
            m = re.search(r'"%s": Color\(([\d.]+), ([\d.]+), ([\d.]+)\)' % art_key, src)
            self.assertIsNotNone(m, art_key)
            self.assertEqual(tuple(float(x) for x in m.groups()), want, key)

    def test_walk_frames_differ(self):
        for kind in ("enemy_assault", "enemy_smg", "enemy_lmg"):
            a, b = self.out[(kind, "move_0")], self.out[(kind, "move_1")]
            h, w = min(a.shape[0], b.shape[0]), min(a.shape[1], b.shape[1])
            self.assertGreater(int((a[:h, :w] != b[:h, :w]).any(axis=-1).sum()), 6, kind)

    def test_barrel_is_a_narrow_tip_and_a_blob_is_rejected(self):
        arr = self.out[("enemy_assault", "idle")]
        top = int((arr[3, :, 3] > 0).sum())
        self.assertLessEqual(top, 5)
        blob = np.zeros_like(arr)
        blob[3:-3, 3:-3] = (150, 80, 60, 255)
        self.assertGreater(int((blob[3, :, 3] > 0).sum()), 5)


if __name__ == "__main__":
    sys.exit(unittest.main(verbosity=1))
