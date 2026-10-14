"""One passing and one failing fixture per rule D1..D10 (docs/03 TA-02)."""

from __future__ import annotations

import unittest

from helpers import RepoCase


class Baseline(RepoCase):
    def test_base_repo_is_clean(self) -> None:
        self.assertClean()
        self.assertEqual(self.rules(warnings=True), [])


class D1Layering(RepoCase):
    def test_pass_allowed_edge(self) -> None:
        self.write("godot/src/sim/a.gd", "class_name A\nextends RefCounted\nvar s: Sphere\n")
        self.assertClean()

    def test_fail_sim_references_net_type(self) -> None:
        self.write("godot/src/sim/a.gd", "class_name A\nextends RefCounted\nvar s: ServerSession\n")
        self.assertHas("D1", "sim/a.gd")

    def test_fail_preload_upward(self) -> None:
        self.write("godot/src/core/a.gd", 'class_name A\nextends RefCounted\nconst H = preload("res://src/ui/hud.gd")\n')
        self.assertHas("D1", "core/a.gd")

    def test_pass_named_type_exceptions(self) -> None:
        self.write("godot/src/input/a.gd", "class_name A\nextends RefCounted\nvar p: PilotInput\n")
        self.write("godot/src/ui/b.gd", "class_name B\nextends Control\nvar v: SimView\n")
        self.write("godot/src/net/c.gd", "class_name C\nextends RefCounted\nvar w: SimWorld\nvar k: Kinematics\n")
        self.assertClean()

    def test_fail_named_type_not_on_list(self) -> None:
        self.write("godot/src/input/a.gd", "class_name A\nextends RefCounted\nvar w: SimWorld\n")
        self.assertHas("D1", "input/a.gd")

    def test_fail_sim_uses_app_autoload(self) -> None:
        self.write("godot/src/sim/a.gd", "class_name A\nextends RefCounted\nfunc f() -> void:\n\tApp.foo()\n")
        self.assertHas("D1", "sim/a.gd")

    def test_comment_and_string_mentions_ignored(self) -> None:
        self.write("godot/src/sim/a.gd", 'class_name A\nextends RefCounted\n# ServerSession\nvar s := "Hud"\n')
        self.assertClean()

    def test_pass_qualified_member_is_not_a_type_reference(self) -> None:
        self.write("godot/src/sim/p.gd", "class_name SimOnlyThing\nextends RefCounted\n")
        self.write("godot/src/core/q.gd", "class_name Q\nextends RefCounted\nconst K := 1\n")
        self.write("godot/src/net/c.gd", "class_name C\nextends RefCounted\nvar k := Q.SimOnlyThing\n")
        self.assertClean()

    def test_fail_qualified_head_still_checked(self) -> None:
        self.write("godot/src/net/n.gd", "class_name NetThing\nextends RefCounted\n")
        self.write("godot/src/core/a.gd", "class_name A\nextends RefCounted\nvar k := NetThing.X\n")
        self.assertHas("D1", "core/a.gd")

    def test_fail_bare_sim_only_class_in_net(self) -> None:
        self.write("godot/src/sim/p.gd", "class_name SimOnlyThing\nextends RefCounted\n")
        self.write("godot/src/net/c.gd", "class_name C\nextends RefCounted\nvar k: SimOnlyThing\n")
        self.assertHas("D1", "net/c.gd")

    def test_fail_scene_script_path(self) -> None:
        self.write("godot/scenes/presentation/x.tscn", '[ext_resource type="Script" path="res://src/ui/hud.gd" id="1"]\n')
        self.assertHas("D1", "x.tscn")

    def test_pass_scene_script_path(self) -> None:
        self.write("godot/scenes/ui/x.tscn", '[ext_resource type="Script" path="res://src/ui/hud.gd" id="1"]\n')
        self.assertClean()

    def test_app_may_depend_on_all(self) -> None:
        self.write("godot/src/app/m.gd", "class_name M\nextends Node\nvar h: Hud\nvar s: ServerSession\n")
        self.assertClean()


class D2NoNodes(RepoCase):
    def test_pass_refcounted_sim(self) -> None:
        self.write("godot/src/sim/a.gd", "class_name A\nextends RefCounted\n")
        self.assertClean()

    def test_fail_each_forbidden_construct(self) -> None:
        body = (
            "class_name A\nextends Node3D\nsignal hit\nfunc f() -> void:\n"
            "\tget_tree()\n\tget_node(\"x\")\n\tvar n := $Foo\n\tadd_child(null)\n\tawait get_tree().process_frame\n"
        )
        self.write("godot/src/sim_ai/a.gd", body)
        got = {ln for r, p, ln in self.rules() if r == "D2"}
        self.assertTrue({2, 3, 5, 6, 7, 8, 9} <= got, got)

    def test_fail_in_core_not_in_ui(self) -> None:
        self.write("godot/src/core/a.gd", "class_name A\nextends Node\n")
        self.write("godot/src/ui/a.gd", "class_name UiA\nextends Node\nsignal s\n")
        self.assertHas("D2", "core/a.gd")
        self.assertFalse([r for r in self.rules() if r[1].endswith("ui/a.gd")])

    def test_autoload_script_exempt(self) -> None:
        # base repo's core/log.gd extends Node and is registered under [autoload]
        self.assertClean(["godot/src/core/log.gd"])

    def test_mentions_in_strings_and_comments_ok(self) -> None:
        self.write("godot/src/sim/a.gd", 'class_name A\nextends RefCounted\n# await $x\nvar s := "get_tree( $"\n')
        self.assertClean()


class D3Threads(RepoCase):
    GUARDED = (
        "class_name OfflineHost\nextends Node\nvar _t: Thread\n\nfunc start() -> void:\n"
        "\tif not OS.has_feature(\"web\"):\n\t\t_t = Thread.new()\n"
    )

    def test_pass_allowlist_with_web_guard(self) -> None:
        self.write("godot/src/app/offline_host.gd", self.GUARDED.replace("var _t: Thread", "var _x := 0"))
        self.assertClean()

    def test_pass_else_branch_of_web_check(self) -> None:
        body = (
            "class_name OfflineHost\nextends Node\nfunc start() -> void:\n\tif OS.has_feature(\"web\"):\n"
            "\t\tpass\n\telse:\n\t\tvar t := Thread.new()\n"
        )
        self.write("godot/src/app/offline_host.gd", body)
        self.assertClean()

    def test_fail_allowlisted_file_without_guard(self) -> None:
        self.write("godot/src/app/offline_host.gd", "class_name OfflineHost\nextends Node\nfunc f() -> void:\n\tvar t := Thread.new()\n")
        self.assertHas("D3", "offline_host.gd")

    def test_fail_guard_is_positive_web_check(self) -> None:
        body = "class_name OfflineHost\nextends Node\nfunc f() -> void:\n\tif OS.has_feature(\"web\"):\n\t\tvar t := Thread.new()\n"
        self.write("godot/src/app/offline_host.gd", body)
        self.assertHas("D3", "offline_host.gd")

    def test_fail_thread_elsewhere(self) -> None:
        self.write("godot/src/net/t.gd", "class_name T\nextends RefCounted\nvar t := Thread.new()\n")
        self.assertHas("D3", "net/t.gd")

    def test_fail_other_primitives_even_in_allowlisted_file(self) -> None:
        body = self.GUARDED + "\t\tvar m := Mutex.new()\n"
        self.write("godot/src/app/offline_host.gd", body)
        self.assertHas("D3", "offline_host.gd")
        self.write("godot/src/server/w.gd", "class_name W\nextends RefCounted\nfunc f() -> void:\n\tWorkerThreadPool.add_task(f)\n\tvar s := Semaphore.new()\n")
        self.assertEqual(len([r for r in self.rules() if r[1].endswith("server/w.gd")]), 2)

    def test_pass_word_only_in_comment_or_string(self) -> None:
        self.write("godot/src/net/t.gd", 'class_name T\nextends RefCounted\n# Thread\nvar s := "Mutex"\nvar ThreadSafe := 1\n')
        self.assertClean()


class D4Autoloads(RepoCase):
    def test_pass_three_autoloads(self) -> None:
        self.assertClean(["godot/project.godot"])

    def test_fail_extra_autoload(self) -> None:
        self.write("godot/project.godot", self.read_project().replace('App="*res://src/app/app.gd"', 'App="*res://src/app/app.gd"\nBus="*res://src/app/bus.gd"'))
        self.assertHas("D4", "project.godot")

    def test_fail_missing_autoload(self) -> None:
        self.write("godot/project.godot", self.read_project().replace('Log="*res://src/core/log.gd"\n', ""))
        self.assertHas("D4", "project.godot")

    def read_project(self) -> str:
        return (self.root / "godot/project.godot").read_text(encoding="utf-8")


class D5Addons(RepoCase):
    def test_pass_allowlisted_addons(self) -> None:
        self.mkdir("godot/addons/gdUnit4")
        self.mkdir("godot/addons/nakama")
        self.write("godot/src/platform/n.gd", 'class_name N\nextends RefCounted\nconst X = preload("res://addons/nakama/a.gd")\n')
        self.write("godot/test/unit/t.gd", 'extends Node\nconst X = preload("res://addons/gdUnit4/a.gd")\n')
        self.assertClean()

    def test_fail_unlisted_addon_dir(self) -> None:
        self.mkdir("godot/addons/shady_sdk")
        self.assertHas("D5", "shady_sdk")

    def test_fail_addon_reference_outside_platform(self) -> None:
        self.write("godot/src/ui/n.gd", 'class_name N\nextends RefCounted\nconst X = preload("res://addons/nakama/a.gd")\n')
        self.assertHas("D5", "ui/n.gd")


class D6Literals(RepoCase):
    def test_pass_no_literals(self) -> None:
        self.write("godot/src/sim/a.gd", "class_name A\nextends RefCounted\nvar r := Sphere.PLANET_RADIUS * 0.5\n")
        self.assertEqual(self.rules(warnings=True), [])

    def test_warning_plain_literal(self) -> None:
        self.write("godot/src/ui/a.gd", "class_name UiA\nextends Control\nconst R := 6000.0\nconst T := 8192\n")
        self.assertHas("D6", "ui/a.gd", warnings=True)
        self.assertClean()

    def test_allowlist_silences_warning(self) -> None:
        self.write("godot/src/ui/a.gd", "class_name UiA\nextends Control\nconst R := 6000.0\n")
        self.write("tools/d6_allow.txt", "# c\ngodot/src/ui/a.gd:3 legacy constant under review\n")
        self.assertEqual(self.rules(warnings=True), [])

    def test_allowlist_entry_needs_reason(self) -> None:
        self.write("tools/d6_allow.txt", "godot/src/ui/a.gd:3\n")
        self.assertHas("D6", "d6_allow.txt")

    def test_error_literal_with_position_variable_in_sim(self) -> None:
        self.write("godot/src/sim/a.gd", "class_name A\nextends RefCounted\nfunc f(p: Vector3) -> float:\n\treturn p.length() - 6000.0\n")
        self.assertHas("D6", "sim/a.gd")
        self.write("tools/d6_allow.txt", "godot/src/sim/a.gd:4 nice try\n")
        self.assertHas("D6", "sim/a.gd")  # errors cannot be allowlisted

    def test_error_in_planet_renderer(self) -> None:
        self.write("godot/src/presentation/planet/c.gd", "class_name C\nextends RefCounted\nfunc f(pos: Vector3) -> bool:\n\treturn pos.length() > 8192\n")
        self.assertHas("D6", "planet/c.gd")

    def test_literal_with_position_outside_error_scope_is_only_warning(self) -> None:
        self.write("godot/src/ui/a.gd", "class_name UiA\nextends Control\nfunc f(pos: Vector3) -> bool:\n\treturn pos.length() > 8192\n")
        self.assertClean()
        self.assertHas("D6", "ui/a.gd", warnings=True)

    def test_sphere_gd_exempt_and_strings_ignored(self) -> None:
        self.write("godot/src/ui/a.gd", 'class_name UiA\nextends Control\nvar s := "6000"\nvar n := 16000\nvar m := 60001\n')
        self.assertEqual(self.rules(warnings=True), [])

    def test_float_literal_warning_in_sim(self) -> None:
        self.write("godot/src/sim/a.gd", "class_name A\nextends RefCounted\nvar a := 0.5 + 2.0 + -1.0\nvar b := 3.7\nvar c := PI * 4.2\n")
        w = [r for r in self.rules(warnings=True) if r[0] == "D6"]
        self.assertEqual([r[2] for r in w], [4])

    def test_float_literal_not_checked_outside_sim(self) -> None:
        self.write("godot/src/ui/a.gd", "class_name UiA\nextends Control\nvar b := 3.7\n")
        self.assertEqual(self.rules(warnings=True), [])


class D7FileShape(RepoCase):
    def test_pass_small_file(self) -> None:
        self.assertClean()

    def test_fail_missing_class_name(self) -> None:
        self.write("godot/src/ui/a.gd", "extends Control\n")
        self.assertHas("D7", "ui/a.gd")

    def test_fail_two_class_names(self) -> None:
        self.write("godot/src/ui/a.gd", "class_name A1\nextends Control\nclass_name A2\n")
        self.assertHas("D7", "ui/a.gd")

    def test_fail_too_long(self) -> None:
        self.write("godot/src/ui/a.gd", "class_name UiA\nextends Control\n" + "# x\n" * 399)
        self.assertHas("D7", "ui/a.gd")

    def test_pass_exactly_400_lines(self) -> None:
        self.write("godot/src/ui/a.gd", "class_name UiA\nextends Control\n" + "# x\n" * 398)
        self.assertClean()

    def test_autoload_without_class_name_exempt(self) -> None:
        self.assertClean(["godot/src/app/app.gd", "godot/src/core/log.gd", "godot/src/content/content_db.gd"])

    def test_non_autoload_without_class_name_not_exempt(self) -> None:
        self.write("godot/src/app/other.gd", "extends Node\n")
        self.assertHas("D7", "app/other.gd")


class D8WarningConfig(RepoCase):
    def test_pass(self) -> None:
        self.assertClean(["godot/project.godot"])

    def test_fail_key_not_two(self) -> None:
        p = (self.root / "godot/project.godot").read_text(encoding="utf-8")
        self.write("godot/project.godot", p.replace("unsafe_cast=2", "unsafe_cast=1"))
        self.assertHas("D8", "project.godot")

    def test_fail_key_missing(self) -> None:
        p = (self.root / "godot/project.godot").read_text(encoding="utf-8")
        self.write("godot/project.godot", p.replace("gdscript/warnings/integer_division=2\n", ""))
        self.assertHas("D8", "project.godot")


class D9WebSafety(RepoCase):
    BODY = "class_name A\nextends RefCounted\nfunc f() -> void:\n\t%s\n"

    def test_pass_in_platform(self) -> None:
        self.write("godot/src/platform/a.gd", self.BODY % "OS.execute(\"x\", [])")
        self.assertClean()

    def test_fail_each_outside_platform(self) -> None:
        for i, stmt in enumerate(["OS.execute(\"x\", [])", "JavaScriptBridge.eval(\"1\")", 'FileAccess.open("/etc/passwd", 1)']):
            self.write(f"godot/src/ui/a{i}.gd", (self.BODY % stmt).replace("class_name A", f"class_name A{i}"))
            self.assertHas("D9", f"ui/a{i}.gd")

    def test_pass_user_path_open(self) -> None:
        self.write("godot/src/ui/a.gd", self.BODY % 'FileAccess.open("user://x", 1)')
        self.assertClean()


class D10TestPresence(RepoCase):
    def md(self, body: str) -> None:
        self.write("godot/src/sim/MODULE.md", "# sim\n\n## Test entry points\n" + body + "\n\n## Open items\nnone\n")

    def test_pass_existing_paths(self) -> None:
        self.write("godot/test/unit/sim/test_k.gd", "extends Node\n")
        self.md("`godot/test/unit/sim/test_k.gd`, `test_k.gd`, `godot/test/unit/sim/`")
        self.assertClean()

    def test_fail_missing_path(self) -> None:
        self.md("`godot/test/unit/sim/test_nope.gd`")
        self.assertHas("D10", "sim/MODULE.md")

    def test_fail_no_paths_listed(self) -> None:
        self.md("see CI")
        self.assertHas("D10", "sim/MODULE.md")

    def test_fail_no_section(self) -> None:
        self.write("godot/src/sim/MODULE.md", "# sim\n")
        self.assertHas("D10", "sim/MODULE.md")

    def test_pass_tools_tests_path(self) -> None:
        self.write("tools/tests/test_x.py", "x = 1\n")
        self.md("`tools/tests/test_x.py`")
        self.assertClean()


if __name__ == "__main__":
    unittest.main()
