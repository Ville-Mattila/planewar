class_name PathClusters extends PathRegions
## Region-level A* of the path hierarchy (03 s3.6): resumable (one search in flight), each pop 1 unit and each lazy
## cluster build PathRegions.BUILD_COST more, never over the budget. Pathing runs it goal -> start so a goal in a
## sealed pocket exhausts after the pocket's few regions. Edge cost = arc between region centroids * mean weights;
## h = great circle to the target cell * (1 + heuristic_pct / 100). On FOUND, mark_corridor stamps the region route
## and every region adjacent to it into PathSearch's corridor; the cell search then runs inside that corridor.

const _PCT: int = 100

var heuristic_pct: int = 0
var state: int = PathSearch.EXHAUSTED
var start: int = -1                         ## region the search starts from
var goal: int = -1                          ## region it searches for
var slot: int = 0
var _g: PackedFloat32Array = PackedFloat32Array()
var _tag: PackedInt32Array = PackedInt32Array()
var _par: PackedInt32Array = PackedInt32Array()
var _hk: PackedFloat32Array = PackedFloat32Array()
var _hv: PackedInt32Array = PackedInt32Array()
var _hn: int = 0
var _sid: int = 0
var _hw: float = 1.0
var _target_dir: Vector3 = Vector3.ZERO


func _init(g: PathLabel) -> void:
	super(g)
	var _r: int = _g.resize(REGIONS)
	_r = _tag.resize(REGIONS)
	_r = _par.resize(REGIONS)
	_r = _hk.resize(REGIONS)
	_r = _hv.resize(REGIONS)


## Starts the region search from region `from_r` toward region `to_r` (heuristic toward `to_dir`) in slot `sl`.
func begin(from_r: int, to_r: int, to_dir: Vector3, sl: int) -> void:
	_sid += 1
	start = from_r
	goal = to_r
	slot = sl
	_hw = 1.0 + float(heuristic_pct) / float(_PCT)
	_target_dir = to_dir
	_hn = 0
	state = PathSearch.RUNNING
	_g[start] = 0.0
	_par[start] = -1
	_tag[start] = _sid + _sid
	_push(0.0, start)


## Up to `budget` units; returns the units used. state becomes FOUND or EXHAUSTED when the search ends.
func run(budget: int) -> int:
	var used: int = 0
	var closed_tag: int = _sid + _sid + 1
	while used < budget and state == PathSearch.RUNNING:
		if _hn == 0:
			state = PathSearch.EXHAUSTED
			break
		var r: int = _hv[0]
		var cost: int = 1
		if _tag[r] != closed_tag and r != goal and _edge_ver[slot * CLUSTERS + (r >> 3)] != _ever[r >> 3]:
			cost += BUILD_COST * 9 + LINK_COST    # worst case: own and 8 neighbour labels + links
		if used + cost > budget and used > 0:
			break
		var _p: int = _pop()
		used += 1
		if _tag[r] == closed_tag:
			continue
		_tag[r] = closed_tag
		if r == goal:
			state = PathSearch.FOUND
			break
		used += ensure_links(slot, r >> 3)
		_expand(r, closed_tag)
	return used


## Stamps the region route (goal back to start along parents) and every region adjacent to it into the corridor.
func mark_corridor() -> void:
	grid.new_corridor(slot)
	var r: int = goal
	while r != -1:
		grid.add_corridor(r)
		var base: int = (slot * REGIONS + r) * 8
		for k: int in 8:
			var bits: int = _adj[base + k]
			for rb: int in MAX_REG:
				if ((bits >> rb) & 1) != 0:
					grid.add_corridor(_nbr[(r >> 3) * 8 + k] * MAX_REG + rb)
		r = _par[r]


## Stamps region `r` and every region adjacent to it (same-region queries) in slot `sl`.
func mark_region(r: int, sl: int) -> void:
	grid.new_corridor(sl)
	grid.add_corridor(r)
	var base: int = (sl * REGIONS + r) * 8
	for k: int in 8:
		var bits: int = _adj[base + k]
		for rb: int in MAX_REG:
			if ((bits >> rb) & 1) != 0:
				grid.add_corridor(_nbr[(r >> 3) * 8 + k] * MAX_REG + rb)


## Stamps every region of the cluster of `cell` and of its 8 neighbours (splice searches) in slot `sl`.
func mark_around(cell: int, sl: int) -> int:
	grid.new_corridor(sl)
	var c: int = PathGrid.cluster_of(cell)
	var cost: int = 0
	for k: int in 9:
		var b: int = c if k == 8 else _nbr[c * 8 + k]
		if b < 0:
			continue
		cost += ensure_labels(sl, b)
		for rb: int in MAX_REG:
			grid.add_corridor(b * MAX_REG + rb)
	return cost


## Regions on the found route, start to goal (tests).
func route() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var r: int = goal
	while r != -1:
		var _a: bool = out.push_back(r)
		r = _par[r]
	return out


func _expand(r: int, closed_tag: int) -> void:
	var base: int = (slot * REGIONS + r) * 8
	var dr: Vector3 = _rdir[slot * REGIONS + r]
	var wr: float = _rw[slot * REGIONS + r]
	var gr: float = _g[r]
	for k: int in 8:
		var bits: int = _adj[base + k]
		if bits == 0:
			continue
		var b: int = _nbr[(r >> 3) * 8 + k]
		for rb: int in MAX_REG:
			if ((bits >> rb) & 1) == 0:
				continue
			var n: int = b * MAX_REG + rb
			if _tag[n] == closed_tag:
				continue
			var dn: Vector3 = _rdir[slot * REGIONS + n]
			var g2: float = gr + Sphere.PLANET_RADIUS * dr.angle_to(dn) * (wr + _rw[slot * REGIONS + n]) * 0.5
			if _tag[n] == closed_tag - 1 and g2 >= _g[n]:
				continue
			_tag[n] = closed_tag - 1
			_g[n] = g2
			_par[n] = r
			_push(g2 + Sphere.PLANET_RADIUS * dn.angle_to(_target_dir) * _hw, n)


func _push(key: float, v: int) -> void:
	if _hn >= _hk.size():
		var _r: int = _hk.resize(_hn + _hn)
		_r = _hv.resize(_hn + _hn)
	var i: int = _hn
	_hn += 1
	while i > 0:
		var p: int = (i - 1) >> 1
		if _hk[p] <= key:
			break
		_hk[i] = _hk[p]
		_hv[i] = _hv[p]
		i = p
	_hk[i] = key
	_hv[i] = v


func _pop() -> int:
	var top: int = _hv[0]
	_hn -= 1
	if _hn == 0:
		return top
	var key: float = _hk[_hn]
	var v: int = _hv[_hn]
	var i: int = 0
	var half: int = _hn >> 1
	while i < half:
		var ch: int = i + i + 1
		if ch + 1 < _hn and _hk[ch + 1] < _hk[ch]:
			ch += 1
		if _hk[ch] >= key:
			break
		_hk[i] = _hk[ch]
		_hv[i] = _hv[ch]
		i = ch
	_hk[i] = key
	_hv[i] = v
	return top
