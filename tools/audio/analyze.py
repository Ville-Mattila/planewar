#!/usr/bin/env python3
"""SFX analyzer (docs/07 s8.1 and s8.4, ART-22). Stdlib only. Agents cannot listen, so acceptance is numeric.

    python tools/audio/analyze.py file.wav [--loop] [--lufs -16 --lufs-tol 2] [--centroid 300 4000]
                                  [--duration 0.2 2] [--recipe recipe.json]

Prints metrics as JSON. Exit 0 = no problems, 1 = at least one problem (printed as `file:1: message`).
Metrics: peak_dbfs, clipped_samples, dc_offset, duration_s, lufs (BS.1770 K-weighted, gated),
centroid_hz (mean of Welch-averaged power spectrum), seam_ratio (loop discontinuity / typical step).
"""

from __future__ import annotations

import argparse
import cmath
import json
import math
import struct
import sys
import wave
from pathlib import Path

PEAK_CEILING_DB = -1.0  # 07 s8.1: peak <= -1 dBFS
DC_LIMIT = 0.01
MAX_DURATION_S = 4.0  # 07 s8.3: no SFX over 4 s
CLIP_RUN = 3  # consecutive full-scale samples that count as clipping
SEAM_LIMIT = 4.0  # jump at the loop point vs RMS sample-to-sample step
SEAM_FLOOR = 0.01  # ignore seam jumps below this fraction of full scale
FRAME = 1024


def read_wav(path: Path) -> tuple[list[float], int]:
    with wave.open(str(path), "rb") as w:
        if w.getnchannels() != 1 or w.getsampwidth() != 2:
            raise ValueError("expected mono PCM16")
        sr = w.getframerate()
        raw = w.readframes(w.getnframes())
    ints = struct.unpack(f"<{len(raw) // 2}h", raw)
    return [v / 32768.0 for v in ints], sr


def _biquad(x: list[float], b: tuple[float, float, float], a1: float, a2: float) -> list[float]:
    y = []
    x1 = x2 = y1 = y2 = 0.0
    for v in x:
        o = b[0] * v + b[1] * x1 + b[2] * x2 - a1 * y1 - a2 * y2
        y.append(o)
        x2, x1, y2, y1 = x1, v, y1, o
    return y


def k_weight(x: list[float], sr: int) -> list[float]:
    f0, g, q = 1681.974450955533, 3.999843853973347, 0.7071752369554196
    k = math.tan(math.pi * f0 / sr)
    vh = 10.0 ** (g / 20.0)
    vb = vh**0.4996667741545416
    a0 = 1.0 + k / q + k * k
    y = _biquad(
        x,
        ((vh + vb * k / q + k * k) / a0, 2.0 * (k * k - vh) / a0, (vh - vb * k / q + k * k) / a0),
        2.0 * (k * k - 1.0) / a0,
        (1.0 - k / q + k * k) / a0,
    )
    f0, q = 38.13547087602444, 0.5003270373238773
    k = math.tan(math.pi * f0 / sr)
    a0 = 1.0 + k / q + k * k
    return _biquad(y, (1.0, -2.0, 1.0), 2.0 * (k * k - 1.0) / a0, (1.0 - k / q + k * k) / a0)


def lufs(x: list[float], sr: int) -> float:
    """Integrated loudness, 400 ms blocks at 75 % overlap, -70 LUFS absolute and -10 LU relative gates.
    Sounds shorter than one block are measured as a single block."""
    if not x:
        return -math.inf
    z = k_weight(x, sr)
    blk, hop = int(0.4 * sr), int(0.1 * sr)
    starts = list(range(0, len(z) - blk + 1, hop)) or [0]
    powers = []
    for s in starts:
        seg = z[s : s + blk]
        powers.append(sum(v * v for v in seg) / len(seg))

    def to_l(p: float) -> float:
        return -0.691 + 10.0 * math.log10(p) if p > 0.0 else -math.inf

    kept = [p for p in powers if to_l(p) > -70.0]
    if not kept:
        return -math.inf
    rel = to_l(sum(kept) / len(kept)) - 10.0
    kept = [p for p in kept if to_l(p) > rel]
    return to_l(sum(kept) / len(kept))


def fft(a: list[complex]) -> list[complex]:
    n = len(a)
    if n == 1:
        return a
    ev, od = fft(a[0::2]), fft(a[1::2])
    t = [cmath.exp(-2j * math.pi * k / n) * od[k] for k in range(n // 2)]
    return [ev[k] + t[k] for k in range(n // 2)] + [ev[k] - t[k] for k in range(n // 2)]


def spectral_centroid(x: list[float], sr: int) -> float:
    """Power-weighted mean frequency of the Welch-averaged spectrum (Hann, 50 % overlap)."""
    if len(x) < FRAME:
        x = x + [0.0] * (FRAME - len(x))
    win = [0.5 - 0.5 * math.cos(2.0 * math.pi * i / FRAME) for i in range(FRAME)]
    acc = [0.0] * (FRAME // 2 + 1)
    for s in range(0, len(x) - FRAME + 1, FRAME // 2):
        spec = fft([complex(x[s + i] * win[i]) for i in range(FRAME)])
        for k in range(FRAME // 2 + 1):
            acc[k] += abs(spec[k]) ** 2
    total = sum(acc)
    if total <= 0.0:
        return 0.0
    return sum(k * sr / FRAME * p for k, p in enumerate(acc)) / total


def seam_ratio(x: list[float]) -> float:
    """Jump from the last sample to the first, in units of the RMS sample-to-sample step."""
    if len(x) < 4:
        return 0.0
    steps = [x[i + 1] - x[i] for i in range(len(x) - 1)]
    rms = math.sqrt(sum(d * d for d in steps) / len(steps))
    jump = abs(x[0] - x[-1])
    return jump / max(rms, 1e-6)


def analyze_samples(x: list[float], sr: int) -> dict:
    peak = max((abs(v) for v in x), default=0.0)
    run = clipped = 0
    for v in x:
        if abs(v) >= 32767.0 / 32768.0:
            run += 1
            if run == CLIP_RUN:
                clipped += CLIP_RUN
            elif run > CLIP_RUN:
                clipped += 1
        else:
            run = 0
    return {
        "sample_rate": sr,
        "duration_s": round(len(x) / sr, 4),
        "peak_dbfs": round(20.0 * math.log10(peak), 2) if peak > 0 else -math.inf,
        "clipped_samples": clipped,
        "dc_offset": round(sum(x) / len(x), 5) if x else 0.0,
        "lufs": round(lufs(x, sr), 2),
        "centroid_hz": round(spectral_centroid(x, sr), 1),
        "seam_jump": round(abs(x[0] - x[-1]), 5) if x else 0.0,
        "seam_ratio": round(seam_ratio(x), 2),
    }


def analyze_wav(path: Path) -> dict:
    x, sr = read_wav(path)
    return analyze_samples(x, sr)


def check(m: dict, loop: bool = False, lufs_target: float | None = None, lufs_tol: float = 2.0,
          centroid: tuple[float, float] | None = None, duration: tuple[float, float] | None = None) -> list[str]:
    problems = []
    if m["clipped_samples"] > 0:
        problems.append(f"clipping: {m['clipped_samples']} samples at full scale")
    if m["peak_dbfs"] > PEAK_CEILING_DB:
        problems.append(f"peak {m['peak_dbfs']} dBFS above the {PEAK_CEILING_DB} dBFS ceiling")
    if abs(m["dc_offset"]) > DC_LIMIT:
        problems.append(f"DC offset {m['dc_offset']} exceeds {DC_LIMIT}")
    if m["duration_s"] > MAX_DURATION_S:
        problems.append(f"duration {m['duration_s']} s exceeds {MAX_DURATION_S} s")
    if loop and m["seam_jump"] > SEAM_FLOOR and m["seam_ratio"] > SEAM_LIMIT:
        problems.append(f"bad loop seam: jump {m['seam_jump']} = {m['seam_ratio']}x the typical step (limit {SEAM_LIMIT}x)")
    if lufs_target is not None and abs(m["lufs"] - lufs_target) > lufs_tol:
        problems.append(f"loudness {m['lufs']} LUFS not within {lufs_tol} of {lufs_target}")
    if centroid is not None and not centroid[0] <= m["centroid_hz"] <= centroid[1]:
        problems.append(f"spectral centroid {m['centroid_hz']} Hz outside {centroid[0]}-{centroid[1]} Hz")
    if duration is not None and not duration[0] <= m["duration_s"] <= duration[1]:
        problems.append(f"duration {m['duration_s']} s outside {duration[0]}-{duration[1]} s")
    return problems


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Numeric SFX acceptance (07 s8.4).")
    ap.add_argument("wav", type=Path)
    ap.add_argument("--loop", action="store_true")
    ap.add_argument("--lufs", type=float)
    ap.add_argument("--lufs-tol", type=float, default=2.0)
    ap.add_argument("--centroid", type=float, nargs=2, metavar=("LO", "HI"))
    ap.add_argument("--duration", type=float, nargs=2, metavar=("LO", "HI"))
    ap.add_argument("--recipe", type=Path, help="take loop and targets from this recipe")
    a = ap.parse_args(argv)
    loop, lt, tol, cen, dur = a.loop, a.lufs, a.lufs_tol, a.centroid, a.duration
    if a.recipe:
        r = json.loads(a.recipe.read_text(encoding="utf-8"))
        t = r.get("targets", {})
        loop = loop or bool(r.get("loop"))
        lt = t.get("lufs", lt)
        tol = t.get("lufs_tol", tol)
        cen = tuple(t["centroid_hz"]) if "centroid_hz" in t else cen
        dur = tuple(t["duration_s"]) if "duration_s" in t else dur
    m = analyze_wav(a.wav)
    print(json.dumps(m, indent=2, sort_keys=True))
    problems = check(m, loop, lt, tol, tuple(cen) if cen else None, tuple(dur) if dur else None)
    for p in problems:
        print(f"{a.wav}:1: {p}", file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
