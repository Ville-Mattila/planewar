"""PLANEWAR Blender helper core (ART-04, docs/07 s4.2-4.4, 4.7): pure Python, no bpy.

Everything that can be computed without Blender lives here so it is unit-tested in plain CI:
palette swatch -> UV mapping, mesh generators (verts, faces), the foundation depth rule, the landing-strut layout
and the geometry checks that `pw.finalize()` reports (same ids and statuses as `tools/art/validate_glb.py`, ART-05).

Coordinates are Blender space (Z up, ships nose toward +Y) unless a name says "gltf". UVs follow the glTF
convention (v = 0 at the top row of the atlas image), which is what 07 s4.3 `v >= 0.875` means for the emblem strip.
"""

from __future__ import annotations

import json
import math
import re
from pathlib import Path

PALETTE_PATH = Path(__file__).resolve().parent.parent / "palette.json"
ID_RE = re.compile(r"^(ship|gnd|str|prop|proj|wreck)_[a-z0-9_]+$")
NAME_RE = re.compile(r"^[A-Za-z0-9_]+$")
SPLAY_DEG = 20.0
UV_TOL = 1e-4
TEAM_MIN, TEAM_MAX = 0.06, 0.35
# Parts kept as separate objects by finalize() (07 s4.2 "Parts that move", Foundation; *Far meshes too).
SEPARATE_NAMES = ("Foundation", "Turret", "Barrel", "Roof", "Arm_L", "Arm_R")

Vec = tuple[float, float, float]


# ---------------------------------------------------------------- palette
class Palette:
    def __init__(self, data: dict | None = None) -> None:
        if data is None:
            data = json.loads(PALETTE_PATH.read_text(encoding="utf-8"))
        atlas = data["atlas"]
        self.size = atlas["size"]
        self.cell = atlas["cell"]
        self.cols = atlas["cols"]
        self.swatch_rows = atlas["swatch_rows"]
        self.emblem_v = atlas["emblem_rows_y"] / self.size  # 0.875
        classes = data["alpha_classes"]
        self.names: list[str] = []
        self.code: list[int] = []
        for name, sw in data["swatches"].items():
            self.names.append(name)
            self.code.append(classes[sw["class"]]["code"])
        for b in data["biomes"]:  # cell order: swatches, then biome ramps (palette.json swatch_note)
            for lvl in ("low", "mid", "high"):
                self.names.append(f"biome_{b['name']}_{lvl}")
                self.code.append(0)
        if len(self.names) > self.cols * self.swatch_rows:
            raise ValueError("palette has more swatches than atlas cells")
        self.index = {n: i for i, n in enumerate(self.names)}

    def cell_of(self, swatch: str) -> tuple[int, int]:
        if swatch not in self.index:
            raise KeyError(f"unknown swatch '{swatch}' (see tools/blender/palette.json)")
        i = self.index[swatch]
        return i % self.cols, i // self.cols

    def uv(self, swatch: str) -> tuple[float, float]:
        """glTF-convention UV of the swatch cell centre (07 s4.3)."""
        col, row = self.cell_of(swatch)
        return (col + 0.5) / self.cols, (row + 0.5) / (self.size // self.cell)

    def swatch_at(self, u: float, v: float) -> int | None:
        """Swatch index whose cell centre is within UV_TOL of (u, v), else None."""
        rows = self.size // self.cell
        col, row = int(u * self.cols), int(v * rows)
        if not (0 <= col < self.cols and 0 <= row < self.swatch_rows):
            return None
        i = row * self.cols + col
        if i >= len(self.names):
            return None
        cu, cv = (col + 0.5) / self.cols, (row + 0.5) / rows
        return i if abs(u - cu) <= UV_TOL and abs(v - cv) <= UV_TOL else None

    def emblem_uv(self, cell: int = 0) -> tuple[float, float]:
        """Centre of emblem cell `cell` (32 px emblems, glTF convention)."""
        per_row = self.size // 32
        return ((cell % per_row) * 32 + 16) / self.size, self.emblem_v + 16 / self.size


def blender_v(v_gltf: float) -> float:
    """Blender UV space has v = 0 at the bottom; the glTF exporter flips it back."""
    return 1.0 - v_gltf


# ---------------------------------------------------------------- generators: (verts, faces)
def _add(a: Vec, b: Vec) -> Vec:
    return a[0] + b[0], a[1] + b[1], a[2] + b[2]


def _sub(a: Vec, b: Vec) -> Vec:
    return a[0] - b[0], a[1] - b[1], a[2] - b[2]


def _mul(a: Vec, s: float) -> Vec:
    return a[0] * s, a[1] * s, a[2] * s


def _cross(a: Vec, b: Vec) -> Vec:
    return a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]


def _len(a: Vec) -> float:
    return math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])


def _norm(a: Vec) -> Vec:
    n = _len(a)
    if n == 0.0:
        raise ValueError("zero-length vector")
    return a[0] / n, a[1] / n, a[2] / n


def box_geometry(size: Vec, loc: Vec, taper: float = 1.0):
    """Box centred on loc; `taper` scales the top (+Z) face about its centre (0 gives a pyramid apex)."""
    hx, hy, hz = size[0] / 2.0, size[1] / 2.0, size[2] / 2.0
    t = taper
    ring = [(-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy)]
    if t == 0.0:  # collapsed top ring: apex pyramid, no degenerate faces
        verts = [_add(loc, (x, y, -hz)) for x, y in ring] + [_add(loc, (0.0, 0.0, hz))]
        return verts, [(0, 3, 2, 1), (0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)]
    verts = [_add(loc, (x, y, -hz)) for x, y in ring] + [_add(loc, (x * t, y * t, hz)) for x, y in ring]
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return verts, faces


_AXES = {"X": (1.0, 0.0, 0.0), "Y": (0.0, 1.0, 0.0), "Z": (0.0, 0.0, 1.0)}


def _basis(axis: Vec) -> tuple[Vec, Vec]:
    ref = (0.0, 0.0, 1.0) if abs(axis[2]) < 0.9 else (1.0, 0.0, 0.0)
    u = _norm(_cross(axis, ref))
    return u, _cross(axis, u)


def prism_between(sides: int, r0: float, r1: float, p0: Vec, p1: Vec, caps: tuple[bool, bool] = (True, True)):
    """Prism from p0 (radius r0) to p1 (radius r1). r == 0 collapses that end to a point (cone/needle)."""
    if sides < 3:
        raise ValueError("prism needs >= 3 sides")
    if r0 <= 0.0 and r1 <= 0.0:
        raise ValueError("both prism radii are zero")
    axis = _norm(_sub(p1, p0))
    u, w = _basis(axis)
    verts: list[Vec] = []
    faces: list[tuple[int, ...]] = []
    ends: list[int | None] = []
    for p, r in ((p0, r0), (p1, r1)):
        if r <= 0.0:
            ends.append(None)
            verts.append(p)
        else:
            ends.append(len(verts))
            for k in range(sides):
                a = 2.0 * math.pi * k / sides
                verts.append(_add(p, _add(_mul(u, r * math.cos(a)), _mul(w, r * math.sin(a)))))
    a, b = ends
    for k in range(sides):
        k2 = (k + 1) % sides
        if a is not None and b is not None:
            faces.append((a + k, a + k2, b + k2, b + k))
        elif a is None and b is not None:
            faces.append((0, b + k2, b + k))
        elif a is not None:
            faces.append((a + k, a + k2, len(verts) - 1))
    if caps[0] and a is not None:
        faces.append(tuple(a + k for k in reversed(range(sides))))
    if caps[1] and b is not None:
        faces.append(tuple(b + k for k in range(sides)))
    return verts, faces


def prism_geometry(sides: int, r0: float, r1: float, length: float, axis: str, loc: Vec):
    """Prism centred on loc along +axis; radius r0 at the -axis end, r1 at the +axis end."""
    a = _AXES[axis.upper()]
    return prism_between(sides, r0, r1, _sub(loc, _mul(a, length / 2.0)), _add(loc, _mul(a, length / 2.0)))


def plate_geometry(pts: list[tuple[float, float]], thickness: float, loc: Vec):
    """Simple polygon in the XY plane extruded +-thickness/2 in Z (winding is normalised)."""
    n = len(pts)
    if n < 3:
        raise ValueError("plate needs >= 3 points")
    area2 = sum(pts[i][0] * pts[(i + 1) % n][1] - pts[(i + 1) % n][0] * pts[i][1] for i in range(n))
    if abs(area2) < 1e-9:
        raise ValueError("plate polygon has zero area")
    pl = list(pts) if area2 > 0 else list(reversed(pts))
    h = thickness / 2.0
    verts = [_add(loc, (x, y, -h)) for x, y in pl] + [_add(loc, (x, y, h)) for x, y in pl]
    faces: list[tuple[int, ...]] = [tuple(reversed(range(n))), tuple(range(n, 2 * n))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))
    return verts, faces


def emblem_geometry(size: float, loc: Vec, rot: Vec):
    """Square quad (normal +Z before rotation), rotated by Euler XYZ radians about loc."""
    h = size / 2.0
    cx, cy, cz = (math.cos(a) for a in rot)
    sx, sy, sz = (math.sin(a) for a in rot)
    out = []
    for x, y, z in ((-h, -h, 0.0), (h, -h, 0.0), (h, h, 0.0), (-h, h, 0.0)):
        y, z = y * cx - z * sx, y * sx + z * cx
        x, z = x * cy + z * sy, -x * sy + z * cy
        x, y = x * cz - y * sz, x * sz + y * cz
        out.append(_add(loc, (x, y, z)))
    return out, [(0, 1, 2, 3)]


def foundation_depth(footprint: tuple[float, float]) -> float:
    """07 s4.2: max(0.27 x half_footprint, 0.6 m); half_footprint is the larger half-extent."""
    return max(0.27 * max(footprint) / 2.0, 0.6)


def foundation_geometry(footprint: tuple[float, float]):
    d = foundation_depth(footprint)
    return box_geometry((footprint[0], footprint[1], d), (0.0, 0.0, -d / 2.0))


def mirrored(verts: list[Vec], faces: list[tuple[int, ...]]):
    """Mirror across X = 0 with flipped winding; vertices on the plane are shared (welded)."""
    remap: dict[int, int] = {}
    out_v = list(verts)
    for i, v in enumerate(verts):
        if abs(v[0]) <= 1e-6:
            remap[i] = i
        else:
            remap[i] = len(out_v)
            out_v.append((-v[0], v[1], v[2]))
    out_f = list(faces) + [tuple(remap[i] for i in reversed(f)) for f in faces]
    return out_v, out_f


# ---------------------------------------------------------------- landing struts (07 s4.5)
def strut_layout(length: float, foot_radius: float, around: list[Vec]) -> dict:
    """Three strut base points, foot-plate centres and plate half-size.

    around = 1 point (single engine, Dart/Scout): bases sit 120 degrees apart at radius
    foot_radius - length*sin(splay) about it and the feet lie on the circle of radius foot_radius.
    around = 3 points (Lancer/Hauler/Bomber): bases are the given points; each foot is pushed outward from their
    XZ centroid by length*sin(splay) (a base on the axis stays put). foot_radius is not used in this case
    because the attach points already fix the stance.
    Feet share one Y (coplanar) = lowest base Y - length*cos(splay), i.e. behind the nozzle plane (-Y).
    """
    if length <= 0.0 or foot_radius <= 0.0:
        raise ValueError("strut length and foot_radius must be > 0")
    sp = math.radians(SPLAY_DEG)
    drop, out = length * math.cos(sp), length * math.sin(sp)
    if len(around) == 1:
        cx, cy, cz = around[0]
        rb = max(foot_radius - out, 0.0)
        dirs = [(math.cos(math.radians(90 + 120 * i)), math.sin(math.radians(90 + 120 * i))) for i in range(3)]
        bases = [(cx + rb * dx, cy, cz + rb * dz) for dx, dz in dirs]
        feet_xz = [(cx + foot_radius * dx, cz + foot_radius * dz) for dx, dz in dirs]
    elif len(around) == 3:
        bases = [(p[0], p[1], p[2]) for p in around]
        cx = sum(p[0] for p in bases) / 3.0
        cz = sum(p[2] for p in bases) / 3.0
        feet_xz = []
        for p in bases:
            dx, dz = p[0] - cx, p[2] - cz
            n = math.hypot(dx, dz)
            feet_xz.append((p[0] + out * dx / n, p[2] + out * dz / n) if n > 1e-9 else (p[0], p[2]))
    else:
        raise ValueError("around must hold 1 (single engine) or 3 attach points")
    fy = min(b[1] for b in bases) - drop
    return {"bases": bases, "feet": [(x, fy, z) for x, z in feet_xz], "plate_half": 0.25 * length}


def strut_geometries(layout: dict, length: float):
    """[(verts, faces)] per strut: open 3-sided prism (6 tris) + double-sided foot plate (4 tris) = 10 tris."""
    out = []
    ph = layout["plate_half"]
    r0, r1 = 0.09 * length, 0.06 * length
    for base, foot in zip(layout["bases"], layout["feet"]):
        v, f = prism_between(3, r0, r1, base, foot, caps=(False, False))
        n = len(v)
        fx, fy, fz = foot
        quad = [(fx - ph, fy, fz - ph), (fx + ph, fy, fz - ph), (fx + ph, fy, fz + ph), (fx - ph, fy, fz + ph)]
        v += quad + quad  # separate vertices for the back face: Blender rejects two faces on the same 4 vertices
        f += [(n, n + 1, n + 2, n + 3), (n + 7, n + 6, n + 5, n + 4)]
        out.append((v, f))
    return out


# ---------------------------------------------------------------- checks (07 s4.7)
def pascal(asset_id: str) -> str:
    return "".join(p.capitalize() for p in asset_id.split("_"))


def tri_normal(p: tuple[Vec, Vec, Vec]) -> Vec:
    return _cross(_sub(p[1], p[0]), _sub(p[2], p[0]))


def _chk(cid: str, status: str, detail: str) -> dict:
    return {"id": cid, "status": status, "detail": detail}


def run_checks(asset_id: str, cls: str, mesh: dict, hardpoints: dict[str, Vec], materials: list[str],
               names: list[str], budget: int | None, palette: Palette, foundation_max: float | None = None) -> dict:
    """Geometry checks V01, V03, V04, V06, V07, V09-V12, V14, V15 on triangulated data.

    mesh = {"tris": [(p0,p1,p2)], "uvs": [(uv0,uv1,uv2)] (glTF convention), "smooth": int (smooth-shaded faces)}.
    Checks needing the glb (V02, V05, V13) or the scale chart (V08) report "skip" here.
    Positions are Blender space (Z up), so V10 reads +Y as forward and V09 'height' is Z.
    """
    tris, uvs = mesh["tris"], mesh["uvs"]
    checks: list[dict] = [_chk("V01", "pass" if ID_RE.match(asset_id) else "fail", f"id '{asset_id}'")]
    n = len(tris)
    if budget is None:
        checks.append(_chk("V03", "skip", f"{n} tris, no budget for class '{cls}' (asset_budgets.json: ART-05)"))
    elif n > budget:
        checks.append(_chk("V03", "fail", f"{n} tris > budget {budget}"))
    elif n < budget * 0.25:
        checks.append(_chk("V03", "warn", f"{n} tris < 25% of budget {budget}"))
    else:
        checks.append(_chk("V03", "pass", f"{n} tris <= {budget}"))
    checks.append(_chk("V04", "pass" if materials == ["PW_Atlas"] else "fail", f"materials {sorted(materials)}"))
    bad6 = 0
    team = total = 0.0
    for t, uv in zip(tris, uvs):
        area = _len(tri_normal(t)) / 2.0
        total += area
        if all(v >= palette.emblem_v for _, v in uv):
            continue
        cells = {palette.swatch_at(u, v) for u, v in uv}
        if len(cells) != 1 or None in cells:
            bad6 += 1
        elif palette.code[next(iter(cells))] in (1, 3):
            team += area
    checks.append(_chk("V06", "pass" if bad6 == 0 else "fail", f"{bad6} triangles off swatch centres"))
    checks.append(_chk("V07", "pass" if mesh["smooth"] == 0 else "fail", f"{mesh['smooth']} smooth faces"))
    degen = sum(1 for t in tris if _len(tri_normal(t)) < 1e-9)
    checks.append(_chk("V12", "pass" if degen == 0 else "fail", f"{degen} zero-area triangles"))
    if total > 0.0:
        frac = team / total
        checks.append(_chk("V14", "pass" if TEAM_MIN <= frac <= TEAM_MAX else "fail",
                           f"team area {frac * 100:.1f}% (6-35%)"))
    else:
        checks.append(_chk("V14", "fail", "no surface"))
    bad_names = [x for x in names if not NAME_RE.match(x)]
    checks.append(_chk("V15", "pass" if not bad_names else "fail", f"bad names {bad_names}"))
    pts = [p for t in tris for p in t]
    lo = tuple(min(p[i] for p in pts) for i in range(3)) if pts else (0.0, 0.0, 0.0)
    hi = tuple(max(p[i] for p in pts) for i in range(3)) if pts else (0.0, 0.0, 0.0)
    mid = tuple((lo[i] + hi[i]) / 2.0 for i in range(3))
    if cls == "ship":
        off = _len(mid)
        checks.append(_chk("V09", "pass" if off <= 0.5 else "fail", f"bbox centre {off:.2f} m from origin"))
        if "HP_Nose" in hardpoints and "HP_Tail" in hardpoints:
            ok = hardpoints["HP_Nose"][1] > hardpoints["HP_Tail"][1]
            checks.append(_chk("V10", "pass" if ok else "fail", "HP_Nose must be ahead (+Y) of HP_Tail"))
        else:
            checks.append(_chk("V10", "fail", "HP_Nose / HP_Tail missing"))
        miss = [r for r in ("HP_Nose", "HP_Tail", "HP_Gear_0", "HP_Gear_1", "HP_Gear_2") if r not in hardpoints]
        if miss:
            checks.append(_chk("V11", "fail", f"missing {miss}"))
        else:
            gear = [hardpoints[f"HP_Gear_{i}"] for i in range(3)]
            spread = max(g[1] for g in gear) - min(g[1] for g in gear)
            tail = hardpoints["HP_Tail"]
            off = math.hypot(sum(g[0] for g in gear) / 3.0 - tail[0], sum(g[2] for g in gear) / 3.0 - tail[2])
            checks.append(_chk("V11", "pass" if spread <= 0.05 and off <= 0.3 else "fail",
                               f"gear coplanar spread {spread:.3f} m, centroid {off:.2f} m off axis"))
    elif cls == "str":
        xy = math.hypot(mid[0], mid[1])
        fmax = foundation_max if foundation_max is not None else 1e9
        ok = xy <= 0.5 and -fmax <= lo[2] <= 0.0
        checks.append(_chk("V09", "pass" if ok else "fail", f"footprint centre {xy:.2f} m, min height {lo[2]:.2f} m"))
    else:
        checks.append(_chk("V09", "skip", f"class '{cls}' has no origin rule here"))
    for cid in ("V02", "V05", "V08", "V13"):
        checks.append(_chk(cid, "skip", "needs the exported glb / scale chart (validate_glb.py)"))
    checks.sort(key=lambda c: c["id"])
    return {"asset_id": asset_id, "class": cls, "tris": n, "ok": all(c["status"] != "fail" for c in checks),
            "checks": checks, "bbox": {"min": list(lo), "max": list(hi)}}
