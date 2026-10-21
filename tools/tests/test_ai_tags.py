"""UX-43: godot/content/ui/ai_tags.json has one HUD label per AiTag.Tag ordinal (0-33, reserved 16-33 included).

The enum is read from godot/src/sim_ai/ai_tag.gd; the sim_ai/MODULE.md 'Enumerations' bullet is the parity source
checked by tools/validate_content.py. Labels are <= 10 characters and equal the English column of ui_hud.csv.
"""

from __future__ import annotations

import csv
import json
import re
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any

TOOLS = Path(__file__).resolve().parent.parent
REPO = TOOLS.parent
sys.path.insert(0, str(TOOLS))

import validate_content  # noqa: E402

AI_TAG_GD = REPO / "godot" / "src" / "sim_ai" / "ai_tag.gd"
AI_TAGS = REPO / "godot" / "content" / "ui" / "ai_tags.json"
UI_HUD_CSV = REPO / "godot" / "content" / "locale" / "src" / "ui_hud.csv"
ENTRY_KEYS = {"ordinal", "name", "id", "label"}


def enum_names_from_gd(text: str) -> list[str]:
    """Member names of `enum Tag { ... }` in ai_tag.gd, in declaration order (index = ordinal)."""
    code = "\n".join(line.split("#", 1)[0] for line in text.splitlines())
    match = re.search(r"enum\s+Tag\s*\{([^}]*)\}", code)
    if match is None:
        raise AssertionError("ai_tag.gd has no `enum Tag { ... }`")
    names = [part.split("=", 1)[0].strip() for part in match.group(1).split(",")]
    return [n for n in names if n]


def load_tags() -> dict[str, Any]:
    return json.loads(AI_TAGS.read_text(encoding="utf-8"))


class RealFiles(unittest.TestCase):
    def setUp(self) -> None:
        self.names = enum_names_from_gd(AI_TAG_GD.read_text(encoding="utf-8"))
        self.data = load_tags()

    def test_enum_has_the_34_frozen_ordinals(self) -> None:
        self.assertEqual(len(self.names), 34)
        self.assertEqual(self.names[0], "NONE")
        self.assertEqual(self.names[15], "LOITER")   # 0-15 are the Dart's modes (AI-13, A-94)
        self.assertEqual(self.names[33], "IDLE")

    def test_every_ordinal_has_exactly_one_entry_and_no_extra_keys(self) -> None:
        self.assertEqual(set(self.data), {"_doc", "tags"})
        tags = self.data["tags"]
        self.assertEqual(sorted(t["ordinal"] for t in tags), list(range(len(self.names))))
        for entry in tags:
            self.assertEqual(set(entry), ENTRY_KEYS, entry)

    def test_each_entry_names_its_enum_member(self) -> None:
        by_ordinal = {t["ordinal"]: t for t in self.data["tags"]}
        for ordinal, name in enumerate(self.names):
            self.assertEqual(by_ordinal[ordinal]["name"], name)
            self.assertEqual(by_ordinal[ordinal]["id"], f"hud.ai_tag.{name.lower()}")

    def test_labels_fit_ten_characters(self) -> None:
        for entry in self.data["tags"]:
            self.assertTrue(0 < len(entry["label"]) <= 10, entry)

    def test_module_bullet_is_the_same_vocabulary(self) -> None:
        module = (REPO / "godot" / "src" / "sim_ai" / "MODULE.md").read_text(encoding="utf-8")
        enum = validate_content.module_ai_tags(module)
        self.assertEqual(enum, dict(enumerate(self.names)))

    def test_every_id_is_an_english_row_with_the_same_label(self) -> None:
        with UI_HUD_CSV.open(encoding="utf-8", newline="") as f:
            rows = {row["id"]: row for row in csv.DictReader(f)}
        for entry in self.data["tags"]:
            row = rows.get(entry["id"])
            self.assertIsNotNone(row, f"{entry['id']} missing from ui_hud.csv")
            self.assertEqual(row["en"], entry["label"])
            self.assertTrue(row["fi"].strip(), f"{entry['id']} has no Finnish")
            self.assertLessEqual(len(row["fi"]), 10, entry["id"])


class Negative(unittest.TestCase):
    """A minimal tree (schemas, manifest, ai_tags.json, sim_ai/MODULE.md): each mutation must trip one rule only."""

    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp(prefix="ai_tags_"))
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        shutil.copytree(REPO / "tools" / "schemas", self.root / "tools" / "schemas")
        shutil.copy(REPO / "tools" / "doc_example_schemas.json", self.root / "tools" / "doc_example_schemas.json")
        shutil.copytree(REPO / "docs" / "examples", self.root / "docs" / "examples")
        (self.root / "godot" / "content" / "ui").mkdir(parents=True)
        (self.root / "godot" / "src" / "sim_ai").mkdir(parents=True)
        shutil.copy(REPO / "godot" / "src" / "sim_ai" / "MODULE.md", self.root / "godot" / "src" / "sim_ai" / "MODULE.md")

    def write(self, data: dict[str, Any]) -> None:
        (self.root / "godot" / "content" / "ui" / "ai_tags.json").write_text(json.dumps(data), encoding="utf-8")

    def errors(self) -> list[str]:
        return validate_content.run(self.root).errors

    def test_canonical_passes(self) -> None:
        self.write(load_tags())
        self.assertEqual(self.errors(), [])

    def test_missing_ordinal_fails_once(self) -> None:
        data = load_tags()
        data["tags"] = [t for t in data["tags"] if t["ordinal"] != 7]
        self.write(data)
        errs = self.errors()
        # the parity rule fires once; the only other error is the minItems count that the same removal causes
        self.assertEqual(len(errs), 2, errs)
        self.assertEqual(sum("ordinal 7 (BOMB)" in e for e in errs), 1, errs)
        self.assertEqual(sum("minItems" in e for e in errs), 1, errs)

    def test_renamed_ordinal_fails_once(self) -> None:
        data = load_tags()
        data["tags"][16]["name"] = "FLY"
        self.write(data)
        errs = self.errors()
        self.assertEqual(len(errs), 1, errs)
        self.assertIn("ordinal 16 is named 'FLY'", errs[0])

    def test_label_over_ten_characters_fails_schema_only(self) -> None:
        data = load_tags()
        data["tags"][10]["label"] = "PULL UP NOW!"   # 12 characters
        self.write(data)
        errs = self.errors()
        self.assertEqual(len(errs), 1, errs)
        self.assertIn("longer than 10", errs[0])


if __name__ == "__main__":
    unittest.main()
