class_name Interest extends RefCounted
## Interest management, shared half (04 s4.1, R0 C1-02; NET-08). begin_tick() runs once per tick after
## SnapshotCodec.prepare_tick: it buckets every entity by interest cell (Sphere.GRID_INTEREST, 384 cells; the cell
## the codec already quantised against) and keeps per-index direction, visibility bits and generation. Arrays are
## indexed by roster index (SnapshotFrame.index_of_row; projectile entities in the block 1,536-3,583, R0 B.22 A-112,
## whose visibility bits are the codec's c_vmask: own team + shooter + target). Team visible sets V come from the
## codec's per-team lists. assign(client) does the per-client half (InterestClient): tiers A /
## B / C, caps, hysteresis, ghost retention, roster adds and removes. Packed arrays only; no Nodes, no threads.

const CAPACITY: int = Roster.CAPACITY
const CELLS: int = Codec.CELL_COUNT
const TEAM_MAX: int = SnapshotCodec.TEAM_MAX
const RING1_STRIDE: int = 8                 # edge + diagonal neighbours; the 24 cube-corner cells have 7 (-1 pad)
const RING2_STRIDE: int = 24                # ring 1 then ring 2 (Commander camera, 04 s4.1), -1 padded
const NO_CELL: int = -1

var tick: int = -1
var ring1: PackedInt32Array = PackedInt32Array()          # CELLS x RING1_STRIDE
var ring2: PackedInt32Array = PackedInt32Array()          # CELLS x RING2_STRIDE
var cell_dir: PackedVector3Array = PackedVector3Array()   # unit direction of each cell's datum centre
var cell_start: PackedInt32Array = PackedInt32Array()     # CELLS + 1 offsets into cell_ids
var cell_ids: PackedInt32Array = PackedInt32Array()       # present slots grouped by cell, ascending within a cell
var all_ids: PackedInt32Array = PackedInt32Array()        # every present index, ascending (spectator V)
var stamp: PackedInt32Array = PackedInt32Array()          # == tick: slot present this tick
var cell: PackedInt32Array = PackedInt32Array()           # slot -> interest cell
var dir: PackedVector3Array = PackedVector3Array()        # slot -> unit direction from the moon's centre
var vmask: PackedInt32Array = PackedInt32Array()          # slot -> visible-to-team bits, own team included
var gen: PackedInt32Array = PackedInt32Array()            # slot -> generation (SnapshotFrame.gen)
var _fill: PackedInt32Array = PackedInt32Array()
var _sorted: PackedInt32Array = PackedInt32Array()
var _team_v: Array[PackedInt32Array] = []
var _team_v_tick: PackedInt32Array = PackedInt32Array()
var _codec: SnapshotCodec = null


func _init() -> void:
	var _a: int = stamp.resize(CAPACITY)
	var _b: int = cell.resize(CAPACITY)
	var _c: int = dir.resize(CAPACITY)
	var _d: int = vmask.resize(CAPACITY)
	var _e: int = gen.resize(CAPACITY)
	var _f: int = cell_start.resize(CELLS + 1)
	var _g: int = _fill.resize(CELLS)
	var _h: int = cell_ids.resize(CAPACITY)
	var _i: int = _team_v_tick.resize(TEAM_MAX)
	stamp.fill(-1)
	_team_v_tick.fill(-1)
	for t: int in TEAM_MAX:
		_team_v.append(PackedInt32Array())
	_build_rings()


## Ring tables from Sphere.neighbours8 (cube-corner cells have 7 neighbours; across a face edge the table follows
## Sphere.EDGE_NEIGHBOUR). Built once.
func _build_rings() -> void:
	var _a: int = ring1.resize(CELLS * RING1_STRIDE)
	var _b: int = ring2.resize(CELLS * RING2_STRIDE)
	var _c: int = cell_dir.resize(CELLS)
	ring1.fill(NO_CELL)
	ring2.fill(NO_CELL)
	for c: int in CELLS:
		cell_dir[c] = Sphere.cell_center_dir(c, Sphere.GRID_INTEREST)
		var n1: PackedInt32Array = Sphere.neighbours8(c, Sphere.GRID_INTEREST)
		var seen: Dictionary[int, bool] = {c: true}
		var k: int = 0
		for nb: int in n1:
			ring1[c * RING1_STRIDE + k] = nb
			ring2[c * RING2_STRIDE + k] = nb
			seen[nb] = true
			k += 1
		for nb: int in n1:
			for nb2: int in Sphere.neighbours8(nb, Sphere.GRID_INTEREST):
				if not seen.has(nb2) and k < RING2_STRIDE:
					seen[nb2] = true
					ring2[c * RING2_STRIDE + k] = nb2
					k += 1


## Once per tick, after `codec.prepare_tick(frame)` (cells come from the codec's cache; a codec prepared for
## another tick, or null, falls back to Sphere.cell_of). Frame slots are unique (SnapshotFrame). Two passes over
## the frame, no per-entity allocation.
func begin_tick(frame: SnapshotFrame, codec: SnapshotCodec) -> void:
	tick = frame.tick
	_codec = codec if codec != null and codec.cache_tick == frame.tick else null
	cell_start.fill(0)
	var _r: int = _sorted.resize(_ingest(frame))
	for c: int in CELLS:
		cell_start[c + 1] += cell_start[c]
		_fill[c] = cell_start[c]
	_sorted.sort()
	var n: int = 0
	_r = all_ids.resize(cell_start[CELLS])
	for s: int in _sorted:
		var c: int = cell[s]
		cell_ids[_fill[c]] = s
		_fill[c] += 1
		all_ids[n] = s
		n += 1
	_r = all_ids.resize(n)


## Per-index stamp, cell, direction, visibility bits and generation; counts per cell into cell_start[c + 1]; the
## indices into _sorted (unsorted). Returns their count.
func _ingest(frame: SnapshotFrame) -> int:
	var cached: bool = _codec != null
	var cpos: PackedInt64Array = _codec.c_pos if cached else PackedInt64Array()
	var cvm: PackedInt32Array = _codec.c_vmask if cached else PackedInt32Array()
	var poss: PackedVector3Array = frame.pos
	var slots: PackedInt32Array = frame.slot                # locals: no property lookup per entity
	var masks: PackedInt32Array = frame.visible_mask
	var teams: PackedByteArray = frame.team
	var gens: PackedInt32Array = frame.gen
	var has_gen: bool = gens.size() >= frame.count
	var t: int = tick
	var n: int = 0
	if _sorted.size() < frame.count:
		var _r: int = _sorted.resize(frame.count)
	for i: int in frame.count:
		var s: int = slots[i]
		if s < 0 or s >= Roster.ENTITY_SLOTS:               # the projectile block (or no roster index)
			s = frame.index_of_row(i)
			if s < 0:
				continue
		var p: Vector3 = poss[i]
		var c: int = (cpos[s] & 0xFFFF) if cached else Sphere.cell_of(p, Sphere.GRID_INTEREST)
		stamp[s] = t
		cell[s] = c
		dir[s] = p.normalized()
		vmask[s] = cvm[s] if cached else masks[i] | (1 << (teams[i] % TEAM_MAX))
		gen[s] = gens[i] if has_gen else 0
		cell_start[c + 1] += 1
		_sorted[n] = s
		n += 1
	return n


func present(s: int) -> bool:
	return s >= 0 and s < CAPACITY and stamp[s] == tick


## Team `team` sees slot `s` this tick (own team always; team < 0 = spectator, sees everything present).
func visible(s: int, team: int) -> bool:
	if not present(s):
		return false
	return team < 0 or ((vmask[s] >> (team % TEAM_MAX)) & 1) != 0


## V for `team` this tick, ascending; built once per team per tick (the codec's per-team list, R0 C1-02).
## team < 0 = every present entity (spectator).
func team_list(team: int) -> PackedInt32Array:
	if team < 0 or team >= TEAM_MAX:
		return all_ids
	if _team_v_tick[team] != tick:
		_team_v_tick[team] = tick
		_team_v[team] = _codec.team_visible(team) if _codec != null else _filter_team(team)
	return _team_v[team]


func _filter_team(team: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for s: int in all_ids:
		if ((vmask[s] >> team) & 1) != 0:
			var _p: bool = out.push_back(s)
	return out


## Per-client tiering for this tick (04 s4.1): fills `client`'s a / b / c lists, cells, added and removed.
func assign(client: InterestClient) -> void:
	client.assign(self)
