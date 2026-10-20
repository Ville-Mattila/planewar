"""pw_core (ART-04, 07 s4.2-4.4, 4.7): swatch UVs, generators, foundation rule, strut layout, check rules."""

from __future__ import annotations

import math
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "blender" / "lib"))

import pw_core as core  # noqa: E402

PAL = core.Palette()


def tri_list(verts, faces):
    out = []
    for f in faces:
        for k in range(1, len(f) - 1):
            out.append((verts[f[0]], verts[f[k]], verts[f[k + 1]]))
    return out


def good_mesh(swatch="hull_300", team="team_paint_mid", team_share=1):
    """Box with `team_share` of 6 faces painted with a team swatch (2 tris per face)."""
    v, f = core.box_geometry((2.0, 2.0, 2.0), (0.0, 0.0, 1.0))
    tris, uvs = [], []
    for i, face in enumerate(f):
        uv = PAL.uv(team if i < team_share else swatch)
        for t in tri_list(v, [face]):
            tris.append(t)
            uvs.append((uv, uv, uv))
    return {"tris": tris, "uvs": uvs, "smooth": 0}


def run(mesh=None, aid="prop_test_box", cls="prop", hp=None, mats=("PW_Atlas",), names=("Hull",), budget=None,
        fmax=None):
    return core.run_checks(aid, cls, mesh or good_mesh(), hp or {}, list(mats), list(names), budget, PAL, fmax)


def status(rep, cid):
    return next(c["status"] for c in rep["checks"] if c["id"] == cid)


class PaletteTests(unittest.TestCase):
    def test_uv_is_cell_centre_row_major(self):
        self.assertEqual(PAL.uv("hull_100"), (0.5 / 16, 0.5 / 16))
        u, v = PAL.uv(PAL.names[17])
        self.assertAlmostEqual(u, 1.5 / 16)
        self.assertAlmostEqual(v, 1.5 / 16)

    def test_swatch_roundtrip_for_all_names(self):
        for i, n in enumerate(PAL.names):
            self.assertEqual(PAL.swatch_at(*PAL.uv(n)), i)

    def test_off_centre_is_not_a_swatch(self):
        u, v = PAL.uv("hull_100")
        self.assertIsNone(PAL.swatch_at(u + 0.01, v))

    def test_unknown_swatch_raises(self):
        with self.assertRaises(KeyError):
            PAL.uv("nope")

    def test_emblem_cell_is_in_emblem_strip(self):
        self.assertGreaterEqual(PAL.emblem_uv(0)[1], 0.875)
        self.assertEqual(core.blender_v(0.25), 0.75)

    def test_team_codes(self):
        self.assertEqual(PAL.code[PAL.index["team_paint_mid"]], 1)
        self.assertEqual(PAL.code[PAL.index["team_glow"]], 3)
        self.assertEqual(PAL.code[PAL.index["hull_100"]], 0)


class Generators(unittest.TestCase):
    def test_box_counts(self):
        v, f = core.box_geometry((2, 4, 6), (1, 1, 1))
        self.assertEqual((len(v), len(f)), (8, 6))
        self.assertEqual(max(p[2] for p in v), 4.0)

    def test_box_taper_zero_is_pyramid(self):
        v, f = core.box_geometry((2, 2, 2), (0, 0, 0), 0.0)
        self.assertEqual((len(v), len(f)), (5, 5))

    def test_prism_sides_and_cone(self):
        v, f = core.prism_geometry(6, 1.0, 1.0, 4.0, "Y", (0, 0, 0))
        self.assertEqual((len(v), len(f)), (12, 8))
        self.assertAlmostEqual(min(p[1] for p in v), -2.0)
        v, f = core.prism_geometry(4, 1.0, 0.0, 2.0, "Z", (0, 0, 0))
        self.assertEqual((len(v), len(f)), (5, 5))

    def test_prism_rejects_degenerate(self):
        with self.assertRaises(ValueError):
            core.prism_geometry(2, 1, 1, 1, "X", (0, 0, 0))
        with self.assertRaises(ValueError):
            core.prism_geometry(4, 0, 0, 1, "X", (0, 0, 0))

    def test_plate_normalises_winding_and_rejects_zero_area(self):
        pts = [(0, 0), (2, 0), (2, 1), (0, 1)]
        for p in (pts, list(reversed(pts))):
            v, f = core.plate_geometry(p, 0.5, (0, 0, 0))
            self.assertEqual((len(v), len(f)), (8, 6))
            top = core.tri_normal(tri_list(v, [f[1]])[0])
            self.assertGreater(top[2], 0.0)
        with self.assertRaises(ValueError):
            core.plate_geometry([(0, 0), (1, 1), (2, 2)], 0.5, (0, 0, 0))

    def test_faces_have_outward_winding(self):
        v, f = core.box_geometry((2, 2, 2), (0, 0, 0))
        for face in f:
            t = tri_list(v, [face])[0]
            n = core.tri_normal(t)
            self.assertGreater(sum(n[i] * t[0][i] for i in range(3)), 0.0)

    def test_mirrored_welds_plane_and_flips(self):
        v, f = core.plate_geometry([(0, 0), (3, 0), (3, 1), (0, 1)], 0.2, (0, 0, 0))
        mv, mf = core.mirrored(v, f)
        self.assertEqual(len(mf), 2 * len(f))
        self.assertEqual(len(mv), len(v) + 4)  # four vertices at x = 0 are shared
        self.assertEqual(min(p[0] for p in mv), -3.0)

    def test_emblem_quad_rotation(self):
        v, _ = core.emblem_geometry(2.0, (0, 0, 5), (math.pi / 2, 0, 0))
        self.assertAlmostEqual(max(abs(p[2] - 5.0) for p in v), 1.0)

    def test_foundation_depth_rule(self):
        self.assertAlmostEqual(core.foundation_depth((4, 4)), 0.6)  # small: 0.6 m floor
        self.assertAlmostEqual(core.foundation_depth((31, 39)), 0.27 * 19.5)
        v, _ = core.foundation_geometry((44, 44))
        self.assertAlmostEqual(min(p[2] for p in v), -0.27 * 22)
        self.assertAlmostEqual(max(p[2] for p in v), 0.0)


class Struts(unittest.TestCase):
    def check_stance(self, lay):
        ys = {round(f[1], 9) for f in lay["feet"]}
        self.assertEqual(len(ys), 1)  # coplanar
        self.assertLess(next(iter(ys)), min(b[1] for b in lay["bases"]))  # behind the nozzle plane

    def test_single_engine_feet_on_circle_and_centroid_on_axis(self):
        lay = core.strut_layout(1.1, 1.6, [(0.0, -6.0, 0.0)])
        for f in lay["feet"]:
            self.assertAlmostEqual(math.hypot(f[0], f[2]), 1.6)
        self.assertAlmostEqual(sum(f[0] for f in lay["feet"]), 0.0)
        self.assertAlmostEqual(sum(f[2] for f in lay["feet"]), 0.0)
        self.check_stance(lay)
        b, f = lay["bases"][0], lay["feet"][0]
        horiz = math.hypot(f[0] - b[0], f[2] - b[2])
        self.assertAlmostEqual(math.degrees(math.atan2(horiz, b[1] - f[1])), core.SPLAY_DEG, places=4)

    def test_three_points_boom_layout(self):
        lay = core.strut_layout(1.5, 2.4, [(-3.0, -7.0, 0.0), (3.0, -7.0, 0.0), (0.0, -5.0, 0.0)])
        self.check_stance(lay)
        self.assertAlmostEqual(sum(f[0] for f in lay["feet"]), 0.0)
        self.assertLess(lay["feet"][0][0], -3.0)  # pushed outward
        self.assertEqual(lay["feet"][2][0], 0.0)

    def test_bad_inputs(self):
        for args in ((0, 1, [(0, 0, 0)]), (1, 0, [(0, 0, 0)]), (1, 1, [(0, 0, 0), (1, 0, 0)])):
            with self.assertRaises(ValueError):
                core.strut_layout(*args)

    def test_tri_budget_about_30(self):
        geos = core.strut_geometries(core.strut_layout(1.1, 1.6, [(0, -6, 0)]), 1.1)
        self.assertEqual(sum(len(tri_list(v, [f])) for v, fs in geos for f in fs), 30)

    def test_gear_passes_v11_and_perturbed_fails(self):
        lay = core.strut_layout(1.1, 1.6, [(0.0, -6.0, 0.0)])
        hp = {"HP_Nose": (0, 6, 0), "HP_Tail": (0, -6, 0)}
        hp.update({f"HP_Gear_{i}": f for i, f in enumerate(lay["feet"])})
        self.assertEqual(status(run(aid="ship_t", cls="ship", hp=hp), "V11"), "pass")
        g = hp["HP_Gear_1"]
        bad = dict(hp, HP_Gear_1=(g[0], g[1] + 0.2, g[2]))
        self.assertEqual(status(run(aid="ship_t", cls="ship", hp=bad), "V11"), "fail")


class Checks(unittest.TestCase):
    def test_clean_prop_is_ok(self):
        rep = run()
        self.assertTrue(rep["ok"], rep["checks"])
        self.assertEqual(rep["tris"], 12)

    def test_v01_name(self):
        self.assertEqual(status(run(aid="prop_ok"), "V01"), "pass")
        self.assertEqual(status(run(aid="Box"), "V01"), "fail")
        self.assertEqual(status(run(aid="thing_box"), "V01"), "fail")

    def test_v03_budget(self):
        self.assertEqual(status(run(budget=12), "V03"), "pass")
        self.assertEqual(status(run(budget=11), "V03"), "fail")
        self.assertEqual(status(run(budget=100), "V03"), "warn")
        self.assertEqual(status(run(), "V03"), "skip")

    def test_v04_material(self):
        self.assertEqual(status(run(mats=["PW_Atlas"]), "V04"), "pass")
        self.assertEqual(status(run(mats=["PW_Atlas", "Other"]), "V04"), "fail")
        self.assertEqual(status(run(mats=[]), "V04"), "fail")

    def test_v06_swatch_rule(self):
        m = good_mesh()
        self.assertEqual(status(run(m), "V06"), "pass")
        u, v = m["uvs"][3][0]
        m["uvs"][3] = ((u + 0.01, v),) + m["uvs"][3][1:]
        self.assertEqual(status(run(m), "V06"), "fail")
        m = good_mesh()
        m["uvs"][5] = (PAL.uv("hull_100"), PAL.uv("hull_200"), PAL.uv("hull_100"))  # straddles two swatches
        self.assertEqual(status(run(m), "V06"), "fail")

    def test_v06_emblem_exempt(self):
        m = good_mesh()
        e = PAL.emblem_uv(0)
        m["uvs"][8] = (e, e, e)
        self.assertEqual(status(run(m), "V06"), "pass")

    def test_v07_flat(self):
        m = good_mesh()
        m["smooth"] = 2
        self.assertEqual(status(run(m), "V07"), "fail")

    def test_v12_degenerate(self):
        m = good_mesh()
        p = (0.0, 0.0, 0.0)
        m["tris"].append((p, p, (1.0, 0.0, 0.0)))
        m["uvs"].append((PAL.uv("hull_300"),) * 3)
        self.assertEqual(status(run(m), "V12"), "fail")
        self.assertEqual(status(run(), "V12"), "pass")

    def test_v14_team_area(self):
        self.assertEqual(status(run(good_mesh(team_share=1)), "V14"), "pass")  # 16.7 %
        self.assertEqual(status(run(good_mesh(team_share=0)), "V14"), "fail")  # 0 %
        self.assertEqual(status(run(good_mesh(team_share=3)), "V14"), "fail")  # 50 %
        self.assertEqual(status(run(good_mesh(team="team_glow")), "V14"), "pass")  # glow counts too

    def test_v15_names(self):
        self.assertEqual(status(run(names=["Hull", "HP_Dock"]), "V15"), "pass")
        self.assertEqual(status(run(names=["Hull.001"]), "V15"), "fail")

    def test_v10_forward(self):
        hp = {"HP_Nose": (0, 6, 0), "HP_Tail": (0, -6, 0)}
        self.assertEqual(status(run(aid="ship_t", cls="ship", hp=hp), "V10"), "pass")
        flipped = {"HP_Nose": (0, -6, 0), "HP_Tail": (0, 6, 0)}
        self.assertEqual(status(run(aid="ship_t", cls="ship", hp=flipped), "V10"), "fail")
        self.assertEqual(status(run(aid="ship_t", cls="ship", hp={}), "V10"), "fail")

    def test_v11_requires_gear_on_ships(self):
        rep = run(aid="ship_t", cls="ship", hp={"HP_Nose": (0, 6, 0), "HP_Tail": (0, -6, 0)})
        self.assertEqual(status(rep, "V11"), "fail")

    def test_v09_ship_origin(self):
        self.assertEqual(status(run(aid="ship_t", cls="ship"), "V09"), "fail")  # box centre is 1 m up

    def test_v09_structure_origin(self):
        v, f = core.box_geometry((4, 4, 2), (0, 0, -1.0))
        m = {"tris": tri_list(v, f), "uvs": [(PAL.uv("hull_700"),) * 3] * 12, "smooth": 0}
        self.assertEqual(status(run(m, aid="str_t", cls="str", fmax=2.0), "V09"), "pass")
        self.assertEqual(status(run(m, aid="str_t", cls="str", fmax=0.5), "V09"), "fail")
        v, f = core.box_geometry((4, 4, 2), (3.0, 0, 1.0))
        m = {"tris": tri_list(v, f), "uvs": [(PAL.uv("hull_700"),) * 3] * 12, "smooth": 0}
        self.assertEqual(status(run(m, aid="str_t", cls="str"), "V09"), "fail")

    def test_report_ids_sorted_and_glb_only_checks_skip(self):
        rep = run()
        ids = [c["id"] for c in rep["checks"]]
        self.assertEqual(ids, sorted(ids))
        skipped = {c["id"] for c in rep["checks"] if c["status"] == "skip"}
        self.assertEqual(skipped - {"V03", "V09"}, {"V02", "V05", "V08", "V13"})

    def test_pascal(self):
        self.assertEqual(core.pascal("ship_dart"), "ShipDart")
        self.assertEqual(core.pascal("prop_test_box"), "PropTestBox")


if __name__ == "__main__":
    unittest.main()
