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
		_flags[c] |= OCCUPIED


func release(cells: PackedInt32Array) -> void:
	for c: int in cells:
		_flags[c] &= ~OCCUPIED


## Marks `cell` as a resource node; `cold_trap` = an Ice node an Ice Extractor may be built on (ADR-05).
func mark_node(cell: int, cold_trap: bool) -> void:
	_flags[cell] |= NODE | (COLD_TRAP if cold_trap else 0)


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
