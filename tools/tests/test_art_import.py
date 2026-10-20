"""tools/art/write_import.py and godot/assets/_pipeline/post_import_asset.gd (ART-05, docs/07 s4.6).

The Godot end-to-end test needs a Godot 4.7.2 editor binary ($GODOT_BIN or `godot` on PATH) and is skipped without one
(the CI art job has it). It imports a generated glb into a throwaway project and checks the result: HP_* become
Marker3D, Far meshes lose shadows and get visibility ranges."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent.parent
REPO = TOOLS.parent
sys.path.insert(0, str(TOOLS / "tests"))
sys.path.insert(0, str(TOOLS / "art"))

import glb_fixture as F  # noqa: E402
import write_import as W  # noqa: E402

GODOT = os.environ.get("GODOT_BIN") or shutil.which("godot")
SKIP_GODOT = "no Godot 4.7.2 editor binary ($GODOT_BIN / PATH)"


def real_debug_section() -> str:
    """The [debug] section (warnings as errors, level 2) of the real godot/project.godot, read, not copied by hand."""
    text = (REPO / "godot" / "project.godot").read_text(encoding="utf-8")
    start = text.index("[debug]")
    end = text.find("\n[", start + 1)
    return text[start:end if end != -1 else len(text)].strip() + "\n"


class Render(unittest.TestCase):
    def test_template_keys_match_the_import_dock(self):
        text = W.render("res://assets/models/ships/ship_dart.glb")
        for line in (
            'importer="scene"', 'type="PackedScene"', 'nodes/root_type="Node3D"', "nodes/apply_root_scale=true",
            "nodes/root_scale=1.0", "meshes/ensure_tangents=false", "meshes/generate_lods=true",
            "meshes/create_shadow_meshes=true", "meshes/light_baking=0", "animation/import=false",
            'import_script/path="res://assets/_pipeline/post_import_asset.gd"',
            'source_file="res://assets/models/ships/ship_dart.glb"',
        ):
            self.assertIn(line + "\n", text, line)
        self.assertNotIn("$", text)

    def test_props_have_no_shadow_meshes(self):
        for res in ("props/prop_boulder_a", "props/wreck_rubble_s", "projectiles/proj_bomb"):
            self.assertIn("meshes/create_shadow_meshes=false", W.render(f"res://assets/models/{res}.glb"), res)
        for res in ("ships/ship_dart", "ground/gnd_harvester", "structures/str_core"):
            self.assertIn("meshes/create_shadow_meshes=true", W.render(f"res://assets/models/{res}.glb"), res)

    def test_uid_and_hash_are_deterministic_and_distinct(self):
        a = W.render("res://assets/models/ships/ship_dart.glb")
        self.assertEqual(a, W.render("res://assets/models/ships/ship_dart.glb"))
        self.assertNotEqual(a, W.render("res://assets/models/ships/ship_lancer.glb"))
        uid = W.uid_text("res://assets/models/ships/ship_dart.glb")
        self.assertRegex(uid, r"^uid://[a-y0-9]{12,13}$")

    def test_rejects_bad_names(self):
        with self.assertRaises(ValueError):
            W.render("res://assets/models/ships/Dart.glb")

    def test_cli_writes_then_check_is_clean_then_stale_fails(self):
        with tempfile.TemporaryDirectory() as d:
            proj = Path(d)
            glb = proj / "assets" / "models" / "ships" / "ship_dart.glb"
            glb.parent.mkdir(parents=True)
            glb.write_bytes(F.pack_glb(*F.sample_ship()))
            run = lambda *a: subprocess.run([sys.executable, str(TOOLS / "art" / "write_import.py"), *a],  # noqa: E731
                                            capture_output=True, text=True)
            self.assertEqual(run(str(glb), "--project", d, "--check").returncode, 1)  # missing
            self.assertEqual(run(str(glb), "--project", d).returncode, 0)
            self.assertEqual(run(str(glb), "--project", d, "--check").returncode, 0)
            imp = Path(str(glb) + ".import")
            imp.write_text(imp.read_text().replace("generate_lods=true", "generate_lods=false"))
            res = run(str(glb), "--project", d, "--check")
            self.assertEqual(res.returncode, 1)
            self.assertIn("stale", res.stderr)
            self.assertEqual(run(str(glb), "--project", d).returncode, 0)  # rewrites
            self.assertEqual(run(str(glb), "--project", d, "--check").returncode, 0)

    def test_committed_imports_are_current(self):
        glbs = sorted((REPO / "godot" / "assets" / "models").rglob("*.glb")) if (REPO / "godot" / "assets" / "models").is_dir() else []
        for glb in glbs:
            self.assertEqual(W.main([str(glb), "--check"]), 0, glb)


@unittest.skipIf(GODOT is None, SKIP_GODOT)
class GodotImport(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.tmp = tempfile.TemporaryDirectory()
        cls.proj = Path(cls.tmp.name)
        (cls.proj / "project.godot").write_text(
            'config_version=5\n[application]\nconfig/name="art_import_test"\n\n' + real_debug_section())
        shutil.copytree(REPO / "godot" / "assets" / "_pipeline", cls.proj / "assets" / "_pipeline")
        (cls.proj / "tools").mkdir()
        shutil.copy(REPO / "godot" / "tools" / "check_post_import.gd", cls.proj / "tools" / "check_post_import.gd")
        (cls.proj / "ship_dart.glb").write_bytes(F.pack_glb(*F.sample_ship()))
        # same glb with the post-import script switched off: the check must reject it
        (cls.proj / "str_pad.glb").write_bytes(F.pack_glb(*F.sample_pad()))
        W.main([str(cls.proj / "ship_dart.glb"), "--project", str(cls.proj)])
        W.main([str(cls.proj / "str_pad.glb"), "--project", str(cls.proj)])
        imp = cls.proj / "str_pad.glb.import"
        imp.write_text(imp.read_text().replace('import_script/path="res://assets/_pipeline/post_import_asset.gd"',
                                               'import_script/path=""'))
        cls.imported = subprocess.run([GODOT, "--headless", "--path", str(cls.proj), "--import"], capture_output=True,
                                      text=True, timeout=300)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.tmp.cleanup()

    def check(self, res: str):
        return subprocess.run([GODOT, "--headless", "--path", str(self.proj), "-s", "res://tools/check_post_import.gd",
                               "--", res], capture_output=True, text=True, timeout=120)

    def test_project_uses_the_real_warning_settings_and_import_log_is_clean(self):
        self.assertIn("unsafe_cast=2", (self.proj / "project.godot").read_text())
        log = self.imported.stdout + self.imported.stderr
        for bad in ("SCRIPT ERROR", "Parse Error", "Failed to load script"):
            self.assertNotIn(bad, log)

    def test_post_import_converts_hardpoints_and_sets_far_ranges(self):
        self.assertIn("post_import_asset: ship_dart 166 tris", self.imported.stdout + self.imported.stderr)
        res = self.check("res://ship_dart.glb")
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("OK 5 markers", res.stdout)  # HP_Nose, HP_Tail, HP_Gear_0..2

    def test_without_the_post_import_script_the_check_fails(self):
        res = self.check("res://str_pad.glb")
        self.assertEqual(res.returncode, 1, res.stdout + res.stderr)
        self.assertIn("expected Marker3D", res.stderr)


if __name__ == "__main__":
    unittest.main()
