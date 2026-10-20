"""pw.py inside real Blender (ART-04 acceptance): fresh-file recipes build assets, and the pure-Python glb read-back
agrees with the finalize() report. Skipped when no Blender >= 4.2 is found ($BLENDER_BIN, PATH, Program Files)."""

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

import pw_core as core  # noqa: E402
import run_headless  # noqa: E402

BLENDER = run_headless.find_blender()
SELFTEST = TOOLS / "blender" / "selftest"
_CT = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}
_NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


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


def accessor(js: dict, binary: bytes, idx: int) -> list:
    acc = js["accessors"][idx]
    bv = js["bufferViews"][acc["bufferView"]]
    n, comps = acc["count"], _NC[acc["type"]]
    fmt = "<" + _CT[acc["componentType"]] * comps
    size = struct.calcsize(fmt)
    stride = bv.get("byteStride", size)
    base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    rows = [struct.unpack_from(fmt, binary, base + i * stride) for i in range(n)]
    return [r[0] for r in rows] if comps == 1 else rows


def glb_geometry(js: dict, binary: bytes) -> dict:
    """Triangles in glTF space (Y up) converted back to Blender space (x, -z, y), UVs untouched."""
    tris, uvs, flat_bad = [], [], 0
    for mesh in js["meshes"]:
        for prim in mesh["primitives"]:
            pos = accessor(js, binary, prim["attributes"]["POSITION"])
            nor = accessor(js, binary, prim["attributes"]["NORMAL"])
            uv = accessor(js, binary, prim["attributes"]["TEXCOORD_0"])
            idx = accessor(js, binary, prim["indices"])
            for i in range(0, len(idx), 3):
                a, b, c = idx[i:i + 3]
                tri = tuple((pos[k][0], -pos[k][2], pos[k][1]) for k in (a, b, c))
                n = core.tri_normal(tri)
                ln = max(sum(x * x for x in n) ** 0.5, 1e-30)
                gn = nor[a]
                bn = (gn[0], -gn[2], gn[1])
                if abs(bn[0] - n[0] / ln) + abs(bn[1] - n[1] / ln) + abs(bn[2] - n[2] / ln) > 3e-3:
                    flat_bad += 1
                tris.append(tri)
                uvs.append(tuple(uv[k] for k in (a, b, c)))
    return {"tris": tris, "uvs": uvs, "smooth": flat_bad}


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

    def test_finalize_report_matches_glb_read_back(self):
        """The same pure-Python rules run on the exported glb must give the finalize() verdicts (V03-V07, V12, V14)."""
        pal = core.Palette()
        for name, cls in (("prop_test_box", "prop"), ("ship_test_gear", "ship")):
            rep = self.report(name)
            js, binary = self.glb(name)
            geo = glb_geometry(js, binary)
            self.assertEqual(len(geo["tris"]), rep["tris"], name)
            back = core.run_checks(name, cls, geo, {}, [m["name"] for m in js["materials"]],
                                   [n["name"] for n in js["nodes"]], None, pal)
            have, want = self.statuses(back), self.statuses(rep)
            for cid in ("V01", "V03", "V04", "V06", "V07", "V12", "V14", "V15"):
                self.assertEqual(have[cid], want[cid], f"{name} {cid}")
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
