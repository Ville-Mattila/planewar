"""TA-08: content hash (tools/content_hash.py) against the committed vector, scope rules, dangling refs."""

from __future__ import annotations

import io
import json
import shutil
import unittest
from contextlib import redirect_stdout
from pathlib import Path

import content_hash as ch
import validate_content
from test_validate_content import Tree, run

VECTOR = json.loads((Path(__file__).resolve().parent / "content_hash_vector.json").read_text(encoding="utf-8"))


class Vector(unittest.TestCase):
    def test_vector_hash(self) -> None:
        self.assertEqual(ch.hash_texts(VECTOR["files"]), VECTOR["sha256"])

    def test_vector_canonical_strings(self) -> None:
        self.assertEqual(ch.included_names(list(VECTOR["files"])), VECTOR["included"])
        self.assertEqual([ch.canonical_text(VECTOR["files"][n]) for n in VECTOR["included"]], VECTOR["canonical"])

    def test_empty_set_is_sha256_of_empty(self) -> None:
        self.assertEqual(ch.hash_texts({}), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")

    def test_number_forms(self) -> None:
        self.assertEqual(ch.canonical_text("[1,1.0,-0.0,1e2,0.1,1e-05,2.5E-3,123456789012]"),
                         "[1,1,0,100,0.1,0.00001,0.0025,123456789012]")

    def test_rejects_non_finite_and_huge(self) -> None:
        for bad in ("NaN", "Infinity", "[1e300]", "9007199254740993"):
            with self.assertRaises(ch.HashError, msg=bad):
                ch.canonical_text(bad)

    def test_scope(self) -> None:
        base = dict(VECTOR["files"])
        h = ch.hash_texts(base)
        for name in ("sfx.json", "vfx_prewarm.json"):
            self.assertEqual(ch.hash_texts({**base, name: '{"changed":true}'}), h, name)
        self.assertEqual(ch.hash_texts({**base, "new.txt": "x"}), h)
        self.assertNotEqual(ch.hash_texts({**base, "assists.json": '{"assists":[]}'}), h)
        self.assertNotEqual(ch.hash_texts({**base, "c_new.json": "{}"}), h)

    def test_presentation_and_doc_stripped_at_any_depth(self) -> None:
        a = '{"x":[{"id":"a","v":1,"presentation":{"m":1},"deep":{"_doc":"q","presentation":2}}]}'
        b = '{"x":[{"id":"a","v":1,"deep":{}}]}'
        self.assertEqual(ch.canonical_text(a), ch.canonical_text(b))
        self.assertNotEqual(ch.canonical_text(b), ch.canonical_text(b.replace('"v":1', '"v":2')))

    def test_key_order_and_whitespace_irrelevant(self) -> None:
        self.assertEqual(ch.canonical_text('{ "b" : 1,\n "a" : [ 1 , 2 ] }'), '{"a":[1,2],"b":1}')


class RepoHash(Tree):
    def test_print_hash_matches_module(self) -> None:
        buf = io.StringIO()
        with redirect_stdout(buf):
            self.assertEqual(validate_content.main(["--root", str(self.root), "--print-hash"]), 0)
        self.assertEqual(buf.getvalue().strip(), ch.content_hash(self.root / "godot/content/defs"))

    def test_summary_carries_hash_and_ui_locale_do_not_change_it(self) -> None:
        code, out = run(self.root)
        self.assertEqual(code, 0, out)
        h = ch.content_hash(self.root / "godot/content/defs")
        self.assertIn(h, out)
        for rel in ("godot/content/ui/x.json", "godot/content/locale/en.json", "godot/content/defs/sfx.json"):
            f = self.root / rel
            f.parent.mkdir(parents=True, exist_ok=True)
            f.write_text('{"a":1}', encoding="utf-8")
        self.assertEqual(ch.content_hash(self.root / "godot/content/defs"), h)

    def test_absent_defs_ok(self) -> None:
        shutil.rmtree(self.root / "godot/content/defs")
        code, out = run(self.root)
        self.assertEqual(code, 0, out)


class Dangling(Tree):
    def test_canonical_has_no_dangling(self) -> None:
        self.assertNotIn("dangling", run(self.root)[1])

    def test_ship_weapon_dangling(self) -> None:
        f = self.root / "godot/content/defs/ships.json"
        d = json.loads(f.read_text(encoding="utf-8"))
        ref = d["ships"][0]["primary"]
        self.assertIsNotNone(ref)
        ref["weapon"] = "no_such_weapon"
        f.write_text(json.dumps(d), encoding="utf-8")
        code, out = run(self.root)
        self.assertEqual(code, 1)
        self.assertRegex(out, r"ships\.json:/ships/0/primary/weapon: dangling weapon 'no_such_weapon'")

    def test_weapon_projectile_dangling(self) -> None:
        f = self.root / "godot/content/defs/weapons.json"
        d = json.loads(f.read_text(encoding="utf-8"))
        d["weapons"][0]["projectile"] = "ghost"
        f.write_text(json.dumps(d), encoding="utf-8")
        code, out = run(self.root)
        self.assertEqual(code, 1)
        self.assertIn("dangling projectile 'ghost'", out)

    def test_skipped_when_target_file_absent(self) -> None:
        (self.root / "godot/content/defs/weapons.json").unlink()
        code, out = run(self.root)
        self.assertNotIn("dangling", out)
        self.assertEqual(code, 0, out)


if __name__ == "__main__":
    unittest.main()
