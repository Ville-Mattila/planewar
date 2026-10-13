class_name FlightTestKit extends RefCounted
## Shared fixtures for the kinematics tests (TA-12, TA-45). Def values come from the schema-validated canonical
## fixture `tools/tests/fixtures/content/canonical` (R0 B.1 values) parsed by content's `*Def.from_dict`, never
## from literals in the tests. `real_content()` builds the shipped defs through `ContentLoader` (no autoload).

const DEFS_DIR: String = "../tools/tests/fixtures/content/canonical/godot/content/defs/"
const REAL_DEFS_DIR: String = "res://content/defs/"


static func load_json(file: String) -> Dictionary:
	var path: String = ProjectSettings.globalize_path("res://").path_join(DEFS_DIR + file)
	var text: String = FileAccess.get_file_as_string(path)
	assert(not text.is_empty(), "fixture missing: " + path)
	var parsed: Variant = JSON.parse_string(text)
	return parsed as Dictionary


## The shipped def set (`res://content/defs/`), built by `ContentLoader` exactly as ContentDB does.
static func real_content() -> ContentSet:
	var texts: Dictionary = {}
	for f: String in DirAccess.get_files_at(REAL_DEFS_DIR):
		if f.ends_with(".json"):
			texts[f] = FileAccess.get_file_as_string(REAL_DEFS_DIR + f)
	return ContentLoader.build(texts, {})


static func ship(id: StringName) -> ShipDef:
	var ships: Array = load_json("ships.json")["ships"]
	for e: Variant in ships:
		var d: Dictionary = e as Dictionary
		if StringName(str(d["id"])) == id:
			return ShipDef.from_dict(d)
	assert(false, "no ship " + str(id))
	return null


static func common() -> FlightCommonDef:
	return FlightCommonDef.from_dict(load_json("ships.json")["flight_common"] as Dictionary)


static func rules(lift_model: StringName = RulesDef.LIFT_SPEED_SCALED) -> RulesDef:
	var r: RulesDef = RulesDef.from_dict(load_json("rules.json"))
	r.lift_model = lift_model
	return r


static func projectile(id: StringName) -> ProjectileDef:
	var list: Array = load_json("projectiles.json")["projectiles"]
	for e: Variant in list:
		var d: Dictionary = e as Dictionary
		if StringName(str(d["id"])) == id:
			return ProjectileDef.from_dict(d)
	assert(false, "no projectile " + str(id))
	return null


static func dt(r: RulesDef) -> float:
	return 1.0 / float(r.tick_hz)


## A spawned ship: flip and boost ready, full fuel, orthonormal frame.
static func spawn(def: ShipDef, p: Vector3, fwd: Vector3, up: Vector3, v: Vector3) -> ShipState:
	var s: ShipState = ShipState.new()
	s.p = p
	s.v = v
	s.fwd = fwd.normalized()
	s.up = (up - s.fwd * up.dot(s.fwd)).normalized()
	s.flip_time = -def.flip_cooldown_s
	s.boost_time = -def.boost_cooldown_s
	s.fuel = def.fuel_s
	return s


## Level flight over (R + alt, 0, 0): nose east (+Y), belly down, velocity `speed` east,
## nose pitched up by `aoa_rad` about the right axis.
static func level(def: ShipDef, alt: float, speed: float, aoa_rad: float) -> ShipState:
	var n: Vector3 = Vector3(1, 0, 0)
	var east: Vector3 = Vector3(0, 1, 0)
	var fwd: Vector3 = east * cos(aoa_rad) + n * sin(aoa_rad)
	var up: Vector3 = n * cos(aoa_rad) - east * sin(aoa_rad)
	return spawn(def, n * (Sphere.PLANET_RADIUS + alt), fwd, up, east * speed)


static func input(thrust: float, pitch: float, yaw: float, roll: float, buttons: int) -> PilotInput:
	var i: PilotInput = PilotInput.new()
	i.thrust = thrust
	i.pitch = pitch
	i.yaw = yaw
	i.roll = roll
	i.buttons = buttons
	return i


static func copy(s: ShipState) -> ShipState:
	var c: ShipState = ShipState.new()
	c.p = s.p
	c.v = s.v
	c.fwd = s.fwd
	c.up = s.up
	c.rates = s.rates
	c.boost_time = s.boost_time
	c.flip_time = s.flip_time
	c.fuel = s.fuel
	c.terrain_hit = s.terrain_hit
	c.hit_normal_speed = s.hit_normal_speed
	c.ceiling_forced = s.ceiling_forced
	c.over_dive_excess = s.over_dive_excess
	return c


## Every ShipState field, bit-exact.
static func state_bytes(s: ShipState) -> PackedByteArray:
	return var_to_bytes([s.p, s.v, s.fwd, s.up, s.rates, s.boost_time, s.flip_time, s.fuel,
		s.terrain_hit, s.hit_normal_speed, s.ceiling_forced, s.over_dive_excess])


static func altitude(s: ShipState) -> float:
	return s.p.length() - Sphere.PLANET_RADIUS


## Angle of attack in the body vertical plane (rad): positive when the nose is above the velocity.
static func aoa(s: ShipState) -> float:
	return atan2(-s.v.dot(s.up), s.v.dot(s.fwd))


## A random but replayable input stream (PCG32 via core Rng); buttons exercise FLIP, BOOST and BRAKE.
static func random_inputs(seed_value: int, count: int) -> Array[PilotInput]:
	var rng: Rng = Rng.new(seed_value)
	var out: Array[PilotInput] = []
	for _k: int in count:
		var b: int = 0
		var roll_dice: int = rng.range_i(0, 99)
		if roll_dice < 3:
			b |= PilotInput.FLIP
		elif roll_dice < 6:
			b |= PilotInput.BOOST
		elif roll_dice < 15:
			b |= PilotInput.BRAKE
		out.append(input(rng.next_float(), rng.range_f(-1.0, 1.0), rng.range_f(-1.0, 1.0),
			rng.range_f(-1.0, 1.0), b))
	return out


## Test PD autopilot for level flight (03 TA-12 "autopilot-held (test PD loop)"): holds altitude `h0` and
## forward speed `v_target`, wings level. Writes into `inp` and returns it.
static func level_hold(s: ShipState, def: ShipDef, r: RulesDef, h0: float, v_target: float,
		inp: PilotInput) -> PilotInput:
	var n: Vector3 = s.p.normalized()
	var v_fwd: float = s.v.dot(s.fwd)
	var vz: float = s.v.dot(n)
	var trim: float = r.gravity / (maxf(v_fwd, 1.0) * Kinematics.k_up_effective(v_fwd, def, r))
	var vz_cmd: float = clampf(0.5 * (h0 - altitude(s)), -5.0, 5.0)
	var theta_cmd: float = trim + 0.02 * (vz_cmd - vz)
	var theta: float = asin(clampf(s.fwd.dot(n), -1.0, 1.0))
	var right: Vector3 = s.fwd.cross(s.up)
	inp.pitch = clampf((4.0 * (theta_cmd - theta) - 0.3 * s.rates.x) / deg_to_rad(def.pitch_rate_dps), -1.0, 1.0)
	inp.roll = clampf((4.0 * right.dot(n) - 0.3 * s.rates.z) / deg_to_rad(def.roll_rate_dps), -1.0, 1.0)
	inp.yaw = 0.0
	inp.thrust = clampf(0.1 + 0.5 * (v_target - v_fwd), 0.0, 1.0)
	inp.buttons = 0
	return inp


## Test PD autopilot for a tail-down hover: thrust axis held on `axis` (unit, world); vertical speed driven to
## `vz_cmd`, or to hold altitude `h0` when `hold_alt`. Writes into `inp` and returns it.
static func hover_hold(s: ShipState, def: ShipDef, r: RulesDef, axis: Vector3, h0: float,
		vz_cmd: float, hold_alt: bool, inp: PilotInput) -> PilotInput:
	var n: Vector3 = s.p.normalized()
	var vz: float = s.v.dot(n)
	var target_vz: float = clampf(h0 - altitude(s), -5.0, 5.0) if hold_alt else vz_cmd
	var a_up: float = r.gravity + 2.0 * (target_vz - vz)
	var cos_tilt: float = maxf(s.fwd.dot(n), 0.2)
	inp.thrust = clampf(a_up / (def.a_thrust * cos_tilt), 0.0, 1.0)
	var e: Vector3 = s.fwd.cross(axis)
	var right: Vector3 = s.fwd.cross(s.up)
	inp.pitch = clampf((6.0 * e.dot(right) - 0.5 * s.rates.x) / deg_to_rad(def.pitch_rate_dps), -1.0, 1.0)
	inp.yaw = clampf((6.0 * e.dot(s.up) - 0.5 * s.rates.y) / deg_to_rad(def.yaw_rate_dps), -1.0, 1.0)
	inp.roll = 0.0
	inp.buttons = 0
	return inp
