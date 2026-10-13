"""Builds godot/content/locale/en.po and fi.po from the CSV domains (docs/06 s11).

  python tools/locale/build_po.py            write en.po, fi.po
  python tools/locale/build_po.py --check    exit 1 when the committed PO files are stale (CI)
  python tools/locale/build_po.py --pseudo --out DIR   also write DIR/en_XA.po (accented, +40 % length)
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import locale_lib as L


def build(locale_dir: Path, out_dir: Path, pseudo: bool, check: bool) -> int:
    table = L.load_table(locale_dir)
    if table.errors:
        print("\n".join(table.errors), file=sys.stderr)
        return 1
    targets: dict[Path, str] = {out_dir / f"{lang}.po": L.render_po(table, lang) for lang in L.LANGS}
    if pseudo:
        targets[out_dir / "en_XA.po"] = L.render_po(table, "en", pseudo=True)
    stale = 0
    for path, text in targets.items():
        if check:
            cur = path.read_text(encoding="utf-8") if path.exists() else None
            if cur != text:
                print(f"stale: {path.name} (run tools/locale/build_po.py)", file=sys.stderr)
                stale += 1
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8", newline="\n")
            print(f"wrote {path.name}: {len(L.group_plurals(table.rows))} entries")
    return 1 if stale else 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--locale-dir", type=Path, default=L.LOCALE_DIR)
    ap.add_argument("--out", type=Path, default=None, help="output dir (default: the locale dir)")
    ap.add_argument("--pseudo", action="store_true")
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args(argv)
    if args.check and args.pseudo:
        ap.error("--check checks the committed PO files only")
    return build(args.locale_dir, args.out or args.locale_dir, args.pseudo, args.check)


if __name__ == "__main__":
    sys.exit(main())
