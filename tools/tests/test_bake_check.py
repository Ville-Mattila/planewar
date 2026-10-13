"""bake-check (TA-17, 03 s8.6): committed map files equal a fresh bake; a stale meta.json or binary fails."""

from __future__ import annotations

import contextlib
import io
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(TOOLS))

import gates  # noqa: E402

try:
    import bake_check
except ImportError as exc:  # numpy is installed by CI (tools/requirements.txt)
    gates.numpy_import_failed(exc)
    bake_check = None

TINY_DIR = TOOLS.parent / "godot/content/maps/tiny_test"


@unittest.skipIf(bake_check is None, gates.NUMPY_SKIP)
class BakeCheck(unittest.TestCase):
    def setUp(self) -> None:
        gates.require_blobs(TINY_DIR)  # every case compares committed binaries with a fresh bake

    def copy_of_tiny(self, td: str) -> Path:
        dst = Path(td) / "tiny_test"
        shutil.copytree(TINY_DIR, dst, ignore=shutil.ignore_patterns("preview.png"))
        return dst

    def test_committed_tiny_test_matches(self) -> None:
        self.assertEqual(bake_check.check_map(TINY_DIR), [])

    def test_stale_meta_json_fails(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            d = self.copy_of_tiny(td)
            meta = json.loads((d / "meta.json").read_text(encoding="utf-8"))
            meta["recipe_sha256"] = "0" * 64  # a recipe edit without a re-bake
            (d / "meta.json").write_text(json.dumps(meta, indent=1, sort_keys=True) + "\n", encoding="utf-8")
            problems = bake_check.check_map(d)
            self.assertEqual(len(problems), 1, problems)
            self.assertIn("meta.json", problems[0])

    def test_edited_binary_fails(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            d = self.copy_of_tiny(td)
            raw = bytearray((d / "face3.height.u16").read_bytes())
            raw[10] ^= 0xFF
            (d / "face3.height.u16").write_bytes(bytes(raw))
            problems = bake_check.check_map(d)
            self.assertEqual(len(problems), 1, problems)
            self.assertIn("face3.height.u16", problems[0])

    def test_missing_meta_fails(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            d = self.copy_of_tiny(td)
            (d / "meta.json").unlink()
            self.assertTrue(bake_check.check_map(d))

    def test_cli_exit_codes(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            d = self.copy_of_tiny(td)
            (d / "face0.biome.u8").write_bytes(b"\x00" * 16)
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(bake_check.main([str(d)]), 1)
                self.assertEqual(bake_check.main([str(TINY_DIR)]), 0)
                self.assertEqual(bake_check.main([td]), 2)  # no recipe.json there


if __name__ == "__main__":
    unittest.main()
