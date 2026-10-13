"""Integer-hash value noise (docs/03 s8.2 step 1). No numpy.random; the hash path is pure uint32 arithmetic."""

from __future__ import annotations

import numpy as np

_U32 = np.uint32
_INV_2_32 = 1.0 / 4294967296.0


def hash32(ix: np.ndarray, iy: np.ndarray, iz: np.ndarray, seed: int) -> np.ndarray:
    """Lattice coordinates (int64 arrays) -> uniform float64 in [0, 1). xorshift-multiply finaliser."""
    with np.errstate(over="ignore"):
        h = ix.astype(_U32) * _U32(0x9E3779B1)
        h ^= iy.astype(_U32) * _U32(0x85EBCA77)
        h ^= iz.astype(_U32) * _U32(0xC2B2AE3D)
        h ^= _U32((seed * 0x27D4EB2F) & 0xFFFFFFFF)
        h ^= h >> _U32(15)
        h *= _U32(0x2C1B3C6D)
        h ^= h >> _U32(12)
        h *= _U32(0x297A2D39)
        h ^= h >> _U32(15)
    return h.astype(np.float64) * _INV_2_32


def _fade(t: np.ndarray) -> np.ndarray:
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


def value_noise(p: np.ndarray, seed: int) -> np.ndarray:
    """Trilinear value noise at points p (M, 3) float64 -> (M,) in [0, 1)."""
    fl = np.floor(p)
    f = p - fl
    i = fl.astype(np.int64)
    fx, fy, fz = _fade(f[:, 0]), _fade(f[:, 1]), _fade(f[:, 2])
    x0, y0, z0 = i[:, 0], i[:, 1], i[:, 2]
    x1, y1, z1 = x0 + 1, y0 + 1, z0 + 1
    c000 = hash32(x0, y0, z0, seed)
    c100 = hash32(x1, y0, z0, seed)
    c010 = hash32(x0, y1, z0, seed)
    c110 = hash32(x1, y1, z0, seed)
    c001 = hash32(x0, y0, z1, seed)
    c101 = hash32(x1, y0, z1, seed)
    c011 = hash32(x0, y1, z1, seed)
    c111 = hash32(x1, y1, z1, seed)
    a = c000 + (c100 - c000) * fx
    b = c010 + (c110 - c010) * fx
    c = c001 + (c101 - c001) * fx
    d = c011 + (c111 - c011) * fx
    e = a + (b - a) * fy
    g = c + (d - c) * fy
    return e + (g - e) * fz


def ridged_fbm(d: np.ndarray, seed: int, octaves: int, cycles: float, lacunarity: float, gain: float) -> np.ndarray:
    """Ridged fBm of unit directions at `cycles` per great circle, normalised to [-1, 1] (about zero mean).

    A great circle spans 2 pi in unit-sphere coordinates, so lattice scale = cycles / (2 pi) cells per unit.
    """
    scale = cycles / (2.0 * np.pi)
    total = np.zeros(len(d))
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        n = value_noise(d * scale, seed + 1013 * o)
        total += amp * (1.0 - np.abs(2.0 * n - 1.0))
        norm += amp
        amp *= gain
        scale *= lacunarity
    return (total / norm - 0.5) * 2.0


def smoothstep(e0: float, e1: float, x: np.ndarray) -> np.ndarray:
    """GLSL smoothstep; e0 > e1 is allowed and gives the falling curve (docs/03 s8.2 writes it that way)."""
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


class SplitMix64:
    """Deterministic sub-RNG for scatter craters (docs/03 s8.2). Python ints, no platform dependence."""

    def __init__(self, seed: int) -> None:
        self.state = seed & 0xFFFFFFFFFFFFFFFF

    def next_u64(self) -> int:
        self.state = (self.state + 0x9E3779B97F4A7C15) & 0xFFFFFFFFFFFFFFFF
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & 0xFFFFFFFFFFFFFFFF
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & 0xFFFFFFFFFFFFFFFF
        return z ^ (z >> 31)

    def uniform(self) -> float:
        return (self.next_u64() >> 11) * (1.0 / 9007199254740992.0)
