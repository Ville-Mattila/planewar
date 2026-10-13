#!/usr/bin/env python3
"""Dependency and hygiene checker, rules D1-D10 of docs/03 s12.4 (stdlib only).

Usage:
    python tools/check_deps.py                      # whole repo
    python tools/check_deps.py FILE [FILE ...]      # only the given files (editor/PostToolUse hook)
    python tools/check_deps.py --root DIR ...       # treat DIR as the repo root (tests)
    python tools/check_deps.py --quiet              # hide warnings (D6 literals)
    python tools/check_deps.py --warnings-as-errors # D6 warnings fail too

Output: one line per finding, `path:line: Dn message` (path relative to the repo root;
warnings read `Dn warning: message`). Exit code 0 = no errors, 1 = at least one error,
2 = usage / unreadable configuration.

Rules (tables: tools/deps.json = docs/reviews/R0 Part B.4; D6 allowlist: tools/d6_allow.txt):
    D1 layering (module deps + named sim types)      D6 6000/8192 and float literals
    D2 no Nodes/await/signals in sim, sim_ai, core   D7 file <= 400 lines, one class_name
    D3 no threads (offline_host.gd web-guarded)      D8 warning keys == 2 in project.godot
    D4 exactly three autoloads                       D9 OS.execute/JavaScriptBridge/abs FileAccess
    D5 addon allowlist and res://addons/ refs        D10 MODULE.md test entry points exist
Scripts registered under [autoload] in project.godot are exempt from D2 and from the D7
class_name requirement (Godot rejects a global class sharing an autoload's name).
In file mode, per-file rules run on .gd/.tscn files under godot/src or godot/scenes, and the
repo rules run when the given file is project.godot (D4, D8), a src/<module>/MODULE.md (D10)
or lives under godot/addons (D5). Other files are ignored.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from depscheck import rules_repo, rules_src  # noqa: E402
from depscheck.source import Violation, build_context  # noqa: E402

DEFAULT_ROOT = Path(__file__).resolve().parent.parent


def run(root: Path, files: list[Path] | None = None) -> list[Violation]:
    """Return all violations (errors and warnings) for the repo or just `files`."""
    root = root.resolve()
    ctx = build_context(root)
    allow, allow_errs = rules_src.load_d6_allow(root)
    out: list[Violation] = []
    godot = root / "godot"
    if files is None:
        out += allow_errs
        out += rules_repo.check_autoloads(ctx)
        out += rules_repo.check_addons(ctx)
        out += rules_repo.check_warning_config(ctx)
        out += rules_repo.check_module_docs(ctx)
        for sub in ("src", "scenes"):
            base = godot / sub
            if not base.is_dir():
                continue
            for p in sorted(base.rglob("*")):
                if p.suffix == ".gd" and sub == "src":
                    out += rules_src.check_gd(ctx, p, allow)
                elif p.suffix == ".tscn":
                    out += rules_src.check_tscn(ctx, p)
        # addon references from non-src/scenes are out of scope by design
    else:
        seen: set[Path] = set()
        for f in files:
            p = f.resolve()
            if p in seen or not p.is_file():
                continue
            seen.add(p)
            try:
                p.relative_to(godot)
            except ValueError:
                continue
            rel = p.relative_to(godot).parts
            if p.name == "project.godot":
                out += rules_repo.check_autoloads(ctx) + rules_repo.check_warning_config(ctx)
            elif p.name == "MODULE.md" and len(rel) == 3 and rel[0] == "src":
                out += rules_repo.check_module_tests(ctx, p)
            elif rel[0] == "addons":
                out += rules_repo.check_addons(ctx)
            elif p.suffix == ".gd" and rel[0] == "src":
                out += rules_src.check_gd(ctx, p, allow)
            elif p.suffix == ".tscn" and rel[0] == "scenes":
                out += rules_src.check_tscn(ctx, p)
        # de-duplicate (e.g. several addon files report the same directory)
        out = list(dict.fromkeys(out))
    return out


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="PLANEWAR dependency checker (D1-D10).")
    ap.add_argument("files", nargs="*", help="check only these files (default: whole repo)")
    ap.add_argument("--root", type=Path, default=DEFAULT_ROOT, help="repo root (default: parent of tools/)")
    ap.add_argument("--quiet", action="store_true", help="do not print warnings")
    ap.add_argument("--warnings-as-errors", action="store_true", help="warnings also fail the run")
    args = ap.parse_args(argv)
    root = args.root.resolve()
    if not (root / "tools" / "deps.json").is_file():
        print(f"check_deps: {root / 'tools' / 'deps.json'} not found", file=sys.stderr)
        return 2
    files = [Path(f) for f in args.files] if args.files else None
    found = run(root, files)
    errors = [v for v in found if not v.warning]
    warns = [v for v in found if v.warning]
    for v in sorted(errors, key=lambda v: (v.path, v.line, v.rule)):
        print(v.format())
    if not args.quiet:
        for v in sorted(warns, key=lambda v: (v.path, v.line)):
            print(v.format())
    failed = bool(errors) or (args.warnings_as_errors and bool(warns))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
