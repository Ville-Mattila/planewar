class_name SensorCover extends RefCounted
## One observer's own sensors of one refresh, bucketed per interest cell (AI-22). `covers(q)` is the 03 s3.7 pair rule
## (`sensor_radius` with an unoccluded segment over the datum, or within `deck_reveal_radius`) against those sensors:
## a ghost whose last position is covered and that the team does not see is gone; an `own`-vision observer (Easy,
## 05 s7.8) keeps only contacts its own slot's sensors cover. Base def radii (a doctrine's sensor modifier and the A-76
## "under construction does not sense" rule are not applied: the result is only ever ANDed with `visible_to` or used
## to forget). Preallocated; `add` / `build` / `covers` allocate nothing once grown.

var n: int = 0                                         ## sensors added since `clear`
var pos: PackedVector3Array = PackedVector3Array()    ## [i]
var r2: PackedFloat32Array = PackedFloat32Array()     ## [i] sensor radius squared
var reveal2: PackedFloat32Array = PackedFloat32Array() ## [i] deck-reveal radius squared
var mine: PackedByteArray = PackedByteArray()         ## [i] 1 = owned by the observer's slot
var cell: PackedInt32Array = PackedInt32Array()       ## [i]
var stats_pair_tests: int = 0                         ## pair tests run by `covers` (work counter)

var _tables: ThreatParams = null
var _cstart: PackedInt32Array = PackedInt32Array()    ## [cell] first index into _order
var _ccount: PackedInt32Array = PackedInt32Array()    ## [cell] sensors in the cell
var _order: PackedInt32Array = PackedInt32Array()     ## sensor indices sorted by cell
var _cells: PackedInt32Array = PackedInt32Array()     ## cells with sensors (first _ncells valid)
var _ncells: int = 0
var _max_m: float = 0.0


func _init(t: ThreatParams) -> void:
	_tables = t
	var e: int = _cstart.resize(ThreatParams.CELLS) | _ccount.resize(ThreatParams.CELLS) | _cells.resize(ThreatParams.CELLS)
	assert(e == OK)
	_ccount.fill(0)


func clear() -> void:
	for k: int in _ncells:
		_ccount[_cells[k]] = 0
	_ncells = 0
	n = 0
	_max_m = 0.0


## One sensor at `p` (interest cell `c`) of radius `sensor_m` / `reveal_m`; `own_slot` marks the observer's own units.
func add(p: Vector3, c: int, sensor_m: float, reveal_m: float, own_slot: bool) -> void:
	if n >= pos.size():
		var g: int = maxi(64, n * 2)
		var e: int = pos.resize(g) | r2.resize(g) | reveal2.resize(g) | mine.resize(g) | cell.resize(g) | _order.resize(g)
		assert(e == OK)
	pos[n] = p
	r2[n] = sensor_m * sensor_m
	reveal2[n] = reveal_m * reveal_m
	mine[n] = 1 if own_slot else 0
	cell[n] = c
	_max_m = maxf(_max_m, maxf(sensor_m, reveal_m))
	n += 1


## Counting sort of the added sensors by cell (call once after the last `add`).
func build() -> void:
	for i: int in n:
		var c: int = cell[i]
		if _ccount[c] == 0:
			_cells[_ncells] = c
			_ncells += 1
		_ccount[c] += 1
	var run: int = 0
	for k: int in _ncells:
		var c: int = _cells[k]
		_cstart[c] = run
		run += _ccount[c]
		_ccount[c] = 0
	for i: int in n:
		var c: int = cell[i]
		_order[_cstart[c] + _ccount[c]] = i
		_ccount[c] += 1


## Whether a sensor (of the observer's slot only, with `own_only`) sees point `q` in interest cell `qc`.
func covers(q: Vector3, qc: int, own_only: bool) -> bool:
	var t: ThreatParams = _tables
	for k: int in range(t.near_start[qc], t.near_start[qc + 1]):
		if t.near_gap[k] > _max_m:
			return false
		var h: int = t.near_cell[k]
		var cnt: int = _ccount[h]
		if cnt == 0:
			continue
		var s0: int = _cstart[h]
		for j: int in cnt:
			var i: int = _order[s0 + j]
			if own_only and mine[i] == 0:
				continue
			stats_pair_tests += 1
			var d2: float = q.distance_squared_to(pos[i])
			if d2 <= reveal2[i] or (d2 <= r2[i] and not Sphere.is_occluded_by_datum(pos[i], q)):
				return true
	return false
