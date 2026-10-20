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


## (supply, demand) from the signed `power` of the team's live, finished structures; a Solar Array's output is scaled by
## `Economy.solar_factor` at its position (02 s8.4, fixed sun along +Z).
static func power_balance(store: EntityStore, defs: WorldDefs, team: int) -> Vector2:
	var b: Vector2 = Vector2.ZERO
	for s: int in store.structures:
		if store.team[s] == team and (store.flags[s] & EntityStore.F_BUILDING) == 0:
			var sd: StructureDef = defs.resolved(store.owner[s]).structure(store.def_id[s])
			if sd != null:
				var pw: float = sd.power
				if sd.solar and defs.economy != null:
					pw *= Economy.solar_factor(store.up[s], Vector3.BACK, false, defs.economy.solar_band_deg, defs.economy.solar_plateau_mult)
				b += Vector2(maxf(pw, 0.0), maxf(-pw, 0.0))
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


## The player-table half of a `PlayerStateView` (counts are the caller's, they read the store).
static func fill_player(v: PlayerStateView, pl: PlayerTable, slot: int) -> void:
	v.slot = slot
	v.team = pl.team[slot]
	v.kind = pl.kind[slot]
	v.doctrine = StringName(pl.doctrine[slot])
	v.possessed = pl.possessed[slot]
	v.eliminated = pl.eliminated[slot] != 0
	v.commander_rights = pl.is_active(slot) and not v.eliminated
	v.connected = pl.connected[slot] != 0
	v.disconnect_tick = pl.disconnect_tick[slot]
	v.adjutant_profile = pl.adjutant_profile[slot]
	v.adjutant_toggles = pl.adjutant_toggles[slot]


## Live entities of `live` owned by player slot `player`.
static func count_owned(store: EntityStore, player: int, live: PackedInt32Array) -> int:
	var n: int = 0
	for s: int in live:
		if store.owner[s] == player:
			n += 1
	return n


## The whole `TeamStateView` of `team` refilled in place (no allocation; `members` is the view's own array).
static func fill_team(v: TeamStateView, team: int, store: EntityStore, defs: WorldDefs, pl: PlayerTable,
		rules: MatchRules, state: MatchState) -> void:
	v.team = team
	v.ore = pl.team_ore[team]
	v.ice = pl.team_ice[team]
	var cap: Vector2i = stockpile_cap(store, defs, team)
	v.ore_cap = cap.x
	v.ice_cap = cap.y
	var pb: Vector2 = power_balance(store, defs, team)
	v.power_supply = pb.x
	v.power_demand = pb.y
	v.unit_cap = rules.caps.units
	v.structure_cap = rules.caps.structures
	pl.members(team, v.members)
	v.eliminated = false
	v.flags = TeamStateView.CORE_EXPOSURE if state.exposure_tick >= 0 else 0
	if pb.x < pb.y:
		v.flags |= TeamStateView.LOW_POWER
