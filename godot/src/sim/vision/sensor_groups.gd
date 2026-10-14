class_name SensorGroups extends RefCounted
## One team's sensors for one Vision pass (TA-37), grouped per interest cell, and the candidate scan.
## `gather`: every live non-wreck entity of team t with sensor or reveal radius > 0 (reach = the larger), grouped by
## its interest cell; per group a centroid c, an extent and, per sensor k, the outer reach reach_k + |p_k - c|; the
## sensors of a group are sorted by outer reach, descending. `cover`: per interest cell h, the groups that can reach a
## point of h (near-cell gap <= the group's reach, then |c| sin(angle to h's cone) <= its max outer reach). `scan`:
## each entity of another team group in a covered cell is visited once and tested against its cell's groups: skipped
## when |p - c| exceeds the group's max outer reach, and inside a group the sensors stop at the first whose outer
## reach is below |p - c|. Every bound is a triangle inequality, so the result equals testing every sensor; the pair
## test is `Vision.sees` with Sphere.is_occluded_by_datum's exact operations, inlined.

const _R2: float = Sphere.PLANET_RADIUS * Sphere.PLANET_RADIUS
const _SLOT_BITS: int = 11                 ## slot < 2048 (EntityStore.SLOT_COUNT)
const _REACH_BITS: int = 28                ## whole metres
const _GROUP_SHIFT: int = _SLOT_BITS + _REACH_BITS
const _REACH_CAP: int = (1 << _REACH_BITS) - 1

var _n: int = 0                                        ## groups this pass
var _g_cell: PackedInt32Array = PackedInt32Array()
var _g_start: PackedInt32Array = PackedInt32Array()
var _g_n: PackedInt32Array = PackedInt32Array()
var _g_c: PackedVector3Array = PackedVector3Array()
var _g_ext: PackedFloat64Array = PackedFloat64Array()
var _g_reach: PackedFloat64Array = PackedFloat64Array()
var _g_lim2: PackedFloat64Array = PackedFloat64Array()  ## (max outer reach)^2 from the centroid
var _sp: PackedVector3Array = PackedVector3Array()      ## sensors, group-major, reach descending
var _ss2: PackedFloat64Array = PackedFloat64Array()     ## sensor radius^2
var _sr2: PackedFloat64Array = PackedFloat64Array()     ## reveal radius^2
var _souter: PackedFloat64Array = PackedFloat64Array()  ## outer reach bound from the centroid (see _fill_sorted)
var _cov_cells: PackedInt32Array = PackedInt32Array()   ## covered cells this pass, first _cov_cells_n valid
var _cov_cells_n: int = 0
var _cov_start: PackedInt32Array = PackedInt32Array()   ## per cell into _cov_g
var _cov_n: PackedInt32Array = PackedInt32Array()       ## per cell; 0 = not covered
var _cov_g: PackedInt32Array = PackedInt32Array()      ## group per cover entry; _cov_c / _cov_lim2 copy its sphere
var _cov_c: PackedVector3Array = PackedVector3Array()
var _cov_lim2: PackedFloat64Array = PackedFloat64Array()

var _keys: PackedInt64Array = PackedInt64Array()
var _tp: PackedVector3Array = PackedVector3Array()
var _ts: PackedFloat64Array = PackedFloat64Array()
var _tr: PackedFloat64Array = PackedFloat64Array()
var _treach: PackedFloat64Array = PackedFloat64Array()
var _pair_h: PackedInt32Array = PackedInt32Array()
var _pair_g: PackedInt32Array = PackedInt32Array()
var _fill: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	var cells: int = InterestGrid.CELLS
	var s: int = EntityStore.SLOT_COUNT
	var e: int = _g_cell.resize(cells) | _g_start.resize(cells) | _g_n.resize(cells) | _g_c.resize(cells)
	e |= _g_ext.resize(cells) | _g_reach.resize(cells) | _g_lim2.resize(cells) | _sp.resize(s) | _ss2.resize(s)
	e |= _sr2.resize(s) | _souter.resize(s) | _treach.resize(s) | _tp.resize(s) | _ts.resize(s) | _tr.resize(s) | _cov_cells.resize(cells)
	e |= _cov_start.resize(cells) | _cov_n.resize(cells) | _fill.resize(cells) | _keys.resize(s)
	assert(e == OK)
	_cov_n.fill(0)


## Groups team `t`'s sensors of the current index; returns the group count.
func gather(t: int, grid: InterestGrid, store: EntityStore, sensor_r: PackedFloat32Array, reveal_r: PackedFloat32Array) -> int:
	var keys: PackedInt64Array = _keys
	_keys = PackedInt64Array()                 # sole owner while writing
	var m: int = 0
	_n = 0
	for k: int in grid.touched_n:
		var b: int = grid.touched[k] * InterestGrid.GROUPS + t
		var s0: int = grid.bucket_start[b]
		var before: int = m
		for q: int in grid.bucket_count[b]:
			var s: int = grid.items[s0 + q]
			var d: int = store.def_id[s]
			if store.kind[s] == EntityStore.K_WRECK or d < 0 or d >= Vision.DEF_N:
				continue
			var row: int = mini(store.owner[s], Vision.OWNERS - 1) * Vision.DEF_N + d
			var r: float = maxf(sensor_r[row], reveal_r[row])
			if r <= 0.0:
				continue
			_tp[m] = store.pos[s]
			_ts[m] = sensor_r[row] * sensor_r[row]
			_tr[m] = reveal_r[row] * reveal_r[row]
			_treach[m] = r
			m += 1
		if m > before:
			_g_cell[_n] = grid.touched[k]
			_g_start[_n] = before
			_g_n[_n] = m - before
			_n += 1
	_spheres(keys)
	_keys = keys
	_fill_sorted(keys.slice(0, m))             # one allocation per pass, then a native sort
	return _n


## Per covered cell, the groups that can reach it (needs `gather` and the grid's near table).
func cover(grid: InterestGrid) -> void:
	var pairs: int = 0
	_cov_cells_n = 0
	for g: int in _n:
		var c: int = _g_cell[g]
		var reach: float = _g_reach[g]
		var outer: float = _souter[_g_start[g]]
		for q: int in range(grid.near_start[c], grid.near_start[c + 1]):
			if grid.near_gap[q] > reach:
				break
			var h: int = grid.near_cell[q]
			if grid.cell_n[h] == 0 or _gap(grid, g, h) > outer:
				continue
			if pairs >= _pair_h.size():
				var _r: int = _pair_h.resize(pairs * 2 + InterestGrid.CELLS) | _pair_g.resize(pairs * 2 + InterestGrid.CELLS)
			_pair_h[pairs] = h
			_pair_g[pairs] = g
			pairs += 1
			if _cov_n[h] == 0:
				_cov_cells[_cov_cells_n] = h
				_cov_cells_n += 1
			_cov_n[h] += 1
	var run: int = 0
	for i: int in _cov_cells_n:
		var h: int = _cov_cells[i]
		_cov_start[h] = run
		_fill[h] = run
		run += _cov_n[h]
	if _cov_g.size() < run:
		var _r: int = _cov_g.resize(run) | _cov_c.resize(run) | _cov_lim2.resize(run)
	for p: int in pairs:
		var h: int = _pair_h[p]
		var g: int = _pair_g[p]
		var j: int = _fill[h]
		_cov_g[j] = g
		_cov_c[j] = _g_c[g]
		_cov_lim2[j] = _g_lim2[g]
		_fill[h] = j + 1


## Resets the cover counts (after the pass's list is built).
func clear_cover() -> void:
	for i: int in _cov_cells_n:
		_cov_n[_cov_cells[i]] = 0
	_cov_cells_n = 0


## Visits every entity of a team group other than `t` in the covered cells once; writes the slots the groups see
## to `out` (pre-sized to EntityStore.SLOT_COUNT) and returns their count.
func scan(t: int, grid: InterestGrid, pos: PackedVector3Array, out: PackedInt32Array) -> int:
	var found: int = 0
	for i: int in _cov_cells_n:
		var h: int = _cov_cells[i]
		var lo: int = _cov_start[h]
		var hi: int = lo + _cov_n[h]
		for u: int in InterestGrid.GROUPS:
			var b: int = h * InterestGrid.GROUPS + u
			if u == t or grid.bucket_count[b] == 0:
				continue
			var s0: int = grid.bucket_start[b]
			for q: int in grid.bucket_count[b]:
				var x: int = grid.items[s0 + q]
				var px: Vector3 = pos[x]
				for j: int in range(lo, hi):
					var d2: float = _cov_c[j].distance_squared_to(px)
					if d2 <= _cov_lim2[j] and _group_sees(_cov_g[j], px, sqrt(d2)):
						out[found] = x
						found += 1
						break
	return found


# Sensors of group g in outer-reach order until one sees px or the rest cannot reach it (dc = |px - centroid|;
# sensor k at r_k from the centroid is >= dc - r_k from px, so _souter[k] < dc rules out k and every later one).
# The pair test is Vision.sees with Sphere.is_occluded_by_datum's exact operations (a = sensor, b = target;
# distance_squared_to is (b - a).length_squared(), its len2).
func _group_sees(g: int, px: Vector3, dc: float) -> bool:
	for k: int in range(_g_start[g], _g_start[g] + _g_n[g]):
		if _souter[k] < dc:
			return false
		var a: Vector3 = _sp[k]
		var d2: float = a.distance_squared_to(px)
		if d2 <= _sr2[k]:
			return true
		if d2 <= _ss2[k]:
			if d2 <= 0.0:
				return true
			var ab: Vector3 = px - a
			var tt: float = -a.dot(ab) / d2
			if tt <= 0.0 or tt >= 1.0 or (a + ab * tt).length_squared() >= _R2:
				return true
	return false


# Per group: centroid, extent, max reach; per sensor the key (group, outer reach floor(reach + |p - c|) descending,
# index) into `keys`.
func _spheres(keys: PackedInt64Array) -> void:
	for g: int in _n:
		var lo: int = _g_start[g]
		var hi: int = lo + _g_n[g]
		var sum: Vector3 = Vector3.ZERO
		for i: int in range(lo, hi):
			sum += _tp[i]
		var c: Vector3 = sum / float(_g_n[g])
		var ext: float = 0.0
		var reach: float = 0.0
		for i: int in range(lo, hi):
			var r_i: float = c.distance_to(_tp[i])
			ext = maxf(ext, r_i)
			reach = maxf(reach, _treach[i])
			var outer: int = mini(floori(_treach[i] + r_i), _REACH_CAP)
			keys[i] = (g << _GROUP_SHIFT) | ((_REACH_CAP - outer) << _SLOT_BITS) | i
		_g_c[g] = c
		_g_ext[g] = ext
		_g_reach[g] = reach


# Sorted keys -> group-major sensor arrays, outer reach descending; _souter = floor(outer) + 1, an upper bound that
# never increases along a group, so `_group_sees` may stop at the first _souter below the centroid distance.
func _fill_sorted(sorted: PackedInt64Array) -> void:
	sorted.sort()
	for k: int in sorted.size():
		var key: int = sorted[k]
		var i: int = key & ((1 << _SLOT_BITS) - 1)
		_sp[k] = _tp[i]
		_ss2[k] = _ts[i]
		_sr2[k] = _tr[i]
		_souter[k] = float(_REACH_CAP - ((key >> _SLOT_BITS) & _REACH_CAP)) + 1.0
	for g: int in _n:
		_g_lim2[g] = _souter[_g_start[g]] * _souter[_g_start[g]]


# Lower bound (m) from group g's centroid c to any point of interest cell h's column (every radius): a point at
# angle phi off the axis to centre(h) beyond cone(h) is |c| sin(phi) from that cone (|c| when phi >= pi / 2).
func _gap(grid: InterestGrid, g: int, h: int) -> float:
	var c: Vector3 = _g_c[g]
	var phi: float = c.angle_to(grid.centre[h]) - grid.cone[h]
	if phi <= 0.0:
		return 0.0
	return c.length() * sin(minf(phi, PI * 0.5))
