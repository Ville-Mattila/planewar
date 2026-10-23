class_name Ai14Kit extends RefCounted
## AI-14 fixtures: the shipped defs plus `ai14_autopilots.json` (ap_dart of AI-13 and every block the Lancer, Bomber
## and Scout brains read; needs content AI-19), a SimWorld on them (players 0 and 2 on team 0, 1 on team 1), and an
## AiDriver whose Dart / Lancer / Bomber / Scout classes run their brains with their overlays and the per-team intel
## (AI-22 TeamIntel on the ai22 fixture, teams 0 and 1 tracked). Spawn and geometry helpers are DartKit's (same defs).

const AUTOPILOTS: String = "res://test/sim/ai/ai14_autopilots.json"

static var _content: ContentSet = null


static func content() -> ContentSet:
	if _content == null:
		var texts: Dictionary = {}
		for f: String in DirAccess.get_files_at(FlightTestKit.REAL_DEFS_DIR):
			if f.ends_with(".json"):
				texts[f] = FileAccess.get_file_as_string(FlightTestKit.REAL_DEFS_DIR + f)
		texts["autopilots.json"] = FileAccess.get_file_as_string(AUTOPILOTS)
		_content = ContentLoader.build(texts, {})
		assert(_content.ok(), "defs + AI-14 autopilots must load: %s" % str(_content.errors))
	return _content


static func ship(id: StringName) -> ShipDef:
	for sd: ShipDef in content().ships:
		if sd.id == id:
			return sd
	return null


static func structure(id: StringName) -> StructureDef:
	for sd: StructureDef in content().structures:
		if sd.id == id:
			return sd
	return null


static func ap(id: StringName) -> Dictionary:
	return BridgeParams.autopilot_raw(content(), ship(id).autopilot)


static func cls(def: StringName) -> int:
	return AiClassTable.class_of(AiClassTable.from_content(content()), DartKit.def_id(def))


static func world(seed_value: int = 7, map_id: StringName = &"") -> SimWorld:
	var w: SimWorld = SimWorld.new(content())
	var map: MapDef = MapDef.new()
	map.id = map_id
	var res: Result = w.load_map(map, seed_value, DartKit.rules())
	assert(res.ok, res.message)
	w.add_player(0, 0, &"", PlayerTable.KIND_HUMAN)
	w.add_player(1, DartKit.FOE, &"vanguard", PlayerTable.KIND_HUMAN)
	w.add_player(2, 0, &"", PlayerTable.KIND_BOT)
	return w


static func lancer(t: Terrain) -> LancerBrain:
	var b: LancerBrain = LancerBrain.create(content(), ap(&"lancer"), ship(&"lancer"), t, FormationKit.ring2_m())
	assert(b != null, "ai14_autopilots.json must build the Lancer brain")
	return b


static func bomber(t: Terrain) -> BomberBrain:
	var b: BomberBrain = BomberBrain.create(content(), ap(&"bomber"), ship(&"bomber"), t, FormationKit.ring2_m())
	assert(b != null, "ai14_autopilots.json must build the Bomber brain")
	return b


static func scout(t: Terrain) -> ScoutBrain:
	var b: ScoutBrain = ScoutBrain.create(content(), ap(&"scout"), ship(&"scout"), t, FormationKit.ring2_m())
	assert(b != null, "ai14_autopilots.json must build the Scout brain")
	return b


static func dart(t: Terrain) -> DartBrain:
	var b: DartBrain = DartBrain.from_content(content(), ap(&"dart"), ship(&"dart"), t, FormationKit.ring2_m())
	assert(b != null, "ai14_autopilots.json must build the Dart brain")
	return b


static func overlays(def: StringName) -> OverlayParams:
	var c: ContentSet = content()
	return OverlayParams.for_ship(ap(def), ship(def), c.rules, c.rules.tick_hz, c.flight_common)


## AiDriver on `w` with the four ship brains, their overlays, SPAWN registration by def, the world's terrain and (when
## `with_intel`) the per-team intel for teams 0 and 1. Brains not wanted: pass false in `which` (dart, lancer,
## bomber, scout).
static func driver(w: SimWorld, with_intel: bool = true, rng_seed: int = 3, which: Array[bool] = [true, true, true, true]) -> AiDriver:
	var d: AiDriver = make_driver(w.terrain(), with_intel, rng_seed, which)
	w.set_ai_hook(d)
	return d


## The same driver, not hooked (a restore configures it before SimWorld.deserialize, as a session does).
static func make_driver(t: Terrain, with_intel: bool = true, rng_seed: int = 3, which: Array[bool] = [true, true, true, true]) -> AiDriver:
	var d: AiDriver = AiDriver.new(Rng.new(rng_seed))
	d.set_class_table(AiClassTable.from_content(content()))
	var defs: Array[StringName] = [&"dart", &"lancer", &"bomber", &"scout"]
	var brains: Array[AiBrain] = [dart(t), lancer(t), bomber(t), scout(t)]
	for i: int in 4:
		if which[i]:
			d.set_brain(cls(defs[i]), brains[i])
			d.set_overlay_params(cls(defs[i]), overlays(defs[i]))
	d.set_terrain(t)
	if with_intel:
		var intel: TeamIntel = TeamIntel.new(IntelKit.tables(), IntelKit.profile("team"), content().rules.tick_hz)
		intel.track(0, true)
		intel.track(DartKit.FOE, true)
		d.set_intel(intel)
	return d


## A Core of `team` on the ground under `dir` (its pad is a home pad). The Core keeps its real collision radius
## (WorldDefs.radius_of, 52.07 m); a ship above its deck is not RAM-tested against it (R0 B.21 A-109).
static func core(w: SimWorld, dir: Vector3, team: int) -> int:
	var p: Vector3 = DartKit.above(w, dir, 0.0)
	return DartKit.spawn(w, &"core", team, p, Vector3.ZERO, DartKit.heading(p, Vector3(0, 1, 0)))


## The brain the driver runs for `def` (tests read its counters).
static func brain_of(d: AiDriver, def: StringName) -> AiBrain:
	return d._brains[cls(def)]


## Steps `w` once and drains its events.
static func step(w: SimWorld) -> Array[SimEvent]:
	w.step()
	return w.drain_events()
