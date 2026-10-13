#!/usr/bin/env python3
"""Web export size gate (01 s8.2, 03 s11.2): prints raw and Brotli size of every file and the Brotli sum.

Initial download = wasm + js + pck (+ html shell); budget 20 MB Brotli. Uses the `brotli` CLI.
Usage: size_gate.py godot/build/web [--budget-mb 20] [--quality 9]
"""
import argparse
import os
import subprocess
import sys

COUNTED = (".wasm", ".js", ".pck", ".html", ".css", ".json")


def brotli_size(path: str, quality: int) -> int:
    out = subprocess.run(["brotli", f"--quality={quality}", "-c", path], check=True, capture_output=True).stdout
    return len(out)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--budget-mb", type=float, default=20.0)
    ap.add_argument("--quality", type=int, default=9)
    a = ap.parse_args()
    rows, raw_sum, br_sum = [], 0, 0
    for name in sorted(os.listdir(a.dir)):
        p = os.path.join(a.dir, name)
        if not os.path.isfile(p) or not name.endswith(COUNTED):
            continue
        raw, br = os.path.getsize(p), brotli_size(p, a.quality)
        rows.append((name, raw, br))
        raw_sum += raw
        br_sum += br
    if not rows:
        print("::error::no web export files found")
        return 1
    lines = ["| file | raw bytes | brotli bytes |", "|---|---|---|"]
    lines += [f"| {n} | {r} | {b} |" for n, r, b in rows]
    budget = int(a.budget_mb * 1024 * 1024)
    lines.append(f"| **sum** | {raw_sum} | **{br_sum}** |")
    lines.append("")
    lines.append(f"BROTLI_SUM_BYTES={br_sum} ({br_sum / 1048576:.2f} MiB) budget={budget} (q{a.quality})")
    text = "\n".join(lines)
    print(text)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write("### Web size gate\n" + text + "\n")
    if br_sum > budget:
        print(f"::error::web Brotli sum {br_sum} exceeds budget {budget}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
