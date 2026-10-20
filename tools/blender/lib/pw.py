"""PLANEWAR Blender helper library (ART-04, docs/07 s4.4).

Runs inside Blender (>= 4.2): through the Blender MCP `execute_blender_code` tool (see ../mcp_bootstrap.py) or
headless (`python tools/blender/run_headless.py <recipe.py> <out_dir>`). Recipes only call this module; geometry
maths and checks live in pw_core.py (pure Python, unit-tested without Blender).

Conventions (07 s4.2): metric, Z up, ships nose +Y, one material `PW_Atlas`, flat shading, every object at
identity transform (geometry is built in place), hardpoints are `HP_*` empties of size 0.5.
"""

from __future__ import annotations

import math
import os
import sys

import bmesh
import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pw_core as core  # noqa: E402

PALETTE = core.Palette()
MATERIAL = "PW_Atlas"
_ctx: dict = {"id": None, "cls": None, "coll": None}


# ---------------------------------------------------------------- session
def begin(asset_id: str, cls: str | None = None) -> bpy.types.Collection:
    """New collection PW_<id> in the current file; only a previous collection of the same name is removed."""
    if not core.ID_RE.match(asset_id):
        raise ValueError(f"asset id '{asset_id}' must match {core.ID_RE.pattern}")
    cls = cls or asset_id.split("_", 1)[0]
    if cls != asset_id.split("_", 1)[0]:
        raise ValueError(f"class '{cls}' does not match the id prefix of '{asset_id}'")
    name = f"PW_{asset_id}"
    old = bpy.data.collections.get(name)
    if old is not None:
        for obj in list(old.all_objects):
            data = obj.data
            bpy.data.objects.remove(obj, do_unlink=True)
            if isinstance(data, bpy.types.Mesh) and data.users == 0:
                bpy.data.meshes.remove(data)
        bpy.data.collections.remove(old)
    coll = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(coll)
    coll["pw_id"], coll["pw_class"] = asset_id, cls
    units = bpy.context.scene.unit_settings
    units.system, units.scale_length = "METRIC", 1.0
    _ctx.update(id=asset_id, cls=cls, coll=coll)
    return coll


def _coll() -> bpy.types.Collection:
    if _ctx["coll"] is None or _ctx["coll"].name not in bpy.data.collections:
        raise RuntimeError("call pw.begin(asset_id, cls) first")
    return _ctx["coll"]


def _material() -> bpy.types.Material:
    mat = bpy.data.materials.get(MATERIAL) or bpy.data.materials.new(MATERIAL)
    return mat


def _link(obj: bpy.types.Object) -> bpy.types.Object:
    _coll().objects.link(obj)
    return obj


def _make(name: str, verts: list, faces: list, swatch: str | None) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    mesh.update()
    mesh.materials.append(_material())
    mesh.shade_flat()
    obj = _link(bpy.data.objects.new(name, mesh))
    mesh.uv_layers.new(name="UVMap")
    if swatch is not None:
        paint(obj, swatch)
    return obj


# ---------------------------------------------------------------- primitives
def box(name: str, size: tuple, loc: tuple, swatch: str, taper: float = 1.0) -> bpy.types.Object:
    v, f = core.box_geometry(tuple(size), tuple(loc), taper)
    return _make(name, v, f, swatch)


def prism(name: str, sides: int, r0: float, r1: float, length: float, axis: str, loc: tuple,
          swatch: str) -> bpy.types.Object:
    v, f = core.prism_geometry(sides, r0, r1, length, axis, tuple(loc))
    return _make(name, v, f, swatch)


def poly_plate(name: str, pts: list, thickness: float, loc: tuple, swatch: str) -> bpy.types.Object:
    v, f = core.plate_geometry([tuple(p) for p in pts], thickness, tuple(loc))
    return _make(name, v, f, swatch)


def emblem_quad(name: str, size: float, loc: tuple, rot: tuple) -> bpy.types.Object:
    """Quad whose UVs map into emblem cell 0 (v >= 0.875); the shader adds team_index * 0.125 to u."""
    v, f = core.emblem_geometry(size, tuple(loc), tuple(rot))
    obj = _make(name, v, f, None)
    eu, ev = PALETTE.emblem_uv(0)
    for d in obj.data.uv_layers[0].data:
        d.uv = (eu, core.blender_v(ev))
    return obj


def foundation(footprint: tuple) -> bpy.types.Object:
    """Footprint extruded down by max(0.27 x half_footprint, 0.6 m), swatch hull_700."""
    v, f = core.foundation_geometry((footprint[0], footprint[1]))
    return _make("Foundation", v, f, "hull_700")


def hardpoint(name: str, loc: tuple) -> bpy.types.Object:
    if not name.startswith("HP_"):
        raise ValueError("hardpoint names start with HP_")
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type, obj.empty_display_size = "PLAIN_AXES", 0.5
    obj.location = tuple(loc)
    obj["hp_type"] = name[3:].rstrip("0123456789_")  # export_extras: hardpoint type for post-import
    return _link(obj)


# ---------------------------------------------------------------- painting / mirroring
def paint(obj: bpy.types.Object, swatch: str, faces: list | None = None) -> None:
    """UV-to-swatch (07 s4.3): the three (all) UVs of each face go to the centre of one swatch cell."""
    u, v = PALETTE.uv(swatch)
    mesh = obj.data
    layer = mesh.uv_layers.active or mesh.uv_layers.new(name="UVMap")
    wanted = None if faces is None else set(faces)
    for poly in mesh.polygons:
        if wanted is not None and poly.index not in wanted:
            continue
        for li in poly.loop_indices:
            layer.data[li].uv = (u, core.blender_v(v))


def mirror_x(objs: list) -> None:
    """Mirror each mesh across X = 0 (flipped winding, plane vertices welded) and apply, in place."""
    for obj in objs:
        if obj.type != "MESH":
            raise TypeError(f"mirror_x takes meshes, '{obj.name}' is {obj.type}")
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        dup = bmesh.ops.duplicate(bm, geom=geom)["geom"]
        dverts = [g for g in dup if isinstance(g, bmesh.types.BMVert)]
        bmesh.ops.scale(bm, vec=(-1.0, 1.0, 1.0), verts=dverts)
        bmesh.ops.reverse_faces(bm, faces=[g for g in dup if isinstance(g, bmesh.types.BMFace)])
        bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
        bm.to_mesh(obj.data)
        bm.free()
        obj.data.shade_flat()


# ---------------------------------------------------------------- ships
def landing_struts(length: float, foot_radius: float, around: list) -> list:
    """Tail landing struts: HP_Gear_0..2 at the foot-plate centres (07 s4.5). Returns the 3 strut objects."""
    layout = core.strut_layout(length, foot_radius, [tuple(p) for p in around])
    out = []
    for i, (v, f) in enumerate(core.strut_geometries(layout, length)):
        out.append(_make(f"Strut_{i}", v, f, "hull_400"))
        hardpoint(f"HP_Gear_{i}", layout["feet"][i])
    return out


# ---------------------------------------------------------------- finish
def _mesh_objs() -> list:
    return [o for o in _coll().objects if o.type == "MESH"]


def _is_separate(name: str) -> bool:
    return name in core.SEPARATE_NAMES or name.endswith("Far")


def _tri_count(obj: bpy.types.Object) -> int:
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    n = sum(len(f.verts) - 2 for f in bm.faces)
    bm.free()
    return n


def far_mesh(source: list, target_tris: int = 48) -> bpy.types.Object:
    """Decimated copy of `source`, repainted to the swatch covering most of its area, named <Pascal(id)>Far."""
    bm = bmesh.new()
    for o in source:
        bm.from_mesh(o.data)
    name = core.pascal(_ctx["id"]) + "Far"
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(_material())
    obj = _link(bpy.data.objects.new(name, mesh))
    if not mesh.uv_layers:
        mesh.uv_layers.new(name="UVMap")
    # dominant swatch by area
    area: dict = {}
    for poly in mesh.polygons:
        li = poly.loop_indices[0]
        uv = tuple(round(c, 4) for c in mesh.uv_layers[0].data[li].uv)
        area[uv] = area.get(uv, 0.0) + poly.area
    dom = max(area, key=area.get) if area else None
    ratio = 1.0
    for _ in range(12):
        if _tri_count(obj) <= target_tris:
            break
        ratio *= min(0.8, target_tris / max(_tri_count(obj), 1))
        mod = obj.modifiers.new("Decimate", "DECIMATE")
        mod.ratio = max(ratio, 0.01)
        dg = bpy.context.evaluated_depsgraph_get()
        new = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
        obj.modifiers.remove(mod)
        old = obj.data
        obj.data = new
        bpy.data.meshes.remove(old)
    obj.data.materials.clear()
    obj.data.materials.append(_material())
    obj.data.shade_flat()
    layer = obj.data.uv_layers.active or obj.data.uv_layers.new(name="UVMap")
    if dom is not None:
        for d in layer.data:
            d.uv = dom
    return obj


def _tri_data(objs: list) -> dict:
    tris, uvs, smooth = [], [], 0
    dg = bpy.context.evaluated_depsgraph_get()
    for o in objs:
        me = bpy.data.meshes.new_from_object(o.evaluated_get(dg))
        smooth += sum(1 for p in me.polygons if p.use_smooth)
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        uv = bm.loops.layers.uv.active
        mw = o.matrix_world
        for f in bm.faces:
            tris.append(tuple(tuple(mw @ l.vert.co) for l in f.loops))
            uvs.append(tuple((l[uv].uv[0], core.blender_v(l[uv].uv[1])) for l in f.loops) if uv
                       else ((-1.0, -1.0),) * 3)
        bm.free()
        bpy.data.meshes.remove(me)
    return {"tris": tris, "uvs": uvs, "smooth": smooth}


def finalize(asset_id: str, budget: int | None = None) -> dict:
    """Join per rules, dissolve coplanar leftovers, flat shade, add Triangulate, validate. Returns the report."""
    if asset_id != _ctx["id"]:
        raise ValueError(f"finalize('{asset_id}') but the open asset is '{_ctx['id']}'")
    coll = _coll()
    bpy.context.view_layer.update()
    for o in coll.objects:
        if any(abs(a) > 1e-9 for a in o.rotation_euler) or any(abs(c - 1.0) > 1e-9 for c in o.scale):
            raise ValueError(f"'{o.name}' has non-identity rotation/scale; recipes build geometry in place")
    joinable = [o for o in _mesh_objs() if not _is_separate(o.name)]
    if len(joinable) > 1 or (joinable and joinable[0].name != "Hull"):
        bm = bmesh.new()
        for o in joinable:
            bm.from_mesh(o.data)
        mesh = bpy.data.meshes.new("Hull")
        bm.to_mesh(mesh)
        bm.free()
        mesh.materials.append(_material())
        for o in joinable:
            data = o.data
            bpy.data.objects.remove(o, do_unlink=True)
            bpy.data.meshes.remove(data)
        _link(bpy.data.objects.new("Hull", mesh))
    for o in _mesh_objs():
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(1.0), verts=bm.verts[:], edges=bm.edges[:],
                                   delimit={"UV", "MATERIAL"})
        bm.to_mesh(o.data)
        bm.free()
        o.data.materials.clear()
        o.data.materials.append(_material())
        o.data.shade_flat()
        for m in [m for m in o.modifiers if m.type == "TRIANGULATE"]:
            o.modifiers.remove(m)
        tri = o.modifiers.new("Triangulate", "TRIANGULATE")
        tri.min_vertices = 4
    if budget is None:
        budget = core.tri_budget(asset_id)  # tools/art/asset_budgets.json (ART-05)
    meshes = _mesh_objs()
    hp = {o.name: tuple(o.matrix_world.translation) for o in coll.objects if o.type == "EMPTY"}
    fmax = None
    fnd = coll.objects.get("Foundation")
    if fnd is not None:
        fmax = -min(v.co.z for v in fnd.data.vertices) + 1e-6
    mats = sorted({s.material.name for o in meshes for s in o.material_slots if s.material})
    report = core.run_checks(asset_id, _ctx["cls"], _tri_data(meshes), hp, mats,
                             [o.name for o in coll.objects], budget, PALETTE, fmax)
    report["hardpoints"] = sorted(hp)
    report["objects"] = sorted(o.name for o in coll.objects)
    return report


# ---------------------------------------------------------------- export
_EXPORT = {
    "export_format": "GLB", "use_selection": True, "export_apply": True, "export_yup": True,
    "export_normals": True, "export_texcoords": True, "export_tangents": False, "export_materials": "EXPORT",
    "export_image_format": "NONE", "export_cameras": False, "export_lights": False, "export_animations": False,
    "export_skins": False, "export_morph": False, "export_extras": True,
    "export_draco_mesh_compression_enable": False,
}


def export_options() -> list:
    """The installed glTF exporter's property names (07 s4.6: print this in a recipe's first call)."""
    return sorted(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())


def export_glb(asset_id: str, out_dir: str) -> str:
    """Export collection PW_<id> under one identity root node named PascalCase(id) to <out_dir>/<id>.glb."""
    if asset_id != _ctx["id"]:
        raise ValueError(f"export_glb('{asset_id}') but the open asset is '{_ctx['id']}'")
    have = set(export_options())
    missing = sorted(k for k in _EXPORT if k not in have)
    if missing:
        raise RuntimeError(f"glTF exporter lacks options {missing}; update pw._EXPORT (07 s4.6)")
    coll = _coll()
    root_name = core.pascal(asset_id)
    root = coll.objects.get(root_name)
    if root is None:
        root = _link(bpy.data.objects.new(root_name, None))
        root.empty_display_size = 0.5
        for o in coll.objects:
            if o is not root and o.parent is None:
                o.parent = root
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, f"{asset_id}.glb")
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in coll.objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(filepath=path, **_EXPORT)
    return path
