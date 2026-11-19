class_name BarrelTestKit extends RefCounted
## GD-50 fixtures: a Siege Crawler on the flat datum or a map, driven possessed (PILOT_INPUT of player 0) or AUTO (a hook
## writing the input slot through `CommandSinkBase.drive`), a dead-beat barrel slew read back through
## `SimView.barrel_elevation`, a test-side lofted solve on `Ballistics.predict_impact`, and the simulated impact of one
## shell (its Collision GROUND contact).

const R: float = Sphere.PLANET_RADIUS
const LOFT_TOL_M: float = 15.0      ## ap_crawler `siege.loft_tol_m` default (05 s6.7, AI-18 CrawlerParams; no override shipped)
const PLAYER: int = 0

static var _flat_content: ContentSet = null


## The shipped defs with `siege_gun.spread_deg` 0 (the on-target tests: a 1.5 deg spread moves the impact ~90 m).
static func no_spread_content() -> ContentSet:
	if _flat_content == null:
		var texts: Dictionary = {}
		for f: String in DirAccess.get_files_at(FlightTestKit.REAL_DEFS_DIR):
			if f.ends_with(".json"):
				texts[f] = FileAccess.get_file_as_string(FlightTestKit.REAL_DEFS_DIR + f)
		var wj: Dictionary = JSON.parse_string(str(texts["weapons.json"]))
		for e: Variant in wj["weapons"]:
			var d: Dictionary = e
			if str(d["id"]) == "siege_gun":
				d["spread_deg"] = 0.0
		texts["weapons.json"] = JSON.stringify(wj)
		_flat_content = ContentLoader.build(texts, {})
		assert(_flat_content.ok(), str(_flat_content.errors))
	return _flat_content


## A world over `content` (null = the shipped defs) with WorldTestKit's players; `map_id` "" = flat datum.
static func world(content: ContentSet = null, map_id: StringName = &"", seed_value: int = 11) -> SimWorld:
	if content == null:
		return WorldTestKit.world(seed_value, null, map_id)
	var w: SimWorld = SimWorld.new(content)
	var map: MapDef = MapDef.new()
	map.id = map_id
	var res: Result = w.load_map(map, seed_value, WorldTestKit.rules())
	assert(res.ok, res.message)
	w.add_player(0, 0, &"", PlayerTable.KIND_HUMAN)
	w.add_player(1, 1, &"vanguard", PlayerTable.KIND_HUMAN)
	w.add_player(2, 0, &"", PlayerTable.KIND_BOT)
	return w


## Spawns a player-0 Siege Crawler on the surface at `dir` heading east and lets GroundMotion snap it (2 ticks).
static func crawler(w: SimWorld, dir: Vector3 = Vector3(1, 0, 0), def: StringName = &"siege_crawler") -> int:
	var n: Vector3 = dir.normalized()
	var id: int = WorldTestKit.spawn(w, def, PLAYER, 0, n * (R + w.terrain().height_at(n) + 7.0))
	for _i: int in 2:
		w.step()
	var _e: Array[SimEvent] = w.drain_events()
	return id


## Drives one unit's input slot, possessed (PILOT_INPUT each tick) or AUTO (a hook through the sink).
class Pilot extends SimAiHook:
	var id: int = 0
	var possessed: bool = false
	var input: PilotInput = PilotInput.new()
	var drive_ok: bool = true

	func on_tick(_t: int, _v: SimView, sink: CommandSinkBase) -> void:
		if not possessed:
			drive_ok = sink.drive(id, input)

	func serialize() -> PackedByteArray:
		var b: StreamPeerBuffer = StreamPeerBuffer.new()
		b.put_var([id, possessed, input.thrust, input.pitch, input.yaw, input.roll, input.buttons])
		return b.data_array

	func deserialize(bytes: PackedByteArray) -> void:
		var b: StreamPeerBuffer = StreamPeerBuffer.new()
		b.data_array = bytes
		var a: Array = b.get_var()
		id = a[0]
		possessed = a[1]
		input.thrust = a[2]
		input.pitch = a[3]
		input.yaw = a[4]
		input.roll = a[5]
		input.buttons = a[6]

	## One tick with the current input (possessed: queued as this player's PILOT_INPUT first).
	func tick(w: SimWorld) -> void:
		if possessed:
			var r: CommandResult = w.apply_command(Command.pilot(PLAYER, w.tick() + 1, input))
			assert(r.code == CommandResult.Code.ACCEPTED)
		w.step()
		var _e: Array[SimEvent] = w.drain_events()


## A pilot of `id`; possessed: player 0 takes it (POSSESS applied in the next step).
static func pilot(w: SimWorld, id: int, possessed: bool) -> Pilot:
	var p: Pilot = Pilot.new()
	p.id = id
	p.possessed = possessed
	w.set_ai_hook(p)
	if possessed:
		assert(w.apply_command(Command.possess(PLAYER, id)).code == CommandResult.Code.ACCEPTED)
		w.step()
		var _e: Array[SimEvent] = w.drain_events()
		assert(w.view().possessor(id) == PLAYER)
	return p


## Dead-beat slew to `e` (radians) through `pitch` only, at most `max_ticks`; returns the ticks used.
static func slew_to(w: SimWorld, p: Pilot, e: float, rate_rad_s: float, max_ticks: int = 300) -> int:
	var dt: float = 1.0 / float(WorldTestKit.content().rules.tick_hz)
	for k: int in max_ticks:
		var cur: float = w.view().barrel_elevation(p.id)
		if absf(cur - e) <= 1e-12:
			p.input.pitch = 0.0
			return k
		p.input.pitch = clampf((e - cur) / (rate_rad_s * dt), -1.0, 1.0)
		p.tick(w)
	p.input.pitch = 0.0
	return max_ticks


## The arc point `d` metres from `p` along the heading `fwd` (a unit direction).
static func ahead(p: Vector3, fwd: Vector3, d: float) -> Vector3:
	var n: Vector3 = p.normalized()
	return (Quaternion(n.cross(fwd).normalized(), d / R) * n).normalized()


## Predicted impact of a shell from crawler slot state (`p`, heading `fwd`, radius `rad`) at elevation `e`, exactly as the
## fire pipeline spawns it with no spread: muzzle `p + dir x rad`, velocity `dir x speed` (the unit stands).
static func predict(w: SimWorld, p: Vector3, fwd: Vector3, rad: float, e: float) -> Vector4:
	var dir: Vector3 = BarrelSlew.muzzle_dir(p, fwd, e)
	return predict_from(w, p + dir * rad, dir * shell().speed_mps)


static func predict_from(w: SimWorld, at: Vector3, v: Vector3) -> Vector4:
	var hz: int = WorldTestKit.content().rules.tick_hz
	var dt: float = 1.0 / float(hz)
	var steps: int = ceili(shell().lifetime_s * float(hz)) + 2
	return Ballistics.predict_impact(at, v, shell(), WorldTestKit.content().rules, w.terrain(), dt, dt, 0.0, steps,
		ProjectileState.new())


## The low-arc elevation (radians) whose predicted impact lies `d` metres along the heading (bisection, 40 halvings).
static func solve(w: SimWorld, id: int, d: float) -> float:
	var s: int = EntityId.slot(id)
	var p: Vector3 = w.store().pos[s]
	var f: Vector3 = w.store().fwd[s]
	var rad: float = w.store().radius[s]
	var n: Vector3 = p.normalized()
	var lo: float = 0.0
	var hi: float = deg_to_rad(40.0)
	for _i: int in 40:
		var mid: float = 0.5 * (lo + hi)
		var r: Vector4 = predict(w, p, f, rad, mid)
		var reach: float = n.angle_to(Vector3(r.x, r.y, r.z)) * R if Ballistics.has_impact(r) else INF
		if reach < d:
			lo = mid
		else:
			hi = mid
	return 0.5 * (lo + hi)


static func shell() -> ProjectileDef:
	var c: ContentSet = WorldTestKit.content()
	return c.projectiles[int(c.projectile_index[&"siege_shell"]) - DefRanges.PROJECTILE_BASE]


## Shot record: the spawned shell's position and velocity, then its simulated impact (GROUND contact point).
class Shot extends RefCounted:
	var at: Vector3 = Vector3.ZERO
	var v: Vector3 = Vector3.ZERO
	var impact: Vector3 = Vector3.ZERO
	var landed: bool = false
	var ticks: int = 0


## Holds FIRE1 until the crawler's first shell spawns, releases, then steps until that shell's GROUND contact.
static func fire_one(w: SimWorld, p: Pilot) -> Shot:
	var out: Shot = Shot.new()
	p.input.buttons = PilotInput.FIRE1
	var shell_id: int = 0
	for _k: int in 10:
		p.tick(w)
		var mine: PackedInt32Array = FireTestKit.fired_by(w, p.id)
		if not mine.is_empty():
			var ps: ProjectileStore = w.projectiles()
			shell_id = ps.id_of(mine[0])
			out.at = ps.pos[mine[0]]
			out.v = ps.vel[mine[0]]
			break
	p.input.buttons = 0
	if shell_id == 0:
		return out
	var col: Collision = w.collision
	for k: int in 600:
		p.tick(w)
		for c: int in col.contact_count:
			if col.c_kind[c] == Collision.C_GROUND and col.c_a[c] == shell_id:
				out.impact = col.c_point[c]
				out.landed = true
				out.ticks = k + 1
				return out
		if not w.projectiles().alive(shell_id):
			return out
	return out


## Barrel slew rate of the Crawler def in rad/s (ground_units.json barrel_slew_dps).
static func rate() -> float:
	var c: ContentSet = WorldTestKit.content()
	var g: GroundUnitDef = c.ground_units[WorldTestKit.def_id(&"siege_crawler") - DefRanges.GROUND_BASE]
	return deg_to_rad(Def.num(g.raw.get("barrel_slew_dps", 0.0)))
