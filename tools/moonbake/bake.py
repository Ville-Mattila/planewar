"""Bake driver: recipe -> height/biome/slope/path faces, features.json, meta.json (docs/03 s8.2, s8.3)."""

from __future__ import annotations

import hashlib
import json
import math
import time
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

from . import BAKER_VERSION, sphere
from .recipe import Plan, build_plan
from .seam import seam
from .sphere import PLANET_RADIUS as R
from .terrain import TAGS, Block, compute, prepare

GRID_PATH = 256
TILES = 16  # per face side, for stamp culling
BIOME = {"mare": 0, "highland": 1, "crater_floor": 2, "rim_ejecta": 3, "cold_trap": 4, "ore_field": 5,
         "solar_plateau": 6, "rille_floor": 7}
OUTPUT_KINDS = ("height.u16", "biome.u8", "slope.u8", "path.u8")


@dataclass
class Bake:
    n: int
    plan: Plan
    height: list = field(default_factory=list)   # 6 x (n, n) uint16
    biome: list = field(default_factory=list)    # 6 x (n, n) uint8
    slope: list = field(default_factory=list)    # 6 x (n, n) uint8, 0.5 degree steps
    path: list = field(default_factory=list)     # 6 x (256, 256) uint8
    features: dict = field(default_factory=dict)
    seconds: float = 0.0
    raw_min: float = math.inf   # extremes before the relief clamp (M1)
    raw_max: float = -math.inf

    @property
    def relief(self) -> tuple[float, float]:
        r = self.plan.recipe["relief"]
        return float(r["min_m"]), float(r["max_m"])

    def height_m(self, face: int) -> np.ndarray:
        lo, hi = self.relief
        return lo + self.height[face].astype(np.float64) * ((hi - lo) / 65535.0)


def _tile_perm(n: int) -> np.ndarray:
    t = n // TILES
    return np.arange(n * n).reshape(TILES, t, TILES, t).transpose(0, 2, 1, 3).reshape(-1)


def quantise(h: np.ndarray, lo: float, hi: float) -> np.ndarray:
    """Clamp, round to 1 mm (kills libm ulp noise, 03 s8.6), then to u16."""
    h = np.round(np.clip(h, lo, hi), 3)
    return np.clip(np.round((h - lo) / (hi - lo) * 65535.0), 0, 65535).astype(np.uint16)


def slope_u8(hm: np.ndarray, d: np.ndarray) -> np.ndarray:
    """Slope per build cell from the 4 texel corners (03 s8.2 step 7); 0.5 degree steps. d: (n, n, 3)."""
    dx = sphere.angle_between(d[:, :-1], d[:, 1:]) * R
    dy = sphere.angle_between(d[:-1, :], d[1:, :]) * R
    gx = (hm[:, 1:] - hm[:, :-1]) / dx
    gy = (hm[1:, :] - hm[:-1, :]) / dy
    sx = 0.5 * (gx[:-1, :] + gx[1:, :])
    sy = 0.5 * (gy[:, :-1] + gy[:, 1:])
    deg = np.degrees(np.arctan(np.hypot(sx, sy)))
    out = np.zeros(hm.shape, dtype=np.float64)
    out[:-1, :-1] = deg
    out[-1, :-1] = deg[-1, :]
    out[:-1, -1] = deg[:, -1]
    out[-1, -1] = deg[-1, -1]
    return np.clip(np.round(out * 2.0), 0, 180).astype(np.uint8)


def biome_ids(hm: np.ndarray, slope_deg: np.ndarray, tags: dict) -> np.ndarray:
    """07 s9.3 first-match rules, applied from the lowest priority up so the highest priority wins."""
    b = np.where(hm < 0.0, BIOME["mare"], BIOME["highland"]).astype(np.uint8)         # 8
    b[(hm > 250.0) | (slope_deg > 18.0)] = BIOME["highland"]                          # 7
    b[(hm < -150.0) & (slope_deg < 6.0)] = BIOME["mare"]                              # 6
    b[tags["floor"]] = BIOME["crater_floor"]                                          # 5
    b[tags["rim"]] = BIOME["rim_ejecta"]                                              # 4
    b[tags["rille"]] = BIOME["rille_floor"]                                           # 3
    b[tags["plateau"]] = BIOME["solar_plateau"]                                       # 2
    b[tags["ore"]] = BIOME["ore_field"]                                               # 1
    b[tags["cold"]] = BIOME["cold_trap"]                                              # 1
    return b


def path_weights(slope: np.ndarray, biome: np.ndarray) -> np.ndarray:
    """Per GRID_PATH cell: w = 1 + 4 * mean_slope / 15 (1..5); 255 above 30 degrees or inside a cold trap or
    rille floor (03 s8.2 step 7). For faces smaller than the grid the cells repeat texels."""
    n = slope.shape[0]
    deg = slope.astype(np.float64) * 0.5
    blocked = ((biome == BIOME["cold_trap"]) | (biome == BIOME["rille_floor"])).astype(np.float64)
    if n >= GRID_PATH:
        k = n // GRID_PATH
        mean = deg.reshape(GRID_PATH, k, GRID_PATH, k).mean(axis=(1, 3))
        frac = blocked.reshape(GRID_PATH, k, GRID_PATH, k).mean(axis=(1, 3))
    else:
        idx = (np.arange(GRID_PATH) * n) // GRID_PATH
        mean, frac = deg[np.ix_(idx, idx)], blocked[np.ix_(idx, idx)]
    w = np.clip(np.round(1.0 + 4.0 * mean / 15.0), 1, 5)
    w[(mean > 30.0) | (frac > 0.5)] = 255
    return w.astype(np.uint8)


def bake(recipe: dict, progress=None) -> Bake:
    t0 = time.perf_counter()
    say = progress or (lambda msg: None)
    n = recipe["face_resolution"]
    if recipe["radius_m"] != R:
        raise ValueError(f"radius_m {recipe['radius_m']} != Sphere.PLANET_RADIUS {R}")
    plan = build_plan(recipe)
    say("prepare probes")
    prepare(plan)
    out = Bake(n, plan)
    lo, hi = out.relief
    perm = _tile_perm(n)
    csize = (n // TILES) ** 2
    tags_all: list[dict] = []
    dirs: list[np.ndarray] = []
    for f in range(6):
        d = sphere.face_grid(f, n)
        dirs.append(d)
        blk = Block(d.reshape(-1, 3)[perm], csize)
        h, tg = compute(blk, plan)
        out.raw_min, out.raw_max = min(out.raw_min, float(h.min())), max(out.raw_max, float(h.max()))
        hq = np.empty(n * n, dtype=np.uint16)
        hq[perm] = quantise(h, lo, hi)
        out.height.append(hq.reshape(n, n))
        tf = {}
        for k in TAGS:
            a = np.empty(n * n, dtype=bool)
            a[perm] = tg[k]
            tf[k] = a.reshape(n, n)
        tags_all.append(tf)
        say(f"face {f} height done ({time.perf_counter() - t0:.1f} s)")
    seam(out.height)
    for k in TAGS:
        seam([t[k] for t in tags_all])
    for f in range(6):
        hm = out.height_m(f)
        sl = slope_u8(hm, dirs[f])
        bi = biome_ids(hm, sl.astype(np.float64) * 0.5, tags_all[f])
        out.slope.append(sl)
        out.biome.append(bi)
    seam(out.biome)  # biome ids depend on per-face slope; the shared edge texels still agree
    for f in range(6):
        out.path.append(path_weights(out.slope[f], out.biome[f]))
    out.features = expand_features(out)
    out.seconds = time.perf_counter() - t0
    return out


# region features.json -------------------------------------------------------------------------------------------
def _r9(v) -> list:
    return [round(float(x), 9) + 0.0 for x in v]


def cell_of(d: np.ndarray, n: int) -> int:
    f, u, v = sphere.dir_to_face_uv(np.asarray(d, dtype=np.float64))
    i = min(int(math.floor(float(u) * n)), n - 1)
    j = min(int(math.floor(float(v) * n)), n - 1)
    return int(f) * n * n + j * n + i


def expand_features(b: Bake) -> dict:
    plan, rec, n = b.plan, b.plan.recipe, b.n
    nodes = []
    for nd in plan.nodes:
        e = {"id": nd.id, "kind": nd.kind, "cell": cell_of(nd.c, n), "dir": _r9(nd.c), "radius_m": nd.radius_m,
             "slot": nd.slot}
        e.update(nd.extra)
        nodes.append(e)
    sl = rec["slots"]
    slots = []
    for k, c in enumerate(plan.slots):
        slots.append({"slot": k, "dir": _r9(c), "facing_dir": _r9(sphere.tangent_toward(c, sl["facing_deg"]))})
    structs = []
    for s in rec.get("neutral_structures", []):
        c = sphere.from_lat_lon(s["lat"], s["lon"])
        structs.append({"def": s["def"], "dir": _r9(c), "facing_dir": _r9(sphere.tangent_toward(c, s["facing_deg"]))})
    boulders = []
    for bf in rec.get("boulder_fields", []):
        for k in range(8):
            c = sphere.rot_z(sphere.from_lat_lon(bf["lat"], bf["lon"]), 45.0 * k)
            boulders.append({"dir": _r9(c), "radius_m": bf["radius_m"], "density": bf["density"]})
    named = []
    for i, cr in enumerate((rec.get("craters") or {}).get("explicit", [])):
        for k in range(8):
            c = sphere.rot_z(sphere.from_lat_lon(cr["lat"], cr["lon"]), 45.0 * k)
            named.append({"id": f"crater_{i}_w{k}", "type": "crater", "dir": _r9(c), "radius_m": cr["diam_m"] / 2.0})
    if rec["poles"]["midnight_ice_ring"]:
        named.append({"id": "midnight_ice_ring", "type": "ice_ring", "dir": [0.0, 0.0, -1.0], "radius_m": 800.0})
    named.append({"id": "noon_plateau", "type": "plateau", "dir": [0.0, 0.0, 1.0],
                  "radius_m": rec["poles"]["noon_plateau_radius_m"]})
    return {"grid": n, "nodes": nodes, "start_slots": slots, "neutral_structures": structs,
            "boulder_props": boulders, "named_features": named,
            "rules_overrides": rec.get("rules_overrides", {}),
            "unused_slot_yield": rec["resources"]["unused_slot_yield"]}
# endregion


# region files ---------------------------------------------------------------------------------------------------
def canonical(obj) -> bytes:
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def render_files(b: Bake) -> dict[str, bytes]:
    """Every output file by name, in memory. Little-endian u16, row-major (03 s8.3)."""
    files: dict[str, bytes] = {}
    for f in range(6):
        files[f"face{f}.height.u16"] = b.height[f].astype("<u2").tobytes()
        files[f"face{f}.biome.u8"] = b.biome[f].tobytes()
        files[f"face{f}.slope.u8"] = b.slope[f].tobytes()
        files[f"face{f}.path.u8"] = b.path[f].tobytes()
    files["features.json"] = (json.dumps(b.features, indent=1, sort_keys=True) + "\n").encode("utf-8")
    rec = b.plan.recipe
    outputs = {k: hashlib.sha256(v).hexdigest() for k, v in sorted(files.items())}
    meta = {"schema_version": 1, "id": rec["id"], "radius_m": R, "face_resolution": b.n, "relief": rec["relief"],
            "recipe_sha256": hashlib.sha256(canonical(rec)).hexdigest(), "outputs": outputs,
            "map_hash": hashlib.sha256("".join(outputs[k] for k in sorted(outputs)).encode()).hexdigest(),
            "baker_version": BAKER_VERSION}
    files["meta.json"] = (json.dumps(meta, indent=1, sort_keys=True) + "\n").encode("utf-8")
    return files


def write_outputs(b: Bake, out_dir: Path, preview: bool = True) -> dict[str, bytes]:
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    files = render_files(b)
    for name, data in files.items():
        (out_dir / name).write_bytes(data)
    if preview:
        from .preview import write_preview
        write_preview(b, out_dir)
    return files
# endregion
