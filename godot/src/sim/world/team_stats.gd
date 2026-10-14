class_name TeamStats
## Team aggregates `LocalSimView` derives from the entity store and the doctrine-resolved defs (no cached state):
## storage caps, power balance, tech requirements, per-player counts. O(structures) per call; view reads, never
## on the tick path.


## Summed `storage_ore` / `storage_ice` of the team's live structures (R0 B.8 A-8).
static func stockpile_cap(store: EntityStore, defs: WorldDefs, team: int) -> Vector2i:
	var c: Vector2i = Vector2i.ZERO
	for s: int in store.structures:
		if store.team[s] == team:
			var sd: StructureDef = defs.resolved(store.owner[s]).structure(store.def_id[s])
			if sd != null:
				c += Vector2i(sd.storage_ore, sd.storage_ice)
	return c


## (supply, demand) from the signed `power` of the team's live, finished structures.
static func power_balance(store: EntityStore, defs: WorldDefs, team: int) -> Vector2:
	var b: Vector2 = Vector2.ZERO
	for s: int in store.structures:
		if store.team[s] == team and (store.flags[s] & EntityStore.F_BUILDING) == 0:
			var sd: StructureDef = defs.resolved(store.owner[s]).structure(store.def_id[s])
			if sd != null:
				b += Vector2(maxf(sd.power, 0.0), maxf(-sd.power, 0.0))
	return b


## True when every `requires` def of `def_id` has a live, finished structure on `team`.
static func tech_available(store: EntityStore, defs: WorldDefs, team: int, def_id: int) -> bool:
	var r: ResolvedDefs = defs.base
	var req: PackedStringArray = PackedStringArray()
	if r.ship(def_id) != null:
		req = r.ship(def_id).requires
	elif r.ground_unit(def_id) != null:
		req = r.ground_unit(def_id).requires
	elif r.structure(def_id) != null:
		req = r.structure(def_id).requires
	else:
		return false
	for need: String in req:
		var d: int = defs.content.entity_index.get(StringName(need), -1)
		if not has_structure(store, team, d):
			return false
	return true


static func has_structure(store: EntityStore, team: int, def_id: int) -> bool:
	for s: int in store.structures:
		if store.def_id[s] == def_id and store.team[s] == team and (store.flags[s] & EntityStore.F_BUILDING) == 0:
			return true
	return false


## Live entities of `live` owned by player slot `player`.
static func count_owned(store: EntityStore, player: int, live: PackedInt32Array) -> int:
	var n: int = 0
	for s: int in live:
		if store.owner[s] == player:
			n += 1
	return n
