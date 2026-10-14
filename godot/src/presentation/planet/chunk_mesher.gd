class_name ChunkMesher extends RefCounted
## Texel-index CPU mesher, variant A (03 s7.3, R0 C1-06). Never round-trips through face_uv_to_dir ->
## height_at for vertex heights: vertex directions come from a per-depth direction table (the equal-angle
## mapping is separable, so the table stores tan() per global vertex column of each depth and a direction
## is normalize(N + tan_u S + tan_v T), bit-identical to Sphere.face_uv_to_dir), and heights are read by
## face-local texel index through Terrain.height_texel with height_at's own bilinear formula at the exact
## texel coordinate x = (n - 1) * g / segs (rational, so depth 5 on a 1024 face lands on texels and coarser
## depths read strided texels). One shared index pattern: 2,048 grid + 256 skirt triangles, clockwise front
## faces (Godot). Only the ring samples outside a cube face (normals of edge vertices) use height_at.

const GRID: int = 32
const VERTS: int = 33
const RING: int = 35
const GRID_VERTS: int = VERTS * VERTS                 ## 1,089
const SKIRT_VERTS: int = 4 * VERTS                     ## 132
const VERTEX_COUNT: int = GRID_VERTS + SKIRT_VERTS     ## 1,221
const INDEX_COUNT: int = GRID * GRID * 6 + 4 * GRID * 6   ## 6,912
const SKIRT_FACTOR: float = 2.5                        ## skirt = 2.5 * max height error of the depth (03 s7.3)
const MAX_SLOPE_TAN: float = 1.0                       ## 45 degree bound on the bilinear slope
const _QUARTER_PI: float = PI / 4.0                    ## same constant expression as Sphere's mapping
const ARRAY_FLAGS: int = Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT

var terrain: Terrain
var max_depth: int = 6
var indices: PackedInt32Array = PackedInt32Array()     ## shared by every chunk
var last_heights: PackedFloat64Array = PackedFloat64Array()   ## 33 x 33 vertex heights of the last build
var last_h_min: float = 0.0
var last_h_max: float = 0.0
var _tan: PackedFloat64Array = PackedFloat64Array()    ## per depth: g = -1 .. segs + 1 at _tan_off[depth] + g + 1
var _tan_off: PackedInt32Array = PackedInt32Array()
var _n: int = 0
var _relief_scale: float = (Sphere.RELIEF_MAX - Sphere.RELIEF_MIN) / float(Terrain.U16_MAX)
# scratch, reused by every build (no per-build allocation of the big arrays)
var _ring_h: PackedFloat64Array = PackedFloat64Array()
var _ring_d: PackedVector3Array = PackedVector3Array()
var _ring_p: PackedVector3Array = PackedVector3Array()
var _ax_t: PackedInt32Array = PackedInt32Array()      ## per ring column/row: texel index, -1 = outside face
var _ax_f: PackedFloat64Array = PackedFloat64Array()  ## fraction within the texel
var _ax_k: PackedInt32Array = PackedInt32Array()      ## index into the compacted texel list
var _cols: PackedInt32Array = PackedInt32Array()
var _rows: PackedInt32Array = PackedInt32Array()
var _win: PackedInt32Array = PackedInt32Array()


func _init(p_terrain: Terrain, p_max_depth: int) -> void:
	terrain = p_terrain
	max_depth = p_max_depth
	_n = terrain.face_resolution
	_build_tan_table()
	_build_indices()
	var _r: int = _ring_h.resize(RING * RING)
	_r = _ring_d.resize(RING * RING)
	_r = _ring_p.resize(RING * RING)
	_r = _ax_t.resize(2 * RING)
	_r = _ax_f.resize(2 * RING)
	_r = _ax_k.resize(2 * RING)
	_r = last_heights.resize(GRID_VERTS)


static func segments(depth: int) -> int:
	return GRID << depth


## Skirt depth of a chunk at `depth`: 2.5 * 0.5 * vertex spacing * tan(45 deg) (03 s7.3): 6 m at depth 6.
static func skirt_depth(depth: int) -> float:
	var spacing: float = Sphere.PLANET_RADIUS * PI * 0.5 / float(segments(depth))
	return SKIRT_FACTOR * 0.5 * spacing * MAX_SLOPE_TAN


## Unit direction of global vertex (gx, gy) at `depth` on `face`, from the direction table.
func vertex_dir(face: int, depth: int, gx: int, gy: int) -> Vector3:
	var o: int = _tan_off[depth] + 1
	var fr: Basis = Sphere.face_frame(face)
	return (fr.z + fr.x * _tan[o + gx] + fr.y * _tan[o + gy]).normalized()


## Height of global vertex (gx, gy), 0 <= g <= segs, by texel index (the reference single-sample path).
func vertex_height(face: int, depth: int, gx: int, gy: int) -> float:
	if _n == 0:
		return 0.0
	var segs: int = segments(depth)
	var x0: int = texel_index(gx, depth)
	var y0: int = texel_index(gy, depth)
	var fx: float = texel_frac(gx, segs, depth)
	var fy: float = texel_frac(gy, segs, depth)
	var h0: float = lerpf(float(terrain.height_texel(face, x0, y0)), float(terrain.height_texel(face, x0 + 1, y0)), fx)
	var h1: float = lerpf(float(terrain.height_texel(face, x0, y0 + 1)), float(terrain.height_texel(face, x0 + 1, y0 + 1)), fx)
	return Sphere.RELIEF_MIN + lerpf(h0, h1, fy) * _relief_scale


## Texel index of global vertex coordinate g (0 <= g <= segs): floor((n - 1) * g / segs), clamped so that
## index + 1 <= n - 1 exactly as height_at clamps.
func texel_index(g: int, depth: int) -> int:
	return mini(((_n - 1) * g) >> (5 + depth), _n - 2)


## Fraction within the texel: ((n - 1) * g mod segs) / segs, or 1.0 on the clamped last texel.
func texel_frac(g: int, segs: int, depth: int) -> float:
	var num: int = (_n - 1) * g
	if (num >> (5 + depth)) >= _n - 1:
		return 1.0
	return float(num & (segs - 1)) / float(segs)


## Surface arrays of `node` (Mesh.ARRAY_MAX entries; flags ARRAY_FLAGS). Also fills last_heights and the
## node-independent last_h_min / last_h_max over the 33 x 33 grid.
func build_arrays(node: ChunkNode) -> Array:
	_sample_ring(node)
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var custom: PackedByteArray = PackedByteArray()
	var _r: int = verts.resize(VERTEX_COUNT)
	_r = normals.resize(VERTEX_COUNT)
	_r = uvs.resize(VERTEX_COUNT)
	_r = custom.resize(VERTEX_COUNT * 4)
	_fill_grid(node, verts, normals, uvs, custom)
	_fill_skirts(node, verts, normals, uvs, custom)
	var arrays: Array = []
	_r = arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_CUSTOM0] = custom
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


## Rebuilds `mesh` for `node` (clear + add surface: the robust 4.7 path, 03 s7.3) and tightens the node's
## bounding sphere to the built heights.
func build_into(node: ChunkNode, mesh: ArrayMesh, material: Material) -> void:
	var arrays: Array = build_arrays(node)
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, ARRAY_FLAGS)
	mesh.surface_set_material(0, material)
	node.set_height_range(last_h_min, last_h_max)


# region sampling
func _sample_ring(node: ChunkNode) -> void:
	var segs: int = segments(node.depth)
	_prepare_axis(node.gx(0) - 1, segs, node.depth, 0)
	_prepare_axis(node.gy(0) - 1, segs, node.depth, RING)
	_read_window(node.face)
	var fr: Basis = Sphere.face_frame(node.face)
	var o: int = _tan_off[node.depth] + 1
	var x0: int = node.gx(0) - 1
	var y0: int = node.gy(0) - 1
	var nc: int = _cols.size()
	for r: int in RING:
		var tan_v: float = _tan[o + y0 + r]
		var ty: int = _ax_t[RING + r]
		var fy: float = _ax_f[RING + r]
		var q: int = _ax_k[RING + r] * nc
		for c: int in RING:
			var i: int = r * RING + c
			var d: Vector3 = (fr.z + fr.x * _tan[o + x0 + c] + fr.y * tan_v).normalized()
			_ring_d[i] = d
			var h: float = 0.0
			if ty >= 0 and _ax_t[c] >= 0:
				var k: int = q + _ax_k[c]
				var fx: float = _ax_f[c]
				var h0: float = lerpf(float(_win[k]), float(_win[k + 1]), fx)
				var h1: float = lerpf(float(_win[k + nc]), float(_win[k + nc + 1]), fx)
				h = Sphere.RELIEF_MIN + lerpf(h0, h1, fy) * _relief_scale
			elif _n > 0:
				h = terrain.height_at(d)
			_ring_h[i] = h
			_ring_p[i] = d * (Sphere.PLANET_RADIUS + h)


## Texel index/fraction for RING consecutive global coordinates starting at g0, and the compacted list of
## distinct texel indices (each sample needs t and t + 1) into _cols (off 0) or _rows (off RING).
func _prepare_axis(g0: int, segs: int, depth: int, off: int) -> void:
	var list: PackedInt32Array = PackedInt32Array()
	for k: int in RING:
		var g: int = g0 + k
		if _n == 0 or g < 0 or g > segs:
			_ax_t[off + k] = -1
			continue
		var t: int = texel_index(g, depth)
		_ax_t[off + k] = t
		_ax_f[off + k] = texel_frac(g, segs, depth)
		if list.is_empty() or list[list.size() - 1] < t:
			var _a: bool = list.push_back(t)
		if list[list.size() - 1] == t:
			var _b: bool = list.push_back(t + 1)
		_ax_k[off + k] = list.size() - 2
	if off == 0:
		_cols = list
	else:
		_rows = list


func _read_window(face: int) -> void:
	var nc: int = _cols.size()
	var _r: int = _win.resize(nc * _rows.size())
	for q: int in _rows.size():
		var y: int = _rows[q]
		for k: int in nc:
			_win[q * nc + k] = terrain.height_texel(face, _cols[k], y)
# endregion


# region vertices
func _fill_grid(node: ChunkNode, verts: PackedVector3Array, normals: PackedVector3Array,
		uvs: PackedVector2Array, custom: PackedByteArray) -> void:
	var inv_segs: float = 1.0 / float(segments(node.depth))
	var inv_range: float = 1.0 / (Sphere.RELIEF_MAX - Sphere.RELIEF_MIN)
	last_h_min = INF
	last_h_max = -INF
	for b: int in VERTS:
		for a: int in VERTS:
			var i: int = (b + 1) * RING + a + 1
			var vi: int = b * VERTS + a
			var h: float = _ring_h[i]
			last_heights[vi] = h
			last_h_min = minf(last_h_min, h)
			last_h_max = maxf(last_h_max, h)
			var d: Vector3 = _ring_d[i]
			var nrm: Vector3 = (_ring_p[i + 1] - _ring_p[i - 1]).cross(_ring_p[i + RING] - _ring_p[i - RING]).normalized()
			verts[vi] = _ring_p[i]
			normals[vi] = nrm
			uvs[vi] = Vector2(float(node.gx(a)) * inv_segs, float(node.gy(b)) * inv_segs)
			custom[vi * 4] = clampi(int((h - Sphere.RELIEF_MIN) * inv_range * 255.0 + 0.5), 0, 255)
			custom[vi * 4 + 1] = clampi(int(acos(clampf(nrm.dot(d), -1.0, 1.0)) / (PI * 0.5) * 255.0 + 0.5), 0, 255)
			custom[vi * 4 + 2] = 0
			custom[vi * 4 + 3] = 0


## 4 x 33 skirt vertices: edge vertices pushed inward along -dir by skirt_depth (03 s7.3); normal and uv
## copy the edge vertex, custom.a = 255 marks the skirt for the shader.
func _fill_skirts(node: ChunkNode, verts: PackedVector3Array, normals: PackedVector3Array,
		uvs: PackedVector2Array, custom: PackedByteArray) -> void:
	var drop: float = skirt_depth(node.depth)
	for e: int in 4:
		for k: int in VERTS:
			var src: int = edge_vertex(e, k)
			var si: int = GRID_VERTS + e * VERTS + k
			var gi: int = (MathX.floori_div(src, VERTS) + 1) * RING + (src % VERTS) + 1
			verts[si] = _ring_d[gi] * (Sphere.PLANET_RADIUS + _ring_h[gi] - drop)
			normals[si] = normals[src]
			uvs[si] = uvs[src]
			custom[si * 4] = custom[src * 4]
			custom[si * 4 + 1] = custom[src * 4 + 1]
			custom[si * 4 + 2] = custom[src * 4 + 2]
			custom[si * 4 + 3] = 255


## Grid vertex index of the k-th vertex along edge e (Sphere.DIR_*: 0 u=0, 1 u=1, 2 v=0, 3 v=1).
static func edge_vertex(e: int, k: int) -> int:
	if e == Sphere.DIR_NEG_U:
		return k * VERTS
	if e == Sphere.DIR_POS_U:
		return k * VERTS + GRID
	if e == Sphere.DIR_NEG_V:
		return k
	return GRID * VERTS + k
# endregion


# region tables
func _build_tan_table() -> void:
	_tan.clear()
	_tan_off.clear()
	for depth: int in max_depth + 1:
		var segs: int = segments(depth)
		var _a: bool = _tan_off.push_back(_tan.size())
		for g: int in range(-1, segs + 2):
			var u: float = float(g) / float(segs)
			var _b: bool = _tan.push_back(tan((u + u - 1.0) * _QUARTER_PI))


## Shared index pattern. Winding is chosen on a planar model (a -> +x, b -> +y, up +z, skirts at z = -1) so
## that every triangle is clockwise seen from outside: grid normals up, skirt normals out of the chunk.
func _build_indices() -> void:
	indices.clear()
	for b: int in GRID:
		for a: int in GRID:
			var v00: int = b * VERTS + a
			_add_tri(v00, v00 + VERTS + 1, v00 + 1, Vector3(0, 0, 1))
			_add_tri(v00, v00 + VERTS, v00 + VERTS + 1, Vector3(0, 0, 1))
	var outward: PackedVector3Array = [Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 1, 0)]
	for e: int in 4:
		for k: int in GRID:
			var t0: int = edge_vertex(e, k)
			var t1: int = edge_vertex(e, k + 1)
			var s0: int = GRID_VERTS + e * VERTS + k
			_add_tri(t0, t1, s0 + 1, outward[e])
			_add_tri(t0, s0 + 1, s0, outward[e])


func _add_tri(i0: int, i1: int, i2: int, outward: Vector3) -> void:
	var p0: Vector3 = _planar(i0)
	var n: Vector3 = (_planar(i1) - p0).cross(_planar(i2) - p0)
	var _a: bool = indices.push_back(i0)
	if n.dot(outward) > 0.0:   # counter-clockwise from outside: swap to clockwise
		_a = indices.push_back(i2)
		_a = indices.push_back(i1)
	else:
		_a = indices.push_back(i1)
		_a = indices.push_back(i2)


static func _planar(i: int) -> Vector3:
	if i < GRID_VERTS:
		return Vector3(float(i % VERTS), float(MathX.floori_div(i, VERTS)), 0.0)
	var s: int = i - GRID_VERTS
	var p: Vector3 = _planar(edge_vertex(MathX.floori_div(s, VERTS), s % VERTS))
	return Vector3(p.x, p.y, -1.0)
# endregion
