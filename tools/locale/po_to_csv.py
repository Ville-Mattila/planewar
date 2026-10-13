"""Re-imports a translator's PO file into the CSV domains (docs/06 s11).

  python tools/locale/po_to_csv.py fi path/to/fi.po [--dry-run]

Only the language column is rewritten; ids not found in any CSV are reported and the run fails.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import locale_lib as L


def import_po(locale_dir: Path, lang: str, po_text: str, dry_run: bool = False) -> int:
    if lang not in L.LANGS or lang == "en":
        print(f"only translated columns can be imported (got '{lang}')", file=sys.stderr)
        return 1
    entries = L.parse_po(po_text)
    known: set[str] = set()
    changed = 0
    for path in sorted((locale_dir / "src").glob("*.csv")):
        t = L.Table()
        L.load_csv(path, t)
        if t.errors:
            print("\n".join(t.errors), file=sys.stderr)
            return 1
        dirty = False
        for row in t.rows:
            base, _, form = row.id.partition("#")
            known.add(base)
            if base not in entries:
                continue
            strs = entries[base]
            idx = L.PLURAL_FORMS.index(form) if form else 0
            new = strs[idx] if idx < len(strs) else ""
            if new != row.fi:
                row.fi = new
                dirty = True
                changed += 1
        if dirty and not dry_run:
            L.write_csv(path, t.rows)
    unknown = sorted(set(entries) - known)
    for u in unknown:
        print(f"unknown id in PO: {u}", file=sys.stderr)
    print(f"{lang}: {changed} strings updated")
    return 1 if unknown else 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("lang")
    ap.add_argument("po", type=Path)
    ap.add_argument("--locale-dir", type=Path, default=L.LOCALE_DIR)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args(argv)
    return import_po(args.locale_dir, args.lang, args.po.read_text(encoding="utf-8"), args.dry_run)


if __name__ == "__main__":
    sys.exit(main())
