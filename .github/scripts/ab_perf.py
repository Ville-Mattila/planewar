#!/usr/bin/env python3
"""Same-job base-vs-head A/B of test/perf/perf_tick.tscn (03 s12.1, R0 C1-11).

Runs --rounds interleaved runs per side (alternating who goes first) and compares the median of the
per-run p95. Fails when head is slower than base by more than --threshold percent.
--noise N : base-vs-base. Runs the A/B N times on one tree and prints each delta.
Usage: ab_perf.py --base godot_base --head godot [--rounds 5] [--ticks 3600] [--threshold 25]
       ab_perf.py --base godot --head godot --noise 10 --rounds 3
"""
import argparse
import os
import re
import statistics
import subprocess
import sys

LINE = re.compile(r"PERF_TICK p50_us=(\d+) p95_us=(\d+) p99_us=(\d+) max_us=(\d+) mean_us=(\d+)")


def run_once(project: str, ticks: int) -> tuple[int, int]:
    godot = os.environ.get("GODOT_BIN", "godot")
    out = subprocess.run(
        [godot, "--headless", "--path", project, "res://test/perf/perf_tick.tscn", "--", f"--ticks={ticks}"],
        check=True, capture_output=True, text=True, timeout=300).stdout
    m = LINE.search(out)
    if not m:
        raise SystemExit(f"no PERF_TICK line from {project}:\n{out}")
    return int(m.group(2)), int(m.group(5))


def compare(base: str, head: str, rounds: int, ticks: int) -> tuple[float, float, float, float]:
    a_p95, a_mean, b_p95, b_mean = [], [], [], []
    for r in range(rounds):
        order = [(base, a_p95, a_mean), (head, b_p95, b_mean)]
        if r % 2:
            order.reverse()
        for proj, p95s, means in order:
            p95, mean = run_once(proj, ticks)
            p95s.append(p95)
            means.append(mean)
    ma, mb = statistics.median(a_p95), statistics.median(b_p95)
    na, nb = statistics.median(a_mean), statistics.median(b_mean)
    return ma, mb, (mb - ma) / ma * 100.0, (nb - na) / na * 100.0


def append_summary(text: str) -> None:
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write(text)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True)
    ap.add_argument("--head", required=True)
    ap.add_argument("--rounds", type=int, default=5)
    ap.add_argument("--ticks", type=int, default=3600)
    ap.add_argument("--threshold", type=float, default=25.0)
    ap.add_argument("--noise", type=int, default=0)
    a = ap.parse_args()
    if a.noise:
        deltas = []
        for i in range(a.noise):
            ma, mb, d95, dmean = compare(a.base, a.base, a.rounds, a.ticks)
            deltas.append(abs(d95))
            print(f"noise run {i + 1}: p95 {ma:.0f} us vs {mb:.0f} us -> {d95:+.2f} % (mean {dmean:+.2f} %)")
        text = (f"base-vs-base noise over {a.noise} repeats x {a.rounds} rounds: max |delta| {max(deltas):.2f} %, "
                f"median {statistics.median(deltas):.2f} % (limit {a.threshold} %)")
        print(text)
        append_summary("### A/B noise (base vs base)\n" + text + "\n")
        if max(deltas) >= a.threshold:
            print(f"::warning::A/B noise {max(deltas):.2f} % is not under {a.threshold} %")
        return 0
    ma, mb, d95, dmean = compare(a.base, a.head, a.rounds, a.ticks)
    text = (f"A/B perf_tick: base p95 {ma:.0f} us, head p95 {mb:.0f} us -> {d95:+.2f} % "
            f"(mean {dmean:+.2f} %), threshold +{a.threshold} %")
    print(text)
    append_summary("### A/B perf\n" + text + "\n")
    if d95 > a.threshold:
        print("::error::head is slower than base beyond the A/B threshold")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
