"""ab_perf.py fingerprint gate: mismatch skips, match passes, match over threshold fails."""
import importlib.util
import pathlib
import unittest

_P = pathlib.Path(__file__).resolve().parents[2] / ".github" / "scripts" / "ab_perf.py"
_S = importlib.util.spec_from_file_location("ab_perf", _P)
ab = importlib.util.module_from_spec(_S)
_S.loader.exec_module(ab)

FP = "harness=1 world=sim scale=ab map=flat rows=13"


class AbPerfTest(unittest.TestCase):
    def test_mismatch_skips_even_when_slower(self) -> None:
        code, msg = ab.decide("harness=1 world=stub scale=stub map=flat rows=0", FP, 160.0, 25.0)
        self.assertEqual(code, 0)
        self.assertIn("::notice::", msg)

    def test_match_within_threshold_passes(self) -> None:
        self.assertEqual(ab.decide(FP, FP, 10.0, 25.0), (0, ""))

    def test_match_over_threshold_fails(self) -> None:
        code, msg = ab.decide(FP, FP, 30.0, 25.0)
        self.assertEqual(code, 1)
        self.assertIn("::error::", msg)

    def test_parse_output_reads_fingerprint_and_legacy(self) -> None:
        tick = "PERF_TICK p50_us=1 p95_us=5 p99_us=6 max_us=7 mean_us=2\n"
        self.assertEqual(ab.parse_output("PERF_FINGERPRINT " + FP + "\n" + tick), (5, 2, FP))
        self.assertEqual(ab.parse_output(tick)[2], "unknown")

    def test_scenario_args(self) -> None:
        self.assertEqual(ab.scenario_args("ai"), ["--ai"])
        self.assertEqual(ab.scenario_args("default"), [])

    def test_ai_fingerprint_differs_from_default_so_old_base_skips(self) -> None:
        code, msg = ab.decide(FP, FP + " scenario=ai", 90.0, 25.0)
        self.assertEqual(code, 0)
        self.assertIn("::notice::", msg)
        self.assertEqual(ab.decide(FP + " scenario=ai", FP + " scenario=ai", 30.0, 25.0, "ai")[0], 1)

    def test_ai_scenario_head_without_ai_fails_and_old_base_skips(self) -> None:
        code, msg = ab.decide(FP, FP, 0.0, 25.0, "ai")        # head ran the default scenario: vacuous gate
        self.assertEqual(code, 1)
        self.assertIn("::error::", msg)
        ai = FP + " scenario=ai ai_v=1"
        self.assertEqual(ab.decide(FP, ai, 90.0, 25.0, "ai")[0], 0)   # base predates --ai: skip
        self.assertIn("::notice::", ab.decide(FP, ai, 90.0, 25.0, "ai")[1])
        self.assertEqual(ab.decide(ai, ai + "x", 0.0, 25.0, "ai")[0], 0)   # retuned ai world: mismatch skips
        self.assertEqual(ab.decide(ai, ai, 10.0, 25.0, "ai"), (0, ""))


if __name__ == "__main__":
    unittest.main()
