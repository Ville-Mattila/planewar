class_name Ai17Kit extends RefCounted
## AI-17 fixtures: the shipped defs plus the AI-14 autopilot fixture and `ai17_autopilots.json` (`ap_tower`; needs
## content AI-19), a SimWorld on them (players 0 and 2 on team 0, 1 on team 1) and an AiDriver whose tower class runs
## `TowerBrain` with the per-team intel (teams 0 and 1 tracked). The sim slews the turret itself (GD-09, `TurretSlew`,
## R0 B.23 A-118 / B.24 A-123): the plain `AiDriver` writes `pitch` / `yaw` into the input slot and step 5 turns the
## muzzle, so the scenarios run against the real law (the AI-17 stand-in `AiDriver` is gone).

const AUTOPILOTS: String = "res://test/sim/ai/ai17_autopilots.json"

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
		list.append_array(extra["autopilots"] as Array)
		texts["autopilots.json"] = JSON.stringify(base)
		_content = ContentLoader.build(texts, {})
		assert(_content.ok(), "defs + AI-17 autopilots must load: %s" % str(_content.errors))
	return _content


static func ap_tower() -> Dictionary:
	for ap: AutopilotDef in content().autopilots:
		if ap.id == &"ap_tower":
			return ap.raw
	return {}


static func tower_cls() -> int:
	return AiClassTable.tower_class(content())


static func brain() -> TowerBrain:
	var b: TowerBrain = TowerBrain.create(content(), ap_tower())
	assert(b != null, "ai17_autopilots.json must build the tower brain")
	return b


static func world(seed_value: int = 7) -> SimWorld:
	var w: SimWorld = SimWorld.new(content())
	var map: MapDef = MapDef.new()
	var res: Result = w.load_map(map, seed_value, DartKit.rules())
	assert(res.ok, res.message)
	w.add_player(0, 0, &"", PlayerTable.KIND_HUMAN)
	w.add_player(1, DartKit.FOE, &"vanguard", PlayerTable.KIND_HUMAN)
	w.add_player(2, 0, &"", PlayerTable.KIND_BOT)
	return w


## The same driver unhooked (a restore configures it before SimWorld.deserialize, as a session does).
## `_w` is unused now (kept so callers keep their shape: a restore passes null).
static func make_driver(_w: SimWorld, with_intel: bool = true, rng_seed: int = 3, b: TowerBrain = null) -> AiDriver:
	var d: AiDriver = AiDriver.new(Rng.new(rng_seed))
	d.set_class_table(AiClassTable.from_content(content()))
	var tb: TowerBrain = b if b != null else brain()
	d.set_brain(tower_cls(), tb)
	if with_intel:
		var intel: TeamIntel = TeamIntel.new(IntelKit.tables(), IntelKit.profile("team"), content().rules.tick_hz)
		intel.track(0, true)
		intel.track(DartKit.FOE, true)
		d.set_intel(intel)
	return d


static func driver(w: SimWorld, with_intel: bool = true, rng_seed: int = 3, b: TowerBrain = null) -> AiDriver:
	var d: AiDriver = make_driver(w, with_intel, rng_seed, b)
	w.set_ai_hook(d)
	return d


## A tower of `def` for `team` `agl` m above the ground under `dir`, its muzzle on the horizon toward `look` (a world
## point). A raised tower (agl > 0) lets a target sit below it (negative h_rel) over the flat datum.
static func tower(w: SimWorld, def: StringName, team: int, dir: Vector3, look: Vector3, agl: float = 0.0) -> int:
	var p: Vector3 = DartKit.above(w, dir, agl)
	return DartKit.spawn(w, def, team, p, Vector3.ZERO, DartKit.heading(p, look))


## A point `h_rel` m above the tower's own radius, `east` m along the tangent from under it and `north` m the other way.
static func rel(w: SimWorld, id: int, east: float, north: float, h_rel: float) -> Vector3:
	var p: Vector3 = w.view().pos(id)
	var f: Basis = Sphere.tangent_frame(p.normalized())
	var q: Vector3 = p + f.x * east + f.y * north
	return q.normalized() * (p.length() + h_rel)


## DartKit.spawn that waits out the command rate limit (a scene of many entities); returns the id.
static func spawn_many(w: SimWorld, def: StringName, team: int, p: Vector3, v: Vector3, fwd: Vector3) -> int:
	var owner: int = 0 if team == 0 else 1
	var cmd: Command = CommandPayload.debug_spawn(owner, DartKit.def_id(def), owner, team, p, v, fwd)
	var code: int = w.apply_command(cmd).code
	while code == CommandResult.Code.REJECTED_RATE:
		w.step()
		var _e: Array[SimEvent] = w.drain_events()
		code = w.apply_command(cmd).code
	assert(code == CommandResult.Code.ACCEPTED, "spawn %s: %d" % [def, code])
	w.step()
	var id: int = 0
	for e: SimEvent in w.drain_events():
		if e.kind == SimEvent.Kind.SPAWN:
			id = e.a
	return id


static func step(w: SimWorld) -> Array[SimEvent]:
	w.step()
	return w.drain_events()


## Entity input slot `id`'s buttons as the sim holds them.
static func buttons(w: SimWorld, id: int) -> int:
	return w._inputs.e_buttons[EntityId.slot(id)]


## Projectiles alive that `id` fired.
static func shots_of(w: SimWorld, id: int) -> int:
	var n: int = 0
	var pr: ProjectileStore = w.projectiles()
	for i: int in pr.live:
		if pr.shooter[i] == id:
			n += 1
	return n
