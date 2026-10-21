#!/usr/bin/env python3
"""Wall-clock bound lint for unit, sim and net tests (TEST-03; R0 B.17 A-97; 03 s4.4, 10 s3.5 item 3). Stdlib only.

On a GitHub-hosted runner a test under godot/test/unit|sim|net must never fail on wall-clock time. A file there
that calls Time.get_ticks_usec() or Time.get_ticks_msec() must therefore do one of:
    - reference PerfGate (godot/test/perf_gate.gd: report-only unless PLANEWAR_PINNED_RUNNER=1);
    - carry the file-level comment `## timing: runaway guards only (R0 B.17 A-97)` (every bound is >= 10x the
      recorded figure; the reviewer checks the classification);
    - transitional: gate inline on the PLANEWAR_PINNED_RUNNER variable (A-97 item 4 allows a lane to inline the same
      four lines until it converts to PerfGate; e.g. test_dart_perf.gd of AI-13). Accepted, reported as a notice.

Usage:  python tools/check_perf_gates.py [--root DIR]
Exit:   0 ok, 1 violations ("<path>:<line>: message" per file), 2 usage error.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
LAYERS = ("unit", "sim", "net")
MARKER = "## timing: runaway guards only (R0 B.17 A-97)"
CALL_RE = re.compile(r"\bget_ticks_(?:usec|msec)\s*\(")
GATE_RE = re.compile(r"\bPerfGate\b")
INLINE_RE = re.compile(r"PLANEWAR_PINNED_RUNNER")


def first_timing_line(text: str) -> int | None:
    """1-based line of the first non-comment call to get_ticks_usec/msec, else None."""
    for n, line in enumerate(text.splitlines(), 1):
        code = line.split("#", 1)[0]
        if CALL_RE.search(code):
            return n
    return None


def check_text(text: str) -> tuple[str, str | None]:
    """Return (status, message): status in ok, inline, fail."""
    line = first_timing_line(text)
    if line is None:
        return "ok", None
    if any(GATE_RE.search(l.split("#", 1)[0]) for l in text.splitlines()):
        return "ok", None
    if any(l.strip() == MARKER for l in text.splitlines()):
        return "ok", None
    if INLINE_RE.search(text):
        return "inline", f"{line}: inline PLANEWAR_PINNED_RUNNER gate; convert to PerfGate"
    return "fail", (f"{line}: wall-clock bound without PerfGate or the file comment '{MARKER}' "
                    "(R0 B.17 A-97: a hosted-runner unit test never fails on time)")


def scan(root: Path) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    notices: list[str] = []
    for layer in LAYERS:
        base = root / "godot" / "test" / layer
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*.gd")):
            status, msg = check_text(path.read_text(encoding="utf-8", errors="replace"))
            rel = path.relative_to(root).as_posix()
            if status == "fail":
                errors.append(f"{rel}:{msg}")
            elif status == "inline":
                notices.append(f"{rel}:{msg}")
    return errors, notices


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    ap.add_argument("--root", type=Path, default=REPO)
    args = ap.parse_args(argv)
    errors, notices = scan(args.root)
    for n in notices:
        print(f"notice {n}")
    for e in errors:
        print(e, file=sys.stderr)
    if errors:
        print(f"check_perf_gates: {len(errors)} violation(s)", file=sys.stderr)
        return 1
    print("check_perf_gates: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
