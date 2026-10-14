class_name PlaceholderMeshes
extends RefCounted
## Primitive stand-ins per class until ART-04/05 deliver the GLBs (07 s4): unit-radius flat-shaded meshes,
## scaled per entity by its sim radius. UV points at the `team_paint_hi` swatch of the palette atlas (cell 18 of
## 16 x 16, tools/blender/palette.json) so `unit_lit` paints them in the team colour. The same meshes serve as
## the `_Far` meshes (<= 48 triangles, ART-A1). Nose points to -Z. All static, built once.

const TEAM_PAINT_CELL: int = 18
const ATLAS_COLS: int = 16
const HEX_SIDES: int = 6
const FAR_TRI_BUDGET: int = 48
const QUAD_HALF: float = 0.5

static var _cache: Dictionary = {}   ## kind (DefRanges.K_*) -> ArrayMesh
static var _quad: QuadMesh = null
static var _cross: ArrayMesh = null


## Placeholder mesh of a view class kind (DefRanges.K_SHIP / K_GROUND / K_STRUCTURE).
static func mesh_for(kind: int) -> ArrayMesh:
	if _cache.has(kind):
		return _cache[kind]
	var m: ArrayMesh = _build(_ship_tris() if kind == DefRanges.K_SHIP else (_box_tris() if kind == DefRanges.K_GROUND else _tower_tris()))
	_cache[kind] = m
	return m


static func triangle_count(kind: int) -> int:
	var verts: PackedVector3Array = mesh_for(kind).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	return floori(float(verts.size()) / 3.0)


## Unit quad billboard for icons (shader billboards it).
static func icon_quad() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
	return _quad


## Two crossed unit quads in the XY and ZY planes, length along Z: tracers, trail segments (visible from any side).
static func crossed_quads() -> ArrayMesh:
	if _cross == null:
		var h: float = QUAD_HALF
		var v: PackedVector3Array = PackedVector3Array([
			Vector3(-h, 0, -h), Vector3(h, 0, -h), Vector3(h, 0, h), Vector3(-h, 0, -h), Vector3(h, 0, h), Vector3(-h, 0, h),
			Vector3(0, -h, -h), Vector3(0, h, -h), Vector3(0, h, h), Vector3(0, -h, -h), Vector3(0, h, h), Vector3(0, -h, h)])
		_cross = _build(v)
	return _cross


## Flat unit quad in the XZ plane (decals lie on the ground, normal +Y).
static func flat_quad() -> ArrayMesh:
	var h: float = QUAD_HALF
	return _build(PackedVector3Array([Vector3(-h, 0, -h), Vector3(-h, 0, h), Vector3(h, 0, h), Vector3(-h, 0, -h), Vector3(h, 0, h), Vector3(h, 0, -h)]))


static func _build(tris: PackedVector3Array) -> ArrayMesh:
	var n: int = tris.size()
	var normals: PackedVector3Array = PackedVector3Array()
	var _r1: int = normals.resize(n)
	var uvs: PackedVector2Array = PackedVector2Array()
	var _r2: int = uvs.resize(n)
	var uv: Vector2 = Vector2((float(TEAM_PAINT_CELL % ATLAS_COLS) + QUAD_HALF) / float(ATLAS_COLS), (float(floori(float(TEAM_PAINT_CELL) / float(ATLAS_COLS))) + QUAD_HALF) / float(ATLAS_COLS))
	for t: int in floori(float(n) / 3.0):
		var nrm: Vector3 = (tris[t * 3 + 1] - tris[t * 3]).cross(tris[t * 3 + 2] - tris[t * 3]).normalized()
		for k: int in 3:
			normals[t * 3 + k] = nrm
			uvs[t * 3 + k] = uv
	var arrays: Array = []
	var _r3: int = arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = tris
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Swept dart: nose, two wing tips, a dorsal and a ventral tail point (8 triangles, outward winding).
static func _ship_tris() -> PackedVector3Array:
	var nose: Vector3 = Vector3(0, 0, -1.6)
	var wl: Vector3 = Vector3(-1.0, 0, 0.8)
	var wr: Vector3 = Vector3(1.0, 0, 0.8)
	var top: Vector3 = Vector3(0, 0.4, 0.5)
	var bot: Vector3 = Vector3(0, -0.2, 0.5)
	var tail: Vector3 = Vector3(0, 0, 0.9)
	return PackedVector3Array([
		nose, wl, top, nose, top, wr, nose, bot, wl, nose, wr, bot,
		tail, top, wl, tail, wr, top, tail, wl, bot, tail, bot, wr])


## Low box for ground units (12 triangles).
static func _box_tris() -> PackedVector3Array:
	return _box(Vector3(0.7, 0.35, 1.0), Vector3(0, 0.35, 0))


## Hexagonal tower with a flat cap for structures (24 triangles).
static func _tower_tris() -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	for i: int in HEX_SIDES:
		var a0: float = TAU * float(i) / float(HEX_SIDES)
		var a1: float = TAU * float(i + 1) / float(HEX_SIDES)
		var b0: Vector3 = Vector3(cos(a0), 0.0, sin(a0))
		var b1: Vector3 = Vector3(cos(a1), 0.0, sin(a1))
		var t0: Vector3 = Vector3(b0.x * 0.7, 1.4, b0.z * 0.7)
		var t1: Vector3 = Vector3(b1.x * 0.7, 1.4, b1.z * 0.7)
		out.append_array(PackedVector3Array([b0, t0, t1, b0, t1, b1, Vector3(0, 1.4, 0), t1, t0]))
	return out


static func _box(half: Vector3, centre: Vector3) -> PackedVector3Array:
	var c: Array[Vector3] = []
	for i: int in 8:
		c.append(centre + Vector3(half.x * (1.0 if (i & 1) != 0 else -1.0), half.y * (1.0 if (i & 2) != 0 else -1.0), half.z * (1.0 if (i & 4) != 0 else -1.0)))
	var quads: Array = [[0, 4, 6, 2], [1, 3, 7, 5], [0, 1, 5, 4], [2, 6, 7, 3], [0, 2, 3, 1], [4, 5, 7, 6]]
	var out: PackedVector3Array = PackedVector3Array()
	for q: Array in quads:
		out.append_array(PackedVector3Array([c[q[0]], c[q[1]], c[q[2]], c[q[0]], c[q[2]], c[q[3]]]))
	return out
