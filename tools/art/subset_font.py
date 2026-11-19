#!/usr/bin/env python3
"""TrueType subsetter for the two UI fonts (ART-21, docs/07 s7). Stdlib only (no fontTools, no new dependency).

Keeps glyph ids stable: glyphs outside the charset get empty outlines (and empty gvar data), so hmtx/HVAR/fvar/avar
stay valid byte for byte. cmap is rebuilt (format 4, BMP). GSUB/GPOS/GDEF/hinting-less extras are dropped; the UI
text needs no shaping beyond plain Latin. Works on static and variable (gvar) TrueType fonts.

Usage: python -I tools/art/subset_font.py SRC.ttf DST.ttf [--static] [--tabular] [--charset godot/content/ui/font_charset.json]
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
DEFAULT_CHARSET = REPO / "godot" / "content" / "ui" / "font_charset.json"
KEEP = ("OS/2", "cmap", "cvt ", "fpgm", "gasp", "glyf", "head", "hhea", "hmtx", "loca", "maxp", "name", "post", "prep",
        "fvar", "avar", "gvar", "HVAR", "MVAR", "STAT")


def read_tables(data: bytes) -> dict[str, bytes]:
    num = struct.unpack(">H", data[4:6])[0]
    out: dict[str, bytes] = {}
    for i in range(num):
        tag, _cs, off, ln = struct.unpack(">4sIII", data[12 + 16 * i:28 + 16 * i])
        out[tag.decode("latin-1")] = data[off:off + ln]
    return out


def charset_codepoints(spec: dict) -> list[int]:
    cps: set[int] = set()
    for lo, hi in spec["ranges"]:
        cps.update(range(lo, hi + 1))
    cps.update(spec.get("extra", []))
    return sorted(cps)


def parse_cmap(cmap: bytes) -> dict[int, int]:
    """Unicode BMP map from a format 4 subtable (3,1) or (0,3); format 12 also read."""
    n = struct.unpack(">H", cmap[2:4])[0]
    best: dict[int, int] = {}
    for i in range(n):
        pid, eid, off = struct.unpack(">HHI", cmap[4 + 8 * i:12 + 8 * i])
        if (pid, eid) not in ((3, 1), (0, 3), (3, 10), (0, 4)):
            continue
        fmt = struct.unpack(">H", cmap[off:off + 2])[0]
        if fmt == 4:
            best.update(_cmap4(cmap, off))
        elif fmt == 12:
            best.update(_cmap12(cmap, off))
    return best


def _cmap4(c: bytes, off: int) -> dict[int, int]:
    segx2 = struct.unpack(">H", c[off + 6:off + 8])[0]
    seg = segx2 // 2
    p = off + 14
    ends = struct.unpack(f">{seg}H", c[p:p + segx2])
    p += segx2 + 2
    starts = struct.unpack(f">{seg}H", c[p:p + segx2])
    p += segx2
    deltas = struct.unpack(f">{seg}h", c[p:p + segx2])
    p += segx2
    ro_pos = p
    ros = struct.unpack(f">{seg}H", c[p:p + segx2])
    m: dict[int, int] = {}
    for i in range(seg):
        for cp in range(starts[i], ends[i] + 1):
            if cp == 0xFFFF:
                continue
            if ros[i] == 0:
                gid = (cp + deltas[i]) & 0xFFFF
            else:
                q = ro_pos + 2 * i + ros[i] + 2 * (cp - starts[i])
                g = struct.unpack(">H", c[q:q + 2])[0]
                gid = (g + deltas[i]) & 0xFFFF if g else 0
            if gid:
                m[cp] = gid
    return m


def _cmap12(c: bytes, off: int) -> dict[int, int]:
    n = struct.unpack(">I", c[off + 12:off + 16])[0]
    m: dict[int, int] = {}
    for i in range(n):
        s, e, g = struct.unpack(">III", c[off + 16 + 12 * i:off + 28 + 12 * i])
        for k in range(e - s + 1):
            m[s + k] = g + k
    return m


def build_cmap(mapping: dict[int, int]) -> bytes:
    """Format 4 with one segment per contiguous (cp, gid) run, platform (3,1) and (0,3)."""
    items = sorted((cp, g) for cp, g in mapping.items() if cp < 0xFFFF)
    segs: list[tuple[int, int, int]] = []
    for cp, g in items:
        if segs and cp == segs[-1][1] + 1 and (g - cp) & 0xFFFF == segs[-1][2]:
            segs[-1] = (segs[-1][0], cp, segs[-1][2])
        else:
            segs.append((cp, cp, (g - cp) & 0xFFFF))
    segs.append((0xFFFF, 0xFFFF, 1))
    n = len(segs)
    sr = 2 * (1 << (n.bit_length() - 1))
    body = struct.pack(">HHHH", n * 2, sr, (n.bit_length() - 1), n * 2 - sr)
    body += b"".join(struct.pack(">H", s[1]) for s in segs) + b"\x00\x00"
    body += b"".join(struct.pack(">H", s[0]) for s in segs)
    body += b"".join(struct.pack(">H", s[2]) for s in segs)
    body += b"\x00\x00" * n
    sub = struct.pack(">HHH", 4, 6 + len(body), 0) + body
    head = struct.pack(">HH", 0, 2) + struct.pack(">HHI", 3, 1, 20) + struct.pack(">HHI", 0, 3, 20)
    return head + sub


def glyph_slices(glyf: bytes, loca: bytes, long_fmt: bool, num: int) -> list[bytes]:
    if long_fmt:
        offs = list(struct.unpack(f">{num + 1}I", loca[:4 * (num + 1)]))
    else:
        offs = [o * 2 for o in struct.unpack(f">{num + 1}H", loca[:2 * (num + 1)])]
    return [glyf[offs[i]:offs[i + 1]] for i in range(num)]


def components(g: bytes) -> list[int]:
    if len(g) < 10 or struct.unpack(">h", g[:2])[0] >= 0:
        return []
    out: list[int] = []
    p = 10
    while True:
        flags, gid = struct.unpack(">HH", g[p:p + 4])
        out.append(gid)
        p += 4 + (4 if flags & 1 else 2)
        p += 2 if flags & 8 else 4 if flags & 0x40 else 8 if flags & 0x80 else 0
        if not flags & 0x20:
            return out


def closure(slices: list[bytes], seeds: set[int]) -> set[int]:
    keep = {0} | seeds
    todo = list(keep)
    while todo:
        for c in components(slices[todo.pop()]):
            if c not in keep:
                keep.add(c)
                todo.append(c)
    return keep


def rebuild_gvar(gvar: bytes, keep: set[int]) -> bytes:
    major, minor, axes, nshared, shared_off, count, flags, data_off = struct.unpack(">HHHHIHHI", gvar[:20])
    if flags & 1:
        offs = list(struct.unpack(f">{count + 1}I", gvar[20:20 + 4 * (count + 1)]))
    else:
        offs = [o * 2 for o in struct.unpack(f">{count + 1}H", gvar[20:20 + 2 * (count + 1)])]
    shared = gvar[shared_off:shared_off + nshared * axes * 2]
    new_off = 20 + 4 * (count + 1)
    new_data_off = new_off + len(shared)
    parts: list[bytes] = []
    table = [0]
    total = 0
    for i in range(count):
        d = gvar[data_off + offs[i]:data_off + offs[i + 1]] if i in keep else b""
        if len(d) % 2:
            d += b"\x00"
        parts.append(d)
        total += len(d)
        table.append(total)
    head = struct.pack(">HHHHIHHI", major, minor, axes, nshared, new_off, count, 1, new_data_off)
    return head + struct.pack(f">{count + 1}I", *table) + shared + b"".join(parts)


ASCII_NAMES = {48 + i: n for i, n in enumerate(
    ("zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"))}
ASCII_NAMES[58] = "colon"


def post_names(post: bytes) -> list[str]:
    """Glyph names from a post format 2.0 table (empty list for other formats)."""
    if struct.unpack(">I", post[:4])[0] != 0x00020000:
        return []
    n = struct.unpack(">H", post[32:34])[0]
    idx = struct.unpack(f">{n}H", post[34:34 + 2 * n])
    pool: list[str] = []
    pos = 34 + 2 * n
    while pos < len(post):
        pool.append(post[pos + 1:pos + 1 + post[pos]].decode("latin-1"))
        pos += 1 + post[pos]
    return [pool[i - 258] if i >= 258 and i - 258 < len(pool) else "" for i in idx]


def tabular_remap(mapping: dict[int, int], post: bytes, cps: list[int]) -> dict[int, int]:
    """Point the given codepoints at their `<name>.tf` glyph so digits keep a fixed advance without GSUB."""
    names = post_names(post)
    by_name = {nm: g for g, nm in enumerate(names) if nm}
    out = dict(mapping)
    for cp in cps:
        base = ASCII_NAMES.get(cp, "")   # post names below index 258 are the standard Mac set, not stored
        if cp in mapping and base + ".tf" in by_name:
            out[cp] = by_name[base + ".tf"]
    return out


def subset(src: bytes, codepoints: list[int], static: bool = False, tabular: list[int] | None = None) -> bytes:
    """static=True drops the variation tables: the font becomes its default instance (smaller, no gvar)."""
    tabs = read_tables(src)
    num = struct.unpack(">H", tabs["maxp"][4:6])[0]
    long_fmt = struct.unpack(">h", tabs["head"][50:52])[0] == 1
    slices = glyph_slices(tabs["glyf"], tabs["loca"], long_fmt, num)
    full = parse_cmap(tabs["cmap"])
    mapping = {cp: full[cp] for cp in codepoints if cp in full}
    mapping = tabular_remap(mapping, tabs["post"], tabular or [])
    keep = closure(slices, set(mapping.values()))
    glyf = b""
    offs = [0]
    for i in range(num):
        glyf += (slices[i] if i in keep else b"")
        glyf += b"\x00" * (len(glyf) % 4)
        offs.append(len(glyf))
    head = bytearray(tabs["head"])
    head[8:12] = b"\x00\x00\x00\x00"
    head[50:52] = struct.pack(">h", 1)
    out = dict(tabs)
    out["glyf"] = glyf
    out["loca"] = struct.pack(f">{num + 1}I", *offs)
    out["head"] = bytes(head)
    out["cmap"] = build_cmap(mapping)
    out["post"] = struct.pack(">I", 0x00030000) + tabs["post"][4:32]
    if static:
        for t in ("fvar", "avar", "gvar", "HVAR", "MVAR", "STAT"):
            out.pop(t, None)
    elif "gvar" in tabs:
        out["gvar"] = rebuild_gvar(tabs["gvar"], keep)
    return assemble({t: out[t] for t in KEEP if t in out})


def checksum(b: bytes) -> int:
    b = b + b"\x00" * (-len(b) % 4)
    return sum(struct.unpack(f">{len(b) // 4}I", b)) & 0xFFFFFFFF


def assemble(tables: dict[str, bytes]) -> bytes:
    tags = sorted(tables)
    n = len(tags)
    sr = 16 * (1 << (n.bit_length() - 1))
    out = struct.pack(">IHHHH", 0x00010000, n, sr, n.bit_length() - 1, n * 16 - sr)
    pos = 12 + 16 * n
    body = b""
    head_at = 0
    for t in tags:
        d = tables[t]
        out += struct.pack(">4sIII", t.encode("latin-1"), checksum(d), pos + len(body), len(d))
        if t == "head":
            head_at = pos + len(body)
        body += d + b"\x00" * (-len(d) % 4)
    font = bytearray(out + body)
    adj = (0xB1B0AFBA - checksum(bytes(font))) & 0xFFFFFFFF
    font[head_at + 8:head_at + 12] = struct.pack(">I", adj)
    return bytes(font)


def coverage(font: bytes) -> set[int]:
    """Codepoints with a non-empty outline (or the space glyph) in a subset font, for tests and the PR table."""
    tabs = read_tables(font)
    num = struct.unpack(">H", tabs["maxp"][4:6])[0]
    sl = glyph_slices(tabs["glyf"], tabs["loca"], struct.unpack(">h", tabs["head"][50:52])[0] == 1, num)
    return set(parse_cmap(tabs["cmap"]).keys()) if sl else set()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--static", action="store_true", help="drop variation tables (default instance)")
    ap.add_argument("--tabular", action="store_true", help="map charset 'tabular' codepoints to .tf glyphs")
    ap.add_argument("--charset", default=str(DEFAULT_CHARSET))
    a = ap.parse_args()
    spec = json.loads(Path(a.charset).read_text(encoding="utf-8"))
    res = subset(Path(a.src).read_bytes(), charset_codepoints(spec), a.static, spec.get("tabular", []) if a.tabular else [])
    Path(a.dst).write_bytes(res)
    print(f"{a.dst}: {len(res)} bytes, {len(coverage(res))} codepoints")
    return 0


if __name__ == "__main__":
    sys.exit(main())
