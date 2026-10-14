class_name Ai09Kit extends RefCounted
## Shared fixtures of the AI-09 tests: the landing parameter file (`ai09_params.json`), LandingParams, ProbeParams
## and a LandingPilot per ship class. Ship / rules / flight_common defs come from FlightTestKit (the canonical
## fixture), flight gains and probe values from AI-05's file.

const PARAMS: String = "res://test/sim/ai/ai09_params.json"


static func block(name: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PARAMS))
	assert(parsed is Dictionary, "missing " + PARAMS)
	return (parsed as Dictionary)[name] as Dictionary


static func landing(rules: RulesDef, overrides: Dictionary = {}) -> LandingParams:
	var d: Dictionary = block("landing")
	d.merge(overrides, true)
	return LandingParams.from_dict(d, rules.gravity)


static func probe(rules: RulesDef) -> ProbeParams:
	var gd: Dictionary = Ai05Kit.block("guidance")
	var times: PackedFloat32Array = PackedFloat32Array()
	for x: Variant in gd["probe_times_s"] as Array:
		var f: float = x
		var _b: bool = times.push_back(f)
	return ProbeParams.make(Ai05Kit.num(gd, "min_clearance_m"), Ai05Kit.num(gd, "clearance_per_mps"), times,
		rules.gravity, Ai05Kit.num(gd, "lift_max_frac"), Ai05Kit.num(gd, "lift_min_time_s"))


static func pilot(def: ShipDef, world: LandingWorld, overrides: Dictionary = {}) -> LandingPilot:
	return LandingPilot.new(def, world.common, world.rules, Ai05Kit.gains(def, world.rules),
		landing(world.rules, overrides), probe(world.rules), block("rtb"), world.terrain, world.pad_radius_by_def)


## The snapshot of a ShipState as LandingPilot fills it (flat ground under the ship unless `ground_h` given).
static func snapshot(s: ShipState, def: ShipDef, common: FlightCommonDef, rules: RulesDef, out: ShipSnapshot,
		ground_h: float = 0.0) -> void:
	out.b = Ai05Kit.basis(s)
	out.p = s.p
	out.v = s.v
	out.a_thrust = def.a_thrust * Kinematics.ceiling_efficiency(s.p.length() - Sphere.PLANET_RADIUS, rules)
	out.eff_fade_start = common.eff_fade_start
	out.bounding_radius = def.bounding_radius
	out.v_cruise = def.v_cruise
	out.ground_h = ground_h
	out.lift_mps = 0.0
	out.tti_s = INF
