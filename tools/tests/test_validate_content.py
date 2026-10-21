"""tools/validate_content.py + tools/schemalite.py (CONTRACT-0): schemas, canonical and negative fixtures, docs examples."""

from __future__ import annotations

import copy
import io
import json
import re
import shutil
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from typing import Any

from helpers import TOOLS

import validate_content
from schemalite import SchemaStore, Validator, check_schema

REPO = TOOLS.parent
FIX = Path(__file__).resolve().parent / "fixtures" / "content"
CANON = FIX / "canonical"
# 03 CONTRACT-0 brief / R0 C1-10: the 15 schemas; GD-05 (R0 B.1 scoring.json) adds `scoring` -> 16; AI-01 (R0 B.1 order_rules.json) adds `order_rules` -> 17;
# TA-47 (R0 B.9 A-22) adds `quality_tiers` -> 18; FEAT-01 (08 SL-2/3/5) adds wing, callsigns, barks, commander_verbs -> 22; ART-14 adds biome_ramps (content/biome_ramps.json, not a def file) -> 23; TA-33 adds sim_scenario (test/sim/scenarios/*.json, not a def file) -> 24; UX-43 adds ai_tags (content/ui/ai_tags.json, not a def file) -> 25.
CONTRACT0 = sorted("ships ground_units weapons projectiles structures towers doctrines economy match_rules modes "
                   "bot_promises bot_profiles autopilots map_recipe rules scoring order_rules quality_tiers "
                   "wing callsigns barks commander_verbs biome_ramps sim_scenario ai_tags".split())
# Tools-only schemas: validated by their own tool, not def files; ART-22 sfx_recipe (tools/audio/recipes/*.json),
# ART-05 asset_budgets (tools/art/asset_budgets.json, loaded and schema-checked by validate_glb.py).
TOOLS_ONLY = ["asset_budgets", "sfx_recipe"]
SINGLETONS = {"rules", "economy", "match_rules", "map_recipe", "scoring", "order_rules", "wing", "callsigns", "biome_ramps", "ai_tags"}


def run(root: Path) -> tuple[int, str]:
    buf = io.StringIO()
    with redirect_stdout(buf):
        code = validate_content.main(["--root", str(root)])
    return code, buf.getvalue()


class Tree(unittest.TestCase):
    """A throwaway repo: the real schemas + manifest + docs/examples, and the canonical fixture content."""

    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp(prefix="vc_"))
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        shutil.copytree(REPO / "tools" / "schemas", self.root / "tools" / "schemas")
        shutil.copy(REPO / "tools" / "doc_example_schemas.json", self.root / "tools" / "doc_example_schemas.json")
        shutil.copytree(REPO / "docs" / "examples", self.root / "docs" / "examples")
        shutil.copytree(CANON / "godot", self.root / "godot")

    def patch(self, rel: str, op: str, path: list, value: Any = None) -> None:
        f = self.root / rel
        data = json.loads(f.read_text(encoding="utf-8")) if f.exists() else {}
        node = data
        for key in path[:-1]:
            node = node[key]
        if op == "set":
            node[path[-1]] = value
        else:
            del node[path[-1]]
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(json.dumps(data), encoding="utf-8")


class SchemaSet(unittest.TestCase):
    def test_exactly_the_contract0_set(self) -> None:
        got = sorted(p.name[: -len(".schema.json")] for p in (TOOLS / "schemas").glob("*.schema.json"))
        self.assertEqual([g for g in got if g not in TOOLS_ONLY], CONTRACT0)
        self.assertEqual(len(got) - len(TOOLS_ONLY), 25)

    def test_meta_clean(self) -> None:
        store = SchemaStore(TOOLS / "schemas")
        for stem in CONTRACT0:
            self.assertEqual(check_schema(store, f"{stem}.schema.json"), [], stem)

    def test_meta_rejects_unsupported_keyword_and_bad_ref(self) -> None:
        d = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, d, ignore_errors=True)
        (d / "x.schema.json").write_text(json.dumps({
            "$schema": "https://json-schema.org/draft/2020-12/schema", "$id": "x.schema.json", "type": "object",
            "additionalProperties": False, "required": ["a"], "properties": {"b": {"if": {}, "$ref": "#/$defs/nope"}}}))
        problems = "\n".join(check_schema(SchemaStore(d), "x.schema.json"))
        self.assertIn("unsupported keyword 'if'", problems)
        self.assertIn("unresolvable $ref", problems)
        self.assertIn("required keys not declared", problems)

    def test_def_envelope_r0_part_b(self) -> None:
        """Every collection entry: id, status (core|candidate), tags required; _doc allowed; no name_key (R0 B, C2-33)."""
        first: dict[str, Any] = {}
        for stem in CONTRACT0:
            if stem == "sim_scenario":   # TA-33: a test-scenario schema, not a def file (no _doc / def envelope)
                continue
            sch = json.loads((TOOLS / "schemas" / f"{stem}.schema.json").read_text(encoding="utf-8"))
            self.assertNotIn("name_key", json.dumps(sch), stem)
            self.assertIn("notes" if stem == "map_recipe" else "_doc", sch["properties"], stem)
            if stem in SINGLETONS:
                continue
            item_ref = sch["properties"][stem]["items"]["$ref"]
            entry = sch["$defs"][item_ref.rsplit("/", 1)[1]]
            self.assertFalse(entry["additionalProperties"], stem)
            for key in ("id", "status", "tags"):
                self.assertIn(key, entry["required"], stem)
            for key in ("_doc", "presentation"):
                self.assertIn(key, entry["properties"], stem)
            for shared in ("status", "tags", "presentation", "doc"):
                first.setdefault(shared, sch["$defs"][shared])
                self.assertEqual(sch["$defs"][shared], first[shared], f"{stem} $defs/{shared} drifted")
        self.assertEqual(first["status"], {"enum": ["core", "candidate"]})

    def test_ship_hover_floor_is_checked_once_in_validate_content(self) -> None:
        """GD-01: the schema carries only the gravity-anchor bound (2 x 5.0); the O-2 floor 2 x rules.gravity
        lives in validate_content.check_cross, so a_thrust 11 is caught there and nowhere else."""
        sch = json.loads((TOOLS / "schemas" / "ships.schema.json").read_text(encoding="utf-8"))
        a_thrust = sch["$defs"]["ship"]["properties"]["a_thrust"]
        self.assertEqual(a_thrust["minimum"], 10.0)
        self.assertIn("validate_content.py check_cross", a_thrust["$comment"])


class Amendments01(unittest.TestCase):
    """R0 B.8 (docs/reviews/R0-amendments-01.md): the schema appends are present and append-only."""

    @staticmethod
    def schema(stem: str) -> dict:
        return json.loads((TOOLS / "schemas" / f"{stem}.schema.json").read_text(encoding="utf-8"))

    def test_a2_range_min_m_is_optional(self) -> None:
        weapon = self.schema("weapons")["$defs"]["weapon"]
        self.assertIn("range_min_m", weapon["properties"])
        self.assertNotIn("range_min_m", weapon["required"])

    def test_a3_weapon_mount_enum_appended_in_both_schemas(self) -> None:
        self.assertEqual(self.schema("weapons")["$defs"]["weapon"]["properties"]["weapon_mount"]["enum"],
                         ["ship", "tower", "ground"])
        sel = self.schema("doctrines")["$defs"]["modifier"]["properties"]["select"]["properties"]["weapon_mount"]
        self.assertEqual(sel["enum"], ["ship", "tower", "ground"])

    def test_a4_fill_rating_weight_is_optional_unit_interval(self) -> None:
        mode = self.schema("modes")["$defs"]["mode"]
        prop = mode["properties"]["fill_rating_weight"]
        self.assertEqual((prop["minimum"], prop["maximum"]), (0, 1))
        self.assertNotIn("fill_rating_weight", mode["required"])

    def test_a6_adjutant_profiles_mirror_normal_cadence(self) -> None:
        defs = json.loads((CANON / "godot/content/defs/bot_profiles.json").read_text(encoding="utf-8"))
        normal = next(p for p in defs["bot_profiles"] if p["id"] == "normal")
        for prof in defs["bot_profiles"]:
            if prof["id"].startswith("adjutant_"):
                self.assertIsNone(prof["promise"], prof["id"])
                self.assertEqual(prof["think_period_ticks"], normal["think_period_ticks"], prof["id"])
                self.assertEqual(prof["reaction_delay_s"], normal["reaction_delay_s"], prof["id"])
                self.assertEqual(prof["max_commands_per_min"], 20, prof["id"])  # 05 s8


class Amendments02(unittest.TestCase):
    """R0 B.9 (docs/reviews/R0-amendments-02.md): the schema appends are present and append-only."""

    @staticmethod
    def schema(stem: str) -> dict:
        return json.loads((TOOLS / "schemas" / f"{stem}.schema.json").read_text(encoding="utf-8"))

    @staticmethod
    def defs(stem: str) -> dict:
        return json.loads((REPO / "godot" / "content" / "defs" / f"{stem}.json").read_text(encoding="utf-8"))

    def test_a13_brake_fade_mps_is_required_in_flight_common(self) -> None:
        fc = self.schema("ships")["$defs"]["flight_common"]
        self.assertEqual((fc["properties"]["brake_fade_mps"]["minimum"], fc["properties"]["brake_fade_mps"]["maximum"]), (1, 30))
        self.assertIn("brake_fade_mps", fc["required"])
        canon = json.loads((CANON / "godot/content/defs/ships.json").read_text(encoding="utf-8"))
        self.assertEqual(canon["flight_common"]["brake_fade_mps"], 10)  # 03 s5.3 `clamp(v_fwd / 10, 0, 1)`

    def test_a29_a35_flight_common_appends_required_with_canonical_values(self) -> None:
        fc = self.schema("ships")["$defs"]["flight_common"]
        want = {"flip_speed_retain": 0.75, "scrape_clear_s": 0.5, "fuel_burn_boost_per_s": 2.0, "fuel_burn_brake_per_s": 0.6,
                "fuel_burn_idle_per_s": 0.05, "landing_damage_tilt_deg": 45, "auto_dock_latch_mult": 5}
        for name in want:
            self.assertIn(name, fc["required"], name)
        for path in (CANON / "godot/content/defs/ships.json", REPO / "godot/content/defs/ships.json"):
            common = json.loads(path.read_text(encoding="utf-8"))["flight_common"]
            for name, value in want.items():
                self.assertEqual(common[name], value, f"{path.name}:{name}")

    def test_a16_pause_scope_optional_enum_and_coop_listen_host(self) -> None:
        mode = self.schema("modes")["$defs"]["mode"]
        self.assertEqual(mode["properties"]["pause_scope"]["enum"], ["in_process", "listen_host"])
        self.assertNotIn("pause_scope", mode["required"])
        by_id = {m["id"]: m for m in self.defs("modes")["modes"]}
        self.assertEqual((by_id["coop"]["pause_save"], by_id["coop"]["pause_scope"]), (True, "listen_host"))
        for mid in ("skirmish", "campaign"):
            self.assertTrue(by_id[mid]["pause_save"])
            self.assertNotIn("pause_scope", by_id[mid])  # omitted = in_process

    def test_a17_caps_web_mobile_optional_lite_for_in_process_modes(self) -> None:
        mode = self.schema("modes")["$defs"]["mode"]
        self.assertEqual(mode["properties"]["caps_web_mobile"]["enum"], ["standard", "reduced", "lite"])
        self.assertNotIn("caps_web_mobile", mode["required"])
        by_id = {m["id"]: m for m in self.defs("modes")["modes"]}
        self.assertEqual([by_id[m].get("caps_web_mobile") for m in ("skirmish", "campaign", "pvp_1v1", "custom")],
                         ["lite", "lite", None, None])

    def test_a18_promise_locale_keys(self) -> None:
        for prom in self.defs("bot_promises")["bot_promises"]:
            self.assertEqual(prom["audience_key"], f"promise.{prom['id']}.audience")
            self.assertEqual(prom["human_target_key"], f"promise.{prom['id']}.human_target")

    def test_a19_launch_pad_optional_bool_shipyard_only(self) -> None:
        struct = self.schema("structures")["$defs"]["structure"]
        self.assertEqual(struct["properties"]["launch_pad"]["type"], "boolean")
        self.assertNotIn("launch_pad", struct["required"])
        launch = [s["id"] for s in self.defs("structures")["structures"] if s.get("launch_pad")]
        self.assertEqual(launch, ["shipyard"])
        shipyard = next(s for s in self.defs("structures")["structures"] if s["id"] == "shipyard")
        self.assertNotIn("pads", shipyard)


class Validation(unittest.TestCase):
    def setUp(self) -> None:
        self.store = SchemaStore(TOOLS / "schemas")
        self.v = Validator(self.store)

    def errs(self, x: Any, schema: dict) -> list:
        return self.v.validate(x, schema, "rules.schema.json")

    def test_bool_is_not_a_number(self) -> None:
        self.assertTrue(self.errs(True, {"type": "integer"}))
        self.assertTrue(self.errs(1, {"enum": [True]}))
        self.assertFalse(self.errs(6000.0, {"const": 6000}))
        self.assertFalse(self.errs(3.0, {"type": "integer"}))

    def test_one_of_exactly_one(self) -> None:
        sch = {"oneOf": [{"type": "number"}, {"type": "integer"}]}
        self.assertIn("2 oneOf branches matched", self.errs(1, sch)[0][1])
        self.assertFalse(self.errs(1.5, sch))

    def test_ref_into_other_file(self) -> None:
        self.assertTrue(self.errs("Bad", {"$ref": "ships.schema.json#/$defs/id"}))
        self.assertFalse(self.errs("dart", {"$ref": "ships.schema.json#/$defs/id"}))


class Repo(unittest.TestCase):
    def test_real_repo_passes(self) -> None:
        code, out = run(REPO)
        self.assertEqual(code, 0, out)
        self.assertIn(f"{25 + len(TOOLS_ONLY)} schemas", out)


class Canonical(Tree):
    def test_canonical_r0_values_pass(self) -> None:
        code, out = run(self.root)
        self.assertEqual(code, 0, out)
        self.assertIn("14 def files, 1 map recipes", out)

    def test_negative_fixtures(self) -> None:
        cases = json.loads((FIX / "negative.json").read_text(encoding="utf-8"))["cases"]
        self.assertGreaterEqual(len(cases), 10)
        pristine = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, pristine, ignore_errors=True)
        shutil.copytree(self.root / "godot", pristine / "godot")
        for case in cases:
            with self.subTest(case["name"]):
                shutil.rmtree(self.root / "godot")
                shutil.copytree(pristine / "godot", self.root / "godot")
                self.patch(case["file"], case["op"], case["path"], case.get("value"))
                code, out = run(self.root)
                self.assertEqual(code, 1, out)
                self.assertIn(case["expect"], out)
                if case.get("sole"):  # GD-01/TA-07: the fixture trips its target rule and nothing else
                    m = re.search(r"(\d+) violations", out)
                    self.assertEqual(int(m.group(1)) if m else 0, 1, out)


class Examples(Tree):
    def test_unmapped_example_fails(self) -> None:
        (self.root / "docs/examples/02/new-block-99.json").write_text("{}", encoding="utf-8")
        code, out = run(self.root)
        self.assertEqual(code, 1)
        self.assertIn("02/new-block-99.json: not mapped", out)

    def test_stale_manifest_entry_fails(self) -> None:
        (self.root / "docs/examples/02/2-4-ship-notes-01.json").unlink()
        code, out = run(self.root)
        self.assertEqual(code, 1)
        self.assertIn("which does not exist", out)

    def test_ship_example_is_schema_checked(self) -> None:
        f = self.root / "docs/examples/02/2-4-ship-notes-01.json"
        data = json.loads(f.read_text(encoding="utf-8"))
        data["a_thrust"] = 11
        f.write_text(json.dumps(data), encoding="utf-8")
        code, out = run(self.root)
        self.assertEqual(code, 1)
        self.assertIn("2-4-ship-notes-01.json:/a_thrust", out)

    def test_keyed_autopilot_example_is_schema_checked(self) -> None:
        f = self.root / "docs/examples/05/4-4-parameter-set-in-json-01.json"
        data = json.loads(f.read_text(encoding="utf-8"))
        bad = copy.deepcopy(data)
        bad["ap_dart"]["flight"]["kp_path"] = 50
        f.write_text(json.dumps(bad), encoding="utf-8")
        code, out = run(self.root)
        self.assertEqual(code, 1)
        self.assertIn(":/ap_dart:/flight/kp_path", out)

    def test_meteor_sets_fragment_is_wrapped_and_checked(self) -> None:
        f = self.root / "docs/examples/08/sl-6-meteor-fall-the-moon-almanac-i-21-v1-x-built-before-sl-06.json"
        text = f.read_text(encoding="utf-8")
        with self.assertRaises(ValueError):
            json.loads(text)  # the doc block really is a bare member, not a JSON document
        f.write_text(text.replace('"midnight_pole"', '"equator"'), encoding="utf-8")
        code, out = run(self.root)
        self.assertEqual(code, 1)
        self.assertIn("sl-06.json:/2/anchor", out)

    def test_parse_only_needs_a_reason(self) -> None:
        m = self.root / "tools/doc_example_schemas.json"
        data = json.loads(m.read_text(encoding="utf-8"))
        data["examples"]["05/7-3-opening-books-per-doctrine-data-02.json"].pop("reason")
        m.write_text(json.dumps(data), encoding="utf-8")
        code, out = run(self.root)
        self.assertEqual(code, 1)
        self.assertIn("has no schema and no reason", out)


if __name__ == "__main__":
    unittest.main()


class Feat01Defs(Tree):
    """FEAT-01 (08 SL-1, SL-2, SL-3, SL-5): the real defs pass; each negative trips exactly one rule."""

    def setUp(self) -> None:
        super().setUp()
        for name in ("scoring", "wing", "callsigns", "barks", "commander_verbs"):
            shutil.copy(REPO / "godot" / "content" / "defs" / f"{name}.json", self.root / "godot" / "content" / "defs")

    def _edit(self, stem: str, mutate: Any) -> None:
        f = self.root / "godot" / "content" / "defs" / f"{stem}.json"
        data = json.loads(f.read_text(encoding="utf-8"))
        mutate(data)
        f.write_text(json.dumps(data), encoding="utf-8")

    def _expect_sole(self, fragment: str) -> None:
        code, out = run(self.root)
        self.assertEqual(code, 1, out)
        self.assertIn(fragment, out)
        self.assertIn("1 violations", out)

    def test_real_files_pass(self) -> None:
        code, out = run(self.root)
        self.assertEqual(code, 0, out)

    def test_landing_grade_weights_must_sum_to_one(self) -> None:
        def bump(d: dict) -> None:  # both copies move together, so only the sum rule fires
            d["landing_grade"]["weights"]["v_vert"] = 0.36
            d["landing"]["q_weights"]["v_vert"] = 0.36
        self._edit("scoring", bump)
        self._expect_sole("weights sum to 1.01, must be 1.0")

    def test_landing_grade_must_mirror_the_02_block(self) -> None:
        self._edit("scoring", lambda d: d["landing_grade"]["points"].update({"ace": 49}))
        self._expect_sole("differs from the 02 landing block")

    def test_bark_source_outside_the_table_fails(self) -> None:
        self._edit("barks", lambda d: d["barks"][0].update({"source": "NOPE"}))
        self._expect_sole("NOPE")

    def test_commander_verb_must_stay_candidate(self) -> None:
        self._edit("commander_verbs", lambda d: d["commander_verbs"][0].update({"status": "core"}))
        self._expect_sole("core")

    def test_wing_fuel_gate_out_of_unit_range_fails(self) -> None:
        self._edit("wing", lambda d: d.update({"min_fuel01": 1.5}))
        self._expect_sole("1.5")

    def test_callsign_slot_outside_0_to_7_fails(self) -> None:
        self._edit("callsigns", lambda d: d["callsigns"].update({"8": d["callsigns"]["0"]}))
        self._expect_sole("8")


class QualityTiers(Tree):
    """TA-47 (03 s13, R0 B.9 A-22): the real quality_tiers.json passes; each negative trips exactly one rule."""

    def setUp(self) -> None:
        super().setUp()
        shutil.copy(REPO / "godot" / "content" / "defs" / "quality_tiers.json", self.root / "godot" / "content" / "defs")

    def _tiers(self) -> dict:
        return json.loads((self.root / "godot/content/defs/quality_tiers.json").read_text(encoding="utf-8"))

    def _write(self, data: dict) -> None:
        (self.root / "godot/content/defs/quality_tiers.json").write_text(json.dumps(data), encoding="utf-8")

    def test_real_file_passes(self) -> None:
        code, out = run(self.root)
        self.assertEqual(code, 0, out)

    def test_missing_high_tier_fails_once(self) -> None:
        data = self._tiers()
        data["quality_tiers"] = data["quality_tiers"][:2]
        self._write(data)
        code, out = run(self.root)
        self.assertEqual(code, 1, out)
        self.assertIn("exactly one entry each for LOW, MEDIUM, HIGH", out)
        # minItems 3 (schema) and the cross-file tier set both fire on a two-entry list: two rules, no others.
        self.assertIn("2 items < minItems 3", out)
        self.assertIn("2 violations", out)

    def test_id_must_match_tier_name_fails_once(self) -> None:
        data = self._tiers()
        data["quality_tiers"][1]["id"] = "mid"
        self._write(data)
        code, out = run(self.root)
        self.assertEqual(code, 1, out)
        self.assertIn("must be 'medium' for tier MEDIUM", out)
        self.assertIn("1 violations", out)

    def test_msaa_outside_enum_fails_once(self) -> None:
        data = self._tiers()
        data["quality_tiers"][2]["msaa_samples"] = 3
        self._write(data)
        code, out = run(self.root)
        self.assertEqual(code, 1, out)
        self.assertIn("1 violations", out)
