class_name Spatial extends RefCounted
## Collision hash (03 s3.6, R0 C1-19, TA-14): every live entity and projectile bucketed by its GRID_HASH cell
## (Sphere.cell_of, 64 x 64 per face) in flat packed arrays, rebuilt each tick by counting sort (tick step 7).
## No Dictionary, no per-cell arrays: `cell_count` / `cell_start` index one `cell_items` array, and only the
## cells listed in `touched_cells` are reset by the next rebuild. Items are store slots: entity slot s, or
## EntityId.PROJECTILE_SLOT_MIN + local index for projectiles. Rebuild writes `hash_cell` in both stores.
##
## Ring logic. The cell plus its 8 neighbours (`ring 1`) contain every point within `ring1_m` (3D distance) of
## any point of the cell; the 5 x 5 block (`ring 2`) within `ring2_m`. Proof sketch: GRID_HASH cell edges are
## great circles (equal-angle mapping), constant-u edges all contain the face's v axis and adjacent ones meet at
## the dihedral angle delta = (pi / 2) / N; a point at angle phi from that axis is asin(sin(phi) sin(k delta))
## from the k-th edge plane, and phi >= 45 degrees everywhere on a face (the minimum is at the middle of a face
## edge, not at a corner). So ring k covers the datum arc asin(sin(k delta) / sqrt(2)): 104.1 m and 208.2 m at
## R = 6,000 m (not the 139 m corner edge length of 03 s2.7: the corner rhombus is narrower than its edge).
## Two points at radius >= PLANET_RADIUS + RELIEF_MIN separated by angle theta are at least
## 2 (R + RELIEF_MIN) sin(theta / 2) apart, which converts the arc to a 3D radius; a 1 / N margin is taken off.
## test_spatial.gd checks coverage by brute force at cube edges and corners. Beyond ring2_m `ids_near` scans the
## touched cells with a bounding-cone test (the interest-grid fallback of 03 s3.6 is Vision's, TA-37).
## Precondition: positions are at radius >= PLANET_RADIUS + RELIEF_MIN (terrain floor).

const MASK_STRUCTURE: int = 1    ## 1 << EntityStore.K_STRUCTURE
const MASK_SHIP: int = 2         ## 1 << EntityStore.K_SHIP
const MASK_GROUND: int = 4       ## 1 << EntityStore.K_GROUND
const MASK_WRECK: int = 8        ## 1 << EntityStore.K_WRECK
const MASK_PROJECTILE: int = 16
const MASK_ENTITIES: int = 15
const MASK_ALL: int = 31
const N: int = Sphere.GRID_HASH
const SHIFT: int = 6             ## N == 1 << SHIFT (asserted in _init)
const CELL_COUNT: int = 6 * N * N
const ITEM_CAP: int = EntityStore.SLOT_COUNT + ProjectileStore.SLOT_COUNT
const _FOUR_OVER_PI: float = 2.0 / (PI * 0.5)

var cell_start: PackedInt32Array = PackedInt32Array()   ## CELL_COUNT + 1; valid where cell_count > 0
var cell_count: PackedInt32Array = PackedInt32Array()   ## CELL_COUNT; 0 for every untouched cell
var cell_items: PackedInt32Array = PackedInt32Array()   ## ITEM_CAP store slots, grouped by cell
var touched_cells: PackedInt32Array = PackedInt32Array()   ## first touched_count entries: non-empty cells, first-seen order
var touched_count: int = 0
var item_count: int = 0
var max_entity_radius: float = 0.0   ## largest `EntityStore.radius` hashed by the last rebuild
var ring1_m: float = 0.0             ## 3D radius covered by a cell and its 8 neighbours
var ring2_m: float = 0.0             ## 3D radius covered by the 5 x 5 block
var cell_entities: PackedInt32Array = PackedInt32Array()   ## per cell: entity items, stored before its projectiles
var ring: PackedInt32Array = PackedInt32Array()            ## scratch filled by ring_cells; read, never keep

var _store: EntityStore
var _proj: ProjectileStore
var _fill: PackedInt32Array = PackedInt32Array()
var _nb8: PackedInt32Array = PackedInt32Array()      ## lazy memo of Sphere.neighbours8 for face-border cells
var _nb8_n: PackedByteArray = PackedByteArray()      ## 0 = not computed, else 7 or 8
var _cone: float = 0.0                               ## bound on a cell's angular circumradius
var _r_min: float = 0.0


func _init(store: EntityStore, projectiles: ProjectileStore) -> void:
	assert(N == 1 << SHIFT)
	_store = store
	_proj = projectiles
	var e: int = cell_start.resize(CELL_COUNT + 1) | cell_count.resize(CELL_COUNT) | _fill.resize(CELL_COUNT)
	e |= cell_entities.resize(CELL_COUNT) | cell_items.resize(ITEM_CAP) | touched_cells.resize(ITEM_CAP) | ring.resize(25)
	e |= _nb8.resize(CELL_COUNT * 8) | _nb8_n.resize(CELL_COUNT)
	assert(e == OK)
	cell_count.fill(0)
	cell_entities.fill(0)
	_nb8_n.fill(0)
	var delta: float = PI * 0.5 / float(N)
	var margin: float = float(N - 1) / float(N)
	_r_min = Sphere.PLANET_RADIUS + Sphere.RELIEF_MIN
	ring1_m = 2.0 * _r_min * sin(asin(sin(delta) * sqrt(0.5)) * margin * 0.5)
	ring2_m = 2.0 * _r_min * sin(asin(sin(2.0 * delta) * sqrt(0.5)) * margin * 0.5)
	_cone = delta


## Tick step 7: counting sort of every live entity (structures, ships, ground, wrecks lists) and projectile.
func rebuild() -> void:
	for t: int in touched_count:
		cell_count[touched_cells[t]] = 0
		cell_entities[touched_cells[t]] = 0
	touched_count = 0
	max_entity_radius = 0.0
	_count_entities(_store.structures)
	_count_entities(_store.ships)
	_count_entities(_store.ground)
	_count_entities(_store.wrecks)
	_count_projectiles()
	var run: int = 0
	for t: int in touched_count:
		var c: int = touched_cells[t]
		cell_start[c] = run
		_fill[c] = run
		run += cell_count[c]
	item_count = run
	cell_start[CELL_COUNT] = run
	_scatter(_store.structures)
	_scatter(_store.ships)
	_scatter(_store.ground)
	_scatter(_store.wrecks)
	var base: int = EntityId.PROJECTILE_SLOT_MIN
	var phc: PackedInt32Array = _proj.hash_cell
	for i: int in _proj.live:
		var c: int = phc[i]
		cell_items[_fill[c]] = base + i
		_fill[c] += 1


## EntityIds of live items (kinds selected by MASK_* bits) whose position is within `radius` (3D) of `p`.
## Order: ring cells, then items in hash order; deterministic for identical state.
func ids_near(p: Vector3, radius: float, mask: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	if radius < 0.0:
		return out
	var r2: float = radius * radius
	if radius <= ring2_m:
		var n: int = ring_cells(cell_of(p), 1 if radius <= ring1_m else 2)
		for k: int in n:
			_collect(ring[k], p, r2, mask, out)
		return out
	var theta: float = PI if radius >= 2.0 * _r_min else 2.0 * asin(radius / (2.0 * _r_min))
	for t: int in touched_count:
		var c: int = touched_cells[t]
		if Sphere.cell_center_dir(c, N).angle_to(p) <= theta + _cone:
			_collect(c, p, r2, mask, out)
	return out


## EntityIds of every item hashed into `cell` (a GRID_HASH cell id) by the last rebuild.
func ids_in_hash_cell(cell: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	if cell < 0 or cell >= CELL_COUNT:
		return out
	var s: int = cell_start[cell]
	for k: int in cell_count[cell]:
		var _a: bool = out.push_back(item_id(cell_items[s + k]))
	return out


## EntityId of a hash item (store slot or PROJECTILE_SLOT_MIN + projectile index).
func item_id(item: int) -> int:
	if item >= EntityId.PROJECTILE_SLOT_MIN:
		return _proj.id_of(item - EntityId.PROJECTILE_SLOT_MIN)
	return _store.id_of(item)


## Ring of `cell` for k in {1, 2} into the scratch `ring`; returns the cell count (9 / 25 inside
## a face, fewer at cube corners). Allocation-free: interior cells by index arithmetic, face-border cells through
## a lazily filled neighbours8 memo, ring 2 there as the union of the rings 1 of ring 1.
func ring_cells(cell: int, k: int) -> int:
	var i: int = cell & (N - 1)
	var j: int = (cell >> SHIFT) & (N - 1)
	if i >= k and j >= k and i < N - k and j < N - k:
		var n: int = 0
		for dj: int in range(-k, k + 1):
			for di: int in range(-k, k + 1):
				ring[n] = cell + dj * N + di
				n += 1
		return n
	ring[0] = cell
	var count: int = _append_nb8(cell, 1)
	if k < 2:
		return count
	var first: int = count
	for r: int in first:
		count = _append_nb8(ring[r], count)
	return count


func _append_nb8(cell: int, count: int) -> int:
	var n8: int = _nb8_n[cell]
	if n8 == 0:
		var nb: PackedInt32Array = Sphere.neighbours8(cell, N)   # once per border cell per Spatial
		n8 = nb.size()
		for q: int in n8:
			_nb8[cell * 8 + q] = nb[q]
		_nb8_n[cell] = n8
	var out: int = count
	for q: int in n8:
		var c: int = _nb8[cell * 8 + q]
		var seen: bool = false
		for r: int in out:
			if ring[r] == c:
				seen = true
				break
		if not seen:
			ring[out] = c
			out += 1
	return out


func _count_entities(list: PackedInt32Array) -> void:
	var pos: PackedVector3Array = _store.pos
	var rad: PackedFloat32Array = _store.radius
	var hc: PackedInt32Array = _store.hash_cell
	_store.hash_cell = PackedInt32Array()          # sole owner while writing: no copy-on-write
	var max_r: float = max_entity_radius
	for s: int in list:
		var c: int = cell_of(pos[s])
		hc[s] = c
		if cell_count[c] == 0:
			touched_cells[touched_count] = c
			touched_count += 1
		cell_count[c] += 1
		cell_entities[c] += 1
		max_r = maxf(max_r, rad[s])
	_store.hash_cell = hc
	max_entity_radius = max_r


func _count_projectiles() -> void:
	var pos: PackedVector3Array = _proj.pos
	var hc: PackedInt32Array = _proj.hash_cell
	_proj.hash_cell = PackedInt32Array()
	for i: int in _proj.live:
		var c: int = cell_of(pos[i])
		hc[i] = c
		if cell_count[c] == 0:
			touched_cells[touched_count] = c
			touched_count += 1
		cell_count[c] += 1
	_proj.hash_cell = hc


## Sphere.cell_of(p, GRID_HASH), bit-identical, with the face frames of 03 s2.5 unrolled (the static call pair costs
## more than the arithmetic on the rebuild path; test_spatial.gd asserts equality at edges, corners and ties).
static func cell_of(p: Vector3) -> int:
	var ax: float = absf(p.x)
	var ay: float = absf(p.y)
	var az: float = absf(p.z)
	var f: int = 0
	var u: float = 0.0
	var v: float = 0.0
	if ax >= ay and ax >= az:
		f = 0 if p.x > 0.0 else 1
		u = p.y * (1.0 / p.x) if f == 0 else p.z * (1.0 / -p.x)
		v = p.z * (1.0 / p.x) if f == 0 else p.y * (1.0 / -p.x)
	elif ay >= az:
		f = 2 if p.y > 0.0 else 3
		u = p.z * (1.0 / p.y) if f == 2 else p.x * (1.0 / -p.y)
		v = p.x * (1.0 / p.y) if f == 2 else p.z * (1.0 / -p.y)
	else:
		f = 4 if p.z > 0.0 else 5
		u = p.x * (1.0 / p.z) if f == 4 else p.y * (1.0 / -p.z)
		v = p.y * (1.0 / p.z) if f == 4 else p.x * (1.0 / -p.z)
	var i: int = mini(int((atan(u) * _FOUR_OVER_PI + 1.0) * 0.5 * float(N)), N - 1)
	var j: int = mini(int((atan(v) * _FOUR_OVER_PI + 1.0) * 0.5 * float(N)), N - 1)
	return (f * N + j) * N + i


func _scatter(list: PackedInt32Array) -> void:
	var hc: PackedInt32Array = _store.hash_cell
	for s: int in list:
		var c: int = hc[s]
		cell_items[_fill[c]] = s
		_fill[c] += 1


func _collect(c: int, p: Vector3, r2: float, mask: int, out: PackedInt32Array) -> void:
	var s0: int = cell_start[c]
	for k: int in cell_count[c]:
		var item: int = cell_items[s0 + k]
		if item >= EntityId.PROJECTILE_SLOT_MIN:
			var i: int = item - EntityId.PROJECTILE_SLOT_MIN
			if (mask & MASK_PROJECTILE) != 0 and _proj.pos[i].distance_squared_to(p) <= r2:
				var _a: bool = out.push_back(_proj.id_of(i))
		elif (mask & (1 << _store.kind[item])) != 0 and _store.pos[item].distance_squared_to(p) <= r2:
			var _b: bool = out.push_back(_store.id_of(item))
