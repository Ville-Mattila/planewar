class_name OverlayKit extends RefCounted
## AI-08 fixtures: the shipped defs plus the autopilot fixture `ai08_autopilots.json` (the 05 s4.4 / s2.4 keys that
## content's autopilots.json does not carry yet), a SimWorld on them (players 0, 3 human team 0; 1 human team 1; 2 bot
## team 0) with an AiDriver hook whose class 0 is the Dart with its OverlayParams, and spawn / pilot helpers.
## Commands are queued before the step that applies them.

const AUTOPILOTS: String = "res://test/sim/ai/ai08_autopilots.json"
const MATE: int = 3
const CLS_DART: int = 0

static var _content: ContentSet = null


static func content() -> ContentSet:
	if _content == null:
		var texts: Dictionary = {}
		for f: String in DirAccess.get_files_at(FlightTestKit.REAL_DEFS_DIR):
			if f.ends_with(".json"):
				texts[f] = FileAccess.get_file_as_string(FlightTestKit.REAL_DEFS_DIR + f)
		texts["autopilots.json"] = FileAccess.get_file_as_string(AUTOPILOTS)
		_content = ContentLoader.build(texts, {})
		assert(_content.ok(), "defs + AI-08 autopilots must load: %s" % str(_content.errors))
	return _content


static func ship(id: StringName) -> ShipDef:
	for sd: ShipDef in content().ships:
		if sd.id == id:
			return sd
	return null


## The autopilot def dictionary of ship class `id`.
static func ap(id: StringName) -> Dictionary:
	return BridgeParams.autopilot_raw(content(), ship(id).autopilot)


static func overlay_params(id: StringName) -> OverlayParams:
	var c: ContentSet = content()
	return OverlayParams.for_ship(ap(id), ship(id), c.rules, c.rules.tick_hz, c.flight_common)


static func world(seed_value: int = 7, map_id: StringName = &"") -> SimWorld:
	var w: SimWorld = SimWorld.new(content())
	var map: MapDef = MapDef.new()
	map.id = map_id
	var res: Result = w.load_map(map, seed_value, WorldTestKit.rules())
	assert(res.ok, res.message)
	w.add_player(0, 0, &"", PlayerTable.KIND_HUMAN)
	w.add_player(1, 1, &"vanguard", PlayerTable.KIND_HUMAN)
	w.add_player(2, 0, &"", PlayerTable.KIND_BOT)
	w.add_player(MATE, 0, &"", PlayerTable.KIND_HUMAN)
	return w


## An AiDriver with the Dart's overlays on class 0 (no brain), hooked into `w`.
static func driver(w: SimWorld) -> AiDriver:
	var d: AiDriver = AiDriver.new(Rng.new(3))
	d.set_overlay_params(CLS_DART, overlay_params(&"dart"))
	d.set_terrain(w.terrain())
	w.set_ai_hook(d)
	return d


## Spawns `def` for slot 0 (team 0) at `p` with velocity `v`, nose along `fwd`; steps once; returns the id.
static func spawn(w: SimWorld, def: StringName, p: Vector3, v: Vector3, fwd: Vector3) -> int:
	var cmd: Command = CommandPayload.debug_spawn(0, WorldTestKit.def_id(def), 0, 0, p, v, fwd)
	assert(w.apply_command(cmd).code == CommandResult.Code.ACCEPTED)
	w.step()
	for e: SimEvent in w.drain_events():
		if e.kind == SimEvent.Kind.SPAWN:
			return e.a
	return 0


## A point `alt` m above the datum at `east` m along +Y from +X, and the dive direction there: east, `deg` below
## the horizon.
static func at(alt: float, east: float = 0.0) -> Vector3:
	return WorldTestKit.at(alt, east)


static func dive_dir(p: Vector3, deg: float) -> Vector3:
	var up: Vector3 = p.normalized()
	var east: Vector3 = (Vector3(0, 1, 0) - up * up.y).normalized()
	return (east * cos(deg_to_rad(deg)) - up * sin(deg_to_rad(deg))).normalized()


static func ok(w: SimWorld, cmd: Command) -> void:
	var code: int = w.apply_command(cmd).code
	assert(code == CommandResult.Code.ACCEPTED, "command %d: code %d" % [cmd.kind, code])


## Queues a PILOT_INPUT from `p` for the next step.
static func pilot(w: SimWorld, p: int, thrust: float, pitch: float, buttons: int = 0) -> void:
	var inp: PilotInput = PilotInput.new()
	inp.thrust = thrust
	inp.pitch = pitch
	inp.buttons = buttons
	ok(w, Command.pilot(p, w.tick() + 1, inp))


static func agl(w: SimWorld, id: int) -> float:
	var p: Vector3 = w.view().pos(id)
	return p.length() - Sphere.PLANET_RADIUS - w.terrain().height_at(p)


static func overlay(w: SimWorld, id: int) -> int:
	return w.store().overlay[EntityId.slot(id)]


static func of_kind(events: Array[SimEvent], kind: SimEvent.Kind) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for e: SimEvent in events:
		if e.kind == kind:
			out.append(e)
	return out


## The entity input slot after the last step (what kinematics flew).
static func entity_input(w: SimWorld, id: int) -> PilotInput:
	var out: PilotInput = PilotInput.new()
	ControlTestKit.inputs(w).read_entity(EntityId.slot(id), out)
	return out
