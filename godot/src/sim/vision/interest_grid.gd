class_name InterestGrid extends RefCounted
## The interest grid of 03 s3.6 (ADR-05: 6 x 8 x 8 = 384 cells, ~1,178 m) inside Vision (TA-37). Three parts:
## 1. the per-tick bucket index: every live entity (structures, ships, ground, wrecks) counting-sorted by
##    (interest cell, team group); group 8 holds neutral entities (team >= TEAMS, e.g. 255). The interest cell of a
##    slot is its GRID_HASH `hash_cell` (Spatial, step 7) shifted by 3 in i and j, which equals
##    `Sphere.cell_of(pos, GRID_INTEREST)` (the hash index is the same equal-angle floor at 8x the resolution);
## 2. the near-cell table: per cell, every cell whose points can lie within the table reach (3D, metres) of a
##    point of the cell, ascending by that lower bound (`near_gap`), shared by every grid with the same reach;
## 3. the per-team interest lists NET-08 reads (`SimWorld.interest_*`): for team t and cell c, the EntityIds visible
##    to t (own team included) at t's last vision pass are `ids[cell_start[t * CELLS + c] + k]`,
##    k < `cell_count[t * CELLS + c]`; a cell absent from the list has count 0. Inside a cell: own team first, then
##    the others in scan order. Team t's entries are the contiguous ids[t * STRIDE, t * STRIDE + list_size[t]).
## Invariant: bit t of `visible_mask` is set only on slots in team t's list, so a pass clears exactly the old list.
## No Dictionary, no per-cell arrays (R0 C1-19): flat packed members only.

const N: int = Sphere.GRID_INTEREST
const CELLS: int = 6 * N * N
const TEAMS: int = PlayerTable.TEAMS
const GROUPS: int = TEAMS + 1            ## team groups 0..7, then NEUTRAL_GROUP
const NEUTRAL_GROUP: int = TEAMS
const STRIDE: int = EntityStore.SLOT_COUNT   ## per-team capacity of `ids`
const _FACE_SHIFT: int = 2 * Spatial.SHIFT   ## hash cell >> 12 = face
const _J_SHIFT: int = Spatial.SHIFT + 3      ## (hash j) >> 3
const _I_SHIFT: int = 3                      ## (hash i) >> 3
const _LOW3: int = N - 1
const _CONE_EPS: float = 1.0 / Sphere.PLANET_RADIUS   ## ~1 m of arc added to every cone (rounding margin)

## Bucket index (b = cell * GROUPS + group), rebuilt by `index()`; items are store slots.
var bucket_start: PackedInt32Array = PackedInt32Array()
var bucket_count: PackedInt32Array = PackedInt32Array()
var items: PackedInt32Array = PackedInt32Array()
var cell_n: PackedInt32Array = PackedInt32Array()      ## live entities per cell this tick
var touched: PackedInt32Array = PackedInt32Array()     ## non-empty cells, first-seen order; first touched_n valid
var touched_n: int = 0
## Cell geometry (shared): unit centre direction and angular circumradius (+ margin) per cell.
var centre: PackedVector3Array = PackedVector3Array()
var cone: PackedFloat64Array = PackedFloat64Array()
var cone_cos: PackedFloat64Array = PackedFloat64Array()  ## cos / sin of `cone`
var cone_sin: PackedFloat64Array = PackedFloat64Array()
## Near-cell table: cells near cell c are near_cell[near_start[c] .. near_start[c + 1]), near_gap ascending.
var near_start: PackedInt32Array = PackedInt32Array()
var near_cell: PackedInt32Array = PackedInt32Array()
var near_gap: PackedFloat32Array = PackedFloat32Array()
var reach_m: float = -1.0                              ## the near table covers gaps <= reach_m
## Per-team interest lists (see header).
var cell_start: PackedInt32Array = PackedInt32Array()
var cell_count: PackedInt32Array = PackedInt32Array()
var ids: PackedInt32Array = PackedInt32Array()
var list_size: PackedInt32Array = PackedInt32Array()   ## per team: entries in its list

var _hmap: PackedInt32Array = PackedInt32Array()       ## GRID_HASH cell -> interest cell (shared)
var _key: PackedInt32Array = PackedInt32Array()        ## per slot: its bucket this tick
var _fill: PackedInt32Array = PackedInt32Array()
var _list_cells: PackedInt32Array = PackedInt32Array() ## per team: cells with cell_count > 0
var _list_cells_n: PackedInt32Array = PackedInt32Array()
var _sc_n: PackedInt32Array = PackedInt32Array()       ## per cell: seen slots (build_list scratch, back to 0)
var _sc_start: PackedInt32Array = PackedInt32Array()
var _sorted: PackedInt32Array = PackedInt32Array()
var _seen_cell: PackedInt32Array = PackedInt32Array()
var _s_list: PackedInt32Array = PackedInt32Array()     ## structures cache: the live list and team bytes it was built
var _s_team: PackedByteArray = PackedByteArray()        ## from; bucket counts, cell counts and non-empty cells
var _s_bc: PackedInt32Array = PackedInt32Array()
var _s_cn: PackedInt32Array = PackedInt32Array()
var _s_touched: PackedInt32Array = PackedInt32Array()
var _s_touched_n: int = 0
var _s_valid: bool = false

static var _g_hmap: PackedInt32Array = PackedInt32Array()
static var _g_centre: PackedVector3Array = PackedVector3Array()
static var _g_cone: PackedFloat64Array = PackedFloat64Array()
static var _g_cone_cos: PackedFloat64Array = PackedFloat64Array()
static var _g_cone_sin: PackedFloat64Array = PackedFloat64Array()
static var _cache_reach: float = -1.0
static var _cache_start: PackedInt32Array = PackedInt32Array()
static var _cache_cell: PackedInt32Array = PackedInt32Array()
static var _cache_gap: PackedFloat32Array = PackedFloat32Array()


func _init() -> void:
	var nb: int = CELLS * GROUPS
	var e: int = bucket_start.resize(nb) | bucket_count.resize(nb) | _fill.resize(nb) | items.resize(STRIDE)
	e |= cell_n.resize(CELLS) | touched.resize(CELLS) | _key.resize(STRIDE) | _sc_n.resize(CELLS)
	e |= cell_start.resize(TEAMS * CELLS) | cell_count.resize(TEAMS * CELLS) | ids.resize(TEAMS * STRIDE)
	e |= list_size.resize(TEAMS) | _list_cells.resize(TEAMS * CELLS) | _list_cells_n.resize(TEAMS)
	e |= _sc_start.resize(CELLS) | _sorted.resize(STRIDE) | _seen_cell.resize(STRIDE)
	e |= _s_bc.resize(nb) | _s_cn.resize(CELLS) | _s_touched.resize(CELLS)
	assert(e == OK)
	bucket_count.fill(0)
	_s_bc.fill(0)
	_s_cn.fill(0)
	cell_n.fill(0)
	cell_count.fill(0)
	cell_start.fill(0)
	list_size.fill(0)
	_list_cells_n.fill(0)
	_sc_n.fill(0)
	if _g_hmap.is_empty():
		_build_geometry()
	_hmap = _g_hmap
	centre = _g_centre
	cone = _g_cone
	cone_cos = _g_cone_cos
	cone_sin = _g_cone_sin


## The interest cell (GRID_INTEREST id) of a GRID_HASH cell id.
static func interest_of_hash(hash_cell: int) -> int:
	return ((hash_cell >> _FACE_SHIFT) * N + ((hash_cell >> _J_SHIFT) & _LOW3)) * N + ((hash_cell >> _I_SHIFT) & _LOW3)


## Makes the near-cell table cover `reach` metres (no-op when it already does). Shared per reach across grids.
func ensure_reach(reach: float) -> void:
	if reach <= reach_m:
		return
	if _cache_reach < reach:
		_build_near(reach)
	near_start = _cache_start
	near_cell = _cache_cell
	near_gap = _cache_gap
	reach_m = _cache_reach


## Rebuilds the bucket index from the store's live lists and `hash_cell` (valid after step 7). Structures never move,
## so their bucket keys and counts are cached and recounted only when the structures list or any team byte changed
## (native compares); ships, ground units and wrecks are counted every call. Same result as counting everything.
func index(store: EntityStore) -> void:
	if not _s_valid or store.structures != _s_list or store.team != _s_team:
		_count_structures(store)
	var bc: PackedInt32Array = bucket_count     # sole owners while writing (no copy-on-write), restored below
	var cn: PackedInt32Array = cell_n
	var tch: PackedInt32Array = touched
	var key: PackedInt32Array = _key
	bucket_count = PackedInt32Array()
	cell_n = PackedInt32Array()
	touched = PackedInt32Array()
	_key = PackedInt32Array()
	for k: int in touched_n:
		var c: int = tch[k]
		cn[c] = 0
		for g: int in GROUPS:
			bc[c * GROUPS + g] = 0
	for k: int in _s_touched_n:
		var c: int = _s_touched[k]
		tch[k] = c
		cn[c] = _s_cn[c]
		for g: int in GROUPS:
			bc[c * GROUPS + g] = _s_bc[c * GROUPS + g]
	var hc: PackedInt32Array = store.hash_cell
	var tm: PackedByteArray = store.team
	var n: int = _count(store.ships, hc, tm, key, cn, bc, tch, _s_touched_n)
	n = _count(store.ground, hc, tm, key, cn, bc, tch, n)
	n = _count(store.wrecks, hc, tm, key, cn, bc, tch, n)
	touched_n = n
	bucket_count = bc
	cell_n = cn
	touched = tch
	_scatter_all(store, key)
	_key = key


## Team `t`'s new list and bit t: the old list's bits are cleared, then the `seen_n` distinct slots of `seen` and,
## when `own`, every indexed slot of team t are written per cell and get bit t. `own` false with `seen` = the slots
## already carrying bit t (`seen_from_mask`) rebuilds the list without changing any bit.
func build_list(t: int, store: EntityStore, seen: PackedInt32Array, seen_n: int, own: bool) -> void:
	var base: int = t * CELLS
	var off: int = t * STRIDE
	var bit: int = 1 << t
	var mask: PackedByteArray = store.visible_mask
	store.visible_mask = PackedByteArray()        # sole owners while writing: no copy-on-write
	var out: PackedInt32Array = ids
	ids = PackedInt32Array()
	for i: int in list_size[t]:
		var s: int = out[off + i] & EntityId.SLOT_MASK
		mask[s] = mask[s] & ~bit
	for k: int in _list_cells_n[t]:
		cell_count[base + _list_cells[base + k]] = 0
	_sort_seen(store, seen, seen_n)
	var gen: PackedInt32Array = store.generation
	var n: int = 0
	var lc: int = 0
	for k: int in touched_n:
		var c: int = touched[k]
		var first: int = n
		var b: int = c * GROUPS + t
		var s0: int = bucket_start[b]
		var n_own: int = bucket_count[b] if own else 0
		for q: int in n_own + _sc_n[c]:
			var s: int = items[s0 + q] if q < n_own else _sorted[_sc_start[c] + q - n_own]
			mask[s] = mask[s] | bit
			out[off + n] = s | ((gen[s] & EntityId.GEN_MASK) << EntityId.GEN_SHIFT)
			n += 1
		_sc_n[c] = 0
		if n > first:
			cell_start[base + c] = off + first
			cell_count[base + c] = n - first
			_list_cells[base + lc] = c
			lc += 1
	ids = out
	store.visible_mask = mask
	_list_cells_n[t] = lc
	list_size[t] = n


## Indexed slots of every team group that carry bit t now, into `out` (rebuilding lists after deserialize).
func seen_from_mask(t: int, store: EntityStore, out: PackedInt32Array) -> int:
	var n: int = 0
	var bit: int = 1 << t
	for k: int in touched_n:
		for g: int in GROUPS:
			var b: int = touched[k] * GROUPS + g
			for q: int in bucket_count[b]:
				var s: int = items[bucket_start[b] + q]
				if (store.visible_mask[s] & bit) != 0:
					out[n] = s
					n += 1
	return n


func _count(list: PackedInt32Array, hc: PackedInt32Array, tm: PackedByteArray, key: PackedInt32Array,
		cn: PackedInt32Array, bc: PackedInt32Array, tch: PackedInt32Array, n0: int) -> int:
	var hmap: PackedInt32Array = _hmap
	var n: int = n0
	for s: int in list:
		var c: int = hmap[hc[s]]
		var g: int = tm[s]
		if g > NEUTRAL_GROUP:
			g = NEUTRAL_GROUP
		var b: int = c * GROUPS + g
		key[s] = b
		if cn[c] == 0:
			tch[n] = c
			n += 1
		cn[c] += 1
		bc[b] += 1
	return n


# The structures cache: keys into _key (kept between calls: dynamic slots never overwrite a live structure's key),
# per-bucket and per-cell counts, the non-empty cells.
func _count_structures(store: EntityStore) -> void:
	for k: int in _s_touched_n:
		var c: int = _s_touched[k]
		_s_cn[c] = 0
		for g: int in GROUPS:
			_s_bc[c * GROUPS + g] = 0
	var key: PackedInt32Array = _key
	var cn: PackedInt32Array = _s_cn
	var bc: PackedInt32Array = _s_bc
	var tch: PackedInt32Array = _s_touched
	_key = PackedInt32Array()
	_s_cn = PackedInt32Array()
	_s_bc = PackedInt32Array()
	_s_touched = PackedInt32Array()
	_s_touched_n = _count(store.structures, store.hash_cell, store.team, key, cn, bc, tch, 0)
	_key = key
	_s_cn = cn
	_s_bc = bc
	_s_touched = tch
	_s_list = store.structures.duplicate()
	_s_team = store.team.duplicate()
	_s_valid = true


# Prefix sums over the touched cells' buckets, then every live slot into `items` at its bucket.
func _scatter_all(store: EntityStore, key: PackedInt32Array) -> void:
	var bs: PackedInt32Array = bucket_start
	var fl: PackedInt32Array = _fill
	var it: PackedInt32Array = items
	bucket_start = PackedInt32Array()
	_fill = PackedInt32Array()
	items = PackedInt32Array()
	var run: int = 0
	for k: int in touched_n:
		var b0: int = touched[k] * GROUPS
		for g: int in GROUPS:
			bs[b0 + g] = run
			fl[b0 + g] = run
			run += bucket_count[b0 + g]
	_scatter(store.structures, key, fl, it)
	_scatter(store.ships, key, fl, it)
	_scatter(store.ground, key, fl, it)
	_scatter(store.wrecks, key, fl, it)
	bucket_start = bs
	_fill = fl
	items = it


func _scatter(list: PackedInt32Array, key: PackedInt32Array, fl: PackedInt32Array, it: PackedInt32Array) -> void:
	for s: int in list:
		var b: int = key[s]
		it[fl[b]] = s
		fl[b] += 1


# Counting sort of the seen slots by interest cell into _sorted; _sc_n / _sc_start per cell (touched cells only).
func _sort_seen(store: EntityStore, seen: PackedInt32Array, seen_n: int) -> void:
	var hc: PackedInt32Array = store.hash_cell
	for i: int in seen_n:
		var c: int = _hmap[hc[seen[i]]]
		_seen_cell[i] = c
		_sc_n[c] += 1
	var run: int = 0
	for k: int in touched_n:
		var c: int = touched[k]
		_sc_start[c] = run
		_fill[c] = run
		run += _sc_n[c]
	for i: int in seen_n:
		var c: int = _seen_cell[i]
		_sorted[_fill[c]] = seen[i]
		_fill[c] += 1


static func _build_geometry() -> void:
	var hn: int = Sphere.GRID_HASH
	var hmap: PackedInt32Array = PackedInt32Array()
	var _a: int = hmap.resize(6 * hn * hn)
	for h: int in hmap.size():
		hmap[h] = interest_of_hash(h)
	var c3: PackedVector3Array = PackedVector3Array()
	var cone_a: PackedFloat64Array = PackedFloat64Array()
	var _b: int = c3.resize(CELLS) | cone_a.resize(CELLS)
	for c: int in CELLS:
		c3[c] = Sphere.cell_center_dir(c, N)
		var cc: float = 1.0
		for corner: Vector3 in Sphere.cell_bounds_dirs(c, N):
			cc = minf(cc, c3[c].dot(corner))
		cone_a[c] = acos(clampf(cc, -1.0, 1.0)) + _CONE_EPS
	_g_centre = c3
	_g_cone = cone_a
	var cc_a: PackedFloat64Array = PackedFloat64Array()
	var cs_a: PackedFloat64Array = PackedFloat64Array()
	var _c: int = cc_a.resize(CELLS) | cs_a.resize(CELLS)
	for c: int in CELLS:
		cc_a[c] = cos(cone_a[c])
		cs_a[c] = sin(cone_a[c])
	_g_cone_cos = cc_a
	_g_cone_sin = cs_a
	_g_hmap = hmap


# Near-cell table for `reach`: cells c, h are near when the chord lower bound between their cones is <= reach.
# Points at angle phi apart with radii >= r_min (PLANET_RADIUS + RELIEF_MIN, the terrain floor) are at least
# 2 r_min sin(phi / 2) apart; phi >= angle(centres) - cone(c) - cone(h), cone = the angular circumradius (the cap
# through the four corners contains the convex cell). Sorted by gap (floored to whole metres, conservative).
static func _build_near(reach: float) -> void:
	var r_min: float = Sphere.PLANET_RADIUS + Sphere.RELIEF_MIN
	var cone_max: float = 0.0
	for c: int in CELLS:
		cone_max = maxf(cone_max, _g_cone[c])
	var limit: float = PI if reach >= 2.0 * r_min else 2.0 * asin(reach / (2.0 * r_min))
	var cos_lim: float = cos(minf(PI, limit + 2.0 * cone_max))
	var start: PackedInt32Array = PackedInt32Array([0])
	var cells: PackedInt32Array = PackedInt32Array()
	var gaps: PackedFloat32Array = PackedFloat32Array()
	for c: int in CELLS:
		var keys: PackedInt64Array = PackedInt64Array()
		for h: int in CELLS:
			var d: float = _g_centre[c].dot(_g_centre[h])
			if d < cos_lim:
				continue
			var phi: float = maxf(0.0, acos(clampf(d, -1.0, 1.0)) - _g_cone[c] - _g_cone[h])
			var gap: int = floori(2.0 * r_min * sin(phi * 0.5))
			if float(gap) <= reach:
				var _k: bool = keys.push_back(gap * CELLS + h)
		keys.sort()
		for key: int in keys:
			var _c: bool = cells.push_back(key % CELLS)
			var _g: bool = gaps.push_back(float(MathX.floori_div(key, CELLS)))
		var _s: bool = start.push_back(cells.size())
	_cache_reach = reach
	_cache_start = start
	_cache_cell = cells
	_cache_gap = gaps
