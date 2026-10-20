#!/usr/bin/env python3
"""validate_glb.py - the authoritative asset gate (ART-05, docs/07 s4.7, checks V01-V15).

    python tools/art/validate_glb.py <file.glb|dir> [...] [--budgets asset_budgets.json] [--report out.json] [--quiet]

Pure Python (struct + json, no Blender, no numpy). Parses the GLB JSON and BIN chunks, rebuilds the triangles in
Blender space (x, -z, y) and runs the same rules `pw.finalize()` runs inside Blender: the geometry rules are
`tools/blender/lib/pw_core.run_checks` (V01, V03, V04, V06, V07, V09-V12, V14, V15); this file adds the glb-only
rules (V02, V05, V08, V13) and the per-asset requirements from `tools/art/asset_budgets.json` (V03 ceiling, V08 sizes,
V11 hardpoints, V13 size, V15 parts and Far mesh).

Output: a JSON report on stdout ({"ok", "files": [...]}); every failed check is also printed to stderr as
`<file>: V03 fail: <detail>`. Exit 0 when every file passes (warnings allowed), 1 otherwise (unreadable file included).
"""

from __future__ import annotations

import argparse
import json
import math
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOOLS = HERE.parent
sys.path.insert(0, str(TOOLS / "blender" / "lib"))
sys.path.insert(0, str(TOOLS))

import pw_core as core  # noqa: E402
from schemalite import SchemaStore, Validator  # noqa: E402

BUDGETS = HERE / "asset_budgets.json"
_CT = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}
_NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
ALLOWED_ATTRS = {"POSITION", "NORMAL", "TEXCOORD_0"}
FLAT_TOL = 1e-3
IDENT_TOL = 1e-6
SHIP_REQUIRED = ("HP_Nose", "HP_Tail", "HP_Gear_0", "HP_Gear_1", "HP_Gear_2")


class GlbError(Exception):
    pass


# ---------------------------------------------------------------- container and accessors
def read_glb(data: bytes) -> tuple[dict, bytes]:
    if len(data) < 20:
        raise GlbError("file shorter than a GLB header")
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF" or version != 2:
        raise GlbError("not a glTF 2.0 binary (magic/version)")
    if length != len(data):
        raise GlbError(f"header length {length} != file size {len(data)}")
    off, js, binary = 12, None, b""
    while off + 8 <= len(data):
        clen, ctype = struct.unpack_from("<II", data, off)
        body = data[off + 8:off + 8 + clen]
        if len(body) != clen:
            raise GlbError("truncated chunk")
        if ctype == 0x4E4F534A:
            try:
                js = json.loads(body)
            except ValueError as e:
                raise GlbError(f"JSON chunk: {e}") from e
        elif ctype == 0x004E4942 and not binary:
            binary = body
        off += 8 + clen
    if not isinstance(js, dict):
        raise GlbError("no JSON chunk")
    return js, binary


def accessor(js: dict, binary: bytes, idx: int) -> list:
    try:
        acc = js["accessors"][idx]
        bv = js["bufferViews"][acc["bufferView"]]
        comps = _NC[acc["type"]]
        fmt = "<" + _CT[acc["componentType"]] * comps
        size = struct.calcsize(fmt)
        stride = bv.get("byteStride", size)
        base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
        rows = [struct.unpack_from(fmt, binary, base + i * stride) for i in range(acc["count"])]
    except (KeyError, IndexError, struct.error, TypeError) as e:
        raise GlbError(f"accessor {idx} unreadable: {e!r}") from e
    return [r[0] for r in rows] if comps == 1 else rows


# ---------------------------------------------------------------- node transforms (column-major 4x4)
def _mat_mul(a: list[float], b: list[float]) -> list[float]:
    return [sum(a[k * 4 + r] * b[c * 4 + k] for k in range(4)) for c in range(4) for r in range(4)]


def _node_matrix(n: dict) -> list[float]:
    if "matrix" in n:
        return [float(x) for x in n["matrix"]]
    tx, ty, tz = n.get("translation", (0.0, 0.0, 0.0))
    qx, qy, qz, qw = n.get("rotation", (0.0, 0.0, 0.0, 1.0))
    sx, sy, sz = n.get("scale", (1.0, 1.0, 1.0))
    xx, yy, zz, xy, xz, yz = qx * qx, qy * qy, qz * qz, qx * qy, qx * qz, qy * qz
    wx, wy, wz = qw * qx, qw * qy, qw * qz
    return [
        (1 - 2 * (yy + zz)) * sx, 2 * (xy + wz) * sx, 2 * (xz - wy) * sx, 0.0,
        2 * (xy - wz) * sy, (1 - 2 * (xx + zz)) * sy, 2 * (yz + wx) * sy, 0.0,
        2 * (xz + wy) * sz, 2 * (yz - wx) * sz, (1 - 2 * (xx + yy)) * sz, 0.0,
        tx, ty, tz, 1.0,
    ]


def _is_identity(n: dict) -> bool:
    m = _node_matrix(n)
    ident = [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0]
    return all(abs(a - b) <= IDENT_TOL for a, b in zip(m, ident))


def _xform(m: list[float], p: tuple[float, float, float], w: float = 1.0) -> tuple[float, float, float]:
    return (m[0] * p[0] + m[4] * p[1] + m[8] * p[2] + m[12] * w,
            m[1] * p[0] + m[5] * p[1] + m[9] * p[2] + m[13] * w,
            m[2] * p[0] + m[6] * p[1] + m[10] * p[2] + m[14] * w)


def _to_blender(p: tuple[float, float, float]) -> tuple[float, float, float]:
    return p[0], -p[2], p[1]


def walk(js: dict) -> list[tuple[dict, list[float]]]:
    """(node, world matrix) for every node reachable from scene 0 (all nodes if there are no scenes)."""
    nodes = js.get("nodes", [])
    scenes = js.get("scenes", [])
    roots = scenes[js.get("scene", 0)].get("nodes", []) if scenes else list(range(len(nodes)))
    out: list[tuple[dict, list[float]]] = []
    seen: set[int] = set()
    ident = _node_matrix({})

    def visit(i: int, parent: list[float]) -> None:
        if i in seen or not 0 <= i < len(nodes):
            return
        seen.add(i)
        world = _mat_mul(parent, _node_matrix(nodes[i]))
        out.append((nodes[i], world))
        for c in nodes[i].get("children", []):
            visit(c, world)

    for r in roots:
        visit(r, ident)
    return out


# ---------------------------------------------------------------- geometry read-back
def geometry(js: dict, binary: bytes) -> dict:
    """{"tris", "uvs", "smooth", "far_tris"}: triangles in Blender space; `smooth` counts triangles whose vertex normals
    differ from the face normal by more than FLAT_TOL (V07). Unsupported primitive modes are reported by V05."""
    tris: list = []
    uvs: list = []
    smooth = 0
    meshes = js.get("meshes", [])
    for node, world in walk(js):
        if "mesh" not in node:
            continue
        for prim in meshes[node["mesh"]].get("primitives", []):
            attrs = prim.get("attributes", {})
            if prim.get("mode", 4) != 4 or "POSITION" not in attrs:
                continue
            pos = accessor(js, binary, attrs["POSITION"])
            nor = accessor(js, binary, attrs["NORMAL"]) if "NORMAL" in attrs else None
            uv = accessor(js, binary, attrs["TEXCOORD_0"]) if "TEXCOORD_0" in attrs else None
            idx = accessor(js, binary, prim["indices"]) if "indices" in prim else list(range(len(pos)))
            for i in range(0, len(idx) - 2, 3):
                a, b, c = idx[i], idx[i + 1], idx[i + 2]
                wp = tuple(_xform(world, pos[k]) for k in (a, b, c))
                tri = tuple(_to_blender(p) for p in wp)
                fn = core.tri_normal(wp)
                ln = math.sqrt(sum(x * x for x in fn))
                if nor is None:
                    smooth += 1
                elif ln > 1e-12:
                    for k in (a, b, c):
                        vn = _xform(world, nor[k], 0.0)
                        vl = math.sqrt(sum(x * x for x in vn)) or 1.0
                        if max(abs(vn[j] / vl - fn[j] / ln) for j in range(3)) > FLAT_TOL:
                            smooth += 1
                            break
                tris.append(tri)
                uvs.append(tuple(tuple(uv[k]) for k in (a, b, c)) if uv else ((0.0, 0.0),) * 3)
    return {"tris": tris, "uvs": uvs, "smooth": smooth}


def hardpoints(js: dict) -> dict[str, tuple[float, float, float]]:
    out = {}
    for node, world in walk(js):
        name = node.get("name", "")
        if name.startswith("HP_") and "mesh" not in node:
            out[name] = _to_blender((world[12], world[13], world[14]))
    return out


# ---------------------------------------------------------------- budgets
def load_budgets(path: Path = BUDGETS) -> dict:
    """Read and schema-check asset_budgets.json (tools/schemas/asset_budgets.schema.json)."""
    data = json.loads(path.read_text(encoding="utf-8"))
    store = SchemaStore(TOOLS / "schemas")
    schema = store.load("asset_budgets.schema.json")
    errs = [f"{p or '/'}: {m}" for p, m in Validator(store).validate(data, schema, "asset_budgets.schema.json")]
    if errs:
        raise GlbError(f"{path}: " + "; ".join(errs[:5]))
    return data


def _chk(cid: str, status: str, detail: str) -> dict:
    return core._chk(cid, status, detail)


def _replace(checks: list[dict], new: dict) -> None:
    for i, c in enumerate(checks):
        if c["id"] == new["id"]:
            checks[i] = new
            return
    checks.append(new)


def _size_check(bbox: dict, entry: dict | None, cls: str, budgets: dict) -> dict:
    size = entry.get("size_m") if entry else None
    if not size:
        return _chk("V08", "skip", "no scale-chart size for this asset (asset_budgets.json)")
    frac = budgets.get("size_tolerance_frac", 0.10)
    slack = budgets.get("size_tolerance_min_m", 0.25)
    lo, hi = bbox["min"], bbox["max"]
    # structures: the foundation skirt below y=0 is not part of the charted height (asset_budgets.json _doc)
    have = [hi[0] - lo[0], hi[1] - lo[1], (hi[2] if cls == "str" else hi[2] - lo[2])]
    bad = []
    for ax, want, got in zip("XYZ", size, have):
        if want is not None and abs(got - want) > max(frac * want, slack):
            bad.append(f"{ax} {got:.2f} m vs chart {want:g} m")
    return _chk("V08", "fail" if bad else "pass",
                "; ".join(bad) if bad else f"{have[0]:.1f} x {have[1]:.1f} x {have[2]:.1f} m within {frac * 100:.0f}% of chart")


def _hardpoint_check(base: dict | None, cls: str, entry: dict | None, hp: dict) -> dict | None:
    extra = [h for h in (entry or {}).get("hardpoints", []) if h not in hp]
    required = (entry or {}).get("hardpoints", [])
    if base is not None:  # ship rules from pw_core (nose/tail/gear geometry)
        if extra:
            return _chk("V11", "fail", f"{base['detail']}; missing {extra} (asset_budgets.json)")
        return base
    if not required:
        return _chk("V11", "skip", f"no hardpoints required for this {cls} asset")
    return _chk("V11", "fail" if extra else "pass", f"missing {extra}" if extra else f"{len(required)} required hardpoints present")


def _names_check(asset_id: str, node_names: list[str], cls: str, entry: dict | None, budgets: dict, base: dict) -> dict:
    problems = []
    if base["status"] == "fail":
        problems.append(base["detail"])
    need = list(budgets["classes"][cls].get("parts", [])) + list((entry or {}).get("parts", []))
    missing = [n for n in need if n not in node_names]
    if missing:
        problems.append(f"missing parts {missing}")
    far = core.pascal(asset_id) + "Far"
    if (entry or {}).get("far") and far not in node_names:
        problems.append(f"missing the '{far}' mesh node")
    return _chk("V15", "fail" if problems else "pass", "; ".join(problems) if problems else "names ok, required parts present")


# ---------------------------------------------------------------- validation
def validate_bytes(asset_id: str, data: bytes, budgets: dict, file_ok: bool = True) -> dict:
    try:
        js, binary = read_glb(data)
        geo = geometry(js, binary)
        hp = hardpoints(js)
    except GlbError as e:
        return {"asset_id": asset_id, "class": None, "tris": 0, "ok": False, "checks": [_chk("GLB", "fail", str(e))]}
    cls = asset_id.split("_", 1)[0] if core.ID_RE.match(asset_id) else "prop"
    entry = budgets["assets"].get(asset_id)
    cdef = budgets["classes"].get(cls)
    names = [n.get("name", "") for n, _ in walk(js)]
    materials = [m.get("name", "") for m in js.get("materials", [])]
    fmax = None
    if cls == "str":
        size = (entry or {}).get("size_m")
        fmax = core.foundation_depth((size[0], size[1])) + 1e-3 if size else None
    rep = core.run_checks(asset_id, cls, geo, hp, materials, names, core.tri_budget(asset_id, budgets), core.Palette(), fmax)
    checks: list[dict] = rep["checks"]
    if not file_ok:
        _replace(checks, _chk("V01", "fail", f"file name must be '{asset_id}.glb'"))
    # V02 root
    scenes = js.get("scenes", [])
    roots = scenes[js.get("scene", 0)].get("nodes", []) if scenes else []
    want = core.pascal(asset_id)
    if len(roots) != 1:
        v02 = _chk("V02", "fail", f"{len(roots)} root nodes, expected exactly one named '{want}'")
    else:
        root = js["nodes"][roots[0]]
        if root.get("name") != want:
            v02 = _chk("V02", "fail", f"root is '{root.get('name')}', expected '{want}'")
        elif not _is_identity(root):
            v02 = _chk("V02", "fail", "root node transform is not identity")
        else:
            v02 = _chk("V02", "pass", f"root '{want}' at identity")
    _replace(checks, v02)
    # V04 images
    if js.get("images") or js.get("textures"):
        v04 = next(c for c in checks if c["id"] == "V04")
        _replace(checks, _chk("V04", "fail", f"{v04['detail']}; images/textures embedded (must be empty)"))
    # V05 attributes
    bad5 = []
    for mi, mesh in enumerate(js.get("meshes", [])):
        for pi, prim in enumerate(mesh.get("primitives", [])):
            extra = sorted(set(prim.get("attributes", {})) - ALLOWED_ATTRS)
            miss = sorted(ALLOWED_ATTRS - set(prim.get("attributes", {})))
            if extra or miss:
                bad5.append(f"mesh {mi}/{pi} extra {extra} missing {miss}")
            if prim.get("mode", 4) != 4:
                bad5.append(f"mesh {mi}/{pi} mode {prim['mode']} is not triangles")
            if prim.get("targets"):
                bad5.append(f"mesh {mi}/{pi} has morph targets")
    for key in ("skins", "animations"):
        if js.get(key):
            bad5.append(f"{key} present")
    if any("skin" in n for n in js.get("nodes", [])):
        bad5.append("node references a skin")
    _replace(checks, _chk("V05", "fail" if bad5 else "pass", "; ".join(bad5) if bad5 else "POSITION, NORMAL, TEXCOORD_0 only"))
    _replace(checks, _size_check(rep["bbox"], entry, cls, budgets))
    # V11 / V15 per-asset requirements
    base11 = next(c for c in checks if c["id"] == "V11") if any(c["id"] == "V11" for c in checks) else None
    v11 = _hardpoint_check(base11, cls, entry, hp)
    if v11 is not None:
        _replace(checks, v11)
    _replace(checks, _names_check(asset_id, names, cls, entry, budgets, next(c for c in checks if c["id"] == "V15")))
    # V13 file size
    limit = (entry or {}).get("max_file_kb", cdef["max_file_kb"] if cdef else 150)
    kb = len(data) / 1024.0
    _replace(checks, _chk("V13", "pass" if kb <= limit else "fail", f"{kb:.1f} KB (limit {limit} KB)"))
    checks.sort(key=lambda c: c["id"])
    return {"asset_id": asset_id, "class": cls, "tris": rep["tris"], "ok": all(c["status"] != "fail" for c in checks),
            "checks": checks, "bbox": rep["bbox"], "hardpoints": sorted(hp)}


def validate_file(path: Path, budgets: dict) -> dict:
    asset_id = path.stem
    try:
        data = path.read_bytes()
    except OSError as e:
        return {"asset_id": asset_id, "class": None, "tris": 0, "ok": False, "checks": [_chk("GLB", "fail", str(e))],
                "file": str(path)}
    rep = validate_bytes(asset_id, data, budgets, file_ok=path.suffix == ".glb")
    rep["file"] = str(path)
    return rep


def collect(paths: list[str]) -> list[Path]:
    out: list[Path] = []
    for p in map(Path, paths):
        out.extend(sorted(p.rglob("*.glb")) if p.is_dir() else [p])
    return out


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("paths", nargs="+", help=".glb files or directories (searched recursively)")
    ap.add_argument("--budgets", default=str(BUDGETS))
    ap.add_argument("--report", help="also write the JSON report here")
    ap.add_argument("--quiet", action="store_true", help="no JSON on stdout; failures on stderr only")
    args = ap.parse_args(argv)
    try:
        budgets = load_budgets(Path(args.budgets))
    except (OSError, ValueError, GlbError) as e:
        print(f"{args.budgets}:1: {e}", file=sys.stderr)
        return 1
    files = collect(args.paths)
    if not files:
        print("validate_glb: no .glb files found", file=sys.stderr)
        return 1
    reports = [validate_file(f, budgets) for f in files]
    ok = all(r["ok"] for r in reports)
    for r in reports:
        for c in r["checks"]:
            if c["status"] == "fail":
                print(f"{r['file']}: {c['id']} fail: {c['detail']}", file=sys.stderr)
            elif c["status"] == "warn":
                print(f"{r['file']}: {c['id']} warn: {c['detail']}", file=sys.stderr)
    doc = json.dumps({"ok": ok, "files": reports}, indent=1)
    if args.report:
        Path(args.report).write_text(doc, encoding="utf-8")
    if not args.quiet:
        print(doc)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
