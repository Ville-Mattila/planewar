"""CI gate for the locale tables (docs/06 s11 "Checks (CI)").

Fails on: bad CSV shape, malformed or duplicate id, empty English, plural row without its sibling, placeholder
set mismatch en vs fi, len(en|fi) > max_len (default 1.4 x len(en)), a tr()/tr_n()/scene key with no row,
a pseudolocale PO that lost an id or a placeholder. Prints the Finnish coverage; --require-fi-full (release
branches) fails below 100 %.

  python tools/locale/check_locale.py [--require-fi-full] [--pseudo-dir DIR]
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import locale_lib as L

TR_RE = re.compile(r"""\btr(?:_n)?\(\s*&?["']([^"'%{}]+)["']""")
TSCN_RE = re.compile(r"""^\s*(?:text|tooltip_text|title|placeholder_text)\s*=\s*"([^"]+)"\s*$""", re.M)


def effective_max_len(row: L.Row) -> float:
    return float(row.max_len) if row.max_len.strip() else L.DEFAULT_MAX_FACTOR * len(row.en)


def check_rows(table: L.Table) -> list[str]:
    errors = list(table.errors)
    seen: dict[str, str] = {}
    for r in table.rows:
        where = f"{r.source}:{r.id}"
        if not L.ID_RE.match(r.id):
            errors.append(f"{where}: id must be lowercase dotted snake case [#one|#other]")
        if r.id in seen:
            errors.append(f"{where}: duplicate id (also in {seen[r.id]})")
        seen[r.id] = r.source
        if not r.en.strip():
            errors.append(f"{where}: English text is empty")
        if r.max_len.strip() and not r.max_len.strip().isdigit():
            errors.append(f"{where}: max_len must be an integer, got '{r.max_len}'")
            continue
        limit = effective_max_len(r)
        if r.max_len.strip() and len(r.en) > limit:
            errors.append(f"{where}: en is {len(r.en)} chars, max_len {r.max_len}")
        if r.fi.strip():
            if L.placeholders(r.en) != L.placeholders(r.fi):
                errors.append(f"{where}: placeholders differ en {sorted(L.placeholders(r.en))} "
                              f"vs fi {sorted(L.placeholders(r.fi))}")
            if len(r.fi) > limit:
                errors.append(f"{where}: fi is {len(r.fi)} chars, max_len {limit:g}")
    bases: dict[str, set[str]] = {}
    for r in table.rows:
        if "#" in r.id:
            bases.setdefault(r.id.split("#", 1)[0], set()).add(r.id.split("#", 1)[1])
        elif r.id in bases:
            errors.append(f"{r.id}: plural and singular rows mixed")
    for base, forms in bases.items():
        if forms != set(L.PLURAL_FORMS):
            errors.append(f"{base}: plural needs both #one and #other rows, has {sorted(forms)}")
    return errors


def scan_keys(root: Path) -> dict[str, list[str]]:
    """Literal keys used by tr()/tr_n() in .gd and by text properties in .tscn, with their files."""
    used: dict[str, list[str]] = {}
    for path in sorted((root / "src").rglob("*.gd")):
        for key in TR_RE.findall(path.read_text(encoding="utf-8")):
            used.setdefault(key, []).append(path.relative_to(root).as_posix())
    for path in sorted((root / "scenes").rglob("*.tscn")):
        for key in TSCN_RE.findall(path.read_text(encoding="utf-8")):
            if L.ID_RE.match(key):
                used.setdefault(key, []).append(path.relative_to(root).as_posix())
    return used


def check_keys(table: L.Table, used: dict[str, list[str]]) -> list[str]:
    ids = {r.id.split("#", 1)[0] for r in table.rows}
    return [f"{files[0]}: key '{k}' has no locale row" for k, files in sorted(used.items()) if k not in ids]


def check_pseudo(table: L.Table, po_text: str) -> list[str]:
    entries = L.parse_po(po_text)
    errors: list[str] = []
    for base, rows in L.group_plurals(table.rows):
        if base not in entries:
            errors.append(f"pseudo: missing id {base}")
            continue
        for form in rows:
            n = L.PLURAL_FORMS.index(form.id.split("#", 1)[1]) if "#" in form.id else 0
            got = entries[base][n] if n < len(entries[base]) else ""
            if L.placeholders(got) != L.placeholders(form.en):
                errors.append(f"pseudo: {form.id} lost or changed a placeholder")
    return errors


def coverage(table: L.Table) -> tuple[int, int]:
    return sum(1 for r in table.rows if r.fi.strip()), len(table.rows)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--locale-dir", type=Path, default=L.LOCALE_DIR)
    ap.add_argument("--godot-dir", type=Path, default=L.REPO / "godot")
    ap.add_argument("--require-fi-full", action="store_true")
    ap.add_argument("--pseudo-dir", type=Path, default=None)
    args = ap.parse_args(argv)
    table = L.load_table(args.locale_dir)
    errors = check_rows(table)
    errors += check_keys(table, scan_keys(args.godot_dir))
    if args.pseudo_dir is not None:
        pseudo = args.pseudo_dir / "en_XA.po"
        errors += check_pseudo(table, pseudo.read_text(encoding="utf-8")) if pseudo.exists() else [f"missing {pseudo}"]
    done, total = coverage(table)
    pct = 100.0 * done / total if total else 100.0
    print(f"locale: {total} strings, fi coverage {done}/{total} ({pct:.1f} %)")
    if args.require_fi_full and done < total:
        errors.append(f"fi coverage {pct:.1f} % < 100 % (release branch)")
    for e in errors:
        print("ERROR " + e, file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
