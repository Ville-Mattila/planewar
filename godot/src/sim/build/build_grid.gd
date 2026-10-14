class_name BuildGrid extends RefCounted
## The build grid of 03 s3.6: per build cell (6 x n x n, n = GRID_BUILD) one flag byte (occupied, resource node,
## cold-trap node) and a lazily filled slope byte (0.5 degree steps; 255 = not yet read from Terrain). Plain packed
## arrays, no per-call allocation; identical inputs give identical bytes (S9).

const OCCUPIED: int = 1
const NODE: int = 2
const COLD_TRAP: int = 4
const SLOPE_UNKNOWN: int = 255

var n: int = Sphere.GRID_BUILD
var _flags: PackedByteArray = PackedByteArray()
var _slope: PackedByteArray = PackedByteArray()
var _terrain: Terrain = null
var _used: PackedInt32Array = PackedInt32Array()   ## cells whose flag byte is non-zero (unsorted); the save is sparse


func _init(terrain: Terrain, grid_n: int = Sphere.GRID_BUILD) -> void:
	n = grid_n
	_terrain = terrain
	var size: int = 6 * n * n
	var e: int = _flags.resize(size) | _slope.resize(size)
	assert(e == OK)
	_flags.fill(0)
	_slope.fill(SLOPE_UNKNOWN)


func cell_count() -> int:
	return _flags.size()


func flags_of(cell: int) -> int:
	return _flags[cell]


func occupy(cells: PackedInt32Array) -> void:
	for c: int in cells:
		_put(c, _flags[c] | OCCUPIED)


func release(cells: PackedInt32Array) -> void:
	for c: int in cells:
		_put(c, _flags[c] & ~OCCUPIED)


## Marks `cell` as a resource node; `cold_trap` = an Ice node an Ice Extractor may be built on (ADR-05).
func mark_node(cell: int, cold_trap: bool) -> void:
	_put(cell, _flags[cell] | NODE | (COLD_TRAP if cold_trap else 0))


func slope_deg(cell: int) -> float:
	var b: int = _slope[cell]
	if b == SLOPE_UNKNOWN:
		var d: float = 0.0
		if _terrain != null:
			if _terrain.face_resolution == n:
				d = _terrain.slope_deg_at(cell)
			else:
				d = _terrain.slope_deg_at_dir(Sphere.cell_center_dir(cell, n))
		b = clampi(roundi(d / Terrain.SLOPE_STEP_DEG), 0, SLOPE_UNKNOWN - 1)
		_slope[cell] = b
	return float(b) * Terrain.SLOPE_STEP_DEG


## Test and bake seam: pins the cached slope of `cell`.
func set_slope_deg(cell: int, deg: float) -> void:
	_slope[cell] = clampi(roundi(deg / Terrain.SLOPE_STEP_DEG), 0, SLOPE_UNKNOWN - 1)


## S4: the non-zero flag bytes as (sorted cell list, flag bytes): a 1,024 grid is 6.3 MB of mostly zeros, the save is
## O(occupied cells). The slope cache is derived from Terrain and refills lazily, so it is not saved.
func write_state(buf: StreamPeerBuffer) -> void:
	var cells: PackedInt32Array = _used.duplicate()
	cells.sort()
	var f: PackedByteArray = PackedByteArray()
	var _r: int = f.resize(cells.size())
	for k: int in cells.size():
		f[k] = _flags[cells[k]]
	buf.put_var(cells)
	buf.put_var(f)


func read_state(buf: StreamPeerBuffer) -> bool:
	var cv: Variant = buf.get_var()
	var fv: Variant = buf.get_var()
	if typeof(cv) != TYPE_PACKED_INT32_ARRAY or typeof(fv) != TYPE_PACKED_BYTE_ARRAY:
		return false
	var cells: PackedInt32Array = cv
	var f: PackedByteArray = fv
	if cells.size() != f.size():
		return false
	for k: int in cells.size():
		if cells[k] < 0 or cells[k] >= _flags.size() or f[k] == 0 or (k > 0 and cells[k] <= cells[k - 1]):
			return false
	_flags.fill(0)
	var _r: int = _used.resize(0)
	for k: int in cells.size():
		_put(cells[k], f[k])
	return true


# Writes a flag byte and keeps `_used` equal to the set of non-zero cells.
func _put(c: int, v: int) -> void:
	var old: int = _flags[c]
	_flags[c] = v
	if old == 0 and v != 0:
		var _a: bool = _used.push_back(c)
	elif old != 0 and v == 0:
		_used.remove_at(_used.find(c))
