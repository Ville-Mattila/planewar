class_name IntelKit extends RefCounted
## AI-22 fixtures: `ai22_params.json` (perception profiles per tier + the 05 s7.4 threat block; needs content), the
## ThreatParams / PerceptionParams built on the AI-13 content (DartKit), and a SimView that counts its calls.

const PARAMS: String = "res://test/sim/ai/ai22_params.json"

static var _raw: Dictionary = {}
static var _tables: ThreatParams = null


static func raw() -> Dictionary:
	if _raw.is_empty():
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(PARAMS))
		assert(v is Dictionary, "ai22_params.json must parse")
		_raw = v
	return _raw


static func threat_block() -> Dictionary:
	return raw()["threat"]


static func tables() -> ThreatParams:
	if _tables == null:
		_tables = ThreatParams.from_content(DartKit.content(), threat_block(), DartKit.content().rules.tick_hz)
		assert(_tables != null, "ai22 threat block must build")
	return _tables


static func profile(tier: String) -> PerceptionParams:
	var d: Dictionary = raw()["perception"][tier]
	return PerceptionParams.from_dict(d, DartKit.content().rules.tick_hz)


static func intel() -> TeamIntel:
	return TeamIntel.new(tables(), profile("team"), DartKit.content().rules.tick_hz)


## Steps `w` `n` times, draining events.
static func run(w: SimWorld, n: int) -> void:
	for _k: int in n:
		w.step()
		var _e: Array[SimEvent] = w.drain_events()


## DEBUG_SPAWN of `def` owned by player `owner` on `team` at `p` (velocity `v`, nose `fwd`); steps once; returns the id.
static func spawn(w: SimWorld, def: StringName, owner: int, team: int, p: Vector3, v: Vector3 = Vector3.ZERO) -> int:
	var up: Vector3 = p.normalized()
	var fwd: Vector3 = v.normalized() if v.length_squared() > 0.0 else Sphere.tangent_frame(up).y
	var cmd: Command = CommandPayload.debug_spawn(owner, DartKit.def_id(def), owner, team, p, v, fwd)
	var code: int = w.apply_command(cmd).code
	assert(code == CommandResult.Code.ACCEPTED, "spawn %s: %d" % [def, code])
	w.step()
	var id: int = 0
	for e: SimEvent in w.drain_events():
		if e.kind == SimEvent.Kind.SPAWN:
			id = e.a
	return id


## A ground position (structure) or `agl` m above it, `east_m` / `north_m` from the unit direction `c`.
static func at(w: SimWorld, c: Vector3, east_m: float, north_m: float, agl: float = 0.0) -> Vector3:
	return DartKit.above(w, DartKit.offset(c, east_m, north_m), agl)


## Moves ship `id` to `p` at rest (store write; tests only).
static func teleport(w: SimWorld, id: int, p: Vector3) -> void:
	var s: int = EntityId.slot(id)
	w.store().pos[s] = p
	w.store().vel[s] = Vector3.ZERO


## Interest cell of `p`.
static func cell(p: Vector3) -> int:
	return Sphere.cell_of(p, Sphere.GRID_INTEREST)


static func weapon(id: StringName) -> WeaponDef:
	for wd: WeaponDef in DartKit.content().weapons:
		if wd.id == id:
			return wd
	return null
