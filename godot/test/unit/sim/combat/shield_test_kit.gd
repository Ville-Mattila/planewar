class_name ShieldTestKit extends RefCounted
## Fixtures for the GD-10 tests: EconomyTestKit's solo world (player 0 team 0 with the C2-14 start kit, the Core at +X),
## player 1 (Vanguard) and player 3 (Foundry) on team 1, a Reactor on the far side that keeps team 0 at power ratio 1,
## Shield Projectors placed `east` metres along +Y, and bombs / rockets written into the pool so that their last step
## enters (or starts inside) a dome. Every helper drains the pending events first (WorldTestKit.spawn returns the first SPAWN).

const R: float = Sphere.PLANET_RADIUS


static func world(reactor: bool = true, rules: MatchRules = null) -> SimWorld:
	var w: SimWorld = EconomyTestKit.solo_world(true, 7, rules)
	w.add_player(3, 1, &"foundry", PlayerTable.KIND_HUMAN)
	if reactor:
		var _r: int = put(w, &"reactor", Vector3(-R, 0.0, 0.0))
	w.step()
	return w


## Spawns `def` for `owner` (team 0 for player 0, else team 1) at `p`; returns its EntityId.
static func put(w: SimWorld, def: StringName, p: Vector3, owner: int = 0) -> int:
	var _old: Array[SimEvent] = w.drain_events()
	return WorldTestKit.spawn(w, def, owner, 0 if owner == 0 else 1, p)


static func projector(w: SimWorld, east: float, owner: int = 0) -> int:
	var id: int = put(w, &"shield_projector", WorldTestKit.at(0.0, east), owner)
	w.step()
	return EntityId.slot(id)


static func core_slot(w: SimWorld, owner: int = 0) -> int:
	return EconomyTestKit.find(w, &"core", owner)


## A bomb / rocket / siege shell of `owner` (team 0 only for player 0) whose last step went from `from_out` m outside
## the dome of `slot` to `into` m inside it, straight down the dome's up axis.
static func shot(w: SimWorld, slot: int, proj: StringName = &"bomb", weapon: StringName = &"bomb", owner: int = 1,
		from_out: float = 2.0, into: float = 2.0) -> int:
	var c: Vector3 = w.store().pos[slot]
	var up: Vector3 = c.normalized()
	var r: float = w.shields().dome_radius(slot)
	var id: int = CombatTestKit.shot(w, proj, weapon, c + up * (r - into), owner, 0 if owner == 0 else 1)
	w.projectiles().prev_pos[w.projectiles().index_of(id)] = c + up * (r + from_out)
	return id


## Rule 6 at the world's current tick: how many projectiles the domes absorbed.
static func absorb(w: SimWorld) -> int:
	return w.shields().absorb(w.tick())


static func kinds(events: Array[SimEvent], kind: SimEvent.Kind) -> int:
	return EconomyTestKit.count_kind(events, kind)


static func sdef(id: StringName) -> StructureDef:
	return WorldTestKit.content().structures[WorldTestKit.def_id(id) - DefRanges.STRUCTURE_BASE]
