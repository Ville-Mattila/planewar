"""AI-06: tools/gain_sweep.py builds the Godot command line, reads and summarises the sweep CSV, and fails loudly."""

from __future__ import annotations

import io
import json
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

from helpers import TOOLS  # noqa: F401  (puts tools/ on sys.path)

import gain_sweep as gs

HEADER = ("model,stage,cand,classes,land_seeds,dive_seeds,score,step_fail,step_worst_t_s,step_worst_overshoot,"
          "dive_worst_t_s,dive_worst_overshoot,dive_hits,dive_min_agl_m,land_docked,land_crashed,land_other,"
          "land_median_gate_dock_s,land_max_go_arounds,wall_s,flight_overrides,landing_overrides")


def row(model: str, stage: str, cand: int, score: float, docked: int = 10) -> str:
    return (f"{model},{stage},{cand},1,10,10,{score},0,1.5,0.05,0.6,0.05,0,30.0,{docked},0,{10 - docked},31.6,0,"
            f"0.5,\"{{\"\"kp_path\"\":5.0}}\",\"{{}}\"")


class GainSweepTest(unittest.TestCase):
    def write_run(self, rows: list[str]) -> Path:
        d = Path(tempfile.mkdtemp())
        self.addCleanup(lambda: __import__("shutil").rmtree(d, ignore_errors=True))
        (d / "sweep.csv").write_text("\n".join([HEADER, *rows]) + "\n", encoding="utf-8")
        return d

    def test_godot_args_headless_scene_and_user_args(self) -> None:
        args = gs.godot_args(Path("/p"), Path("/o"), {"seeds": 200, "models": None, "quick": "", "random": 0})
        self.assertEqual(args[:2], ["--headless", "--path"])
        self.assertIn(gs.SCENE, args)
        tail = args[args.index("--") + 1:]
        self.assertEqual(tail[0], "--out=" + str(Path("/o")))
        self.assertIn("--seeds=200", tail)
        self.assertIn("--random=0", tail)       # 0 is a value, not "unset"
        self.assertFalse(any(a.startswith(("--models", "--quick")) for a in tail))

    def test_read_rows_and_quoted_json_columns(self) -> None:
        d = self.write_run([row("damping_only", "base", 1, 120.0, 0)])
        rows = gs.read_rows(d / "sweep.csv")
        self.assertEqual(len(rows), 1)
        self.assertEqual(json.loads(rows[0]["flight_overrides"]), {"kp_path": 5.0})

    def test_best_row_is_lowest_score_in_stage(self) -> None:
        d = self.write_run([row("a", "oat", 1, 9.0), row("a", "oat", 2, 3.5), row("a", "greedy", 3, 1.0),
                            row("b", "oat", 4, 0.1)])
        rows = gs.read_rows(d / "sweep.csv")
        best = gs.best_row(rows, "a", "oat")
        self.assertIsNotNone(best)
        self.assertEqual(best["cand"], "2")
        self.assertIsNone(gs.best_row(rows, "a", "random"))

    def test_summarise_pairs_baseline_and_best_per_model(self) -> None:
        d = self.write_run([row("speed_scaled", "confirm", 1, 15.0, 10), row("speed_scaled", "confirm", 2, 9.0, 10),
                            row("damping_only", "confirm", 3, 120.0, 0), row("damping_only", "confirm", 4, 40.0, 7)])
        text = gs.summarise(gs.read_rows(d / "sweep.csv"))
        self.assertIn("damping_only: 2 evaluations", text)
        self.assertIn("baseline score=120.0 land_docked=0", text)
        self.assertIn("best     score=40.0 land_docked=7", text)

    def test_summarise_cli_missing_csv_fails(self) -> None:
        err = io.StringIO()
        with redirect_stderr(err), redirect_stdout(io.StringIO()):
            code = gs.main(["--summarise", str(Path(tempfile.gettempdir()) / "no_such_gain_sweep_dir")])
        self.assertEqual(code, 1)
        self.assertIn("not found", err.getvalue())

    def test_summarise_cli_ok(self) -> None:
        d = self.write_run([row("speed_scaled", "confirm", 1, 15.0)])
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(gs.main(["--summarise", str(d)]), 0)
        self.assertIn("speed_scaled", out.getvalue())

    def test_run_without_godot_is_a_usage_error(self) -> None:
        err = io.StringIO()
        with redirect_stderr(err):
            code = gs.main(["--godot", "", "--out", tempfile.gettempdir()])
        self.assertEqual(code, 2)


if __name__ == "__main__":
    unittest.main()
