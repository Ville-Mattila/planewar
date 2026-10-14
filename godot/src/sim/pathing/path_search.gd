class_name PathSearch extends PathGrid
## Resumable cell-level A* over the path grid (03 s3.6, R0 C1-05): one search in flight, advanced by `run(budget)`
## where every heap pop counts as one expansion. Open set = binary min-heap over two parallel packed arrays (f key,
## cell); closed / seen by a u8 per-search tag per cell (cleared once every _SID_MAX searches); the parent of a cell
## is the u8 index of the parent in the cell's own neighbours() list (neighbours8 is symmetric, TA-50 memory cut);
## lazy deletion of stale heap entries.
## Edge cost a -> b = arc(a, b) * (w_a + w_b) / 2 in metres; h = great-circle(cell, goal) * (1 + heuristic_pct / 100),
## admissible and consistent at heuristic_pct 0 (arc >= great circle, w >= 1). Diagonals never cut a corner: both
## orthogonal cells beside a diagonal step must be passable, so no straight segment between consecutive cell
## centres touches an impassable cell. Optional corridor: only cells whose region carries the corridor stamp.
## Extends PathGrid so the hot loop reads weights, slopes and tags as own members (no cross-object packed access).

const RUNNING: int = 0
const FOUND: int = 1
const EXHAUSTED: int = 2
const CLUSTERS: int = FACES * 16 * 16      ## 16 x 16-cell clusters (03 s3.6 hierarchy)
const MAX_REG: int = 8                     ## regions per cluster (PathRegions)
const REGIONS: int = CLUSTERS * MAX_REG
const MASK_SLOTS: int = 2                  ## request masks with a region graph at once (v1: Harvester, Crawler)
const NO_REGION: int = 255
const _PCT: int = 100
const _HEAP_INITIAL: int = 4096
const _SID_MAX: int = 127                  ## u8 tags 2 * sid (open) and 2 * sid + 1 (closed); then one fill(0)
const _INV: PackedInt32Array = [1, 0, 3, 2, 7, 6, 5, 4]   ## in-face: neighbours() index of the way back
const _SEARCH_STATE: PackedStringArray = ["heuristic_pct", "state", "start", "goal", "limit_q", "corridor_stamp",
	"corridor_on", "touched", "_hn", "_sid", "_hw", "_goal_dir", "_lab_off"]

var heuristic_pct: int = 0                 ## heuristic inflation in percent (0 = exact A*)
var state: int = EXHAUSTED
var start: int = -1
var goal: int = -1
var limit_q: int = SLOPE_NO_LIMIT
var corridor: PackedInt32Array = PackedInt32Array()   ## per region: == corridor_stamp when inside the corridor
var label: PackedByteArray = PackedByteArray()        ## MASK_SLOTS * CELLS region labels (PathRegions) or NO_REGION
var corridor_stamp: int = 0
var corridor_on: bool = false
var touched: int = 0                       ## cells discovered by the current search (memory / flood metric)
var _g: PackedFloat32Array = PackedFloat32Array()
var _tag: PackedByteArray = PackedByteArray()         ## 2 * sid seen (open), 2 * sid + 1 closed
var _dir: PackedByteArray = PackedByteArray()         ## parent = neighbours(cell)[_dir[cell]]
var _hk: PackedFloat32Array = PackedFloat32Array()
var _hv: PackedInt32Array = PackedInt32Array()
var _hn: int = 0
var _sid: int = 0
var _hw: float = 1.0
var _goal_dir: Vector3 = Vector3.ZERO
var _nbe: PackedInt32Array = PackedInt32Array()       ## neighbours of an edge cell while _back() reuses nb
var _lab_off: int = 0
var _label_rev: int = 0                               ## bumped by every label write; keys the compressed S4 block
var _lab_blob: PackedByteArray = PackedByteArray()
var _lab_blob_rev: int = -1


func _init() -> void:
	super()
	var _r: int = _g.resize(CELLS)
	_r = _tag.resize(CELLS)
	_r = _dir.resize(CELLS)
	_r = corridor.resize(REGIONS)
	_r = label.resize(MASK_SLOTS * CELLS)
	label.fill(NO_REGION)
	_r = _nbe.resize(8)
	_r = _hk.resize(_HEAP_INITIAL)
	_r = _hv.resize(_HEAP_INITIAL)


## Starts a search from cell `s` to cell `t` under slope limit `lq`; `use_corridor` restricts it to the clusters
## stamped with corridor_stamp. An impassable goal fails at once (EXHAUSTED); the start cell is always allowed.
func begin(s: int, t: int, lq: int, use_corridor: bool) -> void:
	_sid += 1
	if _sid > _SID_MAX:
		_tag.fill(0)
		_sid = 1
	start = s
	goal = t
	limit_q = lq
	corridor_on = use_corridor
	_hw = 1.0 + float(heuristic_pct) / float(_PCT)
	_goal_dir = center_dir(t)
	_hn = 0
	touched = 1
	state = RUNNING if passable(t, lq) else EXHAUSTED
	_g[s] = 0.0
	_tag[s] = _sid + _sid
	_dir[s] = 0                              # never followed (write_path stops at start); fixed for S4 bytes
	_push(Sphere.PLANET_RADIUS * center_dir(s).angle_to(_goal_dir) * _hw, s)


## Up to `budget` heap pops; returns the pops used. state becomes FOUND or EXHAUSTED when the search ends.
func run(budget: int) -> int:
	var used: int = 0
	var closed_tag: int = _sid + _sid + 1
	while used < budget and state == RUNNING:
		if _hn == 0:
			state = EXHAUSTED
			break
		var c: int = _pop()
		used += 1
		if _tag[c] == closed_tag:
			continue
		_tag[c] = closed_tag
		if c == goal:
			state = FOUND
			break
		_expand(c, closed_tag)
	return used


## Opens a new (empty) corridor over the region labels of mask slot `sl`; add_corridor stamps regions into it.
func new_corridor(sl: int) -> void:
	corridor_stamp += 1
	_lab_off = sl * CELLS


func add_corridor(region: int) -> void:
	corridor[region] = corridor_stamp


## Accessors for other pathing classes: reading `grid.label[i]` from another object parks a reference to the array
## in the caller's frame, and the next owner write then copies the whole array (copy-on-write). Use these instead.
func label_at(i: int) -> int:
	return label[i]


func weight_at(cell: int) -> int:
	return weights[cell]


## Path cost in metres of the found path (valid when state == FOUND).
func found_cost() -> float:
	return _g[goal]


## Writes the found path start..goal into out[off ..]; returns the cell count, or -1 when longer than `cap`.
func write_path(out: PackedInt32Array, off: int, cap: int) -> int:
	var n: int = 1
	var c: int = goal
	while c != start:
		c = _parent(c)
		n += 1
		if n > cap:
			return -1
	c = goal
	for k: int in n:
		out[off + n - 1 - k] = c
		if c != start:
			c = _parent(c)
	return n


func _parent(c: int) -> int:
	neighbours(c)
	return nb[_dir[c]]


# Index of `c` in neighbours(n) (n is a neighbour of the edge cell c; Sphere.neighbours8 is symmetric). Clobbers nb.
func _back(n: int, c: int) -> int:
	neighbours(n)
	for d: int in 8:
		if nb[d] == c:
			return d
	return 0


## S4 (TA-50): the grid's bytes, the region labels (zstd, cached until the next label write), the search scalars,
## and while a search runs its heap, the cells it tagged (tag, parent index, g; stale tags never match a later
## search, so the reader zeroes the rest) and the corridor regions. Corridor regions are read only while running.
func write_state(buf: StreamPeerBuffer) -> void:
	super.write_state(buf)
	if _lab_blob_rev != _label_rev:
		_lab_blob = label.compress(FileAccess.COMPRESSION_ZSTD)
		_lab_blob_rev = _label_rev
	buf.put_var(_lab_blob)
	StateIO.put_props(buf, self, _SEARCH_STATE)
	var live: bool = state == RUNNING
	var cells: PackedInt32Array = PackedInt32Array()
	var lo: int = _sid + _sid
	if live:
		for c: int in CELLS:
			if _tag[c] >= lo:
				var _a: bool = cells.push_back(c)
	var tags: PackedByteArray = PackedByteArray()
	var dirs: PackedByteArray = PackedByteArray()
	var gs: PackedFloat32Array = PackedFloat32Array()
	for c: int in cells:
		var _a: bool = tags.push_back(_tag[c])
		_a = dirs.push_back(_dir[c])
		_a = gs.push_back(_g[c])
	var regs: PackedInt32Array = PackedInt32Array()
	if live and corridor_on:
		for r: int in REGIONS:
			if corridor[r] == corridor_stamp:
				var _a: bool = regs.push_back(r)
	for v: Variant in [_hk.slice(0, _hn if live else 0), _hv.slice(0, _hn if live else 0), cells, tags, dirs, gs, regs]:
		buf.put_var(v)


## Inverse of write_state over a grid holding the same map; false on malformed bytes.
func read_state(buf: StreamPeerBuffer) -> bool:
	if not super.read_state(buf):
		return false
	var lab: PackedByteArray = get_z(buf, MASK_SLOTS * CELLS)
	if lab.is_empty() or not StateIO.get_props(buf, self, _SEARCH_STATE):
		return false
	label = lab
	_label_rev += 1
	var parts: Array = []
	for _k: int in 7:
		parts.append(buf.get_var() if buf.get_available_bytes() > 0 else null)
	var types: PackedInt32Array = [TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT32_ARRAY,
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_INT32_ARRAY]
	for k: int in 7:
		if typeof(parts[k]) != types[k]:
			return false
	var hk: PackedFloat32Array = parts[0]
	var hv: PackedInt32Array = parts[1]
	var cells: PackedInt32Array = parts[2]
	var tags: PackedByteArray = parts[3]
	var dirs: PackedByteArray = parts[4]
	var gs: PackedFloat32Array = parts[5]
	var regs: PackedInt32Array = parts[6]
	if hk.size() != hv.size() or hk.size() != (_hn if state == RUNNING else 0) or tags.size() != cells.size():
		return false
	if dirs.size() != cells.size() or gs.size() != cells.size():
		return false
	var _r: int = hk.resize(maxi(_HEAP_INITIAL, hk.size()))
	_r = hv.resize(hk.size())
	_hk = hk
	_hv = hv
	_tag.fill(0)
	for k: int in cells.size():
		var c: int = clampi(cells[k], 0, CELLS - 1)
		_tag[c] = tags[k]
		_dir[c] = dirs[k]
		_g[c] = gs[k]
	corridor.fill(0)
	for r: int in regs:
		corridor[clampi(r, 0, REGIONS - 1)] = corridor_stamp
	return true


func _expand(c: int, closed_tag: int) -> void:
	var i: int = c & LOW
	var j: int = (c >> SHIFT) & LOW
	var edge: bool = i == 0 or i == LOW or j == 0 or j == LOW
	neighbours(c)
	if edge:
		for k: int in 8:
			_nbe[k] = nb[k]
	var f: int = c >> (SHIFT + SHIFT)
	var dc: Vector3 = _fn[f] + _fs[f] * _tan[i] + _ft[f] * _tan[j]   # angle_to is scale-invariant
	var gc: float = _g[c]
	var wc: int = weights[c]
	var seen_tag: int = closed_tag - 1
	var open: int = 0                      # bit d set: orthogonal neighbour d passable (corner rule)
	for k: int in 8:
		var n: int = _nbe[k] if edge else nb[k]
		if n < 0 or (k >= 4 and ((open >> (k & 1)) & 1) == 0) or (k >= 4 and ((open >> (2 + ((k >> 1) & 1))) & 1) == 0):
			continue
		var w: int = weights[n]
		if w == W_BLOCKED or w == W_ZERO:
			continue
		if limit_q < SLOPE_NO_LIMIT:
			var sq: int = slope_q[n]
			if (sample_slope(n) if sq == SLOPE_UNKNOWN else sq) > limit_q:
				continue
		if k < 4:
			open |= 1 << k
		if corridor_on:
			var lab: int = label[_lab_off + n]
			if lab >= MAX_REG or corridor[(((n >> (SHIFT + 4)) << 4) + ((n & LOW) >> 4)) * MAX_REG + lab] != corridor_stamp:
				continue
		var t: int = _tag[n]
		if t == closed_tag:
			continue
		var nf: int = n >> (SHIFT + SHIFT)
		var dn: Vector3 = _fn[nf] + _fs[nf] * _tan[n & LOW] + _ft[nf] * _tan[(n >> SHIFT) & LOW]
		var g2: float = gc + Sphere.PLANET_RADIUS * dc.angle_to(dn) * float(wc + w) * 0.5
		if t == seen_tag and g2 >= _g[n]:
			continue
		if t != seen_tag:
			touched += 1
		_tag[n] = seen_tag
		_g[n] = g2
		_dir[n] = _back(n, c) if edge else _INV[k]
		_push(g2 + Sphere.PLANET_RADIUS * dn.angle_to(_goal_dir) * _hw, n)


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
