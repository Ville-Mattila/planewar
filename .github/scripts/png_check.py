#!/usr/bin/env python3
"""Screenshot sanity: fraction of non-black pixels must exceed --min-ratio (default 1 %). Stdlib PNG reader.
Usage: png_check.py shot.png [--min-ratio 0.01]
"""
import argparse
import struct
import sys
import zlib


def read_png(path: str):
    with open(path, "rb") as fh:
        data = fh.read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    pos, idat, w, h, ctype = 8, b"", 0, 0, 0
    while pos < len(data):
        ln, = struct.unpack(">I", data[pos:pos + 4])
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + ln]
        pos += 12 + ln
        if kind == b"IHDR":
            w, h, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", body)
            assert depth == 8 and interlace == 0 and ctype in (2, 6), f"unsupported PNG {depth}/{ctype}/{interlace}"
        elif kind == b"IDAT":
            idat += body
    bpp = 3 if ctype == 2 else 4
    raw = zlib.decompress(idat)
    stride = w * bpp
    prev = bytearray(stride)
    rows = []
    i = 0
    for _ in range(h):
        f = raw[i]
        line = bytearray(raw[i + 1:i + 1 + stride])
        i += 1 + stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if f == 1:
                line[x] = (line[x] + a) & 255
            elif f == 2:
                line[x] = (line[x] + b) & 255
            elif f == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        rows.append(line)
        prev = line
    return w, h, bpp, rows


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("png")
    ap.add_argument("--min-ratio", type=float, default=0.01)
    a = ap.parse_args()
    w, h, bpp, rows = read_png(a.png)
    lit = sum(1 for r in rows for x in range(0, w * bpp, bpp) if r[x] + r[x + 1] + r[x + 2] > 24)
    ratio = lit / (w * h)
    print(f"{a.png}: {w}x{h} non-black ratio {ratio:.4f}")
    if ratio <= a.min_ratio:
        print("::error::screenshot is (nearly) black")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
