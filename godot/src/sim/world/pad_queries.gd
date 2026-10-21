class_name PadQueries extends RefCounted
## Pad reads of `LocalSimView` (A-73 extraction): occupant of a pad and the nearest friendly pad. Static, allocation-free.


## The docked ship linked to `pad`, or 0. A launch-only pad (no `pad_radius_m`, the Shipyard; A-19) has no occupant.
static func occupant(store: EntityStore, defs: WorldDefs, pad: int) -> int:
	if not store.alive(pad) or not serves(store, defs, EntityId.slot(pad)):
		return 0
	for s: int in store.ships:
		if (store.flags[s] & EntityStore.F_DOCKED) != 0 and store.link[s] == pad:
			return store.id_of(s)
	return 0


## True when the structure def at slot `s` has a service pad (`pad_radius_by_def` > 0).
static func serves(store: EntityStore, defs: WorldDefs, s: int) -> bool:
	var d: int = store.def_id[s]
	return d < defs.pad_radius_by_def.size() and defs.pad_radius_by_def[d] > 0.0


## Nearest live friendly structure with a pad to entity `id`, or 0.
static func nearest_friendly(store: EntityStore, defs: WorldDefs, id: int) -> int:
	if not store.alive(id):
		return 0
	var s0: int = EntityId.slot(id)
	var p: Vector3 = store.pos[s0]
	var best: int = 0
	var best_d2: float = INF
	for s: int in store.structures:
		if store.team[s] != store.team[s0] or not serves(store, defs, s):
			continue
		var d2: float = p.distance_squared_to(store.pos[s])
		if d2 < best_d2:
			best_d2 = d2
			best = store.id_of(s)
	return best
