#!/usr/bin/env python3
"""Commit-subject lint (REPO-06; 01 ADR-14 (01:588); CLAUDE.md "Commit subjects start with the task id").

Every non-merge commit in the git range must have a subject of the form `<ID>: <text>`, where
<ID> is an id present in docs/backlog/backlog.json, or `WAVE: <text>` (orchestrator wave logs).
Merge commits are skipped (`--no-merges`); GitHub squash merges already carry `<ID>: ... (#N)`.

Usage:  python tools/lint_commits.py origin/main..HEAD
Exit:   0 all subjects valid (or empty range), 1 at least one violation, 2 usage or git error.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
REPO = TOOLS.parent
BACKLOG = REPO / "docs" / "backlog" / "backlog.json"

SPECIAL_PREFIXES = frozenset({"WAVE"})
PREFIX_RE = re.compile(r"^(?P<prefix>[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)+|WAVE): (?P<text>\S.*)$")


def load_ids(backlog: Path) -> frozenset[str]:
    """Return every task id in the backlog JSON (a list of objects with an `id` key)."""
    tasks = json.loads(backlog.read_text(encoding="utf-8"))
    return frozenset(str(t["id"]) for t in tasks)


def check_subject(subject: str, ids: frozenset[str]) -> str | None:
    """Return an error message for a bad subject, or None when it is valid."""
    match = PREFIX_RE.match(subject)
    if match is None:
        return "subject must start with '<ID>: ' (e.g. 'TA-03: ...') or 'WAVE: '"
    prefix = match.group("prefix")
    if prefix in SPECIAL_PREFIXES or prefix in ids:
        return None
    return f"'{prefix}' is not an id in docs/backlog/backlog.json"


def read_commits(repo: Path, rev_range: str) -> list[tuple[str, str]] | None:
    """Return (sha, subject) for non-merge commits in the range, or None on git failure."""
    proc = subprocess.run(
        ["git", "-C", str(repo), "log", "--no-merges", "--format=%H%x00%s", rev_range],
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr)
        return None
    commits: list[tuple[str, str]] = []
    for line in proc.stdout.splitlines():
        sha, _, subject = line.partition("\x00")
        commits.append((sha, subject))
    return commits


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Check commit subjects reference a backlog id.")
    parser.add_argument("rev_range", help="git revision range, e.g. origin/main..HEAD")
    parser.add_argument("--repo", type=Path, default=REPO, help="repository root (default: this repo)")
    parser.add_argument("--backlog", type=Path, default=BACKLOG, help="backlog JSON (default: this repo's)")
    args = parser.parse_args(argv)

    ids = load_ids(args.backlog)
    commits = read_commits(args.repo, args.rev_range)
    if commits is None:
        return 2

    failures = 0
    for sha, subject in commits:
        error = check_subject(subject, ids)
        if error is not None:
            failures += 1
            print(f"::error::{sha[:10]} {subject!r}: {error}")
    if failures:
        print(f"commit lint: {failures} of {len(commits)} commit(s) in {args.rev_range} invalid")
        return 1
    print(f"commit lint: {len(commits)} commit(s) in {args.rev_range} OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
