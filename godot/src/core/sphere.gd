class_name Sphere
## Core sphere math (03 s2): constants, tangent frames, great circles, parallel transport, the
## equal-angle cube-sphere mapping, cells at the four ADR-05 resolutions and the edge-neighbour table.
## All static, no state, no Nodes. PLANET_RADIUS lives here and only here (D6).
## Precondition everywhere: direction and position arguments are non-zero vectors.

# region constants (03 s2.1)
const PLANET_RADIUS: float = 6000.0        # the only literal; everything else derives from it
const RELIEF_MIN: float = -500.0           # baked height range, ADR-04
const RELIEF_MAX: float = 700.0
const CEILING_SOFT: float = 1500.0         # altitude above datum, 01 s3.1.5
const CEILING_HARD: float = 2000.0
const MAX_SIM_MAGNITUDE: float = PLANET_RADIUS + CEILING_HARD   # must stay < 8192.0 (ADR-03, C8)
const POLE_AXIS: Vector3 = Vector3(0, 0, 1)   # Noon Pole; terminator = equator
const PRIME_AXIS: Vector3 = Vector3(1, 0, 0)  # longitude 0 = centre of face 0
const SLOT_LON0_DEG: float = 22.5          # start slot k at 22.5 + 45 k degrees (R0 B.6, C1-09)
const SLOT_SPACING_DEG: float = 45.0
const GRID_BUILD: int = 1024
const GRID_PATH: int = 256
const GRID_HASH: int = 64
const GRID_INTEREST: int = 8

## Direction codes for neighbour_cell; also the edge index of a face (u=0, u=1, v=0, v=1).
const DIR_NEG_U: int = 0
const DIR_POS_U: int = 1
const DIR_NEG_V: int = 2
const DIR_POS_V: int = 3

## Edge-neighbour table (03 s2.6), flat with stride 3: row r = face * 4 + edge holds
## [nbr_face, nbr_edge, along_is_u] at EDGE_NEIGHBOUR[3 r .. 3 r + 2]. (A const Array[PackedInt32Array]
## is not a constant expression in GDScript, hence the flat packed form.) The along-edge coordinate
## keeps its value across every edge (never reversed); test_sphere.gd C5 regenerates this table from the
## face frames below and asserts equality.
const EDGE_NEIGHBOUR_STRIDE: int = 3
const EDGE_NEIGHBOUR: PackedInt32Array = [
	3, 1, 0,  2, 3, 1,  5, 3, 1,  4, 1, 0,
	5, 2, 1,  4, 0, 0,  3, 0, 0,  2, 2, 1,
	5, 1, 0,  4, 3, 1,  1, 3, 1,  0, 1, 0,
	1, 2, 1,  0, 0, 0,  5, 0, 0,  4, 2, 1,
	1, 1, 0,  0, 3, 1,  3, 3, 1,  2, 1, 0,
	3, 2, 1,  2, 0, 0,  1, 0, 0,  0, 2, 1,
]

# Face frames (03 s2.5): N_f normal, S_f the u axis, T_f the v axis, S_f x T_f = N_f on every face.
const _FACE_N: PackedVector3Array = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0),
	Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
const _FACE_S: PackedVector3Array = [Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(0, 0, 1),
	Vector3(1, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)]
const _FACE_T: PackedVector3Array = [Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(1, 0, 0),
	Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(1, 0, 0)]
const _QUARTER_PI: float = PI / 4.0
const _FOUR_OVER_PI: float = 4.0 / PI
const _POLE_EPS2: float = 1e-8             # |north|^2 below this: within ~0.6 m of a pole
const _ANTIPODAL_EPS: float = 1e-9
# endregion


# region altitude, tangent frame, geodetic (03 s2.2)
static func altitude(p: Vector3) -> float:
	return p.length() - PLANET_RADIUS


static func up_at(p: Vector3) -> Vector3:
	return p.normalized()


## Basis(east, north, up) as columns x, y, z. Continuous everywhere except within ~0.6 m of a pole.
static func tangent_frame(p: Vector3) -> Basis:
	var up: Vector3 = p.normalized()
	var north: Vector3 = POLE_AXIS - up * POLE_AXIS.dot(up)
	if north.length_squared() < _POLE_EPS2:
		north = PRIME_AXIS - up * PRIME_AXIS.dot(up)
	north = north.normalized()
	return Basis(north.cross(up), north, up)


## Radians: x = latitude in [-pi/2, pi/2] (toward +Z), y = longitude in (-pi, pi].
static func lat_lon(p: Vector3) -> Vector2:
	var d: Vector3 = p.normalized()
	return Vector2(asin(clampf(d.z, -1.0, 1.0)), atan2(d.y, d.x))


static func from_lat_lon(lat: float, lon: float, radius: float) -> Vector3:
	var c: float = cos(lat)
	return Vector3(c * cos(lon), c * sin(lon), sin(lat)) * radius
# endregion


# region great circle (03 s2.3)
## Datum-sphere distance in metres. Vector3.angle_to is atan2(|a x b|, a . b): stable at 0 and pi
## (unlike acos) and scale-invariant, so inputs need no normalize.
static func great_circle(a: Vector3, b: Vector3) -> float:
	return PLANET_RADIUS * a.angle_to(b)


## Radians clockwise from local north at `from`.
static func bearing(from: Vector3, to: Vector3) -> float:
	var f: Basis = tangent_frame(from)
	var d: Vector3 = to.normalized() - from.normalized()
	return atan2(d.dot(f.x), d.dot(f.y))


static func slerp_dir(a: Vector3, b: Vector3, t: float) -> Vector3:
	var an: Vector3 = a.normalized()
	return Quaternion(an, b.normalized()).slerp(Quaternion.IDENTITY, 1.0 - t) * an
# endregion


# region parallel transport (03 s2.4)
## Minimal rotation taking unit n_old to unit n_new; identity when equal. Antipodal input is a bug.
static func transport(n_old: Vector3, n_new: Vector3) -> Quaternion:
	var c: Vector3 = n_old.cross(n_new)
	var w: float = 1.0 + n_old.dot(n_new)
	if w < _ANTIPODAL_EPS:
		assert(false, "Sphere.transport: antipodal directions")
		return Quaternion.IDENTITY
	return Quaternion(c.x, c.y, c.z, w).normalized()
# endregion


# region cube mapping (03 s2.5)
## Columns S_f, T_f, N_f.
static func face_frame(face: int) -> Basis:
	return Basis(_FACE_S[face], _FACE_T[face], _FACE_N[face])


## (face, u, v) with u, v in [0, 1] -> unit direction (equal-angle).
static func face_uv_to_dir(face: int, u: float, v: float) -> Vector3:
	var x: float = tan((u + u - 1.0) * _QUARTER_PI)
	var y: float = tan((v + v - 1.0) * _QUARTER_PI)
	return (_FACE_N[face] + _FACE_S[face] * x + _FACE_T[face] * y).normalized()


## Unit or non-unit direction -> (face as float, u, v). Ties go to the lower face (x before y before z).
static func dir_to_face_uv(d: Vector3) -> Vector3:
	var face: int = _face_of(d)
	var inv: float = 1.0 / d.dot(_FACE_N[face])
	var u: float = (atan(d.dot(_FACE_S[face]) * inv) * _FOUR_OVER_PI + 1.0) * 0.5
	var v: float = (atan(d.dot(_FACE_T[face]) * inv) * _FOUR_OVER_PI + 1.0) * 0.5
	return Vector3(face, clampf(u, 0.0, 1.0), clampf(v, 0.0, 1.0))


static func _face_of(d: Vector3) -> int:
	var ax: float = absf(d.x)
	var ay: float = absf(d.y)
	var az: float = absf(d.z)
	if ax >= ay and ax >= az:
		return 0 if d.x > 0.0 else 1
	if ay >= az:
		return 2 if d.y > 0.0 else 3
	return 4 if d.z > 0.0 else 5
# endregion


# region cells (03 s2.6): cell_id = face * n * n + j * n + i, n in {1024, 256, 64, 8}
static func cell_of(d: Vector3, n: int) -> int:
	var face: int = _face_of(d)
	var inv: float = 1.0 / d.dot(_FACE_N[face])
	var fn: float = float(n)
	var i: int = clampi(floori((atan(d.dot(_FACE_S[face]) * inv) * _FOUR_OVER_PI + 1.0) * 0.5 * fn), 0, n - 1)
	var j: int = clampi(floori((atan(d.dot(_FACE_T[face]) * inv) * _FOUR_OVER_PI + 1.0) * 0.5 * fn), 0, n - 1)
	return (face * n + j) * n + i


static func cell_face(cell: int, n: int) -> int:
	return floori(float(cell) / float(n * n))


static func cell_i(cell: int, n: int) -> int:
	return cell - floori(float(cell) / float(n)) * n


static func cell_j(cell: int, n: int) -> int:
	var row: int = floori(float(cell) / float(n))
	return row - floori(float(row) / float(n)) * n


static func cell_center_dir(cell: int, n: int) -> Vector3:
	var row: int = floori(float(cell) / float(n))
	var face: int = floori(float(row) / float(n))
	var fn: float = float(n)
	return face_uv_to_dir(face, (float(cell - row * n) + 0.5) / fn, (float(row - face * n) + 0.5) / fn)


## The four corner directions, counter-clockwise in (u, v): (i, j), (i+1, j), (i+1, j+1), (i, j+1).
static func cell_bounds_dirs(cell: int, n: int) -> PackedVector3Array:
	var row: int = floori(float(cell) / float(n))
	var face: int = floori(float(row) / float(n))
	var fn: float = float(n)
	var u0: float = float(cell - row * n) / fn
	var v0: float = float(row - face * n) / fn
	var u1: float = u0 + 1.0 / fn
	var v1: float = v0 + 1.0 / fn
	return PackedVector3Array([face_uv_to_dir(face, u0, v0), face_uv_to_dir(face, u1, v0),
		face_uv_to_dir(face, u1, v1), face_uv_to_dir(face, u0, v1)])


## Coarser cell containing `cell`; n_to < n_from, both powers of two (a right shift of i and j).
static func parent_cell(cell: int, n_from: int, n_to: int) -> int:
	var shift: int = 0
	while (n_to << shift) < n_from:
		shift += 1
	var row: int = floori(float(cell) / float(n_from))
	var face: int = floori(float(row) / float(n_from))
	var i: int = (cell - row * n_from) >> shift
	var j: int = (row - face * n_from) >> shift
	return (face * n_to + j) * n_to + i


## dir: 0 -u, 1 +u, 2 -v, 3 +v. Integer step within a face; EDGE_NEIGHBOUR lookup across an edge.
static func neighbour_cell(cell: int, n: int, dir: int) -> int:
	var row: int = floori(float(cell) / float(n))
	var face: int = floori(float(row) / float(n))
	var i: int = cell - row * n
	var j: int = row - face * n
	if dir == DIR_NEG_U and i > 0:
		return cell - 1
	if dir == DIR_POS_U and i < n - 1:
		return cell + 1
	if dir == DIR_NEG_V and j > 0:
		return cell - n
	if dir == DIR_POS_V and j < n - 1:
		return cell + n
	var along: int = j if dir < DIR_NEG_V else i
	var row3: int = (face * 4 + dir) * EDGE_NEIGHBOUR_STRIDE
	var edge: int = EDGE_NEIGHBOUR[row3 + 1]
	var ni: int = along
	var nj: int = along
	if edge == DIR_NEG_U:
		ni = 0
	elif edge == DIR_POS_U:
		ni = n - 1
	elif edge == DIR_NEG_V:
		nj = 0
	else:
		nj = n - 1
	return (EDGE_NEIGHBOUR[row3] * n + nj) * n + ni


## Edge neighbours (-u, +u, -v, +v) then diagonals (-u-v, +u-v, -u+v, +u+v). The diagonal across a
## cube corner does not exist and is omitted, so the 24 cube-corner cells return 7 ids.
static func neighbours8(cell: int, n: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for dir: int in 4:
		var _a: bool = out.push_back(neighbour_cell(cell, n, dir))
	var row: int = floori(float(cell) / float(n))
	var i: int = cell - row * n
	var j: int = row - floori(float(row) / float(n)) * n
	for k: int in 4:
		var du: int = k & 1
		var dv: int = DIR_NEG_V + (k >> 1)
		var i_in: bool = i > 0 if du == DIR_NEG_U else i < n - 1
		var j_in: bool = j > 0 if dv == DIR_NEG_V else j < n - 1
		if i_in:
			var _b: bool = out.push_back(neighbour_cell(neighbour_cell(cell, n, du), n, dv))
		elif j_in:
			var _c: bool = out.push_back(neighbour_cell(neighbour_cell(cell, n, dv), n, du))
	return out


## Conservative: every cell whose bounding cone meets the great-circle disc (callers filter by
## great_circle() afterwards). Flood fill over edge neighbours from cell_of(center).
static func cells_in_radius(center: Vector3, radius_m: float, n: int) -> PackedInt32Array:
	var cdir: Vector3 = center.normalized()
	var limit: float = maxf(radius_m, 0.0) / PLANET_RADIUS
	var start: int = cell_of(cdir, n)
	var out: PackedInt32Array = PackedInt32Array([start])
	var seen: Dictionary[int, bool] = {start: true}
	var head: int = 0
	while head < out.size():
		var c: int = out[head]
		head += 1
		for dir: int in 4:
			var nb: int = neighbour_cell(c, n, dir)
			if seen.has(nb):
				continue
			seen[nb] = true
			if _cell_gap(nb, n, cdir) <= limit:
				var _a: bool = out.push_back(nb)
	return out


## Angle from unit dir `cdir` to the bounding cone of `cell` (negative inside the cone).
static func _cell_gap(cell: int, n: int, cdir: Vector3) -> float:
	var centre: Vector3 = cell_center_dir(cell, n)
	var cos_cone: float = 1.0
	for corner: Vector3 in cell_bounds_dirs(cell, n):
		cos_cone = minf(cos_cone, centre.dot(corner))
	var to_centre: float = cdir.angle_to(centre)
	return to_centre - acos(clampf(cos_cone, -1.0, 1.0)) - _ANTIPODAL_EPS
# endregion


# region horizon (03 s2.8, 01 s5.2)
static func horizon_distance(h: float) -> float:
	return sqrt(maxf(0.0, 2.0 * PLANET_RADIUS * h + h * h))


## True when the segment a-b dips below the datum sphere strictly between its endpoints.
static func is_occluded_by_datum(a: Vector3, b: Vector3) -> bool:
	var ab: Vector3 = b - a
	var len2: float = ab.length_squared()
	if len2 <= 0.0:
		return false
	var t: float = -a.dot(ab) / len2
	if t <= 0.0 or t >= 1.0:
		return false
	return (a + ab * t).length_squared() < PLANET_RADIUS * PLANET_RADIUS
# endregion
