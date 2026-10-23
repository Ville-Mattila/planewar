class_name Ai17Kit extends RefCounted
## AI-17 fixtures: the shipped defs plus the AI-14 autopilot fixture and `ai17_autopilots.json` (`ap_tower`; needs
## content AI-19), a SimWorld on them (players 0 and 2 on team 0, 1 on team 1) and an AiDriver whose tower class runs
## `TowerBrain` with the per-team intel (teams 0 and 1 tracked). The sim does not slew a turret yet (GD-09), so the
## driver is a `SlewDriver`: it hands the brain a sink that also applies each tower's `pitch` / `yaw` drive to the
## entity's `fwd` / `up` (the GD-09 law stand-in: rate = stick x `turret_turn_dps` for one tick), inside step 3, so the
## sim fires along the slewed muzzle at step 9.

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
## `w` null: the store is set after `SimWorld.deserialize` (`d.store = w2.store()`).
static func make_driver(w: SimWorld, with_intel: bool = true, rng_seed: int = 3, b: TowerBrain = null) -> SlewDriver:
	var d: SlewDriver = SlewDriver.new(Rng.new(rng_seed))
	d.set_class_table(AiClassTable.from_content(content()))
	var tb: TowerBrain = b if b != null else brain()
	d.set_brain(tower_cls(), tb)
	d.store = w.store() if w != null else null
	d.turn = tb.prm
	d.dt = 1.0 / float(content().rules.tick_hz)
	if with_intel:
		var intel: TeamIntel = TeamIntel.new(IntelKit.tables(), IntelKit.profile("team"), content().rules.tick_hz)
		intel.track(0, true)
		intel.track(DartKit.FOE, true)
		d.set_intel(intel)
	return d


static func driver(w: SimWorld, with_intel: bool = true, rng_seed: int = 3, b: TowerBrain = null) -> SlewDriver:
	var d: SlewDriver = make_driver(w, with_intel, rng_seed, b)
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


class SlewSink extends CommandSinkBase:
	var inner: CommandSinkBase = null
	var store: EntityStore = null
	var prm: TowerParams = null
	var dt: float = 0.0

	func submit(cmd: Command) -> CommandResult:
		return inner.submit(cmd)

	func drive(id: int, input: PilotInput) -> bool:
		var ok: bool = inner.drive(id, input)
		var env: TowerEnvelope = prm.envelope(store.def_id[EntityId.slot(id)]) if ok and store != null else null
		if env != null and (input.pitch != 0.0 or input.yaw != 0.0):
			var s: int = EntityId.slot(id)
			var f: Vector3 = store.fwd[s]
			var u: Vector3 = store.up[s]
			var step: float = env.turn_rad_s * dt
			var q: Quaternion = Quaternion(f.cross(u), input.pitch * step) * Quaternion(u, input.yaw * step)
			store.fwd[s] = (q * f).normalized()
			store.up[s] = (q * u).normalized()
		return ok

	func set_ai_tag(id: int, tag: int) -> void:
		inner.set_ai_tag(id, tag)

	func end_overlay(id: int) -> void:
		inner.end_overlay(id)

	func pathing() -> Pathing:
		return inner.pathing()


class SlewDriver extends AiDriver:
	var store: EntityStore = null
	var turn: TowerParams = null
	var dt: float = 0.0
	var _slew: SlewSink = SlewSink.new()

	func on_tick(tick: int, view: SimView, sink: CommandSinkBase) -> void:
		_slew.inner = sink
		_slew.store = store
		_slew.prm = turn
		_slew.dt = dt
		super.on_tick(tick, view, _slew)
