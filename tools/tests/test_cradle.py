"""ART-28: the `cradle` map passes M1-M11 (and X1) at face_resolution 1024 and its committed outputs are fresh."""

from __future__ import annotations

import hashlib
import json
import sys
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent.parent
REPO = TOOLS.parent
sys.path.insert(0, str(TOOLS))

import gates  # noqa: E402

try:
    import numpy as np
    from moonbake import validate
    from moonbake.bake import bake, render_files
    from moonbake.recipe import build_plan, load_recipe
except ImportError as exc:
    gates.numpy_import_failed(exc)
    np = None

CRADLE = REPO / "godot/content/maps/cradle"


@unittest.skipIf(np is None, gates.NUMPY_SKIP)
class Cradle(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        gates.require_blobs(CRADLE)
        cls.recipe = load_recipe(CRADLE / "recipe.json")
        cls.baked = bake(cls.recipe)
        cls.files = render_files(cls.baked)

    def test_recipe_shape(self) -> None:
        self.assertEqual(self.recipe["id"], "cradle")
        self.assertEqual(self.recipe["face_resolution"], 1024)
        self.assertEqual(self.recipe["slots"]["count"], 8)

    def test_every_check_passes(self) -> None:
        results = validate.validate_static(build_plan(self.recipe)) + validate.validate_baked(self.baked, self.files)
        self.assertEqual({r.code for r in results} >= {f"M{i}" for i in (1, 2, 3, 5, 7, 8, 9, 10, 11)}, True)
        failed = [str(r) for r in results if not r.ok]
        self.assertEqual(failed, [])

    def test_committed_outputs_are_fresh(self) -> None:
        meta = json.loads((CRADLE / "meta.json").read_text(encoding="utf-8"))
        for name, want in meta["outputs"].items():
            self.assertEqual(hashlib.sha256(self.files[name]).hexdigest(), want, name)
            self.assertEqual(hashlib.sha256((CRADLE / name).read_bytes()).hexdigest(), want, f"committed {name}")


if __name__ == "__main__":
    unittest.main()
