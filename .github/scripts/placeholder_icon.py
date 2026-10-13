#!/usr/bin/env python3
"""Writes a flat-colour PNG (default 1024 px). CI-only stand-in for the app icon the project does not have yet."""
import struct
import sys
import zlib


def chunk(tag: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def main() -> int:
    out = sys.argv[1]
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 1024
    raw = b"".join(b"\x00" + bytes([40, 90, 160]) * n for _ in range(n))
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", n, n, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    with open(out, "wb") as f:
        f.write(png)
    return 0


if __name__ == "__main__":
    sys.exit(main())
