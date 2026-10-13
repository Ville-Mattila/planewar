#!/usr/bin/env python3
"""Report on docs/backlog/backlog.json (stdlib only).

Default output: per milestone, the task count by status and by tier, plus totals.
--ready:        tasks whose status is "todo" and whose depends_on are all "done".
                Tier "Owner" tasks are left out unless --owner is also given.

Usage:
    python tools/backlog_report.py
    python tools/backlog_report.py --ready
    python tools/backlog_report.py --ready --owner
    python tools/backlog_report.py --file path/to/backlog.json

Exit codes: 0 ok, 2 unreadable or malformed backlog file.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_BACKLOG = ROOT / "docs" / "backlog" / "backlog.json"
REQUIRED = ("id", "milestone", "tier", "status", "depends_on")


def load(path: Path) -> list[dict]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise SystemExit(f"backlog_report: cannot read {path}: {exc}") from exc
    if not isinstance(data, list):
        raise SystemExit(f"backlog_report: {path} must hold a JSON list of tasks")
    for i, task in enumerate(data):
        missing = [k for k in REQUIRED if k not in task]
        if missing:
            raise SystemExit(f"backlog_report: task #{i} lacks {', '.join(missing)}")
    return data


def milestone_key(name: str) -> tuple[int, str]:
    # Sort "M0".."M8" numerically; anything else last, alphabetically.
    if name.startswith("M") and name[1:].isdigit():
        return (int(name[1:]), "")
    return (10**6, name)


def print_counts(tasks: list[dict]) -> None:
    by_ms: dict[str, list[dict]] = defaultdict(list)
    for t in tasks:
        by_ms[t["milestone"]].append(t)

    statuses = sorted({t["status"] for t in tasks})
    tiers = sorted({t["tier"] for t in tasks})

    print("Counts by milestone and status")
    print(_table(["milestone", *statuses, "total"],
                 [[ms, *[sum(1 for t in group if t["status"] == s) for s in statuses], len(group)]
                  for ms, group in _sorted_groups(by_ms)],
                 totals=True))
    print()
    print("Counts by milestone and tier")
    print(_table(["milestone", *tiers, "total"],
                 [[ms, *[sum(1 for t in group if t["tier"] == r) for r in tiers], len(group)]
                  for ms, group in _sorted_groups(by_ms)],
                 totals=True))
    print()
    print(f"{len(tasks)} tasks in {len(by_ms)} milestones")


def _sorted_groups(by_ms: dict[str, list[dict]]):
    return sorted(by_ms.items(), key=lambda kv: milestone_key(kv[0]))


def _table(header: list[str], rows: list[list], totals: bool) -> str:
    if totals and rows:
        width = len(header)
        total_row = ["TOTAL"] + [sum(r[i] for r in rows) for i in range(1, width)]
        rows = rows + [total_row]
    cells = [[str(c) for c in header]] + [[str(c) for c in r] for r in rows]
    widths = [max(len(r[i]) for r in cells) for i in range(len(header))]
    lines = []
    for n, r in enumerate(cells):
        lines.append("  ".join(c.ljust(widths[i]) for i, c in enumerate(r)).rstrip())
        if n == 0:
            lines.append("  ".join("-" * w for w in widths))
    return "\n".join(lines)


def ready_tasks(tasks: list[dict], include_owner: bool) -> list[dict]:
    done = {t["id"] for t in tasks if t["status"] == "done"}
    out = []
    for t in tasks:
        if t["status"] != "todo":
            continue
        if t["tier"] == "Owner" and not include_owner:
            continue
        if all(dep in done for dep in t["depends_on"]):
            out.append(t)
    return sorted(out, key=lambda t: (milestone_key(t["milestone"]), t["id"]))


def print_ready(tasks: list[dict], include_owner: bool) -> None:
    ready = ready_tasks(tasks, include_owner)
    scope = "including Owner tasks" if include_owner else "excluding Owner tasks"
    print(f"Ready tasks ({scope}): {len(ready)}")
    if not ready:
        return
    print(_table(["id", "milestone", "tier", "lane", "size_days", "title"],
                 [[t["id"], t["milestone"], t["tier"], t.get("lane", ""), t.get("size_days", ""),
                   t.get("title", "")] for t in ready],
                 totals=False))


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--file", type=Path, default=DEFAULT_BACKLOG, help="backlog.json path")
    ap.add_argument("--ready", action="store_true", help="list tasks ready to start")
    ap.add_argument("--owner", action="store_true", help="with --ready, include tier Owner tasks")
    args = ap.parse_args(argv)
    if args.owner and not args.ready:
        ap.error("--owner only applies with --ready")

    tasks = load(args.file)
    if args.ready:
        print_ready(tasks, args.owner)
    else:
        print_counts(tasks)
    return 0


if __name__ == "__main__":
    sys.exit(main())
