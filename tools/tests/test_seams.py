"""Edge seams: identical bits on both faces of all 12 cube edges and at the 8 corners (docs/03 s8.5, TA-15)."""

from __future__ import annotations

import copy
import json
import sys
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(TOOLS))

try:
    import numpy as np
    from moonbake import seam
    from moonbake.bake import bake
    from moonbake.recipe import load_recipe
except ImportError:
    np = None

TINY = TOOLS.parent / "godot/content/maps/tiny_test/recipe.json"


def _edge(a: "np.ndarray", edge: int) -> "np.ndarray":
    return [a[:, 0], a[:, -1], a[0, :], a[-1, :]][edge]


@unittest.skipIf(np is None, "numpy not installed")
class Seams(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        rec = load_recipe(TINY)
        rough = copy.deepcopy(rec)  # rough terrain so that seams are not trivially flat
        rough["base_noise"].update({"amp_m": 120, "freq_per_circumference": 18, "octaves": 4, "warp_m": 300})
        rough["craters"] = {"explicit": [], "scatter": {"per_wedge": 40, "diam_m": [150, 700], "power": 2.0}}
        cls.rough = bake(rough)
        cls.flat = bake(rec)

    def test_twelve_edges_equal(self) -> None:
        table = seam.edge_table(128)
        self.assertEqual(len(table), 12)
        for b in (self.rough, self.flat):
            for fa, ea, fb, eb in table:
                for arrs, what in ((b.height, "height"), (b.biome, "biome")):
                    self.assertTrue(np.array_equal(_edge(arrs[fa], ea), _edge(arrs[fb], eb)),
                                    f"{what}: face {fa} edge {ea} != face {fb} edge {eb}")

    def test_corners_equal_across_three_faces(self) -> None:
        h = self.rough.height
        corners: dict[tuple, list] = {}
        n = 128
        for f in range(6):
            for (x, y) in ((0, 0), (n - 1, 0), (0, n - 1), (n - 1, n - 1)):
                d = tuple(np.round(self._dir(f, x, y), 6) + 0.0)
                corners.setdefault(d, []).append(int(h[f][y, x]))
        self.assertEqual(len(corners), 8)
        for d, vals in corners.items():
            self.assertEqual(len(vals), 3, d)
            self.assertEqual(len(set(vals)), 1, f"corner {d}: {vals}")

    @staticmethod
    def _dir(f: int, x: int, y: int):
        from moonbake import sphere
        return sphere.face_uv_to_dir(f, x / 127.0, y / 127.0)

    def test_heights_continuous_across_edge(self) -> None:
        """A texel one step inside either face differs by less than the steepest plausible slope step."""
        b = self.rough
        for fa, ea, fb, eb in seam.edge_table(128):
            inner_a = [b.height[fa][:, 1], b.height[fa][:, -2], b.height[fa][1, :], b.height[fa][-2, :]][ea]
            diff = np.abs(inner_a.astype(np.int64) - _edge(b.height[fa], ea).astype(np.int64))
            self.assertLess(int(diff.max()), 65535 * 60 // 1200, "no cliff next to the seam")

    def test_pairs_cover_every_edge_texel(self) -> None:
        for fa, ia, fb, ib, _, _ in seam.edge_pairs(128):
            self.assertEqual(len(ia), len(ib))
            self.assertLess(fa, fb)


if __name__ == "__main__":
    unittest.main()
