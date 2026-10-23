class_name WreckPaths extends RefCounted
## GD-39 (R0 B.20 A-108; 03 s6.1): a resting wreck makes its path cell impassable (weight 255); hooked (F_TETHERED),
## delivered or expired it gives the cell its baked weight back, re-read from the map bake (`Pathing.baked_weight`,
## nothing stored, so S4 and FORMAT are untouched). Two wrecks on one cell keep it blocked until the last leaves: a
## leave scans the wreck list once (derived, per event only). `Salvage` calls this at the five points a wreck changes
## between resting and towed or gone; no per-tick work. No Nodes, no signals, no RNG.

const _NEAR_M: float = Sphere.PLANET_RADIUS * PI / float(PathGrid.N)   ## two path cells: wrecks nearer than this may share a cell

var pathing: Pathing = null     ## set by SimWorld; null (standalone Salvage) = no path effects
var sets: int = 0               ## Pathing.set_weight calls made (hard counter)
var scans: int = 0              ## wreck-list scans made by a leave (hard counter)
var reads: int = 0              ## baked-weight reads made (hard counter)

var _store: EntityStore
var _cells: PackedInt32Array = PackedInt32Array()   ## scratch: cells of wrecks that expired resting this pass


func _init(store: EntityStore) -> void:
	_store = store


## Wreck slot `w` comes to rest (spawned, or released from a tow): its cell is blocked.
func rest(w: int) -> void:
	if pathing != null:
		_put(PathGrid.cell_of(_store.pos[w]), PathGrid.W_BLOCKED)


## Wreck slot `w` was just flagged F_TETHERED: its cell is baked again unless another wreck rests there.
func lift(w: int) -> void:
	if pathing != null:
		_leave(PathGrid.cell_of(_store.pos[w]))


## A resting wreck `w` will be freed at the end of this pass: remember its cell for `settle`.
func defer(w: int) -> void:
	if pathing != null:
		var _a: bool = _cells.push_back(PathGrid.cell_of(_store.pos[w]))


## After the pass freed its wrecks: the deferred cells are baked again unless a wreck still rests there.
func settle() -> void:
	for c: int in _cells:
		_leave(c)
	var _n: int = _cells.resize(0)


func _leave(cell: int) -> void:
	if _shared(cell):
		return
	reads += 1
	_put(cell, pathing.baked_weight(cell))


# True when another live, untethered wreck rests on `cell` (pre-filtered by distance, then by the cell itself).
func _shared(cell: int) -> bool:
	scans += 1
	var centre: Vector3 = Sphere.cell_center_dir(cell, PathGrid.N) * Sphere.PLANET_RADIUS
	var limit: float = _NEAR_M * _NEAR_M
	for w: int in _store.wrecks:
		if (_store.flags[w] & (EntityStore.F_ALIVE | EntityStore.F_TETHERED)) != EntityStore.F_ALIVE:
			continue
		var p: Vector3 = _store.pos[w]
		if p.distance_squared_to(centre) <= limit and PathGrid.cell_of(p) == cell:
			return true
	return false


func _put(cell: int, weight: int) -> void:
	if pathing.weight(cell) != weight:
		pathing.set_weight(cell, weight)
		sets += 1
