"""Fixture helpers: build a throwaway repo tree and run check_deps against it."""

from __future__ import annotations

import shutil
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(TOOLS))

import check_deps  # noqa: E402

PROJECT = """config_version=5

[autoload]

Log="*res://src/core/log.gd"
ContentDB="*res://src/content/content_db.gd"
App="*res://src/app/app.gd"

[debug]

gdscript/warnings/enable=true
""" + "".join(
    f"gdscript/warnings/{k}=2\n"
    for k in (
        "untyped_declaration inferred_declaration unsafe_property_access unsafe_method_access "
        "unsafe_call_argument unsafe_cast unsafe_void_return return_value_discarded missing_await "
        "unused_variable unused_parameter shadowed_variable integer_division narrowing_conversion"
    ).split()
)

BASE_FILES = {
    "godot/project.godot": PROJECT,
    "godot/src/core/log.gd": "extends Node\n\nvar x: int = 0\n",
    "godot/src/content/content_db.gd": "extends Node\n",
    "godot/src/app/app.gd": "extends Node\n",
    "godot/src/core/sphere.gd": "class_name Sphere\nextends RefCounted\n\nconst PLANET_RADIUS := 6000.0\n",
    "godot/src/sim/pilot_input.gd": "class_name PilotInput\nextends RefCounted\n",
    "godot/src/sim/sim_view.gd": "class_name SimView\nextends RefCounted\n",
    "godot/src/sim/kinematics.gd": "class_name Kinematics\nextends RefCounted\n",
    "godot/src/sim/world.gd": "class_name SimWorld\nextends RefCounted\n",
    "godot/src/net/session.gd": "class_name ServerSession\nextends RefCounted\n",
    "godot/src/ui/hud.gd": "class_name Hud\nextends Control\n",
    "godot/src/platform/saves.gd": "class_name Saves\nextends RefCounted\n",
}


class RepoCase(unittest.TestCase):
    """Each test gets a fresh repo seeded with BASE_FILES plus the test's own files."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        shutil.copy(TOOLS / "deps.json", self._mk("tools/deps.json"))
        for rel, text in BASE_FILES.items():
            self.write(rel, text)

    def _mk(self, rel: str) -> Path:
        p = self.root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        return p

    def write(self, rel: str, text: str) -> Path:
        p = self._mk(rel)
        p.write_text(text, encoding="utf-8")
        return p

    def mkdir(self, rel: str) -> None:
        (self.root / rel).mkdir(parents=True, exist_ok=True)

    def run_check(self, files: list[str] | None = None) -> list[check_deps.Violation]:
        paths = None if files is None else [self.root / f for f in files]
        return check_deps.run(self.root, paths)

    def rules(self, files: list[str] | None = None, warnings: bool = False) -> list[tuple[str, str, int]]:
        """(rule, path, line) for errors (or warnings when `warnings`)."""
        return [(v.rule, v.path, v.line) for v in self.run_check(files) if v.warning == warnings]

    def assertClean(self, files: list[str] | None = None) -> None:
        self.assertEqual([v.format() for v in self.run_check(files) if not v.warning], [])

    def assertHas(self, rule: str, path_part: str = "", files: list[str] | None = None, warnings: bool = False) -> None:
        got = [r for r in self.rules(files, warnings) if r[0] == rule and path_part in r[1]]
        self.assertTrue(got, f"expected {rule} on '{path_part}', got {self.rules(files, warnings)}")
