#!/usr/bin/env python3
"""write_import.py - writes the committed `<asset>.glb.import` next to a glb (ART-05, docs/07 s4.6).

    python tools/art/write_import.py <file.glb|dir> [...] [--project godot] [--check]

The import options come from `tools/art/glb.import.template`, whose key names were captured from a Godot 4.7.2
headless import of a glb (so they are exact); only the values 07 s4.6 lists differ from the engine defaults.
The uid and the cache hash are derived from the `res://` path, so the file is reproducible and a re-run is a no-op.
`--check` writes nothing and exits 1 when a `.glb.import` is missing or stale (CI uses it).
Models live in godot/assets/models/<ships|ground|structures|props|projectiles>/<asset_id>.glb (07 s9).
"""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
TEMPLATE = HERE / "glb.import.template"
DEFAULT_PROJECT = HERE.parent.parent / "godot"
ID_RE = re.compile(r"^(ship|gnd|str|prop|proj|wreck)_[a-z0-9_]+$")
UID_CHARS = "abcdefghijklmnopqrstuvwxy0123456789"  # ResourceUID char_map (34 symbols)
# 07 s4.6: shadow meshes for units and structures, none for props; wrecks and projectiles are prop-like.
NO_SHADOW_MESHES = ("prop", "proj", "wreck")
MODEL_DIRS = {"ship": "ships", "gnd": "ground", "str": "structures", "prop": "props", "proj": "projectiles", "wreck": "props"}


def uid_text(res_path: str) -> str:
    """Deterministic `uid://...`: first 63 bits of md5(res_path), written in base 34 like ResourceUID.id_to_text."""
    n = int.from_bytes(hashlib.md5(res_path.encode()).digest()[:8], "big") & 0x7FFFFFFFFFFFFFFF
    n = n or 1
    out = ""
    while n:
        out = UID_CHARS[n % 34] + out
        n //= 34
    return "uid://" + out


def res_path_of(glb: Path, project: Path) -> str:
    try:
        rel = glb.resolve().relative_to(project.resolve())
    except ValueError as e:
        raise ValueError(f"{glb} is not inside the Godot project {project}") from e
    return "res://" + rel.as_posix()


def render(res_path: str, template: str | None = None) -> str:
    name = res_path.rsplit("/", 1)[-1]
    asset_id = name[: -len(".glb")] if name.endswith(".glb") else name
    if not ID_RE.match(asset_id):
        raise ValueError(f"{res_path}: file name must be <asset_id>.glb with asset_id matching {ID_RE.pattern}")
    cls = asset_id.split("_", 1)[0]
    text = template if template is not None else TEMPLATE.read_text(encoding="utf-8")
    digest = hashlib.md5(res_path.encode()).hexdigest()
    for key, val in (("$UID$", uid_text(res_path)), ("$NAME$", name), ("$HASH$", digest), ("$RES$", res_path),
                     ("$SHADOW$", "false" if cls in NO_SHADOW_MESHES else "true")):
        text = text.replace(key, val)
    return text


def collect(paths: list[str]) -> list[Path]:
    out: list[Path] = []
    for p in map(Path, paths):
        out.extend(sorted(p.rglob("*.glb")) if p.is_dir() else [p])
    return out


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--project", default=str(DEFAULT_PROJECT), help="Godot project dir (default godot/)")
    ap.add_argument("--check", action="store_true", help="do not write; exit 1 on a missing or stale .import")
    args = ap.parse_args(argv)
    project = Path(args.project)
    bad = 0
    files = collect(args.paths)
    if not files:
        print("write_import: no .glb files found", file=sys.stderr)
        return 1
    for glb in files:
        try:
            text = render(res_path_of(glb, project))
        except ValueError as e:
            print(f"{glb}:1: {e}", file=sys.stderr)
            bad += 1
            continue
        target = glb.with_name(glb.name + ".import")
        have = target.read_text(encoding="utf-8") if target.is_file() else None
        if args.check:
            if have != text:
                print(f"{target}:1: {'missing' if have is None else 'stale'} (run tools/art/write_import.py)", file=sys.stderr)
                bad += 1
        elif have != text:
            target.write_text(text, encoding="utf-8", newline="\n")
            print(f"wrote {target}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
