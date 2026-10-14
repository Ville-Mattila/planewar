class_name PathGrid extends RefCounted
## The 6 x 256^2 path grid of ADR-05 / 03 s3.6: per-cell weights (baked `face<f>.path.u8`, 1..254 cost, 0 and 255
## impassable), the per-cell maximum slope (lazy, from `Terrain.slope_deg_at` over the covered texels), per-face
## change counters, cell centre directions and the non-allocating 8-neighbour enumeration with the cube-edge table
## of `Sphere.neighbour_cell` (7 neighbours at the 24 cube-corner cells). Lane-internal to `Pathing`.

const N: int = Sphere.GRID_PATH
const SHIFT: int = 8                       ## log2(N); _init asserts 1 << SHIFT == N
const LOW: int = N - 1                     ## bit mask of i and j
const FACES: int = 6
const CELLS: int = FACES * N * N
const W_BLOCKED: int = 255                 ## baker value for impassable (03 s8.2 step 7)
const W_ZERO: int = 0                      ## 03 s3.2 table value for impassable; both block
const SLOPE_UNKNOWN: int = 255             ## slope_q sentinel: not yet sampled
const SLOPE_NO_LIMIT: int = 254            ## limit_q of mask 0: only weights block
const _SLOPE_Q_PER_DEG: int = 2            ## slope_q steps per degree (Terrain.SLOPE_STEP_DEG = 0.5)

var weights: PackedByteArray = PackedByteArray()      ## CELLS bytes, cell id = (face * N + j) * N + i
var slope_q: PackedByteArray = PackedByteArray()      ## CELLS bytes, max slope in 0.5 degree steps or SLOPE_UNKNOWN
var face_version: PackedInt32Array = PackedInt32Array()   ## bumped by every set_weight on that face (C1-05)
var nb: PackedInt32Array = PackedInt32Array()         ## neighbours() output: 0 -u, 1 +u, 2 -v, 3 +v, 4..7 diagonals or -1
var terrain: Terrain = null
var arc_u: PackedFloat32Array = PackedFloat32Array()  ## metres (i, j) -> (i+1, j), any face; (i, j) -> (i, j+1) at i * N + j
var arc_d: PackedFloat32Array = PackedFloat32Array()  ## metres (i, j) -> (i+1, j+1); anti-diagonals by the i mirror
var _tan: PackedFloat64Array = PackedFloat64Array()
var _fn: PackedVector3Array = PackedVector3Array()
var _fs: PackedVector3Array = PackedVector3Array()
var _ft: PackedVector3Array = PackedVector3Array()


func _init() -> void:
	assert((1 << SHIFT) == N, "PathGrid: GRID_PATH must be 2^SHIFT")
	var _r: int = weights.resize(CELLS)
	weights.fill(1)
	_r = slope_q.resize(CELLS)
	slope_q.fill(SLOPE_UNKNOWN)
	_r = face_version.resize(FACES)
	_r = nb.resize(8)
	_r = _tan.resize(N)
	for i: int in N:
		_tan[i] = tan((float(i + i + 1) / float(N) - 1.0) * PI * 0.5 * 0.5)
	for f: int in FACES:
		var b: Basis = Sphere.face_frame(f)
		var _a: bool = _fs.push_back(b.x)
		_a = _ft.push_back(b.y)
		_a = _fn.push_back(b.z)
	_build_arcs()


# In-face step lengths are the same on every face (one mapping): arc_u by row, arc_d by 2 x 2 block.
func _build_arcs() -> void:
	var _r: int = arc_u.resize(N * N)
	_r = arc_d.resize(N * N)
	for j: int in N:
		for i: int in LOW:
			var a: Vector3 = center_dir(j * N + i)
			arc_u[j * N + i] = Sphere.PLANET_RADIUS * a.angle_to(center_dir(j * N + i + 1))
			if j < LOW:
				arc_d[j * N + i] = Sphere.PLANET_RADIUS * a.angle_to(center_dir((j + 1) * N + i + 1))


## Installs CELLS weight bytes (the six `path.u8` faces concatenated); false and unchanged on a size mismatch.
func set_weights(bytes: PackedByteArray) -> bool:
	if bytes.size() != CELLS:
		return false
	weights = bytes.duplicate()
	slope_q.fill(SLOPE_UNKNOWN)
	return true


## Slope source; drops every memoised slope.
func set_terrain(t: Terrain) -> void:
	terrain = t
	slope_q.fill(SLOPE_UNKNOWN)


func version_of(face: int) -> int:
	return face_version[face]


## Unit centre direction of `cell` (equal-angle; equals Sphere.cell_center_dir(cell, N) to float rounding).
func center_dir(cell: int) -> Vector3:
	var f: int = cell >> (SHIFT + SHIFT)
	return (_fn[f] + _fs[f] * _tan[cell & LOW] + _ft[f] * _tan[(cell >> SHIFT) & LOW]).normalized()


## Cell of the direction of `p` (any non-zero vector).
static func cell_of(p: Vector3) -> int:
	return Sphere.cell_of(p, N)


## Coarse cluster (16 x 16 cells, Sphere grid n = N >> 4) containing `cell`.
static func cluster_of(cell: int) -> int:
	var f: int = cell >> (SHIFT + SHIFT)
	return (((f << 4) + ((cell >> (SHIFT + 4)) & 15)) << 4) + ((cell & LOW) >> 4)


## True when `cell` can be entered under slope limit `limit_q` (0.5 degree steps; SLOPE_NO_LIMIT = weights only).
func passable(cell: int, limit_q: int) -> bool:
	var w: int = weights[cell]
	if w == W_BLOCKED or w == W_ZERO:
		return false
	if limit_q >= SLOPE_NO_LIMIT:
		return true
	var s: int = slope_q[cell]
	if s == SLOPE_UNKNOWN:
		s = sample_slope(cell)
	return s <= limit_q


## Fills `nb` with the 8 neighbours of `cell` (-1 for the missing diagonal at a cube corner), same set and
## construction as Sphere.neighbours8 but without allocating. Interior cells take the integer fast path.
func neighbours(cell: int) -> void:
	var i: int = cell & LOW
	var j: int = (cell >> SHIFT) & LOW
	if i > 0 and i < LOW and j > 0 and j < LOW:
		nb[0] = cell - 1
		nb[1] = cell + 1
		nb[2] = cell - N
		nb[3] = cell + N
		nb[4] = cell - N - 1
		nb[5] = cell - N + 1
		nb[6] = cell + N - 1
		nb[7] = cell + N + 1
		return
	for d: int in 4:
		nb[d] = Sphere.neighbour_cell(cell, N, d)
	for k: int in 4:
		var du: int = k & 1
		var dv: int = Sphere.DIR_NEG_V + (k >> 1)
		var i_in: bool = i > 0 if du == Sphere.DIR_NEG_U else i < LOW
		var j_in: bool = j > 0 if dv == Sphere.DIR_NEG_V else j < LOW
		if i_in:
			nb[4 + k] = Sphere.neighbour_cell(nb[du], N, dv)
		elif j_in:
			nb[4 + k] = Sphere.neighbour_cell(nb[dv], N, du)
		else:
			nb[4 + k] = -1


## Maximum baked slope (0.5 degree steps) over the terrain texels covering `cell`; memoised in slope_q. Flat stub
## or no terrain: 0. Texel x of a face of n texels sits at u = x / (n - 1) (Terrain), cell i spans [i, i+1] / N.
func sample_slope(cell: int) -> int:
	var q: int = 0
	if terrain != null and terrain.is_loaded():
		var n: int = terrain.face_resolution
		var f: int = cell >> (SHIFT + SHIFT)
		var x0: int = (cell & LOW) * (n - 1) >> SHIFT
		var y0: int = ((cell >> SHIFT) & LOW) * (n - 1) >> SHIFT
		var x1: int = mini(n - 1, (((cell & LOW) + 1) * (n - 1) + LOW) >> SHIFT)
		var y1: int = mini(n - 1, ((((cell >> SHIFT) & LOW) + 1) * (n - 1) + LOW) >> SHIFT)
		for y: int in range(y0, y1 + 1):
			var row: int = (f * n + y) * n
			for x: int in range(x0, x1 + 1):
				q = maxi(q, int(terrain.slope_deg_at(row + x) * float(_SLOPE_Q_PER_DEG)))
	q = mini(q, SLOPE_NO_LIMIT - 1)
	slope_q[cell] = q
	return q


## Fixes the memoised slope of `cell` (test fixtures; Build flattening once TA-19 needs it). Pathing.override_slope
## also drops the region graphs and the cache.
func override_slope(cell: int, slope_deg: int) -> void:
	slope_q[cell] = mini(slope_deg * _SLOPE_Q_PER_DEG, SLOPE_NO_LIMIT - 1)


## Slope limit in slope_q units for a request mask (bits 0-7 = max slope in whole degrees; 0 = no limit).
static func limit_q_of(mask: int) -> int:
	var deg: int = mask & 0xFF
	return SLOPE_NO_LIMIT if deg == 0 else deg * _SLOPE_Q_PER_DEG


## Sets one weight and bumps the face counter. Returns true when passability (ignoring slope) flipped.
func set_weight(cell: int, w: int) -> bool:
	var old: int = weights[cell]
	var nw: int = clampi(w, W_ZERO, W_BLOCKED)
	weights[cell] = nw
	var f: int = cell >> (SHIFT + SHIFT)
	face_version[f] += 1
	return blocks(old) != blocks(nw)


static func blocks(w: int) -> bool:
	return w == W_BLOCKED or w == W_ZERO


## Sum of face_version over the faces in `face_bits` (bit f = face f). Counters only grow, so equal sums for the
## same face set mean no face in the set changed.
func version_sum(face_bits: int) -> int:
	var s: int = 0
	for f: int in FACES:
		if ((face_bits >> f) & 1) != 0:
			s += face_version[f]
	return s
