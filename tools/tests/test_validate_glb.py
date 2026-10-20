"""tools/art/validate_glb.py (ART-05, docs/07 s4.7): a sample glb passes V01-V15, a deliberately bad glb fails each check;
V11 requires HP_Gear_0..2 on ships; asset_budgets.json is schema-valid and consistent with 07 s5.1."""

from __future__ import annotations

import copy
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(TOOLS / "tests"))
sys.path.insert(0, str(TOOLS / "art"))
sys.path.insert(0, str(TOOLS / "blender" / "lib"))

import glb_fixture as F  # noqa: E402
import pw_core as core  # noqa: E402
import validate_glb as V  # noqa: E402

BUDGETS = V.load_budgets()
SCRIPT = TOOLS / "art" / "validate_glb.py"


def run(asset_id, built, budgets=None, file_ok=True):
    js, binary = built
    return V.validate_bytes(asset_id, F.pack_glb(js, binary), budgets or BUDGETS, file_ok)


def st(rep, cid):
    return next(c["status"] for c in rep["checks"] if c["id"] == cid)


def detail(rep, cid):
    return next(c["detail"] for c in rep["checks"] if c["id"] == cid)


def with_asset(**changes):
    b = copy.deepcopy(BUDGETS)
    b["assets"]["ship_dart"].update(changes)
    return b


def hull_and_far(parts, emp, asset_id="ship_dart"):
    far = core.pascal(asset_id) + "Far"
    return F.build_glb(asset_id, {"Hull": parts, far: parts[:12]}, emp)


class Sample(unittest.TestCase):
    def test_sample_ship_passes_every_check(self):
        rep = run("ship_dart", F.sample_ship())
        self.assertTrue(rep["ok"], [c for c in rep["checks"] if c["status"] != "pass"])
        self.assertEqual([c["id"] for c in rep["checks"]], [f"V{i:02d}" for i in range(1, 16)])
        self.assertEqual({c["status"] for c in rep["checks"]}, {"pass"})

    def test_sample_structure_passes(self):
        rep = run("str_pad", F.sample_pad())
        self.assertTrue(rep["ok"], [c for c in rep["checks"] if c["status"] == "fail"])
        self.assertEqual(st(rep, "V09"), "pass")
        self.assertEqual(st(rep, "V11"), "pass")  # HP_Dock required by asset_budgets.json


class EachCheckFails(unittest.TestCase):
    def test_v01_name(self):
        self.assertEqual(st(run("Ship-Dart", F.sample_ship("ship_dart")), "V01"), "fail")
        self.assertEqual(st(run("ship_dart", F.sample_ship(), file_ok=False), "V01"), "fail")

    def test_v02_root(self):
        self.assertEqual(st(run("ship_dart", F.sample_ship(root_name="Dart")), "V02"), "fail")
        self.assertEqual(st(run("ship_dart", F.sample_ship(root_translation=(0, 1, 0))), "V02"), "fail")
        js, b = F.sample_ship()
        js["scenes"][0]["nodes"].append(1)
        self.assertEqual(st(run("ship_dart", (js, b)), "V02"), "fail")

    def test_v03_triangles(self):
        rep = run("ship_dart", F.sample_ship(), with_asset(max_tris=100))
        self.assertEqual(st(rep, "V03"), "fail")
        self.assertFalse(rep["ok"])
        warn = run("ship_dart", F.sample_ship(), with_asset(max_tris=2000))
        self.assertEqual(st(warn, "V03"), "warn")  # < 25 % of budget
        self.assertTrue(warn["ok"])  # a warning is not a failure

    def test_v03_unknown_asset_uses_class_ceiling(self):
        rep = run("ship_test_gear", F.sample_ship("ship_test_gear"))
        self.assertIn(st(rep, "V03"), ("pass", "warn"))
        self.assertIn("budget 1200", detail(rep, "V03"))

    def test_v04_material_and_images(self):
        self.assertEqual(st(run("ship_dart", F.sample_ship(material="Metal")), "V04"), "fail")
        js, b = F.sample_ship()
        js["materials"].append({"name": "Second"})
        self.assertEqual(st(run("ship_dart", (js, b)), "V04"), "fail")
        js, b = F.sample_ship()
        js["images"] = [{"uri": "a.png"}]
        self.assertEqual(st(run("ship_dart", (js, b)), "V04"), "fail")

    def test_v05_attributes_and_extras(self):
        for mutate in (
            lambda js: js["meshes"][0]["primitives"][0]["attributes"].update(COLOR_0=0),
            lambda js: js["meshes"][0]["primitives"][0]["attributes"].update(TANGENT=0),
            lambda js: js["meshes"][0]["primitives"][0]["attributes"].update(TEXCOORD_1=0),
            lambda js: js["meshes"][0]["primitives"][0]["attributes"].pop("NORMAL"),
            lambda js: js.update(animations=[{"channels": [], "samplers": []}]),
            lambda js: js.update(skins=[{"joints": [1]}]),
            lambda js: js["meshes"][0]["primitives"][0].update(mode=1),
        ):
            js, b = F.sample_ship()
            mutate(js)
            self.assertEqual(st(run("ship_dart", (js, b)), "V05"), "fail")

    def test_v06_off_centre_uv(self):
        parts, emp = F.sample_ship_parts()
        u, v = F.PAL.uv("hull_300")
        parts[0] = (parts[0][0], (u + 0.01, v))
        self.assertEqual(st(run("ship_dart", hull_and_far(parts, emp)), "V06"), "fail")

    def test_v07_smooth_normal(self):
        self.assertEqual(st(run("ship_dart", F.sample_ship(smooth_first_vertex=True)), "V07"), "fail")

    def test_v08_size(self):
        rep = run("ship_dart", F.sample_ship(), with_asset(size_m=[9, 20, 3]))
        self.assertEqual(st(rep, "V08"), "fail")
        self.assertIn("Y", detail(rep, "V08"))
        self.assertEqual(st(run("ship_dart", F.sample_ship(), with_asset(size_m=[None, None, None])), "V08"), "pass")

    def test_v08_without_chart_entry_is_skip(self):
        self.assertEqual(st(run("ship_test_gear", F.sample_ship("ship_test_gear")), "V08"), "skip")

    def test_v09_origin(self):
        self.assertEqual(st(run("ship_dart", F.sample_ship(dy=3.0)), "V09"), "fail")
        self.assertEqual(st(run("str_pad", F.sample_pad()), "V09"), "pass")
        js, b = F.sample_pad()
        js["nodes"][1]["translation"] = [3.0, 0.0, 0.0]  # Hull shifted 3 m: footprint centre off
        self.assertEqual(st(run("str_pad", (js, b)), "V09"), "fail")

    def test_v09_foundation_too_deep(self):
        js, b = F.sample_pad()
        i = next(k for k, n in enumerate(js["nodes"]) if n["name"] == "Foundation")
        js["nodes"][i]["translation"] = [0.0, -2.0, 0.0]
        self.assertEqual(st(run("str_pad", (js, b)), "V09"), "fail")

    def test_v10_forward(self):
        nose, tail = (0.0, 6.4, -0.5), (0.0, -5.6, -0.5)
        rep = run("ship_dart", F.sample_ship(move={"HP_Nose": tail, "HP_Tail": nose}))
        self.assertEqual(st(rep, "V10"), "fail")

    def test_v11_ships_require_gear_0_to_2(self):
        for i in range(3):
            rep = run("ship_dart", F.sample_ship(drop=(f"HP_Gear_{i}",)))
            self.assertEqual(st(rep, "V11"), "fail", i)
            self.assertIn(f"HP_Gear_{i}", detail(rep, "V11"))
        self.assertEqual(st(run("ship_dart", F.sample_ship(drop=("HP_Nose",))), "V11"), "fail")

    def test_v11_gear_not_coplanar_or_off_axis(self):
        g = F.sample_ship_parts()[1]["HP_Gear_0"]
        rep = run("ship_dart", F.sample_ship(move={"HP_Gear_0": (g[0], g[1] + 0.2, g[2])}))
        self.assertEqual(st(rep, "V11"), "fail")
        rep = run("ship_dart", F.sample_ship(move={"HP_Gear_0": (g[0] + 2.0, g[1], g[2])}))
        self.assertEqual(st(rep, "V11"), "fail")

    def test_v11_budget_listed_hardpoints(self):
        rep = run("ship_dart", F.sample_ship(), with_asset(hardpoints=["HP_Tether"]))
        self.assertEqual(st(rep, "V11"), "fail")
        self.assertIn("HP_Tether", detail(rep, "V11"))
        js, b = F.sample_pad()
        js["nodes"] = [n for n in js["nodes"] if n["name"] != "HP_Dock"]
        js["nodes"][0]["children"] = list(range(1, len(js["nodes"])))
        self.assertEqual(st(run("str_pad", (js, b)), "V11"), "fail")  # pad-bearing structure needs HP_Dock

    def test_v12_degenerate(self):
        parts, emp = F.sample_ship_parts()
        p = (0.0, 0.0, 0.0)
        parts.append(((p, p, p), "hull_300"))
        self.assertEqual(st(run("ship_dart", hull_and_far(parts, emp)), "V12"), "fail")

    def test_v13_file_size(self):
        self.assertEqual(st(run("ship_dart", F.sample_ship(), with_asset(max_file_kb=1)), "V13"), "fail")

    def test_v14_team_area(self):
        parts, emp = F.sample_ship_parts()
        none = [(t, "hull_300") for t, _ in parts]
        allteam = [(t, "team_paint_mid") for t, _ in parts]
        for p in (none, allteam):
            self.assertEqual(st(run("ship_dart", hull_and_far(p, emp)), "V14"), "fail")

    def test_v15_names_and_required_parts(self):
        rep = run("ship_dart", F.sample_ship(extra_nodes=[{"name": "Bad-Name"}]))
        self.assertEqual(st(rep, "V15"), "fail")
        rep = run("ship_dart", F.sample_ship(far=False))
        self.assertEqual(st(rep, "V15"), "fail")
        self.assertIn("ShipDartFar", detail(rep, "V15"))
        js, b = F.sample_pad()
        for n in js["nodes"]:
            if n["name"] == "Foundation":
                n["name"] = "Base"
        self.assertEqual(st(run("str_pad", (js, b)), "V15"), "fail")
        rep = run("ship_dart", F.sample_ship(), with_asset(parts=["Turret"]))
        self.assertEqual(st(rep, "V15"), "fail")


class Container(unittest.TestCase):
    def test_garbage_and_truncation_fail_loudly(self):
        self.assertFalse(V.validate_bytes("ship_dart", b"nope", BUDGETS)["ok"])
        data = F.pack_glb(*F.sample_ship())
        rep = V.validate_bytes("ship_dart", data[:-40], BUDGETS)
        self.assertFalse(rep["ok"])
        self.assertEqual(rep["checks"][0]["id"], "GLB")

    def test_cli_exit_codes_and_report(self):
        with tempfile.TemporaryDirectory() as d:
            good, bad = Path(d) / "ship_dart.glb", Path(d) / "ship_scout.glb"
            good.write_bytes(F.pack_glb(*F.sample_ship()))
            bad.write_bytes(F.pack_glb(*F.sample_ship("ship_scout", root_name="Wrong")))
            ok = subprocess.run([sys.executable, str(SCRIPT), str(good), "--quiet"], capture_output=True, text=True)
            self.assertEqual(ok.returncode, 0, ok.stderr)
            report = Path(d) / "r.json"
            res = subprocess.run([sys.executable, str(SCRIPT), str(bad), "--report", str(report)],
                                 capture_output=True, text=True)
            self.assertEqual(res.returncode, 1)
            self.assertIn("ship_scout.glb: V02 fail", res.stderr)
            self.assertFalse(json.loads(res.stdout)["ok"])
            self.assertEqual(json.loads(report.read_text())["files"][0]["asset_id"], "ship_scout")
            both = subprocess.run([sys.executable, str(SCRIPT), d, "--quiet"], capture_output=True, text=True)
            self.assertEqual(both.returncode, 1)  # the directory scan finds the bad one
            gone = subprocess.run([sys.executable, str(SCRIPT), str(Path(d) / "nope.glb"), "--quiet"],
                                  capture_output=True, text=True)
            self.assertEqual(gone.returncode, 1)


class Budgets(unittest.TestCase):
    def test_every_inventory_asset_has_an_entry_with_the_07_s5_1_triangle_budget(self):
        want = {"ship_dart": 600, "ship_lancer": 900, "ship_bomber": 1200, "ship_scout": 450, "ship_hauler": 900,
                "gnd_harvester": 700, "gnd_siege_crawler": 900, "str_core": 3000, "str_outpost": 2000, "str_pylon": 300,
                "str_pad": 500, "str_solar": 600, "str_reactor": 900, "str_extractor": 800, "str_refinery": 1500,
                "str_shipyard": 1500, "str_vehicle_bay": 1300, "str_hangar": 1100, "str_sensor_mast": 700,
                "str_autocannon": 600, "str_flak": 800, "str_missile_tower": 800, "str_shield": 800,
                "str_rail_lance": 1200, "str_relay_station": 1500, "wreck_rubble_s": 80, "wreck_rubble_m": 150,
                "wreck_rubble_l": 300, "proj_bomb": 60, "proj_rocket": 80, "proj_rail_bolt": 12}
        for aid, tris in want.items():
            self.assertEqual(BUDGETS["assets"][aid]["max_tris"], tris, aid)
        props = [a for a in BUDGETS["assets"] if a.startswith("prop_")]
        self.assertEqual(len(props), 13)  # 07 s5.1 says 14 props but lists 13 ids; no 14th invented
        self.assertTrue(all(BUDGETS["assets"][a]["max_tris"] <= 80 for a in props))

    def test_scale_chart_and_far_rules(self):
        self.assertEqual(BUDGETS["assets"]["ship_dart"]["size_m"], [9, 12, 3])
        self.assertEqual(BUDGETS["assets"]["str_sensor_mast"]["size_m"], [13, 13, 90])
        for aid, e in BUDGETS["assets"].items():
            self.assertEqual(e.get("far", False), aid.split("_", 1)[0] in ("ship", "gnd", "str"), aid)
        self.assertIn("HP_Dock", BUDGETS["assets"]["str_hangar"]["hardpoints"])
        self.assertEqual(BUDGETS["classes"]["ship"]["max_file_kb"], 150)
        self.assertEqual(BUDGETS["classes"]["str"]["max_file_kb"], 300)

    def test_schema_rejects_bad_budgets(self):
        bad = copy.deepcopy(BUDGETS)
        bad["assets"]["ship_dart"]["max_tris"] = 0
        bad["assets"]["not_an_id"] = {"max_tris": 5}
        bad["extra"] = 1
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "b.json"
            p.write_text(json.dumps(bad))
            with self.assertRaises(V.GlbError):
                V.load_budgets(p)

    def test_pw_core_reads_the_same_budgets(self):
        self.assertEqual(core.tri_budget("ship_dart"), 600)
        self.assertEqual(core.tri_budget("ship_unknown"), 1200)  # class default
        self.assertIsNone(core.tri_budget("zzz_unknown"))


class MatchesFinalize(unittest.TestCase):
    """pw_core.run_checks (what pw.finalize() reports in Blender) and validate_glb agree on the shared checks."""

    def test_shared_checks_agree_with_run_checks_on_the_same_geometry(self):
        parts, emp = F.sample_ship_parts()
        tris = [t for t, _ in parts]
        uvs = [(F.PAL.uv(sw),) * 3 for _, sw in parts]
        rep = run("ship_dart", F.build_glb("ship_dart", {"Hull": parts}, emp))
        want = core.run_checks("ship_dart", "ship", {"tris": tris, "uvs": uvs, "smooth": 0}, emp, ["PW_Atlas"],
                               ["ShipDart", "Hull"], 600, F.PAL)
        have = {c["id"]: c for c in rep["checks"]}
        for c in want["checks"]:
            if c["id"] in ("V01", "V03", "V04", "V06", "V07", "V09", "V10", "V12", "V14"):
                self.assertEqual(have[c["id"]]["status"], c["status"], c["id"])
                if c["id"] in ("V06", "V14"):
                    self.assertEqual(have[c["id"]]["detail"], c["detail"], c["id"])


if __name__ == "__main__":
    unittest.main()
