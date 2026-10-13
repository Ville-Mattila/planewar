#!/usr/bin/env python3
"""Licence ledger gate, ART-32 (docs/07 s8.4 and IP rule 6). Stdlib only.

Ledger: docs/credits/ASSET_LICENCES.csv, columns exactly as docs/07 s8.4:
    asset_id, path, sha256, source_url_or_recipe, author, licence,
    attribution_required, price, date, proof_file

Scope: every file under godot/assets/** and every font or audio file anywhere under godot/
(excluding godot/addons, godot/.godot and build output). Exempt: .gitkeep and Godot *.import
sidecars (generated metadata for an asset that has its own row).

Fails when:
    - a scoped file has no ledger row;
    - a row names a file that does not exist;
    - a row's licence is not on the allowed list (ALLOWED_LICENCES, from 07 s8.4), or a
      licence is used on a file type it does not cover (CC-BY only for audio, OFL only for fonts);
    - a row is malformed: wrong header, wrong column count, empty required field, sha256 that is
      not 64 hex digits, duplicate asset_id or path.

Usage:
    python tools/check_licences.py [--root DIR]

Exit codes: 0 ok, 1 violations. Output: one "<path>:<line>: message" line per violation.
"""

from __future__ import annotations

import argparse
import csv
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LEDGER = "docs/credits/ASSET_LICENCES.csv"
COLUMNS = [
    "asset_id", "path", "sha256", "source_url_or_recipe", "author", "licence",
    "attribution_required", "price", "date", "proof_file",
]
REQUIRED = [c for c in COLUMNS if c != "proof_file"]
AUDIO_EXTS = frozenset({".wav", ".ogg", ".mp3", ".flac", ".qoa"})
FONT_EXTS = frozenset({".ttf", ".otf", ".woff", ".woff2"})
MEDIA_EXTS = AUDIO_EXTS | FONT_EXTS
EXEMPT_NAMES = frozenset({".gitkeep"})
EXEMPT_SUFFIXES = (".import",)
PRUNE_DIRS = frozenset({"addons", ".godot", "reports", "build"})

# 07 s8.4 "Sourcing" plus IP rule 5 (fonts OFL only). Anything not listed fails.
ALLOWED_LICENCES = {
    "original": "made in-house by a repo tool or by hand; source_url_or_recipe names it",
    "CC0-1.0": "public domain dedication",
    "public-domain": "public domain with proof in proof_file",
    "OFL-1.1": "SIL Open Font Licence; fonts only",
    "CC-BY-4.0": "attribution; SFX and music only, attribution_required must be yes",
    "commercial-licence": "purchased licence allowing closed-source use on all platforms incl. web",
    "commissioned": "contract assigns or licenses all rights worldwide; source names the contract",
}
FORBIDDEN_RE = re.compile(r"NC|NON.?COMMERCIAL|-SA|GPL|\bAI\b", re.IGNORECASE)
SHA_RE = re.compile(r"[0-9a-f]{64}")


def licence_problem(row: dict[str, str], path: str) -> str | None:
    """Return a message when the row's licence is not allowed for this file, else None."""
    licence = row["licence"]
    ext = os.path.splitext(path)[1].lower()
    if row["attribution_required"] not in ("yes", "no"):
        return "attribution_required must be yes or no"
    if licence not in ALLOWED_LICENCES:
        tag = " (forbidden)" if FORBIDDEN_RE.search(licence) else ""
        return f"licence '{licence}' is not on the allowed list{tag}"
    if licence == "CC-BY-4.0":
        if ext not in AUDIO_EXTS:
            return "CC-BY-4.0 is allowed only for SFX and music (audio files)"
        if row["attribution_required"] != "yes":
            return "CC-BY-4.0 requires attribution_required=yes"
    if licence == "OFL-1.1" and ext not in FONT_EXTS:
        return "OFL-1.1 is allowed only for fonts"
    return None


def scoped_files(root: Path) -> list[str]:
    """Repo-relative POSIX paths that need a ledger row."""
    godot = root / "godot"
    out: list[str] = []
    if not godot.is_dir():
        return out
    for dirpath, dirnames, filenames in os.walk(godot):
        dirnames[:] = [d for d in dirnames if d not in PRUNE_DIRS]
        rel_dir = Path(dirpath).relative_to(root).as_posix()
        in_assets = rel_dir == "godot/assets" or rel_dir.startswith("godot/assets/")
        for name in filenames:
            if name in EXEMPT_NAMES or name.endswith(EXEMPT_SUFFIXES):
                continue
            ext = os.path.splitext(name)[1].lower()
            if in_assets or ext in MEDIA_EXTS:
                out.append(f"{rel_dir}/{name}")
    return sorted(out)


def check(root: Path) -> list[str]:
    """Return every violation as a 'path:line: message' string (empty list means pass)."""
    ledger = root / LEDGER
    if not ledger.is_file():
        return [f"{LEDGER}:1: ledger file is missing"]
    errors: list[str] = []
    with ledger.open(newline="", encoding="utf-8") as fh:
        reader = csv.reader(fh)
        header = next(reader, None)
        if header != COLUMNS:
            return [f"{LEDGER}:1: header must be {','.join(COLUMNS)}"]
        rows = [(reader.line_num, rec) for rec in reader if any(c.strip() for c in rec)]

    seen_ids: set[str] = set()
    seen_paths: set[str] = set()
    covered: set[str] = set()
    for line, rec in rows:
        where = f"{LEDGER}:{line}"
        if len(rec) != len(COLUMNS):
            errors.append(f"{where}: expected {len(COLUMNS)} columns, got {len(rec)}")
            continue
        row = {col: value.strip() for col, value in zip(COLUMNS, rec)}
        empty = [col for col in REQUIRED if not row[col]]
        if empty:
            errors.append(f"{where}: empty required field(s): {', '.join(empty)}")
            continue
        path = row["path"].replace("\\", "/")
        if row["asset_id"] in seen_ids:
            errors.append(f"{where}: duplicate asset_id {row['asset_id']}")
        seen_ids.add(row["asset_id"])
        if not SHA_RE.fullmatch(row["sha256"]):
            errors.append(f"{where}: sha256 must be 64 lowercase hex digits")
        if path in seen_paths:
            errors.append(f"{where}: duplicate path {path}")
        seen_paths.add(path)
        if path.startswith("/") or ".." in path.split("/") or not (root / path).is_file():
            errors.append(f"{where}: row names a file that does not exist: {path}")
            continue
        problem = licence_problem(row, path)
        if problem:
            errors.append(f"{where}: {path}: {problem}")
        covered.add(path)

    for path in scoped_files(root):
        if path not in covered:
            errors.append(f"{path}:1: no row in {LEDGER}")
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Check the asset licence ledger (ART-32).")
    parser.add_argument("--root", type=Path, default=ROOT, help="repository root (tests)")
    args = parser.parse_args(argv)
    errors = check(args.root.resolve())
    for err in errors:
        print(err)
    print(f"check_licences: {len(errors)} violation(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
