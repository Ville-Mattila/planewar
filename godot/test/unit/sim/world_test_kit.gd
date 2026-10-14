class_name WorldTestKit extends RefCounted
## Shared SimWorld fixtures for the TA-18 tests and perf_tick: the shipped defs built by ContentLoader (no
## autoload), MatchRules from those defs with debug commands on, three players (0 and 2 on team 0, 1 on team 1;
## slot 2 is a bot), entities spawned through DEBUG_SPAWN so every spawn goes through step 1 like any command.

const R: float = Sphere.PLANET_RADIUS

static var _content: ContentSet = null


static func content() -> ContentSet:
	if _content == null:
		_content = FlightTestKit.real_content()
		assert(_content.ok(), "shipped defs must load: %s" % str(_content.errors))
	return _content


static func def_id(id: StringName) -> int:
	return int(content().entity_index.get(id, -1))


## Rules from the shipped defs: debug commands on, private caps copy, no mode timers unless given.
static func rules(exposure_s: float = -1.0, hard_end_s: float = -1.0, profile: bool = false) -> MatchRules:
	var c: ContentSet = content()
	var r: MatchRules = MatchRules.from_defs(null, c.match_rules, c.rules, &"standard")
	var caps: CapsDef = CapsDef.new()
	caps.id = r.caps.id
	caps.units = r.caps.units
	caps.structures = r.caps.structures
	caps.projectiles = r.caps.projectiles
	caps.wrecks = r.caps.wrecks
	caps.slots = r.caps.slots
	r.caps = caps
	r.debug_commands = true
	r.profile_enabled = profile
	r.core_exposure_s = exposure_s
	r.hard_end_s = hard_end_s
	r.adjutant_allowed = &"full"
	return r


static func world(seed_value: int = 7, r: MatchRules = null, map_id: StringName = &"") -> SimWorld:
	var w: SimWorld = SimWorld.new(content())
	var map: MapDef = MapDef.new()
	map.id = map_id
	var res: Result = w.load_map(map, seed_value, r if r != null else rules())
	assert(res.ok, res.message)
	w.add_player(0, 0, &"", PlayerTable.KIND_HUMAN)
	w.add_player(1, 1, &"vanguard", PlayerTable.KIND_HUMAN)
	w.add_player(2, 0, &"", PlayerTable.KIND_BOT)
	return w


## A point `alt` metres above the datum on the +X axis, `east` metres along +Y.
static func at(alt: float, east: float = 0.0) -> Vector3:
	return Vector3(R + alt, east, 0.0)


## Queues a DEBUG_SPAWN (east-facing, `v` velocity); returns the command result code.
static func queue_spawn(w: SimWorld, def: StringName, owner: int, team: int, p: Vector3,
		v: Vector3 = Vector3.ZERO) -> int:
	var c: Command = CommandPayload.debug_spawn(0, def_id(def), owner, team, p, v, Vector3(0, 1, 0))
	return w.apply_command(c).code


## Spawns now: queues, steps once, returns the new EntityId (from the SPAWN event; other events are dropped).
static func spawn(w: SimWorld, def: StringName, owner: int, team: int, p: Vector3, v: Vector3 = Vector3.ZERO) -> int:
	var code: int = queue_spawn(w, def, owner, team, p, v)
	assert(code == CommandResult.Code.ACCEPTED)
	w.step()
	for e: SimEvent in w.drain_events():
		if e.kind == SimEvent.Kind.SPAWN:
			return e.a
	return 0


static func kinds(events: Array[SimEvent]) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for e: SimEvent in events:
		out.push_back(e.kind)
	return out


static func store_bytes(w: SimWorld) -> PackedByteArray:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	w.store().write_state(buf)
	return buf.data_array


## A projectile written straight into the pool (Combat's spawn is GD-36): `proj_id` from projectiles.json.
static func projectile(w: SimWorld, proj_id: StringName, p: Vector3, v: Vector3, team: int, ttl: float) -> int:
	var ps: ProjectileStore = w.projectiles()
	var local: int = int(content().projectile_index.get(proj_id, -1)) - DefRanges.PROJECTILE_BASE
	assert(local >= 0)
	var id: int = ps.alloc(ProjectileStore.SLUG, w.tick())
	var i: int = ps.index_of(id)
	ps.projectile_def[i] = local
	ps.pos[i] = p
	ps.prev_pos[i] = p
	ps.vel[i] = v
	ps.team[i] = team
	ps.ttl[i] = ttl
	return id


## Records every on_tick call; optionally drives `drive_id` each tick and remembers drive()'s answers.
class RecordingHook extends SimAiHook:
	var ticks: PackedInt32Array = PackedInt32Array()
	var drive_id: int = 0
	var drive_results: Array[bool] = []
	var input: PilotInput = PilotInput.new()
	var possessor_seen: PackedInt32Array = PackedInt32Array()
	var counter: int = 0

	func on_tick(t: int, v: SimView, sink: CommandSinkBase) -> void:
		ticks.push_back(t)
		counter += 1
		if drive_id != 0:
			possessor_seen.push_back(v.possessor(drive_id))
			drive_results.append(sink.drive(drive_id, input))

	func serialize() -> PackedByteArray:
		var b: PackedByteArray = PackedByteArray()
		b.resize(8)
		b.encode_s64(0, counter)
		return b

	func deserialize(bytes: PackedByteArray) -> void:
		counter = bytes.decode_s64(0) if bytes.size() == 8 else -1
