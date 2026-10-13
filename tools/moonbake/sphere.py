"""numpy port of godot/src/core/sphere.gd face mapping (docs/03 s2.5). Cross-checked in test_sphere_parity.py."""

from __future__ import annotations

import math
import re
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parents[2]
SPHERE_GD = REPO / "godot/src/core/sphere.gd"

# Face frames, 03 s2.5 table. S x T = N on every face.
FACE_N = np.array([[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]], dtype=np.float64)
FACE_S = np.array([[0, 1, 0], [0, 0, 1], [0, 0, 1], [1, 0, 0], [1, 0, 0], [0, 1, 0]], dtype=np.float64)
FACE_T = np.array([[0, 0, 1], [0, 1, 0], [1, 0, 0], [0, 0, 1], [0, 1, 0], [1, 0, 0]], dtype=np.float64)
QUARTER_PI = math.pi / 4.0
Z_AXIS = np.array([0.0, 0.0, 1.0])


def _gd_const(name: str) -> float:
    text = SPHERE_GD.read_text(encoding="utf-8")
    m = re.search(rf"^const {name}: float = (-?[0-9.]+)", text, re.M)
    if not m:
        raise RuntimeError(f"{SPHERE_GD}: const {name} not found")
    return float(m.group(1))


# Read from the GDScript source so the baker can never disagree with the sim (docs/03 s8.1).
PLANET_RADIUS = _gd_const("PLANET_RADIUS")
RELIEF_MIN = _gd_const("RELIEF_MIN")
RELIEF_MAX = _gd_const("RELIEF_MAX")


def face_uv_to_dir(face, u, v) -> np.ndarray:
    """(face, u, v) -> unit directions, shape (..., 3). face may be an int or an array."""
    u = np.asarray(u, dtype=np.float64)
    v = np.asarray(v, dtype=np.float64)
    x = np.tan((u + u - 1.0) * QUARTER_PI)
    y = np.tan((v + v - 1.0) * QUARTER_PI)
    f = np.asarray(face)
    d = FACE_N[f] + FACE_S[f] * x[..., None] + FACE_T[f] * y[..., None]
    return d / np.linalg.norm(d, axis=-1, keepdims=True)


def face_of(d: np.ndarray) -> np.ndarray:
    """Largest |component|; ties go x before y before z (matches sphere.gd _face_of)."""
    ax, ay, az = np.abs(d[..., 0]), np.abs(d[..., 1]), np.abs(d[..., 2])
    pick_x = (ax >= ay) & (ax >= az)
    pick_y = ~pick_x & (ay >= az)
    axis = np.where(pick_x, 0, np.where(pick_y, 1, 2))
    comp = np.take_along_axis(d, axis[..., None], axis=-1)[..., 0]
    return 2 * axis + (comp <= 0.0)


def dir_to_face_uv(d: np.ndarray):
    """Directions (..., 3) -> (face int array, u, v), u and v clamped to [0, 1]."""
    d = np.asarray(d, dtype=np.float64)
    f = face_of(d)
    inv = 1.0 / np.einsum("...i,...i->...", d, FACE_N[f])
    u = (np.arctan(np.einsum("...i,...i->...", d, FACE_S[f]) * inv) * (4.0 / math.pi) + 1.0) * 0.5
    v = (np.arctan(np.einsum("...i,...i->...", d, FACE_T[f]) * inv) * (4.0 / math.pi) + 1.0) * 0.5
    return f, np.clip(u, 0.0, 1.0), np.clip(v, 0.0, 1.0)


def from_lat_lon(lat_deg, lon_deg) -> np.ndarray:
    """Unit direction; z is the Noon Pole, longitude 0 is +X (sphere.gd from_lat_lon)."""
    lat = np.radians(np.asarray(lat_deg, dtype=np.float64))
    lon = np.radians(np.asarray(lon_deg, dtype=np.float64))
    c = np.cos(lat)
    return np.stack([c * np.cos(lon), c * np.sin(lon), np.sin(lat)], axis=-1)


def lat_lon_deg(d: np.ndarray):
    d = np.asarray(d, dtype=np.float64)
    n = d / np.linalg.norm(d, axis=-1, keepdims=True)
    return np.degrees(np.arcsin(np.clip(n[..., 2], -1.0, 1.0))), np.degrees(np.arctan2(n[..., 1], n[..., 0]))


def angle_between(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """Stable angle (radians) between direction arrays, atan2(|a x b|, a . b)."""
    cr = np.linalg.norm(np.cross(a, b), axis=-1)
    return np.arctan2(cr, np.einsum("...i,...i->...", a, b))


def great_circle_m(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    return angle_between(a, b) * PLANET_RADIUS


def rot_z(d: np.ndarray, deg: float) -> np.ndarray:
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    out = np.empty_like(d)
    out[..., 0] = c * d[..., 0] - s * d[..., 1]
    out[..., 1] = s * d[..., 0] + c * d[..., 1]
    out[..., 2] = d[..., 2]
    return out


def tangent_toward(p: np.ndarray, bearing_deg: float) -> np.ndarray:
    """Unit tangent at p heading `bearing_deg` (0 = north toward +Z, 90 = east). At the poles north is +X."""
    north = Z_AXIS - p * p[2]
    nn = float(np.linalg.norm(north))
    if nn < 1e-9:
        base = np.array([1.0, 0.0, 0.0])
        north = base - p * float(np.dot(base, p))
        nn = float(np.linalg.norm(north))
    north = north / nn
    east = np.cross(Z_AXIS, p)
    en = float(np.linalg.norm(east))
    east = east / en if en > 1e-9 else np.cross(p, north)
    b = math.radians(bearing_deg)
    return math.cos(b) * north + math.sin(b) * east


def offset_point(p: np.ndarray, bearing_deg: float, dist_m: float) -> np.ndarray:
    th = dist_m / PLANET_RADIUS
    out = math.cos(th) * p + math.sin(th) * tangent_toward(p, bearing_deg)
    return out / np.linalg.norm(out)


def face_grid(face: int, n: int) -> np.ndarray:
    """Directions for every texel of a face, shape (n, n, 3) indexed [y, x]; texel (x, y) is the sample at
    u = x / (n - 1), v = y / (n - 1) for baking and sampling (03 s8.3), so edge texels lie on cube edges."""
    t = np.arange(n, dtype=np.float64) / (n - 1)
    u, v = np.meshgrid(t, t)
    return face_uv_to_dir(face, u, v)


def cube_edge_points(samples: int = 4000) -> np.ndarray:
    """Dense points on the 12 cube-edge arcs (|d_i| == |d_j| >= |d_k|), shape (12 * samples, 3)."""
    pts = []
    t = np.linspace(-1.0, 1.0, samples)
    for i in range(3):
        for j in range(i + 1, 3):
            k = 3 - i - j
            for si in (1.0, -1.0):
                for sj in (1.0, -1.0):
                    p = np.zeros((samples, 3))
                    p[:, k] = t
                    p[:, i] = si
                    p[:, j] = sj
                    pts.append(p / np.linalg.norm(p, axis=1, keepdims=True))
    return np.concatenate(pts)
