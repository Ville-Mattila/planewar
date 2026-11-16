"""GD-21: tools/econ_model.py reproduces 02 s8.2-8.9 from the defs and a bot-book JSON.

Positive: the closed-form tables (8.2, 8.3, 8.6) and the 0-5 minute rows and checkpoints of 8.7 agree with the defs.
Negative: a doc value changed in a copy of the text is flagged; a book step that can never run fails loudly; --check exits 1.
The later rows are reported discrepancies (see the PR), not asserted here: this test pins that they are *reported*.
"""

from __future__ import annotations

import io
import json
import unittest
from contextlib import redirect_stdout

from helpers import TOOLS  # noqa: F401  (puts tools/ on sys.path)

import econ_compare as cmp
import econ_model as em

DOC_TEXT = cmp.DOC.read_text(encoding="utf-8")


class DocParsing(unittest.TestCase):
    def test_num_forms(self) -> None:
        self.assertEqual(cmp.num("1,260"), 1260)
        self.assertEqual(cmp.num("**3,200**"), 3200)
        self.assertEqual(cmp.num("0 / 70"), (0, 70))
        self.assertEqual(cmp.num("32/24"), (32, 24))
        self.assertIsNone(cmp.num("-"))
        self.assertEqual(cmp.parse_time("**0:25**"), 25)

    def test_missing_section_fails_loudly(self) -> None:
        with self.assertRaises(ValueError):
            cmp.section("8.99 ", DOC_TEXT)

    def test_minute_and_window_tables_parse(self) -> None:
        m = cmp.doc_minutes("1v1")
        self.assertEqual(sorted(m), list(range(0, 11)))
        self.assertEqual(m[1]["ore_spent"], 850)
        self.assertEqual(m[6]["ice_out"], 70)
        w = cmp.doc_windows("4v4")
        self.assertEqual(sorted(w), list(range(2, 25, 2)))
        self.assertEqual(w[2]["ore"], 1184)


class ClosedForm(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.defs = em.Defs()

    def test_trip_time_reads_the_defs(self) -> None:
        self.assertAlmostEqual(self.defs.trip_time(450), 108.5, places=3)   # 02 s8.2 row
        self.defs.items["harvester"]["mine_rate"] = 30                       # a def change moves the model
        try:
            self.assertAlmostEqual(self.defs.trip_time(450), 98.5, places=3)
        finally:
            self.defs.items["harvester"]["mine_rate"] = 15

    def test_static_tables_agree(self) -> None:
        rows = cmp.static_checks(self.defs)
        self.assertGreaterEqual(len(rows), 28)
        bad = [r["name"] for r in rows if not r["ok"]]
        self.assertEqual(bad, [], f"8.2 / 8.3 / 8.6 rows outside rounding: {bad}")

    def test_changed_doc_value_is_flagged(self) -> None:
        text = DOC_TEXT.replace("| 62.7 s |", "| 80.0 s |", 1)
        bad = [r["name"] for r in cmp.static_checks(self.defs, text) if not r["ok"]]
        self.assertEqual(bad, ["8.2 d=200 T_trip"])


class Opening1v1(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sim = em.run_book("1v1")
        cls.rows = cmp.compare("1v1", cls.sim)

    def test_first_five_minutes_match_every_column(self) -> None:
        mins = [r for r in self.rows if r["kind"] == "minute" and int(r["name"].split()[1]) <= 5]
        self.assertGreater(len(mins), 40)
        self.assertEqual([r["name"] for r in mins if not r["ok"]], [])

    def test_checkpoints_within_5_s_except_the_known_doc_ledger_gap(self) -> None:
        cps = [r for r in self.rows if r["kind"] == "checkpoint"]
        self.assertGreaterEqual(len(cps), 25)
        miss = [r["name"] for r in cps if not r["ok"]]
        # 02 s8.7 books Ore after the 0:06 Autocannon as 100; the stockpile also holds six seconds of Core trickle
        # (106), so Dart #2 becomes affordable at 0:50, not 0:56. Reported as a doc finding, never tuned away.
        self.assertEqual(miss, ["Dart #2 starts"])

    def test_dart_airborne_checkpoint(self) -> None:
        self.assertAlmostEqual(self.sim.event_time("P0.dart1.airborne"), 28.0, delta=1.0)

    def test_outpost_checkpoint(self) -> None:
        self.assertAlmostEqual(self.sim.event_time("P0.outpost1.done"), 3 * 60 + 44, delta=5.0)

    def test_deterministic(self) -> None:
        again = em.run_book("1v1")
        self.assertEqual(self.sim.events, again.events)
        self.assertEqual(self.sim.minutes, again.minutes)

    def test_rows_outside_tolerance_are_reported(self) -> None:
        out = cmp.render("1v1", self.sim, self.rows, False, False)
        self.assertIn("MISS", out)
        self.assertIn("-- checkpoint: 24/25", out)


class Books(unittest.TestCase):
    def test_unreachable_step_fails_loudly(self) -> None:
        book = em.load_book("1v1")
        book["players"][0]["steps"] = [{"do": "produce", "id": "bomber"}]     # needs a hangar nobody places
        with self.assertRaises(em.BookError) as cm:
            em.Sim(book).run()
        self.assertIn("hangar", str(cm.exception))

    def test_unknown_id_fails_loudly(self) -> None:
        book = em.load_book("1v1")
        book["players"][0]["steps"] = [{"do": "build", "id": "nope"}]
        with self.assertRaises(em.BookError):
            em.Sim(book).run()

    def test_4v4_pool_and_templates(self) -> None:
        book = em.load_book("4v4")
        sim = em.Sim(book)
        self.assertEqual([p.name for p in sim.players], ["P0", "P1", "P2", "P3"])
        self.assertEqual(sim.pool.ore, 3200)        # 4 x start_ore 800 (02 s8.8)
        self.assertEqual(sim.pool.ice, 1200)
        self.assertEqual(sim.players[1].fields["C"].cap, 5000)
        sim.run()
        self.assertAlmostEqual(sim.event_time("P0.dart1.airborne"), 28.0, delta=1.0)
        self.assertAlmostEqual(sim.event_time("P1.outpost1.done"), 3 * 60 + 15, delta=5.0)


class Cli(unittest.TestCase):
    def run_main(self, *args: str) -> tuple[int, str]:
        buf = io.StringIO()
        with redirect_stdout(buf):
            code = em.main(list(args))
        return code, buf.getvalue()

    def test_report_exits_zero_and_check_exits_one(self) -> None:
        code, out = self.run_main("--match", "1v1")
        self.assertEqual(code, 0)
        self.assertIn("== 1v1:", out)
        code, _ = self.run_main("--match", "1v1", "--check")
        self.assertEqual(code, 1)

    def test_json_output(self) -> None:
        code, out = self.run_main("--match", "1v1", "--json")
        self.assertEqual(code, 0)
        rows = json.loads(out)["1v1"]
        self.assertTrue(all({"kind", "name", "doc", "model", "ok"} <= set(r) for r in rows))


if __name__ == "__main__":
    unittest.main()
