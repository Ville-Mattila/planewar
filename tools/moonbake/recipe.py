"""Recipe loading and expansion into the flat feature plan (docs/03 s8.1, s8.2 step 8, R0 B.2)."""

from __future__ import annotations

import json
import sys
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

from . import sphere
from .noise import SplitMix64

TOOLS = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(TOOLS))

from schemalite import SchemaStore, Validator  # noqa: E402
from validate_content import Report, check_recipe_ids, validate  # noqa: E402

NODE_KINDS_WITH_FOOTPRINT = ("ore_field", "cold_trap")
DEFAULT_RADIUS_M = {"ore_field": 250.0, "cold_trap": 60.0, "relay_station": 40.0, "start_refinery": 40.0,
                    "solar_plateau": 300.0}
SCATTER_MIN_DIAM_M = 60.0  # smaller craters are left to the renderer's detail shader (03 s8.2)
SCATTER_LAT_LIMIT_DEG = 70.0


class RecipeError(Exception):
    def __init__(self, messages: list[str]) -> None:
        super().__init__("\n".join(messages))
        self.messages = messages


def load_recipe(path: Path) -> dict:
    """Parse and schema-validate; raises RecipeError with one `file:pointer: message` line per violation."""
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise RecipeError([f"{path}: {exc}"]) from exc
    rep = Report()
    val = Validator(SchemaStore(TOOLS / "schemas"))
    validate(val, rep, str(path), data, "map_recipe")
    if not rep.errors:
        check_recipe_ids(rep, str(path), data)
    if rep.errors:
        raise RecipeError(rep.errors)
    return data


@dataclass
class Crater:
    c: np.ndarray
    r: float
    depth: float
    rim: float
    ejecta: float
    base_mean: float = 0.0  # base height averaged over the crater disc, filled by the baker


@dataclass
class Node:
    id: str
    kind: str
    c: np.ndarray
    radius_m: float
    slot: int
    extra: dict = field(default_factory=dict)
    ring_ref: float = 0.0  # cold trap: mean height on the rim ring, filled by the baker


@dataclass
class Plan:
    """Everything the stamps and validators need, all lengths in metres, directions as unit vectors."""
    recipe: dict
    regions: list[dict]
    craters: list[Crater]
    rilles: list[dict]
    slots: list[np.ndarray]
    nodes: list[Node]
    plateau_c: np.ndarray
    plateau_r: float
    plateau_h: float
    flatten_r: float
    flatten_edge: float
    slot_means: list[float] = field(default_factory=list)


def _rot_copies(c: np.ndarray, count: int = 8) -> list[np.ndarray]:
    return [sphere.rot_z(c, 45.0 * k) for k in range(count)]


def _scatter(recipe: dict) -> list[Crater]:
    sc = (recipe.get("craters") or {}).get("scatter")
    if not sc or not sc["per_wedge"]:
        return []
    rng = SplitMix64(recipe["seed"] ^ sc.get("seed_offset", 0))
    dmin, dmax = float(sc["diam_m"][0]), float(sc["diam_m"][1])
    p = float(sc["power"])
    out: list[Crater] = []
    lo = np.sin(np.radians(-SCATTER_LAT_LIMIT_DEG))
    hi = np.sin(np.radians(SCATTER_LAT_LIMIT_DEG))
    for _ in range(sc["per_wedge"]):
        lon = 22.5 + 45.0 * rng.uniform()
        lat = float(np.degrees(np.arcsin(lo + (hi - lo) * rng.uniform())))
        u = rng.uniform()
        if abs(p - 1.0) < 1e-9:
            diam = dmin * (dmax / dmin) ** u
        else:
            a, b = dmin ** (1.0 - p), dmax ** (1.0 - p)
            diam = (a + u * (b - a)) ** (1.0 / (1.0 - p))
        if diam < SCATTER_MIN_DIAM_M:
            continue
        r = diam / 2.0
        c0 = sphere.from_lat_lon(lat, lon)
        for c in _rot_copies(c0):
            out.append(Crater(c, r, 0.2 * r, 0.08 * r, 2.0 * r))
    return out


def _node_defaults(feat: dict) -> tuple[float, dict]:
    kind = feat["kind"]
    extra = {k: feat[k] for k in ("capacity", "regen_per_s", "rate_per_s", "max_miners") if k in feat}
    return float(feat.get("radius_m", DEFAULT_RADIUS_M[kind])), extra


def build_plan(recipe: dict) -> Plan:
    sl = recipe["slots"]
    count = sl["count"]
    slots = [sphere.from_lat_lon(0.0, sl["lon0_deg"] + sl["spacing_deg"] * k) for k in range(count)]
    regions = []
    for g in recipe.get("regions", []):
        for c in _rot_copies(sphere.from_lat_lon(g["lat"], g["lon"])):
            regions.append({**g, "c": c})
    craters: list[Crater] = []
    for cr in (recipe.get("craters") or {}).get("explicit", []):
        for c in _rot_copies(sphere.from_lat_lon(cr["lat"], cr["lon"])):
            r = cr["diam_m"] / 2.0
            craters.append(Crater(c, r, cr["depth_m"], cr["rim_m"], max(cr.get("ejecta_m", 2.0 * r), r)))
    craters += _scatter(recipe)
    rilles = []
    for ri in recipe.get("rilles", []):
        pts0 = [sphere.from_lat_lon(a, b) for a, b in ri["path"]]
        for k in range(8):
            rilles.append({**ri, "pts": [sphere.rot_z(p, 45.0 * k) for p in pts0]})
    res = recipe["resources"]
    nodes: list[Node] = []
    for k, sc in enumerate(slots):
        for f in res["slot_features"]:
            rad, extra = _node_defaults(f)
            c = sphere.offset_point(sc, f["bearing_deg"], f["distance_m"])
            nodes.append(Node(f"{f['id']}_s{k}", f["kind"], c, rad, k, extra))
        for f in res["ring_features"]:
            rad, extra = _node_defaults(f)
            c = sphere.from_lat_lon(f["lat_deg"], sl["lon0_deg"] + sl["spacing_deg"] * k + f["lon_offset_deg"])
            nodes.append(Node(f"{f['id']}_r{k}", f["kind"], c, rad, -1, extra))
    for f in res["pole_features"]:
        rad, extra = _node_defaults(f)
        pole = sphere.Z_AXIS if f["pole"] == "noon" else -sphere.Z_AXIS
        c = sphere.offset_point(pole, f["bearing_deg"], f["distance_m"])
        nodes.append(Node(f["id"], f["kind"], c, rad, -1, extra))
    po = recipe["poles"]
    return Plan(recipe, regions, craters, rilles, slots, nodes, sphere.Z_AXIS.copy(), po["noon_plateau_radius_m"],
                po["noon_plateau_height_m"], sl["flatten_radius_m"], sl["flatten_edge_m"])
