#!/usr/bin/env python3
"""Build godot/assets/textures/unit_atlas.png from tools/blender/palette.json (ART-02, docs/07 s4.3).

256x256 RGBA8. 16x14 grid of 16 px swatches (row-major cell order = palette.json order:
'swatches' entries, then biome ramps). Rows 14-15 (y 224-255): 8 emblems of 32x32, white
shape on dark, one per team shape. Alpha of a swatch = class code (0/85/170/255).
Deterministic: pure stdlib, fixed zlib level, no timestamps.

Usage: python tools/blender/build_palette.py [--out PATH] [--check]
  --check  build in memory and fail (exit 1) if the file on disk differs.
"""
import json
import math
import os
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
PALETTE = os.path.join(HERE, "palette.json")
DEFAULT_OUT = os.path.join(ROOT, "godot", "assets", "textures", "unit_atlas.png")


def hex_bytes(h):
    h = h.lstrip("#")
    return bytes(int(h[i:i + 2], 16) for i in (0, 2, 4))


def swatch_list(pal):
    """Ordered [(name, hex, alpha)] defining cell indices."""
    classes = pal["alpha_classes"]
    out = [(n, s["hex"], classes[s["class"]]["alpha"]) for n, s in pal["swatches"].items()]
    for b in pal["biomes"]:
        for stop in ("low", "mid", "high"):
            out.append((f"biome_{b['name']}_{stop}", b[stop], classes["plain"]["alpha"]))
    return out


# --- emblem shapes: inside(x, y) for x,y in [-1, 1], y down ---------------------------
def _poly(pts, x, y):
    inside = False
    j = len(pts) - 1
    for i in range(len(pts)):
        xi, yi = pts[i]
        xj, yj = pts[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


_STAR = [(0.8 * math.sin(math.radians(36 * k)) * (1 if k % 2 == 0 else 0.4) / 0.8 * 0.9,
          -0.8 * math.cos(math.radians(36 * k)) * (1 if k % 2 == 0 else 0.4) / 0.8 * 0.9 + 0.05)
         for k in range(10)]

SHAPES = {
    "circle": lambda x, y: x * x + y * y <= 0.72 ** 2,
    "triangle": lambda x, y: _poly([(0, -0.85), (0.85, 0.7), (-0.85, 0.7)], x, y),
    "square": lambda x, y: abs(x) <= 0.65 and abs(y) <= 0.65,
    "diamond": lambda x, y: abs(x) + abs(y) <= 0.9,
    "cross": lambda x, y: (abs(x) <= 0.25 and abs(y) <= 0.8) or (abs(y) <= 0.25 and abs(x) <= 0.8),
    "star5": lambda x, y: _poly(_STAR, x, y),
    "chevron": lambda x, y: _poly([(-0.85, -0.6), (-0.4, -0.6), (0, 0.15), (0.4, -0.6),
                                   (0.85, -0.6), (0, 0.85)], x, y),
    "ring": lambda x, y: 0.4 ** 2 <= x * x + y * y <= 0.78 ** 2,
}


def build(pal):
    a = pal["atlas"]
    size, cell, cols = a["size"], a["cell"], a["cols"]
    assert size == 256 and cell == 16 and cols == 16 and a["swatch_rows"] == 14
    px = bytearray(size * size * 4)

    def put(x, y, rgb, alpha):
        i = (y * size + x) * 4
        px[i:i + 3] = rgb
        px[i + 3] = alpha

    # Unused cells: neutral mid-grey, plain (visible if a face is mis-UV'd).
    for y in range(size):
        for x in range(size):
            put(x, y, b"\x00\x00\x00", 0)
    sw = swatch_list(pal)
    cap = cols * a["swatch_rows"]
    if len(sw) > cap:
        raise SystemExit(f"{len(sw)} swatches exceed {cap} cells")
    for idx, (_, hx, alpha) in enumerate(sw):
        rgb = hex_bytes(hx)
        cx, cy = (idx % cols) * cell, (idx // cols) * cell
        for y in range(cy, cy + cell):
            for x in range(cx, cx + cell):
                put(x, y, rgb, alpha)

    # Emblem strip: white shape on dark, 8 x 32 px, SS 4x4 anti-aliasing into rgb (alpha 0).
    es, y0 = a["emblem_size"], a["emblem_rows_y"]
    bg = hex_bytes(a["emblem_bg"])
    teams = sorted(pal["team"], key=lambda t: t["slot"])
    for t in teams:
        fn = SHAPES[t["shape"]]
        ox = t["slot"] * es
        for y in range(es):
            for x in range(es):
                hit = 0
                for sy in range(4):
                    for sx in range(4):
                        u = ((x + (sx + 0.5) / 4) / es) * 2 - 1
                        v = ((y + (sy + 0.5) / 4) / es) * 2 - 1
                        hit += 1 if fn(u, v) else 0
                k = hit / 16.0
                rgb = bytes(int(round(bg[c] + (255 - bg[c]) * k)) for c in range(3))
                put(ox + x, y0 + y, rgb, 0)
    return size, bytes(px)


def png_bytes(size, rgba):
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + rgba[y * size * 4:(y + 1) * size * 4] for y in range(size))
    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def main(argv):
    out = DEFAULT_OUT
    if "--out" in argv:
        out = argv[argv.index("--out") + 1]
    with open(PALETTE, encoding="utf-8") as f:
        pal = json.load(f)
    data = png_bytes(*build(pal))
    if "--check" in argv:
        try:
            with open(out, "rb") as f:
                same = f.read() == data
        except OSError:
            same = False
        print("unit_atlas.png up to date" if same else "unit_atlas.png is STALE: run build_palette.py")
        return 0 if same else 1
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "wb") as f:
        f.write(data)
    print(f"wrote {out} ({len(data)} bytes, {len(swatch_list(pal))} swatches)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
