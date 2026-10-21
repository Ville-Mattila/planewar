class_name DartKit extends RefCounted
## AI-13 fixtures: the shipped defs plus the autopilot fixture `ai13_autopilots.json` (ap_dart with every 05 s4.4 block
## and the AI-13 additions; needs content AI-19), a SimWorld on them (players 0 and 2 on team 0, 1 on team 1), an
## AiDriver whose Dart class runs `DartBrain` with its overlays, spawn helpers, and the SweepScenarios dive bound
## (`recoverable`) evaluated on the world's own terrain.

const AUTOPILOTS: String = "res://test/sim/ai/ai13_autopilots.json"
const CLS_DART: int = 0
const FOE: int = 1
const R: float = Sphere.PLANET_RADIUS

static var _content: ContentSet = null


static func content() -> ContentSet:
	if _content == null:
		var texts: Dictionary = {}
		for f: String in DirAccess.get_files_at(FlightTestKit.REAL_DEFS_DIR):
			if f.ends_with(".json"):
				texts[f] = FileAccess.get_file_as_string(FlightTestKit.REAL_DEFS_DIR + f)
		texts["autopilots.json"] = FileAccess.get_file_as_string(AUTOPILOTS)
		_content = ContentLoader.build(texts, {})
		assert(_content.ok(), "defs + AI-13 autopilots must load: %s" % str(_content.errors))
	return _content


static func ship(id: StringName) -> ShipDef:
	for sd: ShipDef in content().ships:
		if sd.id == id:
			return sd
	return null


static func def_id(id: StringName) -> int:
	return int(content().entity_index.get(id, -1))


static func ap(id: StringName = &"dart") -> Dictionary:
	return BridgeParams.autopilot_raw(content(), ship(id).autopilot)


static func params() -> DartParams:
	return DartParams.from_content(ap(), ship(&"dart"), content())


static func rules(units: int = 0) -> MatchRules:
	var r: MatchRules = WorldTestKit.rules()
	if units > 0:
		r.caps.units = units
	return r


## A world on the AI-13 content; `map_id` "" = flat datum, "cradle" = the cradle map.
static func world(seed_value: int = 7, map_id: StringName = &"", r: MatchRules = null) -> SimWorld:
	var w: SimWorld = SimWorld.new(content())
	var map: MapDef = MapDef.new()
	map.id = map_id
	var res: Result = w.load_map(map, seed_value, r if r != null else rules())
	assert(res.ok, res.message)
	w.add_player(0, 0, &"", PlayerTable.KIND_HUMAN)
	w.add_player(1, FOE, &"vanguard", PlayerTable.KIND_HUMAN)
	w.add_player(2, 0, &"", PlayerTable.KIND_BOT)
	return w


static func brain(w: SimWorld) -> DartBrain:
	var b: DartBrain = DartBrain.from_content(content(), ap(), ship(&"dart"), w.terrain(), FormationKit.ring2_m())
	assert(b != null, "ai13_autopilots.json must build the Dart brain")
	return b


## AiDriver with the Dart brain and overlays on the Dart class, SPAWN registration by def (A-71), the world's terrain.
static func driver(w: SimWorld, b: DartBrain = null, rng_seed: int = 3) -> AiDriver:
	var d: AiDriver = AiDriver.new(Rng.new(rng_seed))
	var c: ContentSet = content()
	d.set_class_table(AiClassTable.from_content(c))
	d.set_brain(CLS_DART, b if b != null else brain(w))
	d.set_overlay_params(CLS_DART, OverlayParams.for_ship(ap(), ship(&"dart"), c.rules, c.rules.tick_hz, c.flight_common))
	d.set_terrain(w.terrain())
	w.set_ai_hook(d)
	return d


## Queues a DEBUG_SPAWN of `def` for `owner` / `team` at `p`, velocity `v`, nose `fwd` (player 1 issues foes, so
## player 0's token bucket is not drained); steps once; returns the id.
static func spawn(w: SimWorld, def: StringName, team: int, p: Vector3, v: Vector3, fwd: Vector3) -> int:
	var owner: int = 0 if team == 0 else 1
	var cmd: Command = CommandPayload.debug_spawn(owner, def_id(def), owner, team, p, v, fwd)
	var code: int = w.apply_command(cmd).code
	assert(code == CommandResult.Code.ACCEPTED, "spawn %s: %d" % [def, code])
	w.step()
	var id: int = 0
	for e: SimEvent in w.drain_events():
		if e.kind == SimEvent.Kind.SPAWN:
			id = e.a
	return id


## Unit direction at geographic (lat, lon) degrees.
static func geo(lat_deg: float, lon_deg: float) -> Vector3:
	return Sphere.from_lat_lon(deg_to_rad(lat_deg), deg_to_rad(lon_deg), 1.0)


## A point `agl` m above the terrain of `w` under direction `dir`.
static func above(w: SimWorld, dir: Vector3, agl: float) -> Vector3:
	return dir.normalized() * (R + w.terrain().height_at(dir) + agl)


## Unit horizontal direction at `p` toward `q`.
static func heading(p: Vector3, q: Vector3) -> Vector3:
	var n: Vector3 = p.normalized()
	return (q - n * q.dot(n)).normalized()


static func agl(w: SimWorld, id: int) -> float:
	var p: Vector3 = w.view().pos(id)
	return p.length() - R - w.terrain().height_at(p)


static func order(w: SimWorld, id: int, spec: OrderSpec) -> void:
	var res: CommandResult = w.apply_command(Command.order(0, PackedInt32Array([id]), spec))
	assert(res.code == CommandResult.Code.ACCEPTED, "order %d refused: %d" % [spec.kind, res.code])


static func gains() -> FlightGains:
	var c: ContentSet = content()
	return FlightGains.from_dict(ap()["flight"] as Dictionary, ship(&"dart"), c.rules.tick_hz, c.rules, c.flight_common)


## The SweepScenarios.dive_recoverable classification (A-88 (3)) of the Dart's current state in `w`, on `w`'s terrain:
## true when some open-loop pull-up from now avoids terrain contact (`Assist.pull_up` first, then the fixed nose
## elevations 0, 5, ..., 90 degrees; SweepScenarios.bound_hits with the map's terrain instead of the flat datum).
static func recoverable(w: SimWorld, id: int, g: FlightGains) -> bool:
	var v: SimView = w.view()
	var b: Basis = v.basis(id)
	var dart: ShipDef = ship(&"dart")
	for k: int in SweepScenarios.BOUND_ELEVATIONS + 1:
		var j: int = SweepScenarios.BOUND_ELEVATIONS - k   # Assist.pull_up first: the cheap common case
		var s: ShipState = FlightTestKit.spawn(dart, v.pos(id), -b.z, b.y, v.vel(id))
		if not _bound_hits(s, g, j, w.terrain()):
			return true
	return false


static func _bound_hits(s: ShipState, g: FlightGains, j: int, terrain: Terrain) -> bool:
	var c: ContentSet = content()
	var dart: ShipDef = ship(&"dart")
	var inp: PilotInput = PilotInput.new()
	var th: float = deg_to_rad(5.0 * float(j))
	for i: int in 6 * c.rules.tick_hz:
		var n: Vector3 = s.p.normalized()
		if j == SweepScenarios.BOUND_ELEVATIONS:
			Assist.pull_up(Ai05Kit.basis(s), s.v, n, g, inp)
		else:
			var h: Vector3 = (s.v - n * s.v.dot(n)).normalized()
			FlightController.track_thrust_vector(Ai05Kit.basis(s), h * cos(th) + n * sin(th), 1.0, n, g, inp)
			inp.thrust = 1.0 if s.fwd.dot(n) > 0.0 else 0.0
		var _r: ShipState = Kinematics.step_ship(s, inp, dart, c.flight_common, c.rules, terrain, 1.0 / float(c.rules.tick_hz))
		if s.terrain_hit:
			return true
		if s.v.dot(n) > 0.0 and s.fwd.dot(n) > 0.0:
			return false
	return false


static func class_of(def: StringName) -> int:
	return AiClassTable.class_of(AiClassTable.from_content(content()), def_id(def))


## Flight gains of ship class `def` from its fixture autopilot (ContentSet's FlightCommonDef, A-90).
static func gains_of(def: StringName) -> FlightGains:
	var c: ContentSet = content()
	return FlightGains.from_dict(ap(def)["flight"] as Dictionary, ship(def), c.rules.tick_hz, c.rules, c.flight_common)


## Test brain for target ships: each registered id flies its own constant heading (re-projected on the local tangent
## plane every tick) at `speed` m/s, holding `agl` m above the terrain (FlightController.track_velocity).
class CruiseBrain extends AiBrain:
	var gains: FlightGains
	var terrain: Terrain
	var heading: Dictionary = {}     ## id -> world heading at spawn
	var speed: float = 70.0
	var agl: float = 400.0
	var inp: PilotInput = PilotInput.new()

	func _init(g: FlightGains, t: Terrain) -> void:
		gains = g
		terrain = t

	func act_batch(ids: PackedInt32Array, view: SimView, st: AiState, sink: CommandSink) -> void:
		for id: int in ids:
			if not heading.has(id):
				continue
			var p: Vector3 = view.pos(id)
			var up: Vector3 = p.normalized()
			var h: Vector3 = heading[id]
			h = (h - up * h.dot(up)).normalized()
			var vz: float = clampf(0.5 * (agl - (p.length() - Sphere.PLANET_RADIUS - terrain.height_at(p))), -10.0, 10.0)
			var s: int = EntityId.slot(id)
			st.integ[s] = FlightController.track_velocity(view.basis(id), view.vel(id), h * speed + up * vz, up, gains,
				st.integ[s], inp)
			var _ok: bool = sink.drive(id, inp)


## The unit direction `east_m` / `north_m` (great-circle metres) from the unit direction `c`, in c's tangent frame.
static func offset(c: Vector3, east_m: float, north_m: float) -> Vector3:
	var f: Basis = Sphere.tangent_frame(c)
	var r: float = sqrt(east_m * east_m + north_m * north_m)
	if r <= 0.0:
		return c.normalized()
	var a: float = r / R
	return (c.normalized() * cos(a) + (f.x * east_m + f.y * north_m) / r * sin(a)).normalized()
