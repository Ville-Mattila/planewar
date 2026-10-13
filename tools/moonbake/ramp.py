"""moon_ramp.png builder (docs/07 s3.1: 16 biome rows x 64 ramp steps, RGBA8; absorbs ART-31 / hooks ART-14).

Row = biome id (07 s2.1), column = ramp value 0..1 through the biome's low / mid / high stops. Source of truth is
godot/content/biome_ramps.json once ART-14 lands; until then the 07 s2.1 palette below is the fallback.
Accepted JSON shapes: {"biomes": {"<name>": {"id": n, "low": "#rrggbb", "mid": ..., "high": ...}}} or the same
list under "biomes". The PNG is written with stored deflate blocks so its bytes are platform-independent.
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np

from .pngio import write_png

RAMP_WIDTH = 64
RAMP_ROWS = 16
RESERVED_RGB = (255, 0, 255)  # ids 8-15 are reserved; magenta makes a stray sample obvious
REPO = Path(__file__).resolve().parents[2]
DEFAULT_RAMPS_JSON = REPO / "godot/content/biome_ramps.json"
DEFAULT_OUT = REPO / "godot/assets/textures/moon_ramp.png"

# 07 s2.1 (id, name, low, mid, high)
DEFAULT_BIOMES = (
    (0, "mare", "#30343F", "#404552", "#51576A"),
    (1, "highland", "#7A7770", "#959189", "#B1ACA1"),
    (2, "crater_floor", "#2A2C34", "#353840", "#43474F"),
    (3, "rim_ejecta", "#A8A396", "#C0BBAE", "#D6D1C4"),
    (4, "cold_trap", "#34485E", "#5B7C9E", "#B5D8EC"),
    (5, "ore_field", "#6B5B3F", "#8D7648", "#AA9158"),
    (6, "solar_plateau", "#B9B5AA", "#D0CCC0", "#E3DFD2"),
    (7, "rille_floor", "#22242B", "#2C2F37", "#373B44"),
)


def _rgb(hexstr: str) -> tuple[int, int, int]:
    s = hexstr.lstrip("#")
    if len(s) != 6:
        raise ValueError(f"bad colour '{hexstr}'")
    return int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16)


def load_ramps(path: Path | None = None) -> dict[int, tuple[str, tuple, tuple, tuple]]:
    """{biome id: (name, low, mid, high)} with RGB tuples."""
    path = Path(path) if path else DEFAULT_RAMPS_JSON
    rows = DEFAULT_BIOMES
    if path.is_file():
        data = json.loads(path.read_text(encoding="utf-8"))
        b = data["biomes"]
        items = [(v["id"], k, v["low"], v["mid"], v["high"]) for k, v in b.items()] if isinstance(b, dict) \
            else [(v["id"], v["name"], v["low"], v["mid"], v["high"]) for v in b]
        rows = tuple(items)
    out = {}
    for i, name, lo, mid, hi in rows:
        if not 0 <= i < 8:
            raise ValueError(f"biome id {i} outside 0-7 (8-15 reserved)")
        out[i] = (name, _rgb(lo), _rgb(mid), _rgb(hi))
    return out


def build_ramp_image(ramps: dict) -> np.ndarray:
    img = np.zeros((RAMP_ROWS, RAMP_WIDTH, 4), dtype=np.uint8)
    img[..., 3] = 255
    t = np.arange(RAMP_WIDTH) / (RAMP_WIDTH - 1.0)
    for row in range(RAMP_ROWS):
        if row not in ramps:
            img[row, :, :3] = RESERVED_RGB
            continue
        _, lo, mid, hi = (np.array(x, dtype=np.float64) if isinstance(x, tuple) else x for x in ramps[row])
        a = np.clip(t * 2.0, 0.0, 1.0)[:, None]
        b = np.clip(t * 2.0 - 1.0, 0.0, 1.0)[:, None]
        col = np.where(t[:, None] < 0.5, lo + (mid - lo) * a, mid + (hi - mid) * b)
        img[row, :, :3] = np.floor(col + 0.5).astype(np.uint8)
    return img


def build_ramp(out: Path | None = None, ramps_json: Path | None = None) -> bytes:
    data = write_png(Path(out) if out else DEFAULT_OUT, build_ramp_image(load_ramps(ramps_json)), stored=True)
    return data
