class_name CombatTestKit extends RefCounted
## Shared fixtures for the GD-08 tests: a SimWorld over the shipped defs (WorldTestKit) with five players (slot 3
## Foundry and slot 4 Bulwark on team 1 next to the Vanguard slot 1), entities placed exactly (no gravity drift),
## and projectiles written straight into the pool (weapon fire is GD-36's).

const R: float = Sphere.PLANET_RADIUS
const _KIND: Dictionary = {
	&"slug_light": ProjectileStore.SLUG, &"slug_heavy": ProjectileStore.SLUG, &"bomb": ProjectileStore.BOMB,
	&"rocket": ProjectileStore.ROCKET, &"flak_shell": ProjectileStore.FLAK, &"rail_slug": ProjectileStore.RAIL,
	&"siege_shell": ProjectileStore.SIEGE_SHELL,
}


static func world(seed_value: int = 7, rules: MatchRules = null) -> SimWorld:
	var w: SimWorld = WorldTestKit.world(seed_value, rules)
	w.add_player(3, 1, &"foundry", PlayerTable.KIND_HUMAN)
	w.add_player(4, 1, &"bulwark", PlayerTable.KIND_HUMAN)
	return w


## GD-13: a Reactor on the far side of the moon for `owner` / `team` keeps the team at power ratio 1, so its towers are online.
static func power(w: SimWorld, owner: int, team: int) -> void:
	var _id: int = WorldTestKit.spawn(w, &"reactor", owner, team, Vector3(-R, 0.0, 0.0))


## GD-18: an Outpost for `owner` / `team` at `p` is a supply root (radius 400 m, +5 power): towers within it are supplied.
## Without a root every tower is outside the network and fires at the unsupplied rate (02 s5.4).
## The refill is switched off: the fire tests count shots by ammo drops, which a +10 per s refill would blur.
static func feed(w: SimWorld, owner: int, team: int, p: Vector3) -> int:
	w.economy().supply.refill = false
	return WorldTestKit.spawn(w, &"outpost", owner, team, p)


## Spawns `def` and pins it at `p` at rest (up = radial). Returns the EntityId.
static func spawn(w: SimWorld, def: StringName, owner: int, team: int, p: Vector3) -> int:
	var id: int = WorldTestKit.spawn(w, def, owner, team, p)
	var s: int = EntityId.slot(id)
	w.store().pos[s] = p
	w.store().vel[s] = Vector3.ZERO
	return id


## Teleports a spawned entity (zero velocity) to `p`.
static func move(w: SimWorld, id: int, p: Vector3) -> void:
	var s: int = EntityId.slot(id)
	w.store().pos[s] = p
	w.store().vel[s] = Vector3.ZERO


## Docks ship `ship` in structure `home` (DOCKED flag + link), as Docking will.
static func dock(w: SimWorld, ship: int, home: int) -> void:
	var s: int = EntityId.slot(ship)
	w.store().flags[s] |= EntityStore.F_DOCKED
	w.store().link[s] = home


## A projectile of `proj` fired from weapon `weapon` by `shooter` (owner slot / team), `age` seconds old.
static func shot(w: SimWorld, proj: StringName, weapon: StringName, p: Vector3, owner: int, team: int,
		shooter: int = 0, age: float = 1.0) -> int:
	var c: ContentSet = WorldTestKit.content()
	var ps: ProjectileStore = w.projectiles()
	var id: int = ps.alloc(int(_KIND[proj]), w.tick())
	var i: int = ps.index_of(id)
	var pd: ProjectileDef = c.projectiles[int(c.projectile_index[proj]) - DefRanges.PROJECTILE_BASE]
	ps.projectile_def[i] = int(c.projectile_index[proj]) - DefRanges.PROJECTILE_BASE
	ps.weapon_def[i] = int(c.weapon_index[weapon]) - DefRanges.WEAPON_BASE
	ps.pos[i] = p
	ps.prev_pos[i] = p
	ps.vel[i] = Vector3.ZERO
	ps.owner[i] = owner
	ps.team[i] = team
	ps.shooter[i] = shooter
	ps.ttl[i] = pd.lifetime_s - age
	return id


## The weapon `id` as a player with `doctrine` fields it (resolved copy; "" = the base def).
static func weapon(doctrine: StringName, id: StringName) -> WeaponDef:
	var c: ContentSet = WorldTestKit.content()
	var d: WorldDefs = WorldDefs.new(c)
	var ok: bool = d.resolve(0, doctrine)
	assert(ok)
	return d.resolved(0).weapon(int(c.weapon_index[id]))


static func of_kind(events: Array[SimEvent], kind: SimEvent.Kind) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for e: SimEvent in events:
		if e.kind == kind:
			out.append(e)
	return out


static func hp(w: SimWorld, id: int) -> float:
	return w.store().hp[EntityId.slot(id)]


static func alive(w: SimWorld, id: int) -> bool:
	return w.store().alive(id)
