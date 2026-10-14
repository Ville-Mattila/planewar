"""TA-33: godot/test/sim/scenarios/*.json (schema sim_scenario) are checked by validate_content."""

from __future__ import annotations

import copy
import json

from test_validate_content import Tree, run


class Scenarios(Tree):
    GOOD = {"schema_version": 1, "id": "demo", "title": "t", "refs": ["02 s6.3"], "status": "active", "ticks": 5,
            "checks": [{"at": 3, "query": "ship_count", "value": 0}]}

    def put(self, stem: str, doc: dict) -> None:
        f = self.root / "godot" / "test" / "sim" / "scenarios" / f"{stem}.json"
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(json.dumps(doc), encoding="utf-8")

    def test_good_scenario_passes_and_is_counted(self) -> None:
        self.put("demo", self.GOOD)
        code, out = run(self.root)
        self.assertEqual(code, 0, out)
        self.assertIn("1 sim scenarios", out)

    def test_id_must_equal_file_stem(self) -> None:
        self.put("other", self.GOOD)
        code, out = run(self.root)
        self.assertEqual(code, 1)
        self.assertIn("must equal the file stem", out)

    def test_unknown_key_and_bad_query_are_rejected(self) -> None:
        bad = copy.deepcopy(self.GOOD)
        bad["bogus"] = 1
        bad["checks"][0]["query"] = "nope"
        self.put("demo", bad)
        code, out = run(self.root)
        self.assertEqual(code, 1)
        self.assertIn("bogus", out)

    def test_planned_needs_a_reason_and_active_needs_something_to_fail(self) -> None:
        self.put("demo", {**self.GOOD, "status": "planned"})
        code, out = run(self.root)
        self.assertEqual(code, 1)
        self.assertIn("planned scenario must say", out)
        self.put("demo", {k: v for k, v in self.GOOD.items() if k != "checks"})
        code, out = run(self.root)
        self.assertIn("nothing can fail", out)

    def test_tick_after_the_end_of_the_run_is_rejected(self) -> None:
        late = copy.deepcopy(self.GOOD)
        late["checks"][0]["at"] = 9
        self.put("demo", late)
        code, out = run(self.root)
        self.assertEqual(code, 1)
        self.assertIn("after the end of the run", out)
