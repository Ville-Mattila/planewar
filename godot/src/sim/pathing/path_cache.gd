class_name PathCache extends RefCounted
## Route cache of 03 s3.2 / R0 C1-05: key (start cluster, goal cell, mask), ENTRIES slots with LRU replacement, cell
## lists of at most STRIDE cells in one flat pool (no packed array inside a container). An entry is valid while the
## version sum of the faces its path crosses is unchanged (PathGrid.face_version only grows). The key index is a
## Dictionary[int, int] used for lookups only (never iterated), so no result depends on its order.

const ENTRIES: int = 512                   ## 03 s3.2 path_cache row
const STRIDE: int = 128                    ## longest cached route in cells (longer routes are not cached)

var cells: PackedInt32Array = PackedInt32Array()   ## ENTRIES * STRIDE
var length: PackedInt32Array = PackedInt32Array()
var start_cell: PackedInt32Array = PackedInt32Array()
var faces: PackedInt32Array = PackedInt32Array()
var vsum: PackedInt32Array = PackedInt32Array()
var _key: PackedInt64Array = PackedInt64Array()
var _used: PackedInt64Array = PackedInt64Array()
var _clock: int = 0
var _index: Dictionary[int, int] = {}


func _init() -> void:
	var _r: int = cells.resize(ENTRIES * STRIDE)
	_r = length.resize(ENTRIES)
	_r = start_cell.resize(ENTRIES)
	_r = faces.resize(ENTRIES)
	_r = vsum.resize(ENTRIES)
	_r = _key.resize(ENTRIES)
	_key.fill(-1)
	_r = _used.resize(ENTRIES)


static func key_of(start: int, goal: int, mask: int) -> int:
	return goal | (PathGrid.cluster_of(start) << 20) | ((mask & 0xFFFF) << 32)


## Entry index for `key` when present and still valid for `grid`, else -1 (a stale entry is dropped).
func lookup(key: int, grid: PathGrid) -> int:
	var e: int = _index.get(key, -1)
	if e < 0:
		return -1
	if grid.version_sum(faces[e]) != vsum[e]:
		var _x: bool = _index.erase(key)
		_key[e] = -1
		length[e] = 0
		return -1
	_clock += 1
	_used[e] = _clock
	return e


## Stores src[off .. off + n) under `key` (replacing the LRU entry); false when n > STRIDE.
func insert(key: int, src: PackedInt32Array, off: int, n: int, grid: PathGrid) -> bool:
	if n > STRIDE or n <= 0:
		return false
	var e: int = _index.get(key, -1)
	if e < 0:
		e = 0
		for k: int in ENTRIES:
			if _used[k] < _used[e]:
				e = k
		if _key[e] >= 0:
			var _x: bool = _index.erase(_key[e])
	var fb: int = 0
	var base: int = e * STRIDE
	for k: int in n:
		var c: int = src[off + k]
		cells[base + k] = c
		fb |= 1 << (c >> (PathGrid.SHIFT + PathGrid.SHIFT))
	_key[e] = key
	_index[key] = e
	length[e] = n
	start_cell[e] = src[off]
	faces[e] = fb
	vsum[e] = grid.version_sum(fb)
	_clock += 1
	_used[e] = _clock
	return true


## Cells from[..] of entry `e` as a copy (one native slice; callers copy into their own pools).
func segment(e: int, from: int) -> PackedInt32Array:
	return cells.slice(e * STRIDE + from, e * STRIDE + length[e])


## Index within entry `e` of the first cell outside the cluster of its start cell (length - 1 if none).
func exit_index(e: int) -> int:
	var base: int = e * STRIDE
	var c0: int = PathGrid.cluster_of(cells[base])
	for k: int in length[e]:
		if PathGrid.cluster_of(cells[base + k]) != c0:
			return k
	return length[e] - 1


func size() -> int:
	return _index.size()


## Drops every entry (map change).
func clear() -> void:
	_index.clear()
	_key.fill(-1)
	length.fill(0)
	_used.fill(0)
	_clock = 0
