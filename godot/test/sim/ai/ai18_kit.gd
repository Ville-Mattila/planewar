class_name Ai18Kit extends RefCounted
## AI-18 fixtures: the shipped defs (`ap_crawler` with its required `follow` block, R0 B.29 A-145), a SimWorld on them
## (`Ai16Kit.world`: players 0 and 2 on team 0, 1 on team 1), an AiDriver whose Siege Crawler class runs `CrawlerBrain`
## with the ground SAFETY overlay, and probes for the shells the sim spawns. Placement is `Ai16Kit.put` (metres of arc
## along +Y from +X). AI-18b: a world on the shipped defs with `siege_gun.spread_deg` 0 (`BarrelTestKit.no_spread_content`:
## the 1.5 deg spread moves an impact ~90 m, so the on-target scenario turns it off) and the impact point of every shell.


static func content() -> ContentSet:
	return Ai16Kit.content()


static func ap() -> Dictionary:
	return BridgeParams.autopilot_raw(content(), &"ap_crawler")


static func def() -> GroundUnitDef:
	return Ai16Kit.ground_def(&"siege_crawler")


static func cls() -> int:
	return AiClassTable.class_of(AiClassTable.from_content(content()), DartKit.def_id(&"siege_crawler"))


static func brain(t: Terrain) -> CrawlerBrain:
	var b: CrawlerBrain = CrawlerBrain.create(content(), ap(), def(), t)
	assert(b != null, "autopilots.json ap_crawler must build the Crawler brain")
	return b


## The driver with the Crawler brain (and `harvester` too when given) and the ground overlay, hooked into `w`; Crawlers
## spawned before the hook was set are registered.
static func driver(w: SimWorld, b: CrawlerBrain = null, rng_seed: int = 3) -> AiDriver:
	var d: AiDriver = AiDriver.new(Rng.new(rng_seed))
	configure(d, b if b != null else brain(w.terrain()))
	d.set_terrain(w.terrain())
	w.set_ai_hook(d)
	var cid: int = DartKit.def_id(&"siege_crawler")
	for s: int in w.store().ground:
		if w.store().def_id[s] == cid:
			var _r: bool = d.register(w.store().id_of(s), cls())
	return d


## The session configuration of a driver (before `SimWorld.deserialize` on a restore).
static func configure(d: AiDriver, b: CrawlerBrain) -> void:
	var c: ContentSet = content()
	d.set_class_table(AiClassTable.from_content(c))
	d.set_brain(cls(), b)
	d.set_overlay_params(cls(), OverlayParams.for_ground(ap(), c.rules, c.rules.tick_hz))


## Live siege shells of team `team` (ProjectileStore indices).
static func shells(w: SimWorld, team: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var ps: ProjectileStore = w.projectiles()
	for i: int in ps.live:
		if ps.kind[i] == ProjectileStore.SIEGE_SHELL and ps.team[i] == team:
			var _a: bool = out.push_back(i)
	return out


## Drops an enemy (team `team`) bomb from 30 m above the surface point `dir`, falling straight down, owned by player
## `owner`; returns the projectile index.
static func bomb(w: SimWorld, dir: Vector3, team: int, owner: int, shooter: int) -> int:
	var p: Vector3 = dir * (Sphere.PLANET_RADIUS + w.terrain().height_at(dir) + 30.0)
	var c: ContentSet = content()
	var pi: int = c.projectile_index.get(&"bomb", -1)
	var wi: int = c.weapon_index.get(&"bomb", -1)
	return w.projectiles().spawn(ProjectileStore.BOMB, w.tick(), p, -dir * 20.0, 10.0, pi - DefRanges.PROJECTILE_BASE,
		wi - DefRanges.WEAPON_BASE, owner, team, shooter, 0, 0)


## `Ai16Kit.world` on `c` (the shipped defs when null; `BarrelTestKit.no_spread_content()` for the on-target scenario).
static func world(c: ContentSet, seed_value: int, map_id: StringName) -> SimWorld:
	if c == null:
		return Ai16Kit.world(seed_value, map_id)
	var w: SimWorld = SimWorld.new(c)
	var map: MapDef = MapDef.new()
	map.id = map_id
	var res: Result = w.load_map(map, seed_value, DartKit.rules())
	assert(res.ok, res.message)
	w.add_player(0, 0, &"", PlayerTable.KIND_HUMAN)
	w.add_player(1, DartKit.FOE, &"vanguard", PlayerTable.KIND_HUMAN)
	w.add_player(2, 0, &"", PlayerTable.KIND_BOT)
	return w


## The index of this tick's first collision contact of projectile `pid` (GROUND or a hit), or -1.
static func contact(w: SimWorld, pid: int) -> int:
	var col: Collision = w.collision
	for c: int in col.contact_count:
		if col.c_a[c] == pid:
			return c
	return -1


## Where a shell spawned at `at` with velocity `v` meets the ground, flown at the sim's one-tick step for its lifetime
## (`Ballistics.predict_impact`, which GD-50 checked against the sim within 3 m): its ballistic landing point, also for a
## shell that struck a body on the way. ZERO without an impact.
static func ground_point(w: SimWorld, at: Vector3, v: Vector3) -> Vector3:
	var c: ContentSet = content()
	var pd: ProjectileDef = c.projectiles[int(c.projectile_index[&"siege_shell"]) - DefRanges.PROJECTILE_BASE]
	var dt: float = 1.0 / float(c.rules.tick_hz)
	var r: Vector4 = Ballistics.predict_impact(at, v, pd, c.rules, w.terrain(), dt, dt, 0.0,
		ceili(pd.lifetime_s * float(c.rules.tick_hz)), ProjectileState.new())
	return Vector3(r.x, r.y, r.z) if Ballistics.has_impact(r) else Vector3.ZERO
