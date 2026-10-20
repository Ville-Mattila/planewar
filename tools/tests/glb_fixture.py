"""Pure-Python GLB writer for tests (ART-05): builds exporter-shaped glb files from pw_core generators, so the validator
and the import tools are tested without Blender. Blender space (Z up, ships nose +Y) in, glTF space (Y up) out."""

from __future__ import annotations

import json
import math
import struct
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(TOOLS / "blender" / "lib"))

import pw_core as core  # noqa: E402

PAL = core.Palette()
SHIP_DY = 0.4  # recentres the sample ship so the bounding box (struts reach behind the nozzle) is within V09


def _g(p):
    """Blender -> glTF."""
    return (p[0], p[2], -p[1])


def part_from(verts, faces, swatch):
    """(tris_in_blender_space, swatch_per_tri) from a generator result; `swatch` is one name or a list per face."""
    out = []
    for i, f in enumerate(faces):
        sw = swatch if isinstance(swatch, str) else swatch[i]
        for k in range(1, len(f) - 1):
            out.append(((verts[f[0]], verts[f[k]], verts[f[k + 1]]), sw))
    return out


def sample_ship_parts(dy=SHIP_DY):
    """A Dart-like blockout: fuselage, delta wing (top face team paint), two fins, engine, canopy, three tail struts.
    Returns (tris, empties); every Y is shifted by `dy`."""
    parts = []
    fus = core.prism_between(14, 0.9, 0.15, (0.0, -5.0, -0.5), (0.0, 6.0, -0.5))
    parts += part_from(*fus, "hull_300")
    eng = core.prism_between(12, 0.8, 0.8, (0.0, -6.0, -0.5), (0.0, -5.0, -0.5), caps=(False, True))
    parts += part_from(*eng, "engine_emit")
    wing = core.plate_geometry([(0.0, 4.0), (4.5, -4.8), (-4.5, -4.8)], 0.25, (0.0, 0.0, -0.5))
    parts += part_from(*wing, ["hull_300", "team_paint_mid"] + ["hull_400"] * 3)
    for sx in (-1.0, 1.0):
        fin = core.box_geometry((0.25, 2.2, 2.2), (sx * 1.6, -4.0, 0.5), taper=0.6)
        parts += part_from(*fin, ["hull_300", "team_glow"] + ["team_paint_hi"] * 4)
    can = core.box_geometry((1.0, 2.4, 0.8), (0.0, 2.0, 0.2), taper=0.0)
    parts += part_from(*can, "glass")
    lay = core.strut_layout(1.1, 1.6, [(0.0, -6.0, -0.5)])
    for v, f in core.strut_geometries(lay, 1.1):
        parts += part_from(v, f, "hull_600")
    parts = [(tuple((x, y + dy, z) for x, y, z in tri), sw) for tri, sw in parts]
    empties = {"HP_Nose": (0.0, 6.0 + dy, -0.5), "HP_Tail": (0.0, -6.0 + dy, -0.5)}
    for i, foot in enumerate(lay["feet"]):
        empties[f"HP_Gear_{i}"] = (foot[0], foot[1] + dy, foot[2])
    return parts, empties


def build_glb(asset_id, meshes, empties=None, *, root_name=None, material="PW_Atlas", smooth_first_vertex=False,
              root_translation=None, extra_nodes=()):
    """meshes = {node_name: [(tri, swatch)]}; empties = {name: blender position}. Returns (json dict, bin bytes)."""
    pos, nor, uv, bufs, views, accs, mesh_defs, nodes = [], [], [], bytearray(), [], [], [], []
    root = {"name": root_name or core.pascal(asset_id), "children": []}
    if root_translation:
        root["translation"] = list(root_translation)
    nodes.append(root)

    def add_acc(data, ctype, atype, count, target=None, mm=None):
        while len(bufs) % 4:
            bufs.append(0)
        views.append({"buffer": 0, "byteOffset": len(bufs), "byteLength": len(data), **({"target": target} if target else {})})
        bufs.extend(data)
        a = {"bufferView": len(views) - 1, "componentType": ctype, "count": count, "type": atype}
        if mm:
            a["min"], a["max"] = mm
        accs.append(a)
        return len(accs) - 1

    for name, tris in meshes.items():
        pos, nor, uv = [], [], []
        for tri, sw in tris:
            gp = [_g(p) for p in tri]
            a = [gp[1][i] - gp[0][i] for i in range(3)]
            b = [gp[2][i] - gp[0][i] for i in range(3)]
            n = (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
            ln = math.sqrt(sum(x * x for x in n)) or 1.0
            n = tuple(x / ln for x in n)
            cu, cv = sw if isinstance(sw, tuple) else (PAL.emblem_uv() if sw == "emblem" else PAL.uv(sw))
            for p in gp:
                pos.append(p)
                nor.append(n)
                uv.append((cu, cv))
        if smooth_first_vertex:
            nor[0] = (0.0, 1.0, 0.0) if abs(nor[0][1]) < 0.9 else (1.0, 0.0, 0.0)
        flat = [c for p in pos for c in p]
        mm = ([min(p[i] for p in pos) for i in range(3)], [max(p[i] for p in pos) for i in range(3)])
        ap = add_acc(struct.pack(f"<{len(flat)}f", *flat), 5126, "VEC3", len(pos), 34962, mm)
        flat = [c for p in nor for c in p]
        an = add_acc(struct.pack(f"<{len(flat)}f", *flat), 5126, "VEC3", len(nor), 34962)
        flat = [c for p in uv for c in p]
        au = add_acc(struct.pack(f"<{len(flat)}f", *flat), 5126, "VEC2", len(uv), 34962)
        idx = list(range(len(pos)))
        ai = add_acc(struct.pack(f"<{len(idx)}I", *idx), 5125, "SCALAR", len(idx), 34963)
        mesh_defs.append({"name": name, "primitives": [{"attributes": {"POSITION": ap, "NORMAL": an, "TEXCOORD_0": au},
                                                        "indices": ai, "material": 0, "mode": 4}]})
        nodes.append({"name": name, "mesh": len(mesh_defs) - 1})
        root["children"].append(len(nodes) - 1)
    for name, p in (empties or {}).items():
        nodes.append({"name": name, "translation": list(_g(p))})
        root["children"].append(len(nodes) - 1)
    for n in extra_nodes:
        nodes.append(dict(n))
        root["children"].append(len(nodes) - 1)
    js = {"asset": {"version": "2.0", "generator": "pw-test"}, "scene": 0, "scenes": [{"name": "Scene", "nodes": [0]}],
          "nodes": nodes, "meshes": mesh_defs, "materials": [{"name": material}], "accessors": accs,
          "bufferViews": views, "buffers": [{"byteLength": len(bufs)}]}
    return js, bytes(bufs)


def pack_glb(js, binary):
    body = json.dumps(js, separators=(",", ":")).encode()
    body += b" " * (-len(body) % 4)
    binary = binary + b"\0" * (-len(binary) % 4)
    total = 12 + 8 + len(body) + 8 + len(binary)
    return (struct.pack("<4sII", b"glTF", 2, total) + struct.pack("<II", len(body), 0x4E4F534A) + body
            + struct.pack("<II", len(binary), 0x004E4942) + binary)


def sample_ship(asset_id="ship_dart", far=True, dy=SHIP_DY, drop=(), move=None, **kw):
    """A glb that passes V01-V15 for `ship_dart` against the committed asset_budgets.json.
    `drop` removes hardpoints, `move` overrides their positions (Blender space)."""
    parts, empties = sample_ship_parts(dy)
    for name in drop:
        empties.pop(name)
    empties.update(move or {})
    meshes = {"Hull": parts}
    if far:
        meshes[core.pascal(asset_id) + "Far"] = part_from(*core.box_geometry((6.0, 10.0, 2.5), (0.0, dy, 0.0)), "hull_500")
    return build_glb(asset_id, meshes, empties, **kw)


def sample_pad(asset_id="str_pad", **kw):
    """A glb that passes V01-V15 for `str_pad`: 26 x 26 x 0.8 slab, Foundation part, HP_Dock, HP_Light_0, Far mesh."""
    slab = part_from(*core.box_geometry((26.0, 26.0, 0.8), (0.0, 0.0, 0.4)), ["hull_700", "team_paint_mid"] + ["hull_700"] * 4)
    found = part_from(*core.foundation_geometry((26.0, 26.0)), "hull_700")
    far = part_from(*core.box_geometry((20.0, 20.0, 0.5), (0.0, 0.0, 0.25)), "hull_500")
    meshes = {"Hull": slab, "Foundation": found, core.pascal(asset_id) + "Far": far}
    return build_glb(asset_id, meshes, {"HP_Dock": (0.0, 0.0, 0.8), "HP_Light_0": (10.0, 10.0, 0.8)}, **kw)
