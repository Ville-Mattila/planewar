class_name Ai18Kit extends RefCounted
## AI-18 fixtures: the shipped defs (`ap_crawler` with its required `follow` block, R0 B.29 A-145), a SimWorld on them
## (`Ai16Kit.world`: players 0 and 2 on team 0, 1 on team 1), an AiDriver whose Siege Crawler class runs `CrawlerBrain`
## with the ground SAFETY overlay, and probes for the shells the sim spawns. Placement is `Ai16Kit.put` (metres of arc
## along +Y from +X).


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
