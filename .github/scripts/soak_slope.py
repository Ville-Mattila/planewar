#!/usr/bin/env python3
"""Slope of per-minute p95 from a soak log (SOAK_MINUTE lines), R0 C1-11 / 03 s14.5.

slope %/min = per-minute change of p95 as % of the typical p95 (Theil-Sen gates; least squares is reported).
Gate: slope < --limit (default 2.0 %/min) for step_p95_us and for gap_p95_us.
Usage: soak_slope.py soak.log [--limit 2.0] [--min-minutes 5]
"""
import argparse
import re
import sys

LINE = re.compile(r"SOAK_MINUTE (\d+) step_p95_us=(\d+) step_p50_us=(\d+) gap_p95_us=(\d+)")


def slope_pct(ys: list[float]) -> float:
    n = len(ys)
    xs = list(range(n))
    mx, my = sum(xs) / n, sum(ys) / n
    den = sum((x - mx) ** 2 for x in xs)
    num = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    return (num / den) / my * 100.0 if den and my else 0.0


def theil_sen_pct(ys: list[float]) -> float:
    """Median of pairwise slopes / median value: robust to a single noisy minute on shared runners."""
    slopes = [(ys[j] - ys[i]) / (j - i) for i in range(len(ys)) for j in range(i + 1, len(ys))]
    slopes.sort()
    n = len(slopes)
    med_slope = slopes[n // 2] if n % 2 else (slopes[n // 2 - 1] + slopes[n // 2]) / 2
    sy = sorted(ys)
    m = len(sy)
    med = sy[m // 2] if m % 2 else (sy[m // 2 - 1] + sy[m // 2]) / 2
    return med_slope / med * 100.0 if med else 0.0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("--limit", type=float, default=2.0)
    ap.add_argument("--min-minutes", type=int, default=5)
    a = ap.parse_args()
    with open(a.log, encoding="utf-8", errors="replace") as fh:
        rows = [tuple(map(int, m.groups())) for m in map(LINE.search, fh) if m]
    if len(rows) < a.min_minutes:
        print(f"::error::only {len(rows)} SOAK_MINUTE lines, need >= {a.min_minutes}")
        return 1
    md = ["| minute | step p95 us | step p50 us | tick gap p95 us |", "|---|---|---|---|"]
    md += [f"| {m} | {s95} | {s50} | {g95} |" for m, s95, s50, g95 in rows]
    ys_step = [float(r[1]) for r in rows]
    ys_gap = [float(r[3]) for r in rows]
    step, gap = theil_sen_pct(ys_step), theil_sen_pct(ys_gap)
    md.append("")
    md.append(f"GATE (Theil-Sen, robust): step p95 {step:+.3f} %/min, tick-gap p95 {gap:+.3f} %/min (limit {a.limit})")
    md.append(f"info (least squares): step p95 {slope_pct(ys_step):+.3f} %/min, tick-gap p95 {slope_pct(ys_gap):+.3f} %/min")
    text = "\n".join(md)
    print(text)
    with open(a.log + ".md", "w", encoding="utf-8") as f:
        f.write(text + "\n")
    bad = step >= a.limit or gap >= a.limit
    if bad:
        print("::error::soak slope over limit")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
