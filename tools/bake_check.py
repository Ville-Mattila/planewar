"""bake-check (TA-17, docs/03 s8.6): re-bake every map recipe and compare with the committed files.

For each `godot/content/maps/<id>/recipe.json` a fresh bake is rendered in memory. Every committed output
(`face*.u8/u16`, `features.json`, `meta.json`) must equal the fresh bytes; a stale `meta.json` (recipe hash, map hash
or output hash) or a stale binary therefore fails with the file named. `preview.png` is not hashed (03 s8.3).
Usage: python -I tools/bake_check.py [MAP_DIR ...]   Exit 0 all match, 1 any difference, 2 usage error.
"""

from __future__ import annotations

import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
REPO = TOOLS.parent
sys.path.insert(0, str(TOOLS))

from moonbake.bake import bake, render_files  # noqa: E402
from moonbake.recipe import RecipeError, load_recipe  # noqa: E402

MAPS_DIR = REPO / "godot/content/maps"


def _same(name: str, committed: bytes, fresh: bytes) -> bool:
    if name.endswith(".json"):  # text files: tolerate a CRLF working copy, the bytes of the index are LF (.gitattributes)
        return committed.replace(b"\r\n", b"\n") == fresh
    return committed == fresh


def check_map(map_dir: Path) -> list[str]:
    """Problems for one map directory; empty when every committed file equals a fresh bake."""
    recipe_path = map_dir / "recipe.json"
    try:
        recipe = load_recipe(recipe_path)
    except RecipeError as exc:
        return list(exc.messages)
    if not (map_dir / "meta.json").is_file():
        return [f"{map_dir / 'meta.json'}: missing; commit the bake (moonbake bake --no-preview)"]
    fresh = render_files(bake(recipe))
    problems: list[str] = []
    for name in sorted(fresh):
        path = map_dir / name
        if not path.is_file():
            problems.append(f"{path}: missing committed file")
        elif not _same(name, path.read_bytes(), fresh[name]):
            problems.append(f"{path}: differs from a fresh bake of {recipe_path.name} (stale or edited)")
    return problems


def map_dirs() -> list[Path]:
    return sorted(p.parent for p in MAPS_DIR.glob("*/recipe.json"))


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    targets = [Path(a) for a in args] if args else map_dirs()
    for t in targets:
        if not (t / "recipe.json").is_file():
            print(f"bake-check: {t}: no recipe.json", file=sys.stderr)
            return 2
    failed = 0
    for t in targets:
        problems = check_map(t)
        if problems:
            failed += 1
            for line in problems:
                print(line, file=sys.stderr)
        print(f"bake-check: {t.name} {'OK' if not problems else 'FAIL'}")
    print(f"bake-check: {len(targets) - failed}/{len(targets)} maps match a fresh bake")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
