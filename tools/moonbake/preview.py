"""Preview renders (docs/03 s8.2, docs/07 s9.2 step 8): equirectangular shaded map, unfolded faces, polar view.

Previews are for humans; they are written with zlib compression and are not part of meta.json hashes.
"""

from __future__ import annotations

import math
from pathlib import Path

import numpy as np

from . import sphere
from .bake import Bake
from .pngio import write_png
from .ramp import load_ramps

EQ_W, EQ_H = 2048, 1024
POLAR_SIZE = 512
POLAR_REACH_DEG = 60.0  # colatitude shown around each pole


def _biome_rgb(biome: np.ndarray) -> np.ndarray:
    lut = np.full((16, 3), 255, dtype=np.float64)
    for i, (_, _, mid, _) in load_ramps().items():
        lut[i] = mid
    lut[8:, :] = (255, 0, 255)
    return lut[biome]


def _shade(rgb: np.ndarray, h: np.ndarray, hill: np.ndarray, slope_deg: np.ndarray) -> np.ndarray:
    """Biome mid colour x height tint x hillshade x slope darkening, uint8."""
    tint = 0.75 + 0.5 * np.clip((h + 500.0) / 1200.0, 0.0, 1.0)
    k = np.clip(0.8 + hill, 0.35, 1.3) * (1.0 - np.clip(slope_deg / 90.0, 0.0, 0.5)) * tint
    return np.clip(rgb * k[..., None], 0, 255).astype(np.uint8)


def sample_all(b: Bake, d: np.ndarray):
    """Nearest-texel height (m), biome id and slope (deg) at directions d (..., 3)."""
    shp = d.shape[:-1]
    f, u, v = sphere.dir_to_face_uv(d.reshape(-1, 3))
    x = np.rint(u * (b.n - 1)).astype(np.int64)
    y = np.rint(v * (b.n - 1)).astype(np.int64)
    lo, hi = b.relief
    hh = np.empty(len(f))
    bi = np.empty(len(f), dtype=np.uint8)
    sl = np.empty(len(f))
    for face in range(6):
        m = f == face
        hh[m] = lo + b.height[face][y[m], x[m]].astype(np.float64) * ((hi - lo) / 65535.0)
        bi[m] = b.biome[face][y[m], x[m]]
        sl[m] = b.slope[face][y[m], x[m]].astype(np.float64) * 0.5
    return hh.reshape(shp), bi.reshape(shp), sl.reshape(shp)


def equirect(b: Bake) -> np.ndarray:
    lon = (np.arange(EQ_W) + 0.5) / EQ_W * 360.0 - 180.0
    lat = 90.0 - (np.arange(EQ_H) + 0.5) / EQ_H * 180.0
    lo, la = np.meshgrid(lon, lat)
    d = sphere.from_lat_lon(la, lo)
    h, bi, sl = sample_all(b, d)
    gy, gx = np.gradient(h)
    hill = np.clip((gx - gy) * 0.02, -0.5, 0.5)  # light from the north-west
    return _shade(_biome_rgb(bi), h, hill, sl)


def faces_image(b: Bake, what: str) -> np.ndarray:
    n = b.n
    img = np.zeros((2 * n, 3 * n, 3), dtype=np.uint8)
    for f in range(6):
        if what == "height":
            t = np.clip((b.height[f].astype(np.float64) / 65535.0), 0.0, 1.0)
            tile = np.repeat((t * 255).astype(np.uint8)[..., None], 3, axis=2)
        elif what == "slope":
            t = np.clip(b.slope[f].astype(np.float64) / 60.0, 0.0, 1.0)  # 0..30 deg
            tile = np.repeat((t * 255).astype(np.uint8)[..., None], 3, axis=2)
        else:
            tile = _biome_rgb(b.biome[f]).astype(np.uint8)
        r, c = divmod(f, 3)
        img[r * n:(r + 1) * n, c * n:(c + 1) * n] = tile
    return img


def polar_image(b: Bake) -> np.ndarray:
    """Azimuthal-equidistant views of the Noon Pole (left) and Midnight Pole (right), Earth side mirrored."""
    s = POLAR_SIZE
    xs = (np.arange(s) + 0.5) / s * 2.0 - 1.0
    px, py = np.meshgrid(xs, -xs)
    rr = np.hypot(px, py)
    theta = np.radians(POLAR_REACH_DEG) * np.minimum(rr, 1.0)
    az = np.arctan2(py, px)
    out = []
    for sign in (1.0, -1.0):
        d = np.stack([np.sin(theta) * np.cos(az), np.sin(theta) * np.sin(az) * sign, np.cos(theta) * sign], axis=-1)
        h, bi, sl = sample_all(b, d)
        gy, gx = np.gradient(h)
        img = _shade(_biome_rgb(bi), h, np.clip((gx - gy) * 0.05, -0.5, 0.5), sl)
        img[rr > 1.0] = (5, 7, 12)
        out.append(img)
    return np.concatenate(out, axis=1)


def write_preview(b: Bake, out_dir: Path, full: bool = False) -> list[str]:
    """preview.png always; the unfolded faces and polar view when `full` (the `preview` command)."""
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    names = ["preview.png"]
    write_png(out_dir / "preview.png", equirect(b))
    if full:
        for what in ("height", "slope", "biome"):
            write_png(out_dir / f"faces_{what}.png", faces_image(b, what))
            names.append(f"faces_{what}.png")
        write_png(out_dir / "polar.png", polar_image(b))
        names.append("polar.png")
    return names
