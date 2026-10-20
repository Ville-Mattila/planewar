#!/usr/bin/env python3
"""gain_sweep: wrapper around the AI-06 gain-tuning harness (godot/test/tuning/gain_sweep.tscn; 05 s5).

Runs the headless sweep of FlightGains / LandingParams keys under both lift models and prints a summary of the CSV
it writes (sweep.csv, landing_failures.csv, best_gains.json in --out).

    python tools/gain_sweep.py --out reports/gain_sweep [--godot BIN] [--import] [--seeds 200] [--quick 16]
        [--random 24] [--models speed_scaled,damping_only] [--stages base,oat,greedy,random,confirm,cross]
        [--max-minutes 15]
    python tools/gain_sweep.py --summarise reports/gain_sweep     # only print the summary of an existing run

Godot binary: --godot, else $GODOT_BIN. Exit code: 0 ok, 1 harness failed or produced no CSV, 2 usage.
Standard library only.
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GODOT_PROJECT = ROOT / "godot"
SCENE = "res://test/tuning/gain_sweep.tscn"
SUMMARY_COLS = ("land_docked", "land_crashed", "land_other", "land_median_gate_dock_s", "dive_hits", "step_fail",
                "step_worst_t_s", "step_worst_overshoot")


def godot_args(project: Path, out: Path, opts: dict[str, object]) -> list[str]:
    """Arguments after the binary: headless run of the sweep scene with the user args after `--`."""
    args = ["--headless", "--path", str(project), SCENE, "--", f"--out={out}"]
    for key, val in opts.items():
        if val is not None and val != "":
            args.append(f"--{key}={val}")
    return args


def read_rows(csv_path: Path) -> list[dict[str, str]]:
    with csv_path.open(newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def best_row(rows: list[dict[str, str]], model: str, stage: str) -> dict[str, str] | None:
    """Lowest-score row of `model` in `stage`, or None."""
    cand = [r for r in rows if r["model"] == model and r["stage"] == stage]
    return min(cand, key=lambda r: float(r["score"])) if cand else None


def summarise(rows: list[dict[str, str]]) -> str:
    """One block per model: the confirm-stage baseline vs best rows on the full seed count."""
    lines: list[str] = []
    for model in sorted({r["model"] for r in rows}):
        confirm = [r for r in rows if r["model"] == model and r["stage"] == "confirm"]
        lines.append(f"{model}: {len([r for r in rows if r['model'] == model])} evaluations")
        for tag, r in zip(("baseline", "best"), confirm):
            cols = " ".join(f"{c}={r[c]}" for c in SUMMARY_COLS)
            lines.append(f"  {tag:8} score={r['score']} {cols}")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", type=Path, default=Path("reports/gain_sweep"))
    ap.add_argument("--godot", default=os.environ.get("GODOT_BIN", ""))
    ap.add_argument("--import", dest="do_import", action="store_true", help="run --import first (clean checkout)")
    ap.add_argument("--summarise", type=Path, help="only summarise this existing output directory")
    ap.add_argument("--max-minutes", type=float, default=0.0, help="kill the sweep after this wall time (0 = none)")
    for name in ("seeds", "dive-seeds", "quick", "random", "seed", "models", "stages", "failures", "dive-deg",
                 "dive-agl"):
        ap.add_argument(f"--{name}")
    a = ap.parse_args(argv)

    if a.summarise:
        csv_path = a.summarise / "sweep.csv"
        if not csv_path.is_file():
            print(f"gain_sweep: {csv_path} not found", file=sys.stderr)
            return 1
        print(summarise(read_rows(csv_path)))
        return 0

    if not a.godot:
        print("gain_sweep: set --godot or GODOT_BIN", file=sys.stderr)
        return 2
    out = a.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    if a.do_import:
        subprocess.run([a.godot, "--headless", "--path", str(GODOT_PROJECT), "--import"], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=600)
    opts = {k: getattr(a, k.replace("-", "_")) for k in ("seeds", "dive-seeds", "quick", "random", "seed", "models",
                                                       "stages", "failures", "dive-deg", "dive-agl")}
    started = time.monotonic()
    timeout = a.max_minutes * 60 if a.max_minutes > 0 else None
    try:
        proc = subprocess.run([a.godot, *godot_args(GODOT_PROJECT, out, opts)], check=False, timeout=timeout)
    except subprocess.TimeoutExpired:
        print(f"gain_sweep: timed out after {a.max_minutes} min", file=sys.stderr)
        return 1
    wall = time.monotonic() - started
    csv_path = out / "sweep.csv"
    if proc.returncode != 0 or not csv_path.is_file():
        print(f"gain_sweep: harness failed (exit {proc.returncode}); {csv_path} missing", file=sys.stderr)
        return 1
    print(summarise(read_rows(csv_path)))
    best = json.loads((out / "best_gains.json").read_text(encoding="utf-8"))
    print(f"best_gains.json: {', '.join(best)}; wall {wall:.0f} s; {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
