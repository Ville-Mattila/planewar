"""Minimal PNG writer (stdlib zlib; no Pillow). `stored=True` emits uncompressed deflate blocks, so the bytes do
not depend on the zlib build (zlib vs zlib-ng differ); used for anything whose hash is recorded."""

from __future__ import annotations

import struct
import zlib
from pathlib import Path

import numpy as np

_SIG = b"\x89PNG\r\n\x1a\n"


def _chunk(tag: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def _stored_zlib(raw: bytes) -> bytes:
    out = bytearray(b"\x78\x01")
    pos, n = 0, len(raw)
    while True:
        blk = raw[pos:pos + 65535]
        pos += len(blk)
        final = pos >= n
        out += struct.pack("<BHH", 1 if final else 0, len(blk), len(blk) ^ 0xFFFF) + blk
        if final:
            break
    out += struct.pack(">I", zlib.adler32(raw) & 0xFFFFFFFF)
    return bytes(out)


def encode_png(img: np.ndarray, stored: bool = False) -> bytes:
    """img: (h, w) grey, (h, w, 3) RGB or (h, w, 4) RGBA uint8."""
    img = np.ascontiguousarray(img, dtype=np.uint8)
    h, w = img.shape[:2]
    ctype = 0 if img.ndim == 2 else (2 if img.shape[2] == 3 else 6)
    rows = np.zeros((h, 1 + img.size // h), dtype=np.uint8)  # filter byte 0 per row
    rows[:, 1:] = img.reshape(h, -1)
    raw = rows.tobytes()
    idat = _stored_zlib(raw) if stored else zlib.compress(raw, 9)
    ihdr = struct.pack(">IIBBBBB", w, h, 8, ctype, 0, 0, 0)
    return _SIG + _chunk(b"IHDR", ihdr) + _chunk(b"IDAT", idat) + _chunk(b"IEND", b"")


def write_png(path: Path, img: np.ndarray, stored: bool = False) -> bytes:
    data = encode_png(img, stored)
    Path(path).write_bytes(data)
    return data


def decode_png(data: bytes) -> np.ndarray:
    """Decode what encode_png writes (8-bit, filter 0); used by tests."""
    assert data[:8] == _SIG
    pos, idat, w = 8, b"", 0
    h = ctype = 0
    while pos < len(data):
        (ln,) = struct.unpack(">I", data[pos:pos + 4])
        tag = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + ln]
        if tag == b"IHDR":
            w, h, _, ctype = struct.unpack(">IIBB", body[:10])
        elif tag == b"IDAT":
            idat += body
        pos += 12 + ln
    ch = {0: 1, 2: 3, 6: 4}[ctype]
    raw = np.frombuffer(zlib.decompress(idat), dtype=np.uint8).reshape(h, 1 + w * ch)
    img = raw[:, 1:].reshape(h, w, ch)
    return img[..., 0] if ch == 1 else img
