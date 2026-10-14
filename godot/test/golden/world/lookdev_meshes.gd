class_name LookdevMeshes
extends RefCounted
## ART-01 look-dev helpers (test only, not shipped): 12 primitive stand-in sample meshes sized from 07 s1.2,
## flat-shaded and painted by face with palette-atlas swatch centres (07 s4.3 UV method), plus single-swatch
## plates and the site frame on the sphere. The Blender sample meshes arrive with the ART-04 helper library.

## Atlas cell indices (palette.json order; cell = row-major index of the 16 x 14 swatch grid).
const HULL_300: int = 2
const HULL_400: int = 3
const HULL_600: int = 5
const HULL_700: int = 6
const GLASS_EMIT: int = 10
const ENGINE_EMIT: int = 11
const TEAM_PAINT_MID: int = 19
const TEAM_GLOW: int = 21
const MARE_MID: int = 24

const NAMES: PackedStringArray = ["dart", "lancer", "bomber", "scout", "hauler", "harvester", "siege_crawler",
	"pylon", "autocannon", "shield", "solar", "core"]


static func swatch_uv(cell: int) -> Vector2:
	return Vector2((float(cell % 16) + 0.5) / 16.0, (float(cell >> 4) + 0.5) / 16.0)


## Site frame on the datum sphere at `dir`: local X = east, Y = up, Z = -north (meshes are authored Y-up).
static func site(dir: Vector3, lift: float) -> Transform3D:
	var f: Basis = Sphere.tangent_frame(dir)
	var b: Basis = Basis(f.x, f.z, -f.y)
	return Transform3D(b, dir.normalized() * (Sphere.PLANET_RADIUS + lift))


static func primitive(i: int) -> PrimitiveMesh:
	match i:
		0:
			var p: PrismMesh = PrismMesh.new()
			p.size = Vector3(9.0, 3.0, 12.0)
			return p
		1:
			var b: BoxMesh = BoxMesh.new()
			b.size = Vector3(12.0, 4.0, 16.0)
			return b
		2:
			var s: SphereMesh = SphereMesh.new()
			s.radius = 12.0
			s.height = 6.0
			s.radial_segments = 10
			s.rings = 4
			return s
		3:
			var c: CylinderMesh = CylinderMesh.new()
			c.top_radius = 0.2
			c.bottom_radius = 1.1
			c.height = 8.0
			c.radial_segments = 6
			c.rings = 1
			return c
		4:
			var b: BoxMesh = BoxMesh.new()
			b.size = Vector3(14.0, 7.0, 20.0)
			return b
		5:
			var b: BoxMesh = BoxMesh.new()
			b.size = Vector3(6.0, 4.0, 9.0)
			return b
		6:
			var p: PrismMesh = PrismMesh.new()
			p.size = Vector3(8.0, 6.0, 14.0)
			p.left_to_right = 0.0
			return p
		7:
			var c: CylinderMesh = CylinderMesh.new()
			c.top_radius = 1.2
			c.bottom_radius = 2.0
			c.height = 30.0
			c.radial_segments = 6
			c.rings = 2
			return c
		8:
			var s: SphereMesh = SphereMesh.new()
			s.radius = 6.5
			s.height = 6.5
			s.is_hemisphere = true
			s.radial_segments = 12
			s.rings = 4
			return s
		9:
			var t: TorusMesh = TorusMesh.new()
			t.inner_radius = 7.0
			t.outer_radius = 10.0
			t.rings = 16
			t.ring_segments = 6
			return t
		10:
			var b: BoxMesh = BoxMesh.new()
			b.size = Vector3(20.0, 3.0, 20.0)
			return b
		_:
			var c: CylinderMesh = CylinderMesh.new()
			c.top_radius = 12.0
			c.bottom_radius = 22.0
			c.height = 30.0
			c.radial_segments = 8
			c.rings = 1
			return c


## Non-indexed, flat-shaded copy of a primitive with one swatch per face: top faces team paint, bottom
## faces hull_700, the upper band of side faces team glow, rear faces engine accent (`engine`), the rest `body`.
static func painted(src: PrimitiveMesh, body: int, engine: bool = false) -> ArrayMesh:
	var arr: Array = src.get_mesh_arrays()
	var pv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var pn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var aabb: AABB = src.get_aabb()
	var band: float = aabb.position.y + aabb.size.y * 0.8
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	for t: int in idx.size() / 3:
		var ia: int = idx[t * 3]
		var ib: int = idx[t * 3 + 1]
		var ic: int = idx[t * 3 + 2]
		var a: Vector3 = pv[ia]
		var b: Vector3 = pv[ib]
		var c: Vector3 = pv[ic]
		var n: Vector3 = (b - a).cross(c - a)
		if n.length_squared() < 1e-12:
			continue
		n = n.normalized()
		if n.dot(pn[ia] + pn[ib] + pn[ic]) < 0.0:
			n = -n
		var cell: int = _cell_for(n, (a.y + b.y + c.y) / 3.0, band, body, engine)
		var uv: Vector2 = swatch_uv(cell)
		for v: Vector3 in [a, b, c]:
			verts.append(v)
			normals.append(n)
			uvs.append(uv)
	return _mesh(verts, normals, uvs)


static func _cell_for(n: Vector3, cy: float, band: float, body: int, engine: bool) -> int:
	if n.y > 0.6:
		return TEAM_PAINT_MID
	if n.y < -0.6:
		return HULL_700
	if engine and n.z > 0.8:
		return ENGINE_EMIT
	if cy > band:
		return TEAM_GLOW
	return body


## Square plate in the XZ plane facing +Y, one swatch.
static func plate(size: float, cell: int) -> ArrayMesh:
	var h: float = size * 0.5
	var p: PackedVector3Array = [Vector3(-h, 0, -h), Vector3(h, 0, -h), Vector3(h, 0, h), Vector3(-h, 0, -h), Vector3(h, 0, h), Vector3(-h, 0, h)]
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	for i: int in 6:
		normals.append(Vector3.UP)
		uvs.append(swatch_uv(cell))
	return _mesh(p, normals, uvs)


static func _mesh(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array) -> ArrayMesh:
	var out: Array = []
	var _r: int = out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_TEX_UV] = uvs
	var m: ArrayMesh = ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return m
