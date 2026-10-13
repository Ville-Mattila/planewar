"""TA-27: gen_module_api --check on throwaway module trees (positive and negative fixture per rule)."""

from __future__ import annotations

import contextlib
import io
import shutil
import tempfile
import unittest
from pathlib import Path

from helpers import TOOLS

import gen_module_api

REPO = TOOLS.parent

PROJECT = 'config_version=5\n\n[autoload]\n\nLog="*res://src/m/log.gd"\n'

GD = """class_name Foo extends RefCounted
signal changed(v: int)
enum Level { LOW, HIGH = 5 }
const MAX: int = 3
var count: int = 0
var _hidden: int = 0
static var shared: String = ""

func _init(seed_value: int, stream: int = 0) -> void:
	pass

func add(a: int, b: int = 1) -> int:
	return a + b

static func make(n: int) -> Foo:
	return Foo.new(n)

func _private() -> void:
	pass

func multi(a: int,
		b: Vector3) -> void:
	pass
"""

DOC = """class_name Foo extends RefCounted
signal changed(v: int)
enum Level { LOW, HIGH = 5 }
const MAX: int
var count: int; static var shared: String
func _init(seed_value: int, stream: int = 0) -> void
func add(a: int, b: int = 1) -> int
static func make(n: int) -> Foo
func multi(a: int, b: Vector3) -> void
"""


def md(block: str) -> str:
    return (
        "# m - MODULE.md\n\n## Public API\n\n```gdscript\n" + block + "```\n\n"
        "## Invariants\n\n```gdscript\nfunc nonsense(\n```\n"
    )


class Tree:
    """A temporary repo root with godot/src/m/{MODULE.md,foo.gd}."""

    def __init__(self, doc: str, gd: str = GD) -> None:
        self.root = Path(tempfile.mkdtemp(prefix="gma_"))
        (self.root / "godot" / "src" / "m").mkdir(parents=True)
        (self.root / "godot" / "project.godot").write_text(PROJECT, encoding="utf-8")
        self.put("m/MODULE.md", md(doc))
        self.put("m/foo.gd", gd)

    def put(self, rel: str, text: str) -> None:
        p = self.root / "godot" / "src" / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")

    def check(self) -> list[str]:
        return gen_module_api.compare_module("m", self.root)

    def close(self) -> None:
        shutil.rmtree(self.root, ignore_errors=True)


class Base(unittest.TestCase):
    def tree(self, doc: str, gd: str = GD) -> Tree:
        t = Tree(doc, gd)
        self.addCleanup(t.close)
        return t

    def codes(self, doc: str, gd: str = GD) -> list[str]:
        return [f.split(": ", 1)[1].split()[0] for f in self.tree(doc, gd).check()]


class Positive(Base):
    def test_clean_module_passes(self) -> None:
        # _hidden / _private exist only in the code; the Invariants fence holds junk that must not be parsed
        self.assertEqual(self.tree(DOC).check(), [])

    def test_several_statements_per_line_and_comments(self) -> None:
        doc = DOC.replace("signal changed(v: int)\n", "signal changed(v: int)   # emitted; a; b\n")
        doc = doc.replace("func add(a: int, b: int = 1) -> int\nstatic func make(n: int) -> Foo\n",
                          "func add(a: int, b: int = 1) -> int;  static func make(n: int) -> Foo   # x\n")
        self.assertEqual(self.codes(doc), [])

    def test_multiline_enum_and_range_consts(self) -> None:
        doc = DOC.replace("enum Level { LOW, HIGH = 5 }", "enum Level { LOW,   # first\n            HIGH = 5 }")
        doc = doc.replace("const MAX: int", "const MAX: int .. const MAX: int")
        self.assertEqual(self.codes(doc), [])

    def test_unused_parameter_underscore_and_fixture_type(self) -> None:
        gd = GD.replace("func add(a: int", "func add(_a: int").replace("b: Vector3", "b: Vector3Fixture")
        self.assertEqual(self.codes(DOC, gd), [])

    def test_untyped_doc_param_matches_typed_code(self) -> None:
        self.assertEqual(self.codes(DOC.replace("func multi(a: int, b: Vector3)", "func multi(a, b: Vector3)")), [])

    def test_missing_return_means_void(self) -> None:
        self.assertEqual(self.codes(DOC.replace("func multi(a: int, b: Vector3) -> void", "func multi(a: int, b: Vector3)")), [])

    def test_nested_submodule_is_its_own_module(self) -> None:
        # R0 B.9 A-21: godot/src/m/sub/MODULE.md owns sub/*.gd; the parent module neither lists nor demands them
        t = self.tree(DOC)
        t.put("m/sub/MODULE.md", md("class_name Bar extends RefCounted\nfunc go(n: int) -> int\n"))
        bar = "class_name Bar extends RefCounted\n\nfunc go(n: int) -> int:\n\treturn n\n"
        t.put("m/sub/bar.gd", bar)
        self.assertIn("m/sub", gen_module_api.modules(t.root, None))
        self.assertEqual(t.check(), [])
        self.assertEqual(gen_module_api.compare_module("m/sub", t.root), [])
        t.put("m/sub/bar.gd", bar.replace("go(", "stop("))
        self.assertTrue(any("GMA-2" in f for f in gen_module_api.compare_module("m/sub", t.root)))
        self.assertEqual(t.check(), [])

    def test_real_repo_is_clean(self) -> None:
        found = [f for m in gen_module_api.modules(REPO, None) for f in gen_module_api.compare_module(m, REPO)]
        self.assertEqual(found, [])


class Negative(Base):
    def test_renamed_public_func_is_detected(self) -> None:
        out = self.tree(DOC, GD.replace("func add(", "func sum(")).check()
        self.assertTrue(any("GMA-2" in f and "add" in f and "MODULE.md:" in f for f in out), out)
        self.assertTrue(any("GMA-4" in f and "sum" in f and "foo.gd:" in f for f in out), out)

    def test_param_type_name_default_and_count(self) -> None:
        for new in (
            "a: float, b: int = 1",
            "x: int, b: int = 1",
            "a: int, b: int = 2",
            "a: int, b: int",
            "a: int",
        ):
            with self.subTest(new=new):
                self.assertEqual(self.codes(DOC.replace("a: int, b: int = 1", new))[:1], ["GMA-3"])

    def test_return_type_and_static(self) -> None:
        self.assertEqual(self.codes(DOC.replace("-> Foo", "-> int")), ["GMA-3"])
        self.assertEqual(self.codes(DOC.replace("static func make", "func make")), ["GMA-3"])

    def test_const_var_type_and_signal(self) -> None:
        self.assertEqual(self.codes(DOC.replace("const MAX: int", "const MAX: float")), ["GMA-3"])
        self.assertEqual(self.codes(DOC.replace("var count: int", "var count: float")), ["GMA-3"])
        self.assertEqual(self.codes(DOC.replace("changed(v: int)", "changed(v: float)")), ["GMA-3"])

    def test_documented_member_missing_in_code(self) -> None:
        extra = "var gone: int\nconst GONE: int\nsignal gone2()\nenum Gone { A }\n"
        self.assertEqual(self.codes(DOC + extra), ["GMA-2"] * 4)

    def test_enum_reorder_rename_and_value(self) -> None:
        for new in ("enum Level { HIGH = 5, LOW }", "enum Level { LOW, HIGHER = 5 }", "enum Level { LOW, HIGH = 6 }", "enum Level { LOW }"):
            with self.subTest(new=new):
                self.assertEqual(self.codes(DOC.replace("enum Level { LOW, HIGH = 5 }", new)), ["GMA-3"])

    def test_extends_mismatch(self) -> None:
        self.assertEqual(self.codes(DOC.replace("extends RefCounted", "extends Node")), ["GMA-3"])

    def test_documented_class_missing_and_undocumented_class(self) -> None:
        self.assertEqual(self.codes(DOC + "class_name Bar\n"), ["GMA-1"])
        t = self.tree(DOC)
        t.put("m/extra.gd", "class_name Extra\nfunc go() -> void:\n\tpass\n")
        out = t.check()
        self.assertEqual([f.split()[1] for f in out], ["GMA-4"])
        self.assertIn("extra.gd:1", out[0])

    def test_undocumented_public_func_but_not_const(self) -> None:
        self.assertEqual(self.codes(DOC, GD + "\nfunc extra() -> int:\n\treturn 1\n"), ["GMA-4"])
        self.assertEqual(self.codes(DOC, GD + "\nconst EXTRA: int = 1\n"), [])

    def test_unparseable_doc_line_and_member_before_class(self) -> None:
        self.assertEqual(self.codes(DOC + "func broken(\n")[:1], ["GMA-5"])
        self.assertEqual(self.codes("func orphan() -> void\n" + DOC), ["GMA-5"])


class Overrides(Base):
    PARENT_DOC = "class_name Base extends RefCounted\nfunc send(conn: int, reliable: bool) -> void\nfunc poll() -> void\n"
    CHILD_DOC = "class_name Child extends Base\nfunc extra() -> int\n"
    PARENT_GD = "class_name Base extends RefCounted\nfunc send(_conn: int, _reliable: bool) -> void:\n\tpass\nfunc poll() -> void:\n\tpass\n"

    def tree2(self, child_gd: str, child_doc: str | None = None) -> Tree:
        t = self.tree(DOC + self.PARENT_DOC + (child_doc or self.CHILD_DOC))
        t.put("m/base.gd", self.PARENT_GD)
        t.put("m/child.gd", child_gd)
        return t

    CHILD_GD = "class_name Child extends Base\nfunc send(conn: int, _reliable: bool) -> void:\n\tpass\nfunc poll() -> void:\n\tpass\nfunc extra() -> int:\n\treturn 1\n"

    def test_override_of_documented_parent_method_is_documented(self) -> None:
        self.assertEqual(self.tree2(self.CHILD_GD).check(), [])

    def test_override_with_different_signature_is_flagged(self) -> None:
        out = self.tree2(self.CHILD_GD.replace("conn: int", "conn: float")).check()
        self.assertEqual([f.split()[1] for f in out], ["GMA-3"])
        self.assertIn("child.gd:2", out[0])

    def test_new_method_not_on_parent_is_still_undocumented(self) -> None:
        out = self.tree2(self.CHILD_GD + "func more() -> void:\n\tpass\n").check()
        self.assertEqual([f.split()[1] for f in out], ["GMA-4"])

    def test_parent_without_documentation_gives_no_cover(self) -> None:
        t = self.tree(DOC + "class_name Child extends Base\n")
        t.put("m/child.gd", "class_name Child extends Base\nfunc poll() -> void:\n\tpass\n")
        self.assertEqual([f.split()[1] for f in t.check()], ["GMA-4"])


class Planned(Base):
    def test_planned_class_inline_marker(self) -> None:
        self.assertEqual(self.codes(DOC + "class_name Later   # [planned: TA-99]\nfunc go() -> void\n"), [])

    def test_owner_task_marker_and_directive(self) -> None:
        self.assertEqual(self.codes(DOC + "class_name Later   # [owner-task: TA-99]\nfunc go() -> void\n"), [])
        doc = "# planned: Later, Other\n" + DOC + "class_name Later\nfunc go() -> void\nclass_name Other\n"
        self.assertEqual(self.codes(doc), [])

    def test_planned_member_on_existing_class(self) -> None:
        self.assertEqual(self.codes(DOC + "func later() -> void   # [planned]\n"), [])
        self.assertEqual(self.codes(DOC + "func later() -> void\n"), ["GMA-2"])

    def test_planned_class_still_checks_members_that_exist(self) -> None:
        doc = DOC.replace("extends RefCounted", "extends RefCounted   # [planned]", 1).replace("b: int = 1) -> int", "b: int = 1) -> String")
        self.assertEqual(self.codes(doc + "func later() -> void\n"), ["GMA-3"])

    def test_marker_text_without_brackets_is_not_a_marker(self) -> None:
        self.assertEqual(self.codes(DOC + "class_name Later   # planned later\n"), ["GMA-1"])


class Autoload(Base):
    LOG = "extends Node\nenum Level { DEBUG, INFO }\nfunc info(tag: StringName, msg: String) -> void:\n\tpass\n"

    def autoload_tree(self, doc: str) -> Tree:
        t = self.tree(DOC + doc)
        t.put("m/log.gd", self.LOG)
        return t

    def test_bare_name_and_path_comment_forms(self) -> None:
        bare = "Log\nenum Level { DEBUG, INFO }\nfunc info(tag: StringName, msg: String) -> void\n"
        self.assertEqual(self.autoload_tree(bare).check(), [])
        by_path = ("# autoload: godot/src/m/log.gd, extends Node\nenum Level { DEBUG, INFO }\n"
                   "func info(tag: StringName, msg: String) -> void\n")
        self.assertEqual(self.autoload_tree(by_path).check(), [])

    def test_autoload_drift(self) -> None:
        bad = "Log\nfunc info(tag: StringName, msg: int) -> void\n"
        self.assertEqual([f.split()[1] for f in self.autoload_tree(bad).check() if "MODULE.md" in f], ["GMA-3"])

    def test_planned_autoload_directive(self) -> None:
        doc = ("# planned: Log\nLog\nfunc debug(tag: StringName, msg: String) -> void\n"
               "func info(tag: StringName, msg: String) -> void\n")
        t = self.tree(doc + DOC)
        t.put("m/log.gd", self.LOG)
        self.assertEqual(t.check(), [])


class Cli(Base):
    def run_cli(self, *argv: str) -> tuple[int, str]:
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            try:
                rc = gen_module_api.main(list(argv))
            except SystemExit as e:
                rc = int(e.code or 0)
        return rc, out.getvalue() + err.getvalue()

    def test_exit_codes(self) -> None:
        good = self.tree(DOC)
        self.assertEqual(self.run_cli("--check", "--root", str(good.root))[0], 0)
        bad = self.tree(DOC.replace("-> Foo", "-> int"))
        rc, text = self.run_cli("--check", "--root", str(bad.root))
        self.assertEqual(rc, 1)
        self.assertIn("MODULE.md:", text)
        self.assertEqual(self.run_cli("--root", str(good.root))[0], 2)
        empty = Path(tempfile.mkdtemp(prefix="gma_"))
        self.addCleanup(shutil.rmtree, empty, True)
        (empty / "godot" / "src").mkdir(parents=True)
        self.assertEqual(self.run_cli("--check", "--root", str(empty))[0], 2)


if __name__ == "__main__":
    unittest.main()
