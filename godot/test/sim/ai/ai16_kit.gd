class_name Ai16Kit extends RefCounted
## AI-16 fixtures: the shipped defs plus the AI-14 autopilot fixture with its `ap_harvester` replaced by
## `ai16_autopilots.json` (needs content AI-19), a SimWorld on them (players 0 and 2 on team 0, 1 on team 1; flat datum or a
## map), an AiDriver whose Harvester class runs `HarvesterBrain` with the ground SAFETY overlay, and placement helpers by
## metres of arc along +Y from +X (the HarvestTestKit convention). The sim runs the real Pathing, GroundMotion and Harvest.

const AUTOPILOTS: String = "res://test/sim/ai/ai16_autopilots.json"
const R: float = Sphere.PLANET_RADIUS

static var _content: ContentSet = null


static func content() -> ContentSet:
	if _content == null:
		var texts: Dictionary = {}
		for f: String in DirAccess.get_files_at(FlightTestKit.REAL_DEFS_DIR):
			if f.ends_with(".json"):
				texts[f] = FileAccess.get_file_as_string(FlightTestKit.REAL_DEFS_DIR + f)
		var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Ai14Kit.AUTOPILOTS))
		var extra: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AUTOPILOTS))
		var list: Array = base["autopilots"]
		for i: int in list.size():
			var ap: Dictionary = list[i]
			if ap["id"] == "ap_harvester":
				list[i] = (extra["autopilots"] as Array)[0]
		texts["autopilots.json"] = JSON.stringify(base)
		_content = ContentLoader.build(texts, {})
		assert(_content.ok(), "defs + AI-16 autopilots must load: %s" % str(_content.errors))
	return _content


static func ground_def(id: StringName = &"harvester") -> GroundUnitDef:
	for gd: GroundUnitDef in content().ground_units:
		if gd.id == id:
			return gd
	return null


static func ap() -> Dictionary:
	return BridgeParams.autopilot_raw(content(), &"ap_harvester")


static func cls() -> int:
	return AiClassTable.class_of(AiClassTable.from_content(content()), DartKit.def_id(&"harvester"))


static func brain() -> HarvesterBrain:
	var b: HarvesterBrain = HarvesterBrain.create(content(), ap(), ground_def())
	assert(b != null, "ai16_autopilots.json must build the Harvester brain")
	return b


## A world on the AI-16 content; `map_id` "" = the flat datum.
static func world(seed_value: int = 7, map_id: StringName = &"", r: MatchRules = null) -> SimWorld:
	var w: SimWorld = SimWorld.new(content())
	var map: MapDef = MapDef.new()
	map.id = map_id
	var res: Result = w.load_map(map, seed_value, r if r != null else DartKit.rules())
	assert(res.ok, res.message)
	w.add_player(0, 0, &"", PlayerTable.KIND_HUMAN)
	w.add_player(1, DartKit.FOE, &"vanguard", PlayerTable.KIND_HUMAN)
	w.add_player(2, 0, &"", PlayerTable.KIND_BOT)
	return w


## The driver with the Harvester brain and the ground overlay, hooked into `w`; the fields already added to `w` are bound.
static func driver(w: SimWorld, b: HarvesterBrain = null, rng_seed: int = 3) -> AiDriver:
	var d: AiDriver = AiDriver.new(Rng.new(rng_seed))
	var c: ContentSet = content()
	var hb: HarvesterBrain = b if b != null else brain()
	hb.bind_fields(w.economy().harvest.fields)
	d.set_class_table(AiClassTable.from_content(c))
	d.set_brain(cls(), hb)
	d.set_overlay_params(cls(), OverlayParams.for_ground(ap(), c.rules, c.rules.tick_hz))
	d.set_terrain(w.terrain())
	w.set_ai_hook(d)
	var hid: int = DartKit.def_id(&"harvester")
	for s: int in w.store().ground:   # Harvesters spawned before the hook was set missed their SPAWN event
		if w.store().def_id[s] == hid:
			var _r: bool = d.register(w.store().id_of(s), cls())
	return d


static func dir_at(east: float, north: float = 0.0) -> Vector3:
	var a: float = east / R
	var b: float = north / R
	return Vector3(cos(a) * cos(b), sin(a) * cos(b), sin(b)).normalized()


## Spawns `def` of `team` (owner 0 / 1) on the ground at arc (`east`, `north`) m, facing +Y; steps once; returns the id.
static func put(w: SimWorld, def: StringName, team: int, east: float, north: float = 0.0) -> int:
	var d: Vector3 = dir_at(east, north)
	var p: Vector3 = d * (R + w.terrain().height_at(d))
	var fwd: Vector3 = DartKit.heading(p, dir_at(east + 100.0, north) * R)
	return Ai17Kit.spawn_many(w, def, team, p, Vector3.ZERO, fwd)


static func field(w: SimWorld, east: float, north: float = 0.0, capacity: int = 6000, regen: float = 2.0, radius: float = 150.0,
		max_miners: int = 4) -> int:
	return w.economy().harvest.fields.add(dir_at(east, north), capacity, regen, radius, max_miners)


static func step(w: SimWorld, n: int = 1) -> void:
	for _i: int in n:
		w.step()
		var _e: Array[SimEvent] = w.drain_events()


static func delivered(w: SimWorld, player: int = 0) -> int:
	return w.economy().build.delivered_ore[player]


## Flat distance in metres between two entities.
static func apart(w: SimWorld, a: int, b: int) -> float:
	return GroundFollower.flat(w.view().pos(a), w.view().pos(b))
