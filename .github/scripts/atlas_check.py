#!/usr/bin/env python3
"""Pixel-level freshness check of godot/assets/textures/unit_atlas.png.

tools/blender/build_palette.py --check compares PNG *bytes*, which depend on the zlib build
(Windows CPython 3.14 ships zlib-ng, Linux CI uses zlib), so it reports STALE on a correct atlas.
This check regenerates the pixels with the same builder and compares decoded RGBA instead.
Usage (repo root): python .github/scripts/atlas_check.py
"""
import importlib.util
import json
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.dirname(__file__))
from png_check import read_png  # noqa: E402


def main() -> int:
    spec = importlib.util.spec_from_file_location("build_palette", os.path.join(ROOT, "tools", "blender", "build_palette.py"))
    bp = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(bp)
    with open(bp.PALETTE, encoding="utf-8") as f:
        pal = json.load(f)
    size, rgba = bp.build(pal)
    w, h, bpp, rows = read_png(bp.DEFAULT_OUT)
    got = b"".join(bytes(r) for r in rows)
    ok = (w, h, bpp) == (size, size, 4) and got == bytes(rgba)
    print("unit_atlas.png pixels up to date" if ok else "unit_atlas.png pixels are STALE: run tools/blender/build_palette.py")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
