"""Validation M1-M12 (docs/07 s9.5, docs/03 s8.2). Static checks need only the recipe; baked checks need a Bake."""

from __future__ import annotations

import json
import math
import zlib
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from . import sphere
from .bake import BIOME, GRID_PATH, Bake
from .recipe import Plan
from .sphere import PLANET_RADIUS as R

HERE = Path(__file__).resolve().parent
# Thresholds, 07 s9.5 / 03 s8.2.
M2_DISC_M, M2_FRAC, M2_MAX_DEG, M2_MEAN_DEG = 600.0, 0.85, 15.0, 6.0
M3_MAX_DEG, M3_FRAC = 10.0, 0.98
M4_MAX_LAT, M4_MIN_DEPTH = -5.0, 80.0
M5_RMS_M = 8.0
M6_ORE = (1000.0, 1500.0)
M6_TRAP = (1500.0, 2000.0)
M6_SOUTH_HALF_ARC = 45.0
M6_CONTEST_FRAC = 0.05
M7_SPACING_M = 150.0
M10_MAX_BYTES = 4 * 1024 * 1024
M12_MAX_STEP_M = 200.0  # largest height difference between two edge-adjacent texels (cliff/pillar guard)


@dataclass
class Result:
    code: str
    ok: bool
    msg: str

    def __str__(self) -> str:
        return f"{self.code} {'ok  ' if self.ok else 'FAIL'} {self.msg}"


def _res(code: str, problems: list[str], ok_msg: str) -> Result:
    return Result(code, not problems, "; ".join(problems) if problems else ok_msg)


def _bearing_ok(bearing: float) -> bool:
    return abs((bearing % 360.0) - 180.0) <= M6_SOUTH_HALF_ARC


# region static checks --------------------------------------------------------------------------------------------
def m4_latitude(plan: Plan) -> Result:
    bad = []
    for n in plan.nodes:
        if n.kind == "cold_trap":
            lat = float(sphere.lat_lon_deg(n.c)[0])
            if not lat < M4_MAX_LAT:
                bad.append(f"{n.id} at lat {lat:.1f} (cold traps need lat < {M4_MAX_LAT:g})")
    return _res("M4a", bad, "all cold traps at lat < -5")


def m6_distances(plan: Plan) -> Result:
    rec, bad = plan.recipe, []
    for f in rec["resources"]["slot_features"]:
        if f["kind"] == "ore_field" and not M6_ORE[0] <= f["distance_m"] <= M6_ORE[1]:
            bad.append(f"slot feature {f['id']} distance {f['distance_m']:g} m not in {M6_ORE[0]:g}-{M6_ORE[1]:g}")
        if f["kind"] == "cold_trap":
            if not M6_TRAP[0] <= f["distance_m"] <= M6_TRAP[1]:
                bad.append(f"slot feature {f['id']} distance {f['distance_m']:g} m not in {M6_TRAP[0]:g}-{M6_TRAP[1]:g}")
            if not _bearing_ok(f["bearing_deg"]):
                bad.append(f"slot feature {f['id']} bearing {f['bearing_deg']:g} is not south (180 +-{M6_SOUTH_HALF_ARC:g})")
    sl = rec["slots"]
    tol = M6_CONTEST_FRAC * math.radians(sl["spacing_deg"]) * R
    for k in range(sl["count"]):
        mid = sphere.from_lat_lon(0.0, sl["lon0_deg"] + sl["spacing_deg"] * (k + 0.5))
        for n in plan.nodes:
            if n.slot == -1 and n.id.endswith(f"_r{k}") and n.kind == "ore_field":
                lat = float(sphere.lat_lon_deg(n.c)[0])
                if abs(lat) < 5.0 and sphere.great_circle_m(n.c, mid) > tol:
                    bad.append(f"contested field {n.id} is {float(sphere.great_circle_m(n.c, mid)):.0f} m from the midpoint (limit {tol:.0f})")
    return _res("M6", bad, "template distances ok")


def m7_spacing(plan: Plan) -> Result:
    bad = []
    nodes = plan.nodes
    for i, a in enumerate(nodes):
        for b in nodes[i + 1:]:
            d = float(sphere.great_circle_m(a.c, b.c))
            if d < M7_SPACING_M:
                bad.append(f"{a.id} and {b.id} are {d:.0f} m apart (< {M7_SPACING_M:g})")
        for k, c in enumerate(plan.slots):
            d = float(sphere.great_circle_m(a.c, c))
            if k != a.slot and d < M7_SPACING_M:
                bad.append(f"{a.id} is {d:.0f} m from slot {k} centre (< {M7_SPACING_M:g})")
    return _res("M7", bad, f"{len(nodes)} nodes spaced >= {M7_SPACING_M:g} m")


def m11_cube_edges(plan: Plan) -> Result:
    edges = sphere.cube_edge_points()
    reach = plan.flatten_r + plan.flatten_edge
    bad = []
    for k, c in enumerate(plan.slots):
        dist = float(sphere.great_circle_m(edges, c).min())
        if reach >= dist:
            bad.append(f"slot {k} flatten disc ({reach:g} m) touches a cube edge {dist:.0f} m from its centre")
    return _res("M11", bad, "no flatten disc touches a cube edge")


def no_node_in_flatten_disc(plan: Plan) -> Result:
    reach = plan.flatten_r + plan.flatten_edge
    bad = []
    for n in plan.nodes:
        for k, c in enumerate(plan.slots):
            d = float(sphere.great_circle_m(n.c, c))
            if d < reach:
                bad.append(f"{n.id} lies inside the flatten disc of slot {k} ({d:.0f} m < {reach:g})")
    return _res("X1", bad, "no resource node inside a flatten disc")


def validate_static(plan: Plan) -> list[Result]:
    return [m4_latitude(plan), m6_distances(plan), m7_spacing(plan), m11_cube_edges(plan), no_node_in_flatten_disc(plan)]
# endregion


# region baked checks ---------------------------------------------------------------------------------------------
class Sampler:
    """Nearest-texel lookups and disc selections on a Bake."""

    def __init__(self, b: Bake) -> None:
        self.b, self.n = b, b.n
        self._dirs: dict[int, np.ndarray] = {}
        self._hm: dict[int, np.ndarray] = {}

    def dirs(self, f: int) -> np.ndarray:
        if f not in self._dirs:
            self._dirs[f] = sphere.face_grid(f, self.n)
        return self._dirs[f]

    def hm(self, f: int) -> np.ndarray:
        if f not in self._hm:
            self._hm[f] = self.b.height_m(f)
        return self._hm[f]

    def height(self, d: np.ndarray) -> np.ndarray:
        d = np.atleast_2d(d)
        f, u, v = sphere.dir_to_face_uv(d)
        x = np.rint(u * (self.n - 1)).astype(np.int64)
        y = np.rint(v * (self.n - 1)).astype(np.int64)
        lo, hi = self.b.relief
        raw = np.stack([self.b.height[ff][yy, xx] for ff, yy, xx in zip(f, y, x)])
        return lo + raw.astype(np.float64) * ((hi - lo) / 65535.0)

    def disc(self, c: np.ndarray, radius_m: float):
        """[(face, boolean mask (n, n))] of texels within radius_m of c."""
        out = []
        cap = math.radians(54.74) + radius_m / R
        for f in range(6):
            if math.acos(max(-1.0, min(1.0, float(sphere.FACE_N[f] @ c)))) > cap:
                continue
            m = sphere.angle_between(self.dirs(f), c) * R <= radius_m
            if m.any():
                out.append((f, m))
        return out

    def slopes(self, c: np.ndarray, radius_m: float) -> np.ndarray:
        parts = [self.b.slope[f][m].astype(np.float64) * 0.5 for f, m in self.disc(c, radius_m)]
        return np.concatenate(parts) if parts else np.zeros(0)


def m1_relief(b: Bake) -> Result:
    lo, hi = b.relief
    bad = []
    if b.raw_min < lo - 1e-6 or b.raw_max > hi + 1e-6:
        bad.append(f"height {b.raw_min:.1f}..{b.raw_max:.1f} m leaves the relief range {lo:g}..{hi:g} (clamped)")
    return _res("M1", bad, f"relief {b.raw_min:.1f}..{b.raw_max:.1f} m inside {lo:g}..{hi:g}")


def m2_slots(b: Bake, s: Sampler) -> Result:
    bad = []
    for k, c in enumerate(b.plan.slots):
        sl = s.slopes(c, M2_DISC_M)
        frac, mean = float((sl <= M2_MAX_DEG).mean()), float(sl.mean())
        if frac < M2_FRAC or mean > M2_MEAN_DEG:
            bad.append(f"slot {k}: {frac * 100:.0f} % cells <= {M2_MAX_DEG:g} deg (need {M2_FRAC * 100:g}), mean {mean:.1f} deg (max {M2_MEAN_DEG:g})")
    return _res("M2", bad, "slot slopes ok")


def m3_ore(b: Bake, s: Sampler) -> Result:
    bad = []
    for n in b.plan.nodes:
        if n.kind == "ore_field":
            sl = s.slopes(n.c, n.radius_m)
            frac = float((sl <= M3_MAX_DEG).mean()) if len(sl) else 1.0
            if frac < M3_FRAC:
                bad.append(f"{n.id}: only {frac * 100:.0f} % of cells <= {M3_MAX_DEG:g} deg")
    return _res("M3", bad, "ore field slopes ok")


def m4_depth(b: Bake, s: Sampler) -> Result:
    bad = []
    for n in b.plan.nodes:
        if n.kind != "cold_trap":
            continue
        floor = float(s.height(n.c)[0])
        rim = float(s.height(np.stack([sphere.offset_point(n.c, a * 30.0, n.radius_m) for a in range(12)])).mean())
        if rim - floor < M4_MIN_DEPTH:
            bad.append(f"{n.id}: floor only {rim - floor:.0f} m below its rim (need {M4_MIN_DEPTH:g})")
    return _res("M4b", bad, "cold trap floors >= 80 m below rim")


def m5_symmetry(b: Bake, s: Sampler) -> Result:
    lons = 22.5 + np.arange(12) * 3.75 + 1.875
    lats = np.arange(-60.0, 60.1, 5.0)
    pts = np.stack([sphere.from_lat_lon(la, lo) for la in lats for lo in lons])
    base = s.height(pts)
    acc, cnt = 0.0, 0
    for k in range(1, 8):
        diff = s.height(sphere.rot_z(pts, 45.0 * k)) - base
        acc += float((diff ** 2).sum())
        cnt += len(diff)
    rms = math.sqrt(acc / cnt)
    return _res("M5", [f"wedge RMS {rms:.1f} m > {M5_RMS_M:g}"] if rms > M5_RMS_M else [], f"wedge RMS {rms:.2f} m")


def texel_weights(n: int) -> np.ndarray:
    t = np.tan((np.arange(n) / (n - 1.0) * 2.0 - 1.0) * (math.pi / 4.0))
    x, y = np.meshgrid(t, t)
    return (1.0 + x * x) * (1.0 + y * y) / (1.0 + x * x + y * y) ** 1.5


def biome_shares(b: Bake) -> dict[str, float]:
    w = texel_weights(b.n)
    total = w.sum() * 6
    names = {v: k for k, v in BIOME.items()}
    acc = {k: 0.0 for k in BIOME}
    for f in range(6):
        for i, name in names.items():
            acc[name] += float(w[b.biome[f] == i].sum())
    return {k: 100.0 * v / total for k, v in acc.items()}


def m9_biomes(b: Bake) -> Result:
    cfg = json.loads((HERE / "biome_targets.json").read_text(encoding="utf-8"))
    row = cfg.get(b.plan.recipe["id"])
    if row is None:
        return Result("M9", True, "no coverage row for this map (skipped)")
    shares, bad = biome_shares(b), []
    for name, target in row.items():
        if abs(shares[name] - target) > cfg["tolerance_pp"]:
            bad.append(f"{name} {shares[name]:.1f} % vs target {target} % (+-{cfg['tolerance_pp']} pp)")
    return _res("M9", bad, "biome coverage within tolerance")


def _delta_planes(h: np.ndarray) -> bytes:
    """Row-wise delta of a u16 face split into low and high byte planes: what a pack filter would do."""
    d = np.diff(h.astype(np.int32), axis=1, prepend=0).astype(np.int16)
    return (d & 0xFF).astype(np.uint8).tobytes() + ((d >> 8) & 0xFF).astype(np.uint8).tobytes()


def m10_size(b: Bake, files: dict[str, bytes]) -> Result:
    """Estimate of the web map pack (height + biome + features) after a delta filter and deflate. The real pack
    codec (Brotli/zstd) is stronger than zlib, so this is conservative; plain zlib on raw u16 is about 2.4x larger."""
    total = len(zlib.compress(files["features.json"], 6))
    for f in range(6):
        total += len(zlib.compress(_delta_planes(b.height[f]) + files[f"face{f}.biome.u8"], 6))
    msg = f"{total / 1048576:.2f} MB estimated compressed height+biome+features"
    return Result("M10", total <= M10_MAX_BYTES, msg + ("" if total <= M10_MAX_BYTES else " exceeds 4 MB"))


def m12_texel_step(b: Bake) -> Result:
    """Largest height difference between edge-adjacent texels of any face. A single-texel cliff reads as a pillar
    at chase height and a spike from orbit (TA-15: craters stamped inside maria were mesas)."""
    worst, where = 0.0, ""
    for f in range(6):
        h = b.height_m(f)
        for axis, name in ((0, "y"), (1, "x")):
            d = np.abs(np.diff(h, axis=axis))
            i = np.unravel_index(int(np.argmax(d)), d.shape)
            if d[i] > worst:
                worst, where = float(d[i]), f"face {f} texel ({i[1]}, {i[0]}) along {name}"
    ok = worst <= M12_MAX_STEP_M
    return Result("M12", ok, f"max single-texel step {worst:.1f} m at {where}" + ("" if ok else f" exceeds {M12_MAX_STEP_M:g} m"))


# region M8 ground connectivity
def path_adjacency(g: int = GRID_PATH) -> np.ndarray:
    """(8, 6 g g) neighbour ids over the path grid: 4 orthogonal steps (across cube edges through the mapping)
    and 4 in-face diagonals (-1 where none exists)."""
    ids = np.arange(6 * g * g, dtype=np.int64).reshape(6, g, g)
    jj, ii = np.meshgrid(np.arange(g), np.arange(g), indexing="ij")
    adj = np.full((8, 6, g, g), -1, dtype=np.int64)
    steps = [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, -1), (-1, 1), (1, 1)]
    for s, (di, dj) in enumerate(steps):
        for f in range(6):
            i2, j2 = ii + di, jj + dj
            inside = (i2 >= 0) & (i2 < g) & (j2 >= 0) & (j2 < g)
            adj[s, f][inside] = ids[f][j2[inside], i2[inside]]
            if s < 4 and not inside.all():
                u = (i2[~inside] + 0.5) / g
                v = (j2[~inside] + 0.5) / g
                d = sphere.face_uv_to_dir(f, u, v)
                nf, nu, nv = sphere.dir_to_face_uv(d)
                ni = np.minimum((nu * g).astype(np.int64), g - 1)
                nj = np.minimum((nv * g).astype(np.int64), g - 1)
                adj[s, f][~inside] = nf * g * g + nj * g + ni
    return adj.reshape(8, -1)


def path_cell(d: np.ndarray, g: int = GRID_PATH) -> int:
    f, u, v = sphere.dir_to_face_uv(np.asarray(d, dtype=np.float64))
    return int(f) * g * g + min(int(v * g), g - 1) * g + min(int(u * g), g - 1)


def flood(adj: np.ndarray, passable: np.ndarray, start: int) -> np.ndarray:
    seen = np.zeros(len(passable), dtype=bool)
    if not passable[start]:
        return seen
    seen[start] = True
    frontier = np.array([start])
    while len(frontier):
        nb = np.unique(adj[:, frontier].ravel())
        nb = nb[nb >= 0]
        nb = nb[passable[nb] & ~seen[nb]]
        seen[nb] = True
        frontier = nb
    return seen


def reaches(adj: np.ndarray, seen: np.ndarray, cell: int, steps: int) -> bool:
    cur = np.array([cell])
    for _ in range(steps + 1):
        if seen[cur].any():
            return True
        nb = np.unique(adj[:, cur].ravel())
        cur = nb[nb >= 0]
    return False


def m8_connectivity(b: Bake) -> Result:
    plan = b.plan
    if not plan.slots:
        return Result("M8", True, "no slots")
    adj = path_adjacency()
    passable = np.concatenate([p.reshape(-1) for p in b.path]) < 255
    cell_m = math.pi / 2.0 * R / GRID_PATH
    bad = []
    seen_by_slot = []
    for k, c in enumerate(plan.slots):
        seen = flood(adj, passable, path_cell(c))
        seen_by_slot.append(seen)
        if not seen.any():
            bad.append(f"slot {k} Core cell is impassable")
    if not bad:
        base = seen_by_slot[0]
        for k, c in enumerate(plan.slots):
            if not base[path_cell(c)]:
                bad.append(f"Core {k} cannot reach Core 0 (Siege Crawler path)")
        for n in plan.nodes:
            if n.slot >= 0 and n.kind in ("ore_field", "cold_trap"):
                steps = int(math.ceil(n.radius_m / cell_m)) + 1
                if not reaches(adj, seen_by_slot[n.slot], path_cell(n.c), steps):
                    bad.append(f"{n.id} is not reachable from Core {n.slot} (Harvester path)")
    return _res("M8", bad, "Cores, home fields and traps connected on the path grid")
# endregion


def validate_baked(b: Bake, files: dict[str, bytes]) -> list[Result]:
    s = Sampler(b)
    return [m1_relief(b), m2_slots(b, s), m3_ore(b, s), m4_depth(b, s), m5_symmetry(b, s), m8_connectivity(b),
            m9_biomes(b), m10_size(b, files), m12_texel_step(b)]
# endregion
