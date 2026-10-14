"""Height field: base noise, 8-fold symmetry, and the stamp pipeline (docs/03 s8.2 steps 1-3).

All heights are float64 metres. Points are processed in `Block`s (tile-major order) so each stamp only
touches the tiles its reach cone intersects.
"""

from __future__ import annotations

import math

import numpy as np

from . import sphere
from .noise import ridged_fbm, smoothstep, value_noise
from .recipe import NODE_KINDS_WITH_FOOTPRINT, Plan
from .sphere import PLANET_RADIUS as R

WEDGE_BAND_DEG = 3.0       # width of the blend between rotated copies of the base noise (keeps the base continuous)
COLD_TRAP_DEPTH_M = 100.0  # trap floor below its rim ring (M4 needs >= 80)
TRAP_FLAT_FRAC = 0.6       # flat floor for s < 0.6 r, cosine blend to the rim (03 s8.2)
STAGES = ("regions", "craters", "rilles", "poles", "footprints", "flatten")
TAGS = ("floor", "rim", "rille", "plateau", "cold", "ore")


class Block:
    """Directions (M, 3) in chunks of `csize` consecutive points with bounding cones for culling."""

    def __init__(self, d: np.ndarray, csize: int) -> None:
        self.d = d
        m = len(d)
        self.starts = np.arange(0, m, csize)
        self.sizes = np.minimum(csize, m - self.starts)
        ssum = np.add.reduceat(d, self.starts, axis=0)
        self.centre = ssum / np.maximum(np.linalg.norm(ssum, axis=1, keepdims=True), 1e-12)
        cid = np.repeat(np.arange(len(self.starts)), self.sizes)
        dots = np.einsum("ij,ij->i", d, self.centre[cid])
        self.radius = np.maximum.reduceat(np.arccos(np.clip(dots, -1.0, 1.0)), self.starts)

    def __len__(self) -> int:
        return len(self.d)

    def near(self, c: np.ndarray, reach_m: float):
        """(indices, great-circle distance in metres) of points within reach_m of unit vector c."""
        reach = reach_m / R
        ang_c = np.arccos(np.clip(self.centre @ c, -1.0, 1.0))
        sel = ang_c <= reach + self.radius + 1e-9
        if not sel.any():
            return np.zeros(0, dtype=np.int64), np.zeros(0)
        idx = np.flatnonzero(np.repeat(sel, self.sizes))
        s = sphere.angle_between(self.d[idx], c) * R
        keep = s <= reach_m
        return idx[keep], s[keep]


# region base noise ---------------------------------------------------------------------------------------------
def _base_raw(d: np.ndarray, recipe: dict) -> np.ndarray:
    bn, seed = recipe["base_noise"], recipe["seed"]
    cyc = float(bn["freq_per_circumference"])
    warp = float(bn.get("warp_m", 0.0)) / R
    p = d
    if warp > 0.0:
        sc = cyc * 0.5 / (2.0 * math.pi)
        w = np.stack([value_noise(d * sc, seed + 101 + i) * 2.0 - 1.0 for i in range(3)], axis=1)
        p = d + w * warp
        p = p / np.linalg.norm(p, axis=1, keepdims=True)
    h = bn["amp_m"] * ridged_fbm(p, seed, bn["octaves"], cyc, bn.get("lacunarity", 2.0), bn.get("gain", 0.5))
    hl = recipe.get("highlands")
    if hl and hl["amplitude_m"] > 0.0:
        mask = smoothstep(hl["threshold"] - hl["softness"], hl["threshold"] + hl["softness"],
                          value_noise(d * (hl["mask_frequency"] / (2.0 * math.pi)), seed + 211))
        h = h + mask * hl["amplitude_m"] * ridged_fbm(p, seed + 7, 3, cyc * 0.5, 2.0, 0.5)
    return h


def base_height(d: np.ndarray, recipe: dict) -> np.ndarray:
    """Rotation-symmetric (order 8) base: each point is folded into the wedge starting at wedge_start_deg and
    blended with the neighbouring fold inside a narrow band at the wedge borders, so the field is continuous."""
    start = recipe["symmetry"]["wedge_start_deg"]
    lon = np.degrees(np.arctan2(d[:, 1], d[:, 0]))
    kf = np.floor((lon - start) / 45.0)
    phi = lon - start - 45.0 * kf
    ang = np.radians(-45.0 * kf)
    c, s = np.cos(ang), np.sin(ang)
    d0 = np.stack([c * d[:, 0] - s * d[:, 1], s * d[:, 0] + c * d[:, 1], d[:, 2]], axis=1)
    h = _base_raw(d0, recipe)
    b = WEDGE_BAND_DEG
    lo = np.flatnonzero(phi < b)
    if len(lo):
        t = 0.5 * (1.0 - smoothstep(0.0, b, phi[lo]))
        h[lo] = (1.0 - t) * h[lo] + t * _base_raw(sphere.rot_z(d0[lo], 45.0), recipe)
    hi = np.flatnonzero(phi > 45.0 - b)
    if len(hi):
        t = 0.5 * smoothstep(45.0 - b, 45.0, phi[hi])
        h[hi] = (1.0 - t) * h[hi] + t * _base_raw(sphere.rot_z(d0[hi], -45.0), recipe)
    return h
# endregion


# region probes -------------------------------------------------------------------------------------------------
def _ring(c: np.ndarray, radius_m: float, n: int, phase: float = 0.0) -> np.ndarray:
    return np.stack([sphere.offset_point(c, 360.0 * (i + phase) / n, radius_m) for i in range(n)])


def disc_probes(c: np.ndarray, radius_m: float) -> np.ndarray:
    """36 points on three equal-area annuli of the disc: their mean height is the disc average."""
    return np.concatenate([_ring(c, radius_m * math.sqrt((2 * i + 1) / 6.0), 12, 0.5 * i) for i in range(3)])


def prepare(plan: Plan) -> None:
    """Fill the probe-derived constants: crater base means, trap rim references, slot flatten means."""
    recipe = plan.recipe
    if plan.craters:
        # Each crater pulls its floor to the surface as it is when it is stamped (regions and earlier craters
        # applied), so a crater inside a mare does not become a mesa at the pre-mare level.
        for i, cr in enumerate(plan.craters):
            blk = Block(disc_probes(cr.c, cr.r), 36)
            cr.base_mean = float(compute(blk, plan, "rilles", crater_count=i)[0].mean())
    traps = [n for n in plan.nodes if n.kind == "cold_trap"]
    for n in traps:
        n.ring_ref = float(compute(Block(_ring(n.c, n.radius_m, 12), 12), plan, "footprints")[0].mean())
    if plan.slots:
        for c in plan.slots:
            blk = Block(disc_probes(c, plan.flatten_r), 36)
            plan.slot_means.append(float(compute(blk, plan, "flatten")[0].mean()))
# endregion


# region stamps -------------------------------------------------------------------------------------------------
def _seg_angle(p: np.ndarray, a: np.ndarray, b: np.ndarray) -> np.ndarray:
    m = np.cross(a, b)
    m = m / np.linalg.norm(m)
    pm = p @ m
    q = p - pm[:, None] * m
    inside = (np.cross(a, q) @ m >= 0.0) & (np.cross(q, b) @ m >= 0.0)
    perp = np.arcsin(np.clip(np.abs(pm), 0.0, 1.0))
    ends = np.minimum(sphere.angle_between(p, a), sphere.angle_between(p, b))
    return np.where(inside, perp, ends)


def _regions(blk: Block, h: np.ndarray, tags: dict, plan: Plan) -> None:
    for g in plan.regions:
        idx, s = blk.near(g["c"], g["radius_m"] + g["edge_m"])
        if not len(idx):
            continue
        w = smoothstep(g["radius_m"] + g["edge_m"], g["radius_m"], s) if g["edge_m"] > 0 else (s <= g["radius_m"]) * 1.0
        hh = h[idx]
        target = g["floor_m"] + 0.1 * hh if g["kind"] == "mare" else g["height_m"] + hh
        h[idx] = hh + (target - hh) * w


def _craters(blk: Block, h: np.ndarray, tags: dict, plan: Plan, count: int | None = None) -> None:
    seed = plan.recipe["seed"] + 4001
    for cr in plan.craters[:count]:
        r = cr.r
        idx, s = blk.near(cr.c, max(cr.ejecta, 1.75 * r))
        if not len(idx):
            continue
        w = smoothstep(1.3 * r, r, s)
        bowl = np.where(s < r, -cr.depth * (1.0 - (s / r) ** 2), 0.0)
        rim = cr.rim * np.exp(-(((s - r) / (0.25 * r)) ** 2))
        n = value_noise(blk.d[idx] * (R / (0.5 * r)), seed) * 2.0 - 1.0
        span = max(cr.ejecta - r, 1e-6)
        ej = 0.08 * cr.rim * np.maximum(0.0, 1.0 - (s - r) / span) * (1.0 + 0.5 * n) * (s > r)
        hh = h[idx]
        h[idx] = hh + (cr.base_mean - hh) * w + bowl + rim + ej
        tags["floor"][idx[s < 0.88 * r]] = True
        ring = (s >= 0.88 * r) & (s <= 1.12 * r)
        ray = (s > r) & (s < cr.ejecta) & (n > 0.7)
        tags["rim"][idx[ring | ray]] = True


def _rilles(blk: Block, h: np.ndarray, tags: dict, plan: Plan) -> None:
    for ri in plan.rilles:
        half = ri["width_m"] / 2.0
        best = None
        for a, b in zip(ri["pts"][:-1], ri["pts"][1:]):
            mid = a + b
            nm = np.linalg.norm(mid)
            mid = mid / nm if nm > 1e-9 else a
            seg_m = float(sphere.angle_between(a, b)) * R
            idx, _ = blk.near(mid, seg_m / 2.0 + half + 1.0)
            if not len(idx):
                continue
            ang = _seg_angle(blk.d[idx], a, b) * R
            if best is None:
                best = np.full(len(blk), np.inf)
            best[idx] = np.minimum(best[idx], ang)
        if best is None:
            continue
        sel = np.flatnonzero(best <= half)
        s = best[sel]
        h[sel] -= ri["depth_m"] * (1.0 - smoothstep(0.0, half, s)) ** 1.5
        tags["rille"][sel[s <= 0.5 * half]] = True


def _poles(blk: Block, h: np.ndarray, tags: dict, plan: Plan) -> None:
    r = plan.plateau_r
    if r <= 0.0:
        return
    idx, s = blk.near(plan.plateau_c, 1.2 * r)
    if len(idx):
        w = smoothstep(1.2 * r, r, s)
        h[idx] = h[idx] + (plan.plateau_h - h[idx]) * w
        tags["plateau"][idx[s < r]] = True


def _footprints(blk: Block, h: np.ndarray, tags: dict, plan: Plan) -> None:
    for n in plan.nodes:
        if n.kind not in NODE_KINDS_WITH_FOOTPRINT:
            continue
        idx, s = blk.near(n.c, n.radius_m)
        if not len(idx):
            continue
        if n.kind == "ore_field":
            tags["ore"][idx] = True
            continue
        flat = TRAP_FLAT_FRAC * n.radius_m
        t = np.clip((s - flat) / max(n.radius_m - flat, 1e-6), 0.0, 1.0)
        w = 0.5 * (1.0 + np.cos(math.pi * t))
        floor = n.ring_ref - COLD_TRAP_DEPTH_M
        h[idx] = h[idx] + (floor - h[idx]) * w
        tags["cold"][idx] = True


def _flatten(blk: Block, h: np.ndarray, tags: dict, plan: Plan) -> None:
    if plan.flatten_r <= 0.0:
        return
    for c, mean in zip(plan.slots, plan.slot_means):
        idx, s = blk.near(c, plan.flatten_r + plan.flatten_edge)
        if not len(idx):
            continue
        w = smoothstep(plan.flatten_r + plan.flatten_edge, plan.flatten_r, s) if plan.flatten_edge > 0 else 1.0
        h[idx] = h[idx] + (mean - h[idx]) * w


_STAGE_FN = {"regions": _regions, "craters": _craters, "rilles": _rilles, "poles": _poles,
             "footprints": _footprints, "flatten": _flatten}
# endregion


def compute(blk: Block, plan: Plan, upto: str = "end", crater_count: int | None = None):
    """Height (metres, float64) and biome tag masks for every point of the block, running the stages before
    `upto` (a stage name or "end"). `crater_count` limits the craters stamped (used by `prepare`)."""
    h = base_height(blk.d, plan.recipe)
    tags = {k: np.zeros(len(blk), dtype=bool) for k in TAGS}
    for name in STAGES:
        if name == upto:
            break
        if name == "craters":
            _craters(blk, h, tags, plan, crater_count)
        else:
            _STAGE_FN[name](blk, h, tags, plan)
    return h, tags
