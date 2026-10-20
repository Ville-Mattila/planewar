class_name Ai05Kit extends RefCounted
## Shared fixtures of the AI-05 tests: the parameter file (`ai05_params.json`), FlightGains per ship class, the
## SimView-style basis of a ShipState and a step helper. Ship / rules / flight_common defs come from FlightTestKit
## (the schema-validated canonical fixture), never from literals.

const PARAMS: String = "res://test/sim/ai/ai05_params.json"


static func params() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PARAMS))
	assert(parsed is Dictionary, "missing " + PARAMS)
	return parsed as Dictionary


static func block(name: String) -> Dictionary:
	return params()[name] as Dictionary


static func num(d: Dictionary, key: String) -> float:
	assert(d.has(key), "missing key " + key)
	var x: float = d[key]
	return x


static func gains(def: ShipDef, rules: RulesDef) -> FlightGains:
	return FlightGains.from_dict(block("flight"), def, rules.tick_hz, rules, FlightTestKit.common())


## SimView.basis(id) convention: Basis(right, up, -fwd), right = fwd x up.
static func basis(s: ShipState) -> Basis:
	return Basis(s.fwd.cross(s.up), s.up, -s.fwd)


static func step(s: ShipState, inp: PilotInput, def: ShipDef, common: FlightCommonDef, rules: RulesDef,
		terrain: Terrain) -> void:
	var _r: ShipState = Kinematics.step_ship(s, inp, def, common, rules, terrain, 1.0 / float(rules.tick_hz))


## Height of the ship's centre above the terrain under it (05 s5.3 clearance convention).
static func agl(s: ShipState, terrain: Terrain) -> float:
	return s.p.length() - Sphere.PLANET_RADIUS - terrain.height_at(s.p)


static func geo(lat_deg: float, lon_deg: float) -> Vector3:
	return Sphere.from_lat_lon(deg_to_rad(lat_deg), deg_to_rad(lon_deg), 1.0)
