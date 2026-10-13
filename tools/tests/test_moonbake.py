"""moonbake: determinism, committed outputs, M1-M11 pass/fail fixtures, ramp, PNG, CLI (TA-15)."""

from __future__ import annotations

import copy
import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent.parent
REPO = TOOLS.parent
sys.path.insert(0, str(TOOLS))

import gates  # noqa: E402

try:
    import numpy as np
    from moonbake import noise, pngio, ramp, validate
    from moonbake.bake import bake, render_files
    from moonbake.recipe import RecipeError, build_plan, load_recipe
except ImportError as exc:  # numpy is installed by CI (tools/requirements.txt)
    gates.numpy_import_failed(exc)
    np = None

TINY_DIR = REPO / "godot/content/maps/tiny_test"
TINY = TINY_DIR / "recipe.json"


def results_by_code(results) -> dict:
    return {r.code: r for r in results}


@unittest.skipIf(np is None, gates.NUMPY_SKIP)
class Determinism(unittest.TestCase):
    def test_same_recipe_same_bytes(self) -> None:
        rec = load_recipe(TINY)
        a, b = render_files(bake(rec)), render_files(bake(copy.deepcopy(rec)))
        self.assertEqual(a.keys(), b.keys())
        for name in a:
            self.assertEqual(a[name], b[name], name)

    def test_rough_recipe_deterministic(self) -> None:
        rec = _rough()
        self.assertEqual(render_files(bake(rec))["meta.json"], render_files(bake(copy.deepcopy(rec)))["meta.json"])

    def test_seed_changes_output(self) -> None:
        rec = _rough()
        other = copy.deepcopy(rec)
        other["seed"] += 1
        self.assertNotEqual(render_files(bake(rec))["meta.json"], render_files(bake(other))["meta.json"])

    def test_committed_tiny_test_matches_fresh_bake(self) -> None:
        gates.require_blobs(TINY_DIR)
        meta = json.loads((TINY_DIR / "meta.json").read_text(encoding="utf-8"))
        files = render_files(bake(load_recipe(TINY)))
        for name, want in meta["outputs"].items():
            self.assertEqual(hashlib.sha256(files[name]).hexdigest(), want, name)
            self.assertEqual(hashlib.sha256((TINY_DIR / name).read_bytes()).hexdigest(), want, f"committed {name}")
        self.assertEqual(json.loads(files["meta.json"])["map_hash"], meta["map_hash"])

    def test_committed_radius_variant_matches_fresh_bake(self) -> None:
        """S-WORLD-1 R = 6,000 variant (TA-16): the only radius the schema accepts; outputs committed and fresh."""
        d = REPO / "godot/content/maps/s_world1_r6000"
        gates.require_blobs(d)
        meta = json.loads((d / "meta.json").read_text(encoding="utf-8"))
        files = render_files(bake(load_recipe(d / "recipe.json")))
        self.assertEqual(meta["radius_m"], 6000.0)
        for name, want in meta["outputs"].items():
            self.assertEqual(hashlib.sha256(files[name]).hexdigest(), want, name)
            self.assertEqual(hashlib.sha256((d / name).read_bytes()).hexdigest(), want, f"committed {name}")

    def test_output_sizes(self) -> None:
        files = render_files(bake(load_recipe(TINY)))
        for f in range(6):
            self.assertEqual(len(files[f"face{f}.height.u16"]), 2 * 128 * 128)
            self.assertEqual(len(files[f"face{f}.biome.u8"]), 128 * 128)
            self.assertEqual(len(files[f"face{f}.slope.u8"]), 128 * 128)
            self.assertEqual(len(files[f"face{f}.path.u8"]), 256 * 256)

    def test_hash_vector(self) -> None:
        z = np.zeros(1, dtype=np.int64)
        self.assertEqual(float(noise.hash32(z, z, z, 0)[0]), float(noise.hash32(z, z, z, 0)[0]))
        self.assertNotEqual(float(noise.hash32(z, z, z, 0)[0]), float(noise.hash32(z + 1, z, z, 0)[0]))
        self.assertTrue(0.0 <= float(noise.hash32(z - 5, z + 7, z, 99)[0]) < 1.0)
        self.assertEqual(noise.SplitMix64(1).next_u64(), 10451216379200822465)  # reference splitmix64 output


def _rough() -> dict:
    rec = load_recipe(TINY)
    rec["base_noise"].update({"amp_m": 90, "freq_per_circumference": 12, "octaves": 4, "warp_m": 200})
    rec["highlands"] = {"amplitude_m": 150, "mask_frequency": 1.5, "threshold": 0.5, "softness": 0.1}
    rec["regions"] = [{"kind": "mare", "lat": 8, "lon": 45, "radius_m": 1500, "floor_m": -200, "edge_m": 400}]
    rec["craters"] = {"explicit": [{"lat": 30, "lon": 45, "diam_m": 1200, "depth_m": 150, "rim_m": 80, "ejecta_m": 1800}],
                      "scatter": {"per_wedge": 10, "diam_m": [100, 400], "power": 2.0, "seed_offset": 7}}
    rec["rilles"] = [{"path": [[10, 32], [22, 45], [28, 57]], "width_m": 160, "depth_m": 70}]
    return rec


@unittest.skipIf(np is None, gates.NUMPY_SKIP)
class Validation(unittest.TestCase):
    """Each check passes on the good recipe and fails on exactly its fixture."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.rec = load_recipe(TINY)
        cls.bake = bake(cls.rec)
        cls.files = render_files(cls.bake)

    def static(self, rec: dict) -> dict:
        return results_by_code(validate.validate_static(build_plan(rec)))

    def baked(self, rec: dict) -> dict:
        b = bake(rec)
        return results_by_code(validate.validate_baked(b, render_files(b)))

    def mutated(self, fn) -> dict:
        rec = copy.deepcopy(self.rec)
        fn(rec)
        return rec

    def test_good_recipe_passes_everything(self) -> None:
        res = self.static(self.rec)
        res.update(results_by_code(validate.validate_baked(self.bake, self.files)))
        self.assertEqual({k: v.msg for k, v in res.items() if not v.ok}, {})
        for code in ("M1", "M2", "M3", "M4a", "M4b", "M5", "M6", "M7", "M8", "M9", "M10", "M11"):
            self.assertIn(code, res)

    def test_m1_relief(self) -> None:
        res = self.baked(self.mutated(lambda r: r["base_noise"].update(amp_m=1200)))
        self.assertFalse(res["M1"].ok)

    def test_m2_and_m3_slopes(self) -> None:
        def rough(r: dict) -> None:
            r["base_noise"].update(amp_m=500, freq_per_circumference=60, octaves=3)
            r["slots"].update(flatten_radius_m=0, flatten_edge_m=0)
        res = self.baked(self.mutated(rough))
        self.assertFalse(res["M2"].ok)
        self.assertFalse(res["M3"].ok)

    def test_m4a_day_side_cold_trap_rejected(self) -> None:
        def north(r: dict) -> None:
            r["resources"]["slot_features"][1]["bearing_deg"] = 0
        res = self.static(self.mutated(north))
        self.assertFalse(res["M4a"].ok)
        self.assertIn("home_trap", res["M4a"].msg)

    def test_m4b_shallow_trap(self) -> None:
        b = bake(self.rec)
        for f in range(6):
            b.height[f][:] = 30000  # level the world: no floor below any rim
        s = validate.Sampler(b)
        self.assertFalse(validate.m4_depth(b, s).ok)
        self.assertTrue(validate.m4_depth(self.bake, validate.Sampler(self.bake)).ok)

    def test_m5_asymmetric_wedges(self) -> None:
        b = bake(self.rec)
        b.height[4][:, :64] += 6000  # one-sided bump on the Noon face
        self.assertFalse(validate.m5_symmetry(b, validate.Sampler(b)).ok)

    def test_m6_distances(self) -> None:
        res = self.static(self.mutated(lambda r: r["resources"]["slot_features"][0].update(distance_m=900)))
        self.assertFalse(res["M6"].ok)
        res = self.static(self.mutated(lambda r: r["resources"]["slot_features"][1].update(bearing_deg=0)))
        self.assertFalse(res["M6"].ok)

    def test_m7_spacing(self) -> None:
        def crowd(r: dict) -> None:
            r["resources"]["slot_features"][1].update(bearing_deg=90, distance_m=1250)  # 50 m from the ore field
        self.assertFalse(self.static(self.mutated(crowd))["M7"].ok)

    def test_m8_all_impassable(self) -> None:
        b = bake(self.rec)
        self.assertTrue(validate.m8_connectivity(b).ok)
        for f in range(6):
            b.path[f][:] = 255
        self.assertFalse(validate.m8_connectivity(b).ok)

    def test_m8_wall_between_core_and_ore(self) -> None:
        b = bake(self.rec)
        node = next(n for n in b.plan.nodes if n.id == "field_a_s0")
        core = b.plan.slots[0]
        g = validate.GRID_PATH
        # block every path cell whose centre is within 150 m of the ore field and not within 260 m: a full ring
        for f in range(6):
            t = (np.arange(g) + 0.5) / g
            u, v = np.meshgrid(t, t)
            from moonbake import sphere
            d = sphere.face_uv_to_dir(f, u, v)
            dist = sphere.great_circle_m(d, node.c)
            b.path[f][(dist > 300.0) & (dist < 420.0)] = 255
        self.assertFalse(validate.m8_connectivity(b).ok)
        self.assertIsNotNone(core)

    def test_m9_coverage(self) -> None:
        b = bake(self.rec)
        b.plan.recipe = dict(b.plan.recipe, id="cradle")  # tiny_test is all highland-or-mare flat: not 45/30/10
        self.assertFalse(validate.m9_biomes(b).ok)
        self.assertTrue(validate.m9_biomes(self.bake).ok)  # no row: skipped

    def test_m10_size(self) -> None:
        old = validate.M10_MAX_BYTES
        validate.M10_MAX_BYTES = 10
        try:
            self.assertFalse(validate.m10_size(self.bake, self.files).ok)
        finally:
            validate.M10_MAX_BYTES = old
        self.assertTrue(validate.m10_size(self.bake, self.files).ok)

    def test_m11_flatten_disc_on_cube_edge(self) -> None:
        def wide(r: dict) -> None:
            r["slots"].update(flatten_radius_m=2000, flatten_edge_m=1000)
        res = self.static(self.mutated(wide))
        self.assertFalse(res["M11"].ok)
        self.assertIn("cube edge", res["M11"].msg)

    def test_node_inside_flatten_disc(self) -> None:
        res = self.static(self.mutated(lambda r: r["resources"]["slot_features"][0].update(distance_m=200)))
        self.assertFalse(res["X1"].ok)

    def test_schema_violation_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            bad = copy.deepcopy(self.rec)
            bad["radius_m"] = 5000
            p = Path(td) / "recipe.json"
            p.write_text(json.dumps(bad), encoding="utf-8")
            with self.assertRaises(RecipeError):
                load_recipe(p)


FIXTURES = REPO / "tools/tests/fixtures/maps"
# ART-37: one recipe per validate check (07 s9.5), each failing exactly its own code; good passes everything.
FIXTURE_CODES = {"good": None, "m01_relief": "M1", "m02_slot_slope": "M2", "m03_ore_slope": "M3",
                 "m04a_day_side_trap": "M4a", "m04b_shallow_trap": "M4b", "m05_asymmetry": "M5",
                 "m06_ore_distance": "M6", "m07_node_spacing": "M7", "m08_disconnected": "M8",
                 "m09_biome_coverage": "M9", "m10_size": "M10", "m11_cube_edge": "M11"}


@unittest.skipIf(np is None, gates.NUMPY_SKIP)
class MapFixtures(unittest.TestCase):
    """The ART-37 fixtures run through the TA-15 validator: each fails only its check; good passes all."""

    def failing(self, name: str) -> set[str]:
        rec = load_recipe(FIXTURES / name / "recipe.json")  # schema must pass, so the failure is the check's own
        res = {r.code: r for r in validate.validate_static(build_plan(rec))}
        b = bake(rec)
        res.update({r.code: r for r in validate.validate_baked(b, render_files(b))})
        return {k for k, v in res.items() if not v.ok}

    def test_each_fixture_fails_exactly_its_check(self) -> None:
        for name, code in FIXTURE_CODES.items():
            with self.subTest(fixture=name):
                self.assertEqual(self.failing(name), set() if code is None else {code})

    def test_fixture_directories_match_the_table(self) -> None:
        self.assertEqual(sorted(p.name for p in FIXTURES.iterdir() if p.is_dir()), sorted(FIXTURE_CODES))

    def test_every_check_has_a_fixture(self) -> None:
        codes = {c for c in FIXTURE_CODES.values() if c}
        self.assertEqual(codes, {"M1", "M2", "M3", "M4a", "M4b", "M5", "M6", "M7", "M8", "M9", "M10", "M11"})


@unittest.skipIf(np is None, gates.NUMPY_SKIP)
class RampAndPng(unittest.TestCase):
    def test_png_round_trip_and_stored_is_stable(self) -> None:
        img = (np.arange(8 * 5 * 4) % 251).astype(np.uint8).reshape(8, 5, 4)
        a, b = pngio.encode_png(img, stored=True), pngio.encode_png(img, stored=True)
        self.assertEqual(a, b)
        self.assertTrue(np.array_equal(pngio.decode_png(a), img))
        self.assertTrue(np.array_equal(pngio.decode_png(pngio.encode_png(img)), img))

    def test_ramp_image(self) -> None:
        img = ramp.build_ramp_image(ramp.load_ramps(Path("/nonexistent/biome_ramps.json")))
        self.assertEqual(img.shape, (16, 64, 4))
        self.assertEqual(tuple(img[0, 0, :3]), (0x30, 0x34, 0x3F))     # mare low
        self.assertEqual(tuple(img[0, 63, :3]), (0x51, 0x57, 0x6A))    # mare high
        self.assertEqual(tuple(img[4, 63, :3]), (0xB5, 0xD8, 0xEC))    # cold_trap high
        self.assertEqual(tuple(img[9, 10, :3]), (255, 0, 255))         # reserved
        self.assertTrue((img[..., 3] == 255).all())

    def test_ramp_from_json_hook(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            j = Path(td) / "biome_ramps.json"
            j.write_text(json.dumps({"biomes": {"mare": {"id": 0, "low": "#000000", "mid": "#808080", "high": "#ffffff"}}}),
                         encoding="utf-8")
            out = Path(td) / "moon_ramp.png"
            data = ramp.build_ramp(out, j)
            img = pngio.decode_png(out.read_bytes())
            self.assertEqual(tuple(img[0, 0, :3]), (0, 0, 0))
            self.assertEqual(tuple(img[0, 63, :3]), (255, 255, 255))
            self.assertEqual(data, ramp.build_ramp(out, j))

    def test_committed_ramp_is_fresh(self) -> None:
        p = REPO / "godot/assets/textures/moon_ramp.png"
        gates.require_blobs(p)
        self.assertEqual(p.read_bytes(), pngio.encode_png(ramp.build_ramp_image(ramp.load_ramps()), stored=True))


@unittest.skipIf(np is None, gates.NUMPY_SKIP)
class Cli(unittest.TestCase):
    def run_cli(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run([sys.executable, str(TOOLS / "moonbake"), *args], capture_output=True, text=True)

    def test_validate_tiny(self) -> None:
        r = self.run_cli("validate", str(TINY), "--quiet")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("13/13", r.stdout)

    def test_check_and_bake(self) -> None:
        gates.require_blobs(TINY_DIR)
        r = self.run_cli("check", str(TINY), "--quiet")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        with tempfile.TemporaryDirectory() as td:
            r = self.run_cli("bake", str(TINY), "--out", td, "--quiet", "--ramp")
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertTrue((Path(td) / "preview.png").is_file())
            self.assertTrue((Path(td) / "moon_ramp.png").is_file())
            self.assertEqual((Path(td) / "meta.json").read_bytes(), (TINY_DIR / "meta.json").read_bytes())

    def test_bad_recipe_exits_1(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "recipe.json"
            p.write_text(json.dumps({"schema_version": 1}), encoding="utf-8")
            self.assertEqual(self.run_cli("validate", str(p)).returncode, 1)


if __name__ == "__main__":
    unittest.main()
