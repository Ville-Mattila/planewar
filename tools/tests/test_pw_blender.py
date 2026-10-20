"""pw.py inside real Blender (ART-04 acceptance): fresh-file recipes build assets, and validate_glb.py (ART-05) run on the
exported glb agrees with the finalize() report. Skipped when no Blender >= 4.2 is found ($BLENDER_BIN, PATH, Program Files)."""

from __future__ import annotations

import json
import struct
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(TOOLS / "blender"))
sys.path.insert(0, str(TOOLS / "blender" / "lib"))
sys.path.insert(0, str(TOOLS / "art"))

import run_headless  # noqa: E402
import validate_glb  # noqa: E402

BLENDER = run_headless.find_blender()
SELFTEST = TOOLS / "blender" / "selftest"


def read_glb(path: Path) -> tuple[dict, bytes]:
    data = path.read_bytes()
    magic, version, _length = struct.unpack_from("<4sII", data, 0)
    assert magic == b"glTF" and version == 2
    off, js, binary = 12, None, b""
    while off < len(data):
        clen, ctype = struct.unpack_from("<II", data, off)
        body = data[off + 8:off + 8 + clen]
        if ctype == 0x4E4F534A:
            js = json.loads(body)
        elif ctype == 0x004E4942:
            binary = body
        off += 8 + clen
    return js, binary


@unittest.skipIf(BLENDER is None, "no Blender >= 4.2 found (CI installs it; set BLENDER_BIN)")
class BlenderRecipes(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.tmp = tempfile.TemporaryDirectory()
        cls.out = cls.tmp.name
        cls.runs: dict = {}
        for name in ("prop_test_box", "ship_test_gear"):
            res = run_headless.run(str(SELFTEST / f"{name}.py"), cls.out)
            cls.runs[name] = res
            if res.returncode != 0:
                print(res.stdout, res.stderr, file=sys.stderr)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.tmp.cleanup()

    def report(self, name: str) -> dict:
        res = self.runs[name]
        self.assertEqual(res.returncode, 0, res.stdout[-2000:] + res.stderr[-2000:])
        line = next(ln for ln in res.stdout.splitlines() if ln.startswith("PW_REPORT "))
        return json.loads(line[len("PW_REPORT "):])

    def glb(self, name: str):
        path = Path(self.out) / f"{name}.glb"
        self.assertTrue(path.is_file())
        return read_glb(path)

    def statuses(self, rep: dict) -> dict:
        return {c["id"]: c["status"] for c in rep["checks"]}

    def test_box_report_ok_and_counts(self):
        rep = self.report("prop_test_box")
        self.assertTrue(rep["ok"])
        self.assertEqual(rep["tris"], 12)
        self.assertEqual(rep["objects"], ["HP_Dock", "Hull"])

    def test_box_glb_structure(self):
        js, _ = self.glb("prop_test_box")
        self.assertEqual([m["name"] for m in js["materials"]], ["PW_Atlas"])
        self.assertNotIn("images", js)
        self.assertNotIn("animations", js)
        self.assertNotIn("skins", js)
        names = {n["name"] for n in js["nodes"]}
        self.assertEqual(names, {"PropTestBox", "Hull", "HP_Dock"})
        roots = js["scenes"][0]["nodes"]
        self.assertEqual(len(roots), 1)
        self.assertEqual(js["nodes"][roots[0]]["name"], "PropTestBox")
        attrs = set(js["meshes"][0]["primitives"][0]["attributes"])
        self.assertEqual(attrs, {"POSITION", "NORMAL", "TEXCOORD_0"})  # V05

    def test_finalize_report_matches_validate_glb(self):
        """ART-05: the authoritative tools/art/validate_glb.py run on the exported glb must give the finalize() verdicts
        for every check finalize() computes (it skips only V02, V05, V08, V13, which need the glb)."""
        budgets = validate_glb.load_budgets()
        for name in ("prop_test_box", "ship_test_gear"):
            rep = self.report(name)
            data = (Path(self.out) / f"{name}.glb").read_bytes()
            back = validate_glb.validate_bytes(name, data, budgets)
            have, want = self.statuses(back), self.statuses(rep)
            self.assertEqual(back["tris"], rep["tris"], name)
            for cid, status in want.items():
                if status != "skip":
                    self.assertEqual(have[cid], status, f"{name} {cid}")
            for cid in ("V02", "V05", "V13"):  # the glb-only checks pass on a recipe export
                self.assertEqual(have[cid], "pass", f"{name} {cid}")
            for cid in ("V06", "V14"):
                detail = lambda r: next(c["detail"] for c in r["checks"] if c["id"] == cid)  # noqa: E731
                self.assertEqual(detail(back), detail(rep), f"{name} {cid} detail")

    def test_ship_gear_and_orientation(self):
        rep = self.report("ship_test_gear")
        st = self.statuses(rep)
        for cid in ("V09", "V10", "V11"):
            self.assertEqual(st[cid], "pass", cid)
        js, _ = self.glb("ship_test_gear")
        by = {n["name"]: n for n in js["nodes"]}
        for h in ("HP_Nose", "HP_Tail", "HP_Gear_0", "HP_Gear_1", "HP_Gear_2"):
            self.assertIn(h, by)
        # nose +Y in Blender becomes -Z in glTF (Godot forward)
        self.assertLess(by["HP_Nose"]["translation"][2], by["HP_Tail"]["translation"][2])
        feet = [by[f"HP_Gear_{i}"]["translation"][2] for i in range(3)]  # V11: coplanar within 5 cm
        self.assertLess(max(feet) - min(feet), 0.05)
        self.assertGreater(min(feet), by["HP_Tail"]["translation"][2])  # feet are behind the nozzle (glTF +Z)
        self.assertEqual(rep["tris"], 92)

    def test_recipe_is_deterministic(self):
        with tempfile.TemporaryDirectory() as other:
            res = run_headless.run(str(SELFTEST / "ship_test_gear.py"), other)
            self.assertEqual(res.returncode, 0)
            self.assertEqual((Path(other) / "ship_test_gear.glb").read_bytes(),
                             (Path(self.out) / "ship_test_gear.glb").read_bytes())

    def test_second_begin_replaces_only_same_collection(self):
        res = run_headless.run(str(SELFTEST / "begin_twice.py"), self.out)
        self.assertEqual(res.returncode, 0, res.stdout[-1500:] + res.stderr[-1500:])
        self.assertIn("BEGIN_TWICE_OK", res.stdout)

    def test_bad_recipe_fails_exit_code(self):
        res = run_headless.run(str(SELFTEST / "prop_bad_swatch.py"), self.out)
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("unknown swatch", res.stdout + res.stderr)

    def test_finalize_flags_defects(self):
        res = run_headless.run(str(SELFTEST / "prop_defects.py"), self.out)
        self.assertEqual(res.returncode, 0, res.stdout[-1500:] + res.stderr[-1500:])
        self.assertIn("DEFECTS_OK", res.stdout)


if __name__ == "__main__":
    unittest.main()
