class_name SfMeshes
## Procedural low-poly meshes for the spike (no art pipeline yet, 07 beyond the Dart is gated on TA-30).
## Godot convention for ship meshes: nose along -Z, body up +Y, right +X.

const _ICO_T: float = 1.618033988749895


## Flat-shaded icosphere of `radius` subdivided 2^level times per edge; per-face vertex colour from a low
## frequency noise (maria) plus per-face jitter so speed and height read on a flat stub.
static func icosphere(level: int, radius: float, rng: Rng) -> ArrayMesh:
	var v: PackedVector3Array = _ico_vertices()
	var f: PackedInt32Array = _ico_faces()
	var n: int = 1 << level
	var pos: PackedVector3Array = PackedVector3Array()
	var nor: PackedVector3Array = PackedVector3Array()
	var col: PackedColorArray = PackedColorArray()
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 3.0 / radius
	var base: Color = Color(0.55, 0.54, 0.52)
	var mare: Color = Color(0.30, 0.30, 0.32)
	for k: int in 20:
		var a: Vector3 = v[f[k * 3]]
		var b: Vector3 = v[f[k * 3 + 1]]
		var c: Vector3 = v[f[k * 3 + 2]]
		for j: int in n:
			for i: int in n - j:
				_tri(_grid(a, b, c, i, j, n), _grid(a, b, c, i + 1, j, n), _grid(a, b, c, i, j + 1, n),
					radius, noise, base, mare, rng, pos, nor, col)
				if i + j < n - 1:
					_tri(_grid(a, b, c, i + 1, j, n), _grid(a, b, c, i + 1, j + 1, n), _grid(a, b, c, i, j + 1, n),
						radius, noise, base, mare, rng, pos, nor, col)
	var arrays: Array = []
	var _r: bool = arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nor
	arrays[Mesh.ARRAY_COLOR] = col
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, vertex_material())
	return mesh


static func vertex_material() -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.metallic_specular = 0.1
	return m


static func flat(c: Color, emission: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emission
	return m


static func unlit(c: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## The Dart (12 m, nose -Z): diamond fuselage, delta wings, fin, three tail struts (tail-down gear, O-2).
static func dart(body: Color, wing: Color) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nose: Vector3 = Vector3(0, 0, -6)
	var tail: Vector3 = Vector3(0, 0, 5)
	var ring: PackedVector3Array = [Vector3(1.2, 0, 0), Vector3(0, 1.0, 0.5), Vector3(-1.2, 0, 0), Vector3(0, -0.8, 0.5)]
	for i: int in 4:
		var r0: Vector3 = ring[i] + Vector3(0, 0, -0.5)
		var r1: Vector3 = ring[(i + 1) % 4] + Vector3(0, 0, -0.5)
		_face(st, body, nose, r1, r0, (r0 + r1) * 0.5 + Vector3(0, 0, -1))
		_face(st, body, tail, r0, r1, (r0 + r1) * 0.5 + Vector3(0, 0, 1))
	for sx: float in [1.0, -1.0]:
		var w0: Vector3 = Vector3(0.8 * sx, -0.1, -1.5)
		var w1: Vector3 = Vector3(5.0 * sx, -0.2, 3.5)
		var w2: Vector3 = Vector3(0.8 * sx, -0.1, 3.8)
		_face(st, wing, w0, w1, w2, Vector3.UP)
		_face(st, wing, w0, w2, w1, Vector3.DOWN)
	_face(st, wing, Vector3(0, 0.8, 2.0), Vector3(0, 2.8, 5.0), Vector3(0, 0.8, 4.8), Vector3.RIGHT)
	_face(st, wing, Vector3(0, 0.8, 2.0), Vector3(0, 0.8, 4.8), Vector3(0, 2.8, 5.0), Vector3.LEFT)
	var strut: Color = Color(0.25, 0.25, 0.28)
	for k: int in 3:
		var ang: float = TAU * float(k) / 3.0
		var o: Vector3 = Vector3(cos(ang) * 1.6, sin(ang) * 1.6, 5.0)
		_box(st, strut, o + Vector3(0, 0, 0.5), Vector3(0.25, 0.25, 1.0))
	return st.commit()


static func octahedron(r: float, c: Color) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var p: PackedVector3Array = [Vector3(r, 0, 0), Vector3(0, r, 0), Vector3(-r, 0, 0), Vector3(0, -r, 0),
		Vector3(0, 0, r), Vector3(0, 0, -r)]
	var idx: PackedInt32Array = [0, 1, 4, 1, 2, 4, 2, 3, 4, 3, 0, 4, 1, 0, 5, 2, 1, 5, 3, 2, 5, 0, 3, 5]
	for i: int in 8:
		var a: Vector3 = p[idx[i * 3]]
		var b: Vector3 = p[idx[i * 3 + 1]]
		var e: Vector3 = p[idx[i * 3 + 2]]
		_face(st, c, a, b, e, a + b + e)
	return st.commit()


## Boulder: a squashed icosahedron (decor only).
static func boulder() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var v: PackedVector3Array = _ico_vertices()
	var f: PackedInt32Array = _ico_faces()
	var c: Color = Color(0.42, 0.41, 0.40)
	for k: int in 20:
		var a: Vector3 = v[f[k * 3]] * Vector3(1, 0.6, 1)
		var b: Vector3 = v[f[k * 3 + 1]] * Vector3(1, 0.6, 1)
		var e: Vector3 = v[f[k * 3 + 2]] * Vector3(1, 0.6, 1)
		_face(st, c, a, b, e, a + b + e)
	return st.commit()


## Emit one triangle facing `out_dir` (Godot front faces are clockwise), with its flat normal.
static func _face(st: SurfaceTool, c: Color, a: Vector3, b: Vector3, d: Vector3, out_dir: Vector3) -> void:
	var n: Vector3 = (b - a).cross(d - a)
	var p1: Vector3 = b
	var p2: Vector3 = d
	if n.dot(out_dir) < 0.0:
		p1 = d
		p2 = b
		n = -n
	n = n.normalized()
	for p: Vector3 in [a, p2, p1]:
		st.set_color(c)
		st.set_normal(n)
		st.add_vertex(p)


static func _box(st: SurfaceTool, c: Color, centre: Vector3, size: Vector3) -> void:
	var h: Vector3 = size * 0.5
	var p: PackedVector3Array = PackedVector3Array()
	for i: int in 8:
		var _a: bool = p.push_back(centre + Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
	var q: PackedInt32Array = [0, 2, 3, 1, 4, 5, 7, 6, 0, 1, 5, 4, 2, 6, 7, 3, 0, 4, 6, 2, 1, 3, 7, 5]
	for k: int in 6:
		var out: Vector3 = (p[q[k * 4]] + p[q[k * 4 + 2]]) * 0.5 - centre
		_face(st, c, p[q[k * 4]], p[q[k * 4 + 1]], p[q[k * 4 + 2]], out)
		_face(st, c, p[q[k * 4]], p[q[k * 4 + 2]], p[q[k * 4 + 3]], out)


static func _grid(a: Vector3, b: Vector3, c: Vector3, i: int, j: int, n: int) -> Vector3:
	var fn: float = float(n)
	return (a + (b - a) * (float(i) / fn) + (c - a) * (float(j) / fn)).normalized()


static func _tri(a: Vector3, b: Vector3, c: Vector3, radius: float, noise: FastNoiseLite, base: Color,
		mare: Color, rng: Rng, pos: PackedVector3Array, nor: PackedVector3Array, col: PackedColorArray) -> void:
	var pa: Vector3 = a * radius
	var pb: Vector3 = b * radius
	var pc: Vector3 = c * radius
	var nn: Vector3 = (pb - pa).cross(pc - pa).normalized()
	if nn.dot(a) < 0.0:
		var t: Vector3 = pb
		pb = pc
		pc = t
		nn = -nn
	var cen: Vector3 = (pa + pb + pc) / 3.0
	var m: float = clampf(noise.get_noise_3dv(cen) * 2.0 + 0.5, 0.0, 1.0)
	var j: float = (rng.next_float() - 0.5) * 0.12
	var cl: Color = mare.lerp(base, m)
	cl = Color(cl.r + j, cl.g + j, cl.b + j)
	for p: Vector3 in [pa, pc, pb]:
		var _x: bool = pos.push_back(p)
		var _y: bool = nor.push_back(nn)
		var _z: bool = col.push_back(cl)


static func _ico_vertices() -> PackedVector3Array:
	var t: float = _ICO_T
	var out: PackedVector3Array = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for i: int in out.size():
		out[i] = out[i].normalized()
	return out


static func _ico_faces() -> PackedInt32Array:
	return PackedInt32Array([0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2,
		10, 7, 6, 7, 1, 8, 3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7,
		9, 8, 1])
