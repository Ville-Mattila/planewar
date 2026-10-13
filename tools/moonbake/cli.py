"""moonbake CLI: bake, validate, preview, check, ramp. Exit codes: 0 ok, 1 validation failure, 2 usage or I/O."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

from .bake import bake, render_files, write_outputs
from .preview import write_preview
from .ramp import build_ramp
from .recipe import RecipeError, build_plan, load_recipe
from .validate import validate_baked, validate_static


def _load(path: str) -> dict:
    try:
        return load_recipe(Path(path))
    except RecipeError as exc:
        for line in exc.messages:
            print(line, file=sys.stderr)
        raise SystemExit(1)


def _log(quiet: bool):
    return (lambda msg: None) if quiet else (lambda msg: print(msg, file=sys.stderr))


def run_validate(recipe: dict, rpath: str, progress=None, baked=None) -> int:
    results = validate_static(build_plan(recipe))
    b = baked or bake(recipe, progress)
    files = render_files(b)
    results += validate_baked(b, files)
    bad = 0
    for r in results:
        print(f"{rpath}: {r}")
        bad += 0 if r.ok else 1
    print(f"moonbake validate: {len(results) - bad}/{len(results)} checks ok, bake {b.seconds:.1f} s")
    return 1 if bad else 0


def cmd_bake(a) -> int:
    recipe = _load(a.recipe)
    b = bake(recipe, _log(a.quiet))
    write_outputs(b, Path(a.out), preview=not a.no_preview)
    if a.ramp:
        build_ramp(Path(a.out) / "moon_ramp.png")
    print(f"moonbake bake: {recipe['id']} {b.n}x{b.n}x6 in {b.seconds:.1f} s -> {a.out}")
    return 0


def cmd_validate(a) -> int:
    recipe = _load(a.recipe)
    return run_validate(recipe, a.recipe, _log(a.quiet))


def cmd_preview(a) -> int:
    recipe = _load(a.recipe)
    b = bake(recipe, _log(a.quiet))
    names = write_preview(b, Path(a.out), full=True)
    print(f"moonbake preview: wrote {', '.join(names)} to {a.out}")
    return 0


def cmd_check(a) -> int:
    """Re-bake and compare every output with the committed meta.json (the bake-check CI step, 03 s8.6)."""
    rpath = Path(a.recipe)
    recipe = _load(a.recipe)
    meta = json.loads((rpath.parent / "meta.json").read_text(encoding="utf-8"))
    files = render_files(bake(recipe, _log(a.quiet)))
    bad = []
    for name, want in sorted(meta["outputs"].items()):
        got = hashlib.sha256(files[name]).hexdigest() if name in files else "(missing)"
        if got != want:
            bad.append(name)
    new_meta = json.loads(files["meta.json"])
    if new_meta["map_hash"] != meta["map_hash"] and not bad:
        bad.append("meta.json (map_hash)")
    for name in bad:
        print(f"{rpath.parent / name}: differs from a fresh bake of {rpath.name}", file=sys.stderr)
    print(f"moonbake check: {recipe['id']} {'OK' if not bad else str(len(bad)) + ' files differ'}")
    return 1 if bad else 0


def cmd_ramp(a) -> int:
    data = build_ramp(Path(a.out) if a.out else None, Path(a.ramps) if a.ramps else None)
    print(f"moonbake ramp: wrote {len(data)} bytes, sha256 {hashlib.sha256(data).hexdigest()[:16]}")
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="moonbake", description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name, fn in (("bake", cmd_bake), ("validate", cmd_validate), ("preview", cmd_preview), ("check", cmd_check)):
        p = sub.add_parser(name)
        p.add_argument("recipe")
        p.add_argument("--quiet", action="store_true")
        if name in ("bake", "preview"):
            p.add_argument("--out", required=True)
        if name == "bake":
            p.add_argument("--no-preview", action="store_true", help="skip preview.png (zlib output is not byte-stable)")
            p.add_argument("--ramp", action="store_true", help="also write moon_ramp.png next to the outputs")
        p.set_defaults(fn=fn)
    p = sub.add_parser("ramp", help="build moon_ramp.png from godot/content/biome_ramps.json (or the 07 s2.1 palette)")
    p.add_argument("--out")
    p.add_argument("--ramps")
    p.set_defaults(fn=cmd_ramp)
    a = ap.parse_args(argv)
    try:
        return a.fn(a)
    except (OSError, ValueError, RuntimeError) as exc:
        print(f"moonbake: {exc}", file=sys.stderr)
        return 2
