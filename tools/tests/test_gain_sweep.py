"""AI-06 / AI-39: tools/gain_sweep.py builds the Godot command line, reads and summarises the sweep CSV, and fails loudly.

Header-drift pattern: the CSV header is read from the committed reports (never a hand list), and the scene flags are
parsed from gain_sweep.gd's "Options" usage line; a flag the usage line gains without a sample here fails the test.
"""

from __future__ import annotations

import csv
import io
import json
import re
import shutil
import subprocess
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

from helpers import TOOLS  # noqa: F401  (puts tools/ on sys.path)

import gain_sweep as gs

ROOT = TOOLS.parent
TUNING = ROOT / "godot" / "test" / "tuning"
REPORTS = TUNING / "reports"
AI38 = REPORTS / "ai38"
GD_SCENE_SCRIPT = TUNING / "gain_sweep.gd"

# one sample value per scene flag; None = the wrapper's own --out, always forwarded
SAMPLES: dict[str, str | None] = {
    "out": None, "models": "speed_scaled,damping_only", "seeds": "20", "dive-seeds": "21", "quick": "7",
    "random": "0", "seed": "606", "stages": "confirm", "failures": "3", "dive-deg": "10,45", "dive-agl": "100,300",
    "dive-leg-m": "0", "given": None,   # given: a real temp file, see GainSweepTest.setUp
}


def committed_header(name: str = "sweep.csv") -> list[str]:
    """The header of a committed sweep CSV (first line), split into column names."""
    return (REPORTS / name).read_text(encoding="utf-8").splitlines()[0].split(",")


def scene_usage_flags() -> set[str]:
    """Flag names in gain_sweep.gd's `## Options` usage paragraph (up to `## Files:`)."""
    text = GD_SCENE_SCRIPT.read_text(encoding="utf-8")
    m = re.search(r"^## Options.*?(?=^## Files:)", text, re.S | re.M)
    if m is None:
        raise AssertionError("gain_sweep.gd: no `## Options` usage paragraph")
    return set(re.findall(r"--([a-z][a-z-]*)=", m.group(0)))


def scene_csv_cols() -> list[str]:
    """CSV_COLS of gain_sweep.gd (the header the scene writes)."""
    text = GD_SCENE_SCRIPT.read_text(encoding="utf-8")
    m = re.search(r"const CSV_COLS: PackedStringArray = \[(.*?)\]", text, re.S)
    if m is None:
        raise AssertionError("gain_sweep.gd: no CSV_COLS constant")
    return re.findall(r'"([a-z_0-9]+)"', m.group(1))


def csv_text(header: list[str], rows: list[dict[str, object]]) -> str:
    """A CSV with `header`; missing cells get "0" (flight/landing overrides get "{}")."""
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\n")
    w.writerow(header)
    for r in rows:
        w.writerow([r.get(c, "{}" if c.endswith("_overrides") else "0") for c in header])
    return buf.getvalue()


class GainSweepTest(unittest.TestCase):
    def setUp(self) -> None:
        self.dir = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir, ignore_errors=True)
        self.given_file = self.dir / "given.json"
        self.given_file.write_text(json.dumps({"damping_only": {"flight": {}, "landing": {}}}), encoding="utf-8")

    def write_run(self, rows: list[dict[str, object]], header: list[str] | None = None) -> Path:
        d = Path(tempfile.mkdtemp(dir=self.dir))
        (d / "sweep.csv").write_text(csv_text(header or committed_header(), rows), encoding="utf-8")
        return d

    def run_wrapper(self, extra: list[str]) -> list[str]:
        """main() with subprocess.run mocked: returns the command the wrapper would run; the fake writes a run."""
        captured: dict[str, list[str]] = {}

        def fake_run(cmd: list[str], **_kw: object) -> subprocess.CompletedProcess[bytes]:
            captured["cmd"] = cmd
            out = Path(next(a for a in cmd if a.startswith("--out=")).split("=", 1)[1])
            (out / "sweep.csv").write_text(csv_text(committed_header(), []), encoding="utf-8")
            (out / "best_gains.json").write_text("{}", encoding="utf-8")
            return subprocess.CompletedProcess(cmd, 0)

        with mock.patch.object(gs.subprocess, "run", side_effect=fake_run), redirect_stdout(io.StringIO()):
            code = gs.main(["--godot", "/fake/godot", "--out", str(self.dir / "run"), *extra])
        self.assertEqual(code, 0)
        return captured["cmd"]

    def test_godot_args_headless_scene_and_user_args(self) -> None:
        args = gs.godot_args(Path("/p"), Path("/o"), {"seeds": 200, "models": None, "quick": "", "random": 0})
        self.assertEqual(args[:2], ["--headless", "--path"])
        self.assertIn(gs.SCENE, args)
        tail = args[args.index("--") + 1:]
        self.assertEqual(tail[0], "--out=" + str(Path("/o")))
        self.assertIn("--seeds=200", tail)
        self.assertIn("--random=0", tail)       # 0 is a value, not "unset"
        self.assertFalse(any(a.startswith(("--models", "--quick")) for a in tail))

    def test_usage_line_flags_parse_and_have_samples(self) -> None:
        flags = scene_usage_flags()
        self.assertTrue({"out", "given", "dive-leg-m", "stages", "failures"} <= flags, flags)
        missing = flags - set(SAMPLES)
        self.assertFalse(missing, f"add a sample for the new scene flag(s) {sorted(missing)}")

    def test_every_scene_usage_flag_is_forwarded(self) -> None:
        for flag in sorted(scene_usage_flags()):
            with self.subTest(flag=flag):
                argv: list[str] = []
                if flag == "given":
                    argv = ["--given", str(self.given_file)]
                elif flag != "out":
                    argv = [f"--{flag}", SAMPLES[flag] or ""]
                tail = self.run_wrapper(argv)
                tail = tail[tail.index("--") + 1:]
                if flag == "out":
                    self.assertTrue(any(a.startswith("--out=") for a in tail), tail)
                elif flag == "given":
                    self.assertIn(f"--given={self.given_file.resolve()}", tail)
                else:
                    self.assertIn(f"--{flag}={SAMPLES[flag]}", tail)

    def test_dive_leg_zero_is_forwarded_as_a_value(self) -> None:
        tail = self.run_wrapper(["--dive-leg-m", "0"])
        self.assertIn("--dive-leg-m=0", tail[tail.index("--") + 1:])

    def test_unset_flags_are_not_forwarded(self) -> None:
        cmd = self.run_wrapper([])
        tail = cmd[cmd.index("--") + 1:]
        self.assertFalse(any(a.startswith(("--dive-leg-m", "--given", "--stages")) for a in tail), tail)

    def test_given_must_exist_and_dive_leg_must_be_numeric(self) -> None:
        err = io.StringIO()
        with redirect_stderr(err):
            self.assertEqual(gs.main(["--godot", "/g", "--out", str(self.dir), "--given",
                                      str(self.dir / "missing.json")]), 2)
            self.assertEqual(gs.main(["--godot", "/g", "--out", str(self.dir), "--dive-leg-m", "far"]), 2)
        self.assertIn("--given file not found", err.getvalue())
        self.assertIn("--dive-leg-m must be a number", err.getvalue())

    def test_read_rows_and_quoted_json_columns(self) -> None:
        d = self.write_run([{"model": "damping_only", "stage": "base", "score": 120.0, "land_docked": 0,
                             "flight_overrides": '{"kp_path": 5.0}'}])
        rows = gs.read_rows(d / "sweep.csv")
        self.assertEqual(len(rows), 1)
        self.assertEqual(json.loads(rows[0]["flight_overrides"]), {"kp_path": 5.0})

    def test_best_row_is_lowest_score_in_stage(self) -> None:
        d = self.write_run([{"model": "a", "stage": "oat", "cand": 1, "score": 9.0},
                            {"model": "a", "stage": "oat", "cand": 2, "score": 3.5},
                            {"model": "a", "stage": "greedy", "cand": 3, "score": 1.0},
                            {"model": "b", "stage": "oat", "cand": 4, "score": 0.1}])
        rows = gs.read_rows(d / "sweep.csv")
        best = gs.best_row(rows, "a", "oat")
        self.assertIsNotNone(best)
        self.assertEqual(best["cand"], "2")
        self.assertIsNone(gs.best_row(rows, "a", "random"))

    def test_summarise_pairs_baseline_and_best_per_model(self) -> None:
        d = self.write_run([{"model": "speed_scaled", "stage": "confirm", "cand": 1, "score": 15.0, "land_docked": 10},
                            {"model": "speed_scaled", "stage": "confirm", "cand": 2, "score": 9.0, "land_docked": 10},
                            {"model": "damping_only", "stage": "confirm", "cand": 3, "score": 120.0, "land_docked": 0},
                            {"model": "damping_only", "stage": "confirm", "cand": 4, "score": 40.0, "land_docked": 7}])
        text = gs.summarise(gs.read_rows(d / "sweep.csv"))
        self.assertIn("damping_only: 2 evaluations", text)
        self.assertIn("baseline score=120.0 land_docked=0", text)
        self.assertIn("best     score=40.0 land_docked=7", text)

    def test_summarise_committed_ai06_header_marks_missing_ai38_columns(self) -> None:
        text = gs.summarise(gs.read_rows(REPORTS / "sweep.csv"))
        self.assertIn("dive_unrecoverable=n/a", text)
        self.assertIn("land_thrust_zero_run_max=n/a", text)

    def test_summarise_ai38_run_prints_the_four_ai38_columns(self) -> None:
        rows = gs.read_rows(AI38 / "after_new_sweep.csv")
        text = gs.summarise(rows)
        self.assertNotIn("n/a", text)
        damping_best = [r for r in rows if r["model"] == "damping_only" and r["stage"] == "confirm"][-1]
        self.assertEqual(damping_best["dive_unrecoverable"], "17")
        self.assertIn(f"dive_unrecoverable={damping_best['dive_unrecoverable']}", text)
        self.assertIn(f"dive_hits_recoverable={damping_best['dive_hits_recoverable']}", text)
        self.assertIn(f"land_thrust_zero_run_max={damping_best['land_thrust_zero_run_max']}", text)
        self.assertIn(f"land_thrust_zero_unsupported_run_max={damping_best['land_thrust_zero_unsupported_run_max']}",
                      text)

    def test_summarise_cli_missing_csv_fails(self) -> None:
        err = io.StringIO()
        with redirect_stderr(err), redirect_stdout(io.StringIO()):
            code = gs.main(["--summarise", str(Path(tempfile.gettempdir()) / "no_such_gain_sweep_dir")])
        self.assertEqual(code, 1)
        self.assertIn("not found", err.getvalue())

    def test_summarise_cli_ok(self) -> None:
        d = self.write_run([{"model": "speed_scaled", "stage": "confirm", "cand": 1, "score": 15.0}])
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(gs.main(["--summarise", str(d)]), 0)
        self.assertIn("speed_scaled", out.getvalue())

    def test_summarise_cli_on_committed_ai38_run(self) -> None:
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(gs.main(["--summarise", str(AI38 / "after_new_sweep.csv")]), 0)
            self.assertEqual(gs.main(["--summarise", str(AI38 / "after_legacy_sweep.csv")]), 0)
        self.assertIn("dive_unrecoverable=17", out.getvalue())
        self.assertIn("dive_hits=10 dive_unrecoverable=17", out.getvalue())

    def test_run_without_godot_is_a_usage_error(self) -> None:
        err = io.StringIO()
        with redirect_stderr(err):
            code = gs.main(["--godot", "", "--out", tempfile.gettempdir()])
        self.assertEqual(code, 2)


class CsvHeaderDriftTest(unittest.TestCase):
    """The scene's CSV_COLS, the committed AI-38 run and the committed AI-06 run must agree."""

    def test_scene_header_matches_committed_ai38_runs(self) -> None:
        cols = scene_csv_cols()
        self.assertEqual(len(cols), len(set(cols)))
        for name in ("after_new_sweep.csv", "after_legacy_sweep.csv", "before_new_sweep.csv"):
            with self.subTest(run=name):
                self.assertEqual(committed_header(f"ai38/{name}"), cols)

    def test_committed_ai06_header_is_a_prefix_of_scene_header(self) -> None:
        committed = committed_header()
        cols = scene_csv_cols()
        self.assertEqual(committed, cols[:len(committed)])
        self.assertEqual(cols[len(committed):], ["dive_unrecoverable", "dive_hits_recoverable",
                                                 "land_thrust_zero_run_max",
                                                 "land_thrust_zero_unsupported_run_max"])

    def test_summary_columns_exist_in_scene_header(self) -> None:
        self.assertTrue(set(gs.SUMMARY_COLS) <= set(scene_csv_cols()))


if __name__ == "__main__":
    unittest.main()
