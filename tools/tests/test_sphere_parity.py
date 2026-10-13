"""moonbake/sphere.py against godot/src/core/sphere.gd and the docs/03 s2.8 vectors (TA-15)."""

from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(TOOLS))

import gates  # noqa: E402

try:
    import numpy as np
    from moonbake import seam, sphere
except ImportError as exc:  # numpy is installed by CI (tools/requirements.txt)
    gates.numpy_import_failed(exc)
    np = None

# docs/03 s2.6 edge table: (face, edge, neighbour face, neighbour edge)
DOC_EDGES = {
    (0, "u0", 3, "u1"), (0, "u1", 2, "v1"), (0, "v0", 5, "v1"), (0, "v1", 4, "u1"),
    (1, "u0", 5, "v0"), (1, "u1", 4, "u0"), (1, "v0", 3, "u0"), (1, "v1", 2, "v0"),
    (2, "u0", 5, "u1"), (2, "u1", 4, "v1"), (2, "v0", 1, "v1"), (2, "v1", 0, "u1"),
    (3, "u0", 1, "v0"), (3, "u1", 0, "u0"), (3, "v0", 5, "u0"), (3, "v1", 4, "v0"),
    (4, "u0", 1, "u1"), (4, "u1", 0, "v1"), (4, "v0", 3, "v1"), (4, "v1", 2, "u1"),
    (5, "u0", 3, "v0"), (5, "u1", 2, "u0"), (5, "v0", 1, "u0"), (5, "v1", 0, "v0"),
}

# docs/03 s2.8: (face, u, v) -> direction
VECTORS = [
    ((0, 0.5, 0.5), (1.0, 0.0, 0.0)),
    ((0, 0.0, 0.0), (0.577350, -0.577350, -0.577350)),
    ((0, 1.0, 0.5), (0.707107, 0.707107, 0.0)),
    ((4, 0.5, 0.5), (0.0, 0.0, 1.0)),
    ((2, 0.75, 0.25), (-0.357407, 0.862856, 0.357407)),
    ((5, 0.1, 0.9), (0.506732, -0.506732, -0.697457)),
]


@unittest.skipIf(np is None, gates.NUMPY_SKIP)
class SphereParity(unittest.TestCase):
    def test_forward_vectors(self) -> None:
        for (f, u, v), want in VECTORS:
            got = sphere.face_uv_to_dir(f, u, v)
            self.assertTrue(np.allclose(got, want, atol=1e-6), f"{(f, u, v)} -> {got}, want {want}")

    def test_inverse_round_trip(self) -> None:
        for (f, u, v), want in VECTORS:
            d = sphere.face_uv_to_dir(f, u, v)
            rf, ru, rv = sphere.dir_to_face_uv(d)
            if f == 0 and u in (0.0, 1.0):
                continue  # exactly on an edge or corner: ties resolve to the lower face (03 s2.5)
            self.assertEqual(int(rf), f)
            self.assertAlmostEqual(float(ru), u, delta=1e-6)
            self.assertAlmostEqual(float(rv), v, delta=1e-6)

    def test_edge_ties_resolve_to_lower_face(self) -> None:
        f, u, v = sphere.dir_to_face_uv(np.array([0.707107, 0.707107, 0.0]))
        self.assertEqual(int(f), 0)
        self.assertAlmostEqual(float(u), 1.0, delta=1e-5)

    def test_frames_match_gdscript(self) -> None:
        text = sphere.SPHERE_GD.read_text(encoding="utf-8")
        for name, table in (("_FACE_N", sphere.FACE_N), ("_FACE_S", sphere.FACE_S), ("_FACE_T", sphere.FACE_T)):
            m = re.search(rf"const {name}: PackedVector3Array = \[(.*?)\]\n", text, re.S)
            self.assertIsNotNone(m, name)
            vals = np.array([float(x) for x in re.findall(r"-?\d+(?:\.\d+)?", " ".join(re.findall(r"Vector3\(([^)]*)\)", m.group(1))))]).reshape(6, 3)
            self.assertTrue(np.array_equal(vals, table), name)

    def test_handedness_s_cross_t_is_n(self) -> None:
        for f in range(6):
            self.assertTrue(np.array_equal(np.cross(sphere.FACE_S[f], sphere.FACE_T[f]), sphere.FACE_N[f]))

    def test_constants_come_from_gdscript(self) -> None:
        self.assertEqual(sphere.PLANET_RADIUS, 6000.0)
        self.assertEqual((sphere.RELIEF_MIN, sphere.RELIEF_MAX), (-500.0, 700.0))

    def test_cell_size_at_centre(self) -> None:
        a = sphere.face_uv_to_dir(0, 0.5, 0.5)
        b = sphere.face_uv_to_dir(0, 0.5 + 1.0 / 1024, 0.5)
        self.assertAlmostEqual(float(sphere.great_circle_m(a, b)), 9.20, delta=0.01)  # 03 s2.7

    def test_edge_table_matches_doc(self) -> None:
        derived = set()
        for fa, ea, fb, eb in seam.edge_table(64):
            derived.add((fa, seam.EDGE_NAMES[ea], fb, seam.EDGE_NAMES[eb]))
            derived.add((fb, seam.EDGE_NAMES[eb], fa, seam.EDGE_NAMES[ea]))
        self.assertEqual(derived, DOC_EDGES)

    def test_lat_lon_and_offsets(self) -> None:
        d = sphere.from_lat_lon(0.0, 22.5)
        lat, lon = sphere.lat_lon_deg(d)
        self.assertAlmostEqual(float(lon), 22.5, places=9)
        p = sphere.offset_point(d, 90.0, 3.7)  # 3.7 m east
        self.assertAlmostEqual(float(sphere.great_circle_m(d, p)), 3.7, delta=1e-3)
        self.assertGreater(float(sphere.lat_lon_deg(sphere.offset_point(d, 0.0, 500.0))[0]), 0.0)


if __name__ == "__main__":
    unittest.main()
