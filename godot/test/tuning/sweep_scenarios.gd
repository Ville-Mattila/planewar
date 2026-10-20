class_name SweepScenarios extends RefCounted
## Scenario runners of the gain-tuning harness (AI-06; 05 s5): three families, each a function of one candidate
## (`flight` / `landing` dictionaries layered over the AI-05 / AI-09 parameter files) and one lift model.
##   step_response  AI-05 acceptance steps (turn, climb, dive) from trimmed flight; time-in-5-degrees and overshoot.
##   steep_dive     a Dart pitched 10-45 degrees nose-down at 100-300 m above flat ground (about 1 % terrain
##                  contacts at the AI-05 gains under speed_scaled: the "very steep low dive" tail), flown by the
##                  TerrainFlightRig (deck hold + PULL_UP re-check); counts terrain contacts.
##   landing        SC-04 geometry (2-4 km out, 150-450 m, random bearing / heading) through LandingScenario.
## Seeds are common across candidates (seed k is the same start state for every candidate). Test code, not a contract.

const CONVERGE_DEG: float = 5.0
const SETTLE_TICKS: int = 900
const STEP_TICKS: int = 240
const PAD_LAT: float = 40.0
const PAD_LON: float = 22.5
const TILT_MAX_DEG: float = 10.0
const R: float = Sphere.PLANET_RADIUS
const DIVE_DEG: Vector2 = Vector2(10.0, 45.0)
const DIVE_AGL: Vector2 = Vector2(100.0, 300.0)
const OUTCOMES: PackedStringArray = ["flying", "landed", "damaged", "crashed", "off_pad"]
## Per-landing diagnostics `landing` writes into its `out` dictionary.
const LANDING_COLS: PackedStringArray = ["outcome", "gate_to_dock_s", "go_arounds", "scrapes", "phase_end", "speed_end",
	"agl_end", "thrust_min_approach", "thrust_low_ticks", "td_sink", "td_hspeed", "td_tilt"]


## One candidate under one lift model.
class Setup extends RefCounted:
	var model: StringName = RulesDef.LIFT_SPEED_SCALED
	var flight: Dictionary = {}
	var landing: Dictionary = {}

	func rules() -> RulesDef:
		return FlightTestKit.rules(model)

	func gains(def: ShipDef, rules_def: RulesDef) -> FlightGains:
		var d: Dictionary = Ai05Kit.block("flight").duplicate()
		d.merge(flight, true)
		return FlightGains.from_dict(d, def, rules_def.tick_hz)

	func pilot(def: ShipDef, world: LandingWorld) -> LandingPilot:
		var d: Dictionary = Ai09Kit.block("landing").duplicate()
		d.merge(landing, true)
		return LandingPilot.new(def, world.common, world.rules, gains(def, world.rules),
			LandingParams.from_dict(d, world.rules.gravity), Ai09Kit.probe(world.rules), Ai09Kit.block("rtb"),
			world.terrain, world.pad_radius_by_def)


# region step response (the AI-05 acceptance steps, test_flight_controller.gd)
## (time to stay within 5 degrees, overshoot fraction along the step plane) for a step of `hdg_deg` (+ right) and
## `pitch_deg` (+ climb) from level flight at v_cruise settled under the controller. Time is -1 if never settled.
static func step_response(su: Setup, id: StringName, hdg_deg: float, pitch_deg: float) -> Vector2:
	var def: ShipDef = FlightTestKit.ship(id)
	var rules: RulesDef = su.rules()
	var common: FlightCommonDef = FlightTestKit.common()
	var flat: Terrain = Terrain.new()
	var g: FlightGains = su.gains(def, rules)
	var s: ShipState = FlightTestKit.level(def, 800.0, def.v_cruise, 0.0)
	var inp: PilotInput = PilotInput.new()
	var integ: Vector2 = Vector2.ZERO
	var d: Vector3 = Vector3(0, 1, 0)
	for i: int in SETTLE_TICKS:
		integ = FlightController.track_velocity(Ai05Kit.basis(s), s.v, d * def.v_cruise, s.p.normalized(), g, integ, inp)
		d = _advance(s, inp, def, common, rules, flat) * d
	var n: Vector3 = s.p.normalized()
	var v0: Vector3 = (s.v - n * s.v.dot(n)).normalized()
	d = v0.rotated(n, -deg_to_rad(hdg_deg))
	d = d.rotated(d.cross(n).normalized(), deg_to_rad(pitch_deg))
	var amp: float = v0.angle_to(d)
	var perp: Vector3 = (d - v0 * d.dot(v0)).normalized()
	var t_in: float = -1.0
	var max_prog: float = 0.0
	for i: int in STEP_TICKS:
		integ = FlightController.track_velocity(Ai05Kit.basis(s), s.v, d * def.v_cruise, s.p.normalized(), g, integ, inp)
		var q: Quaternion = _advance(s, inp, def, common, rules, flat)
		d = q * d
		v0 = q * v0
		perp = q * perp
		var vh: Vector3 = s.v.normalized()
		max_prog = maxf(max_prog, atan2(vh.dot(perp), vh.dot(v0)))
		if rad_to_deg(vh.angle_to(d)) > CONVERGE_DEG:
			t_in = -1.0
		elif t_in < 0.0:
			t_in = float(i + 1) / float(rules.tick_hz)
	return Vector2(t_in, (max_prog - amp) / amp)


static func _advance(s: ShipState, inp: PilotInput, def: ShipDef, common: FlightCommonDef, rules: RulesDef,
		terrain: Terrain) -> Quaternion:
	var n0: Vector3 = s.p.normalized()
	Ai05Kit.step(s, inp, def, common, rules, terrain)
	return Sphere.transport(n0, s.p.normalized())
# endregion


# region steep low dive
## One steep low dive from seed `k`: returns Vector3(contacts, min AGL m, pull-ups). Start 100-300 m above flat
## ground, 10-45 degrees nose-down along the heading at 0.7-1.1 v_cruise, a straight waypoint line, 12 s.
## `dive_deg` / `agl_m` override the (min, max) ranges.
static func steep_dive(su: Setup, base_seed: int, k: int, dive_deg: Vector2 = DIVE_DEG, agl_m: Vector2 = DIVE_AGL) -> Vector3:
	var rng: Rng = Rng.new(base_seed + 7919 * k)
	var def: ShipDef = FlightTestKit.ship(&"dart")
	var rules: RulesDef = su.rules()
	var rig: TerrainFlightRig = TerrainFlightRig.new(def, FlightTestKit.common(), rules, Terrain.new())
	rig.g = su.gains(def, rules)
	var a: Vector3 = Ai05Kit.geo(PAD_LAT, rng.range_f(0.0, 360.0))
	var b: Vector3 = Sphere.slerp_dir(a, Ai05Kit.geo(PAD_LAT - 12.0, rng.range_f(0.0, 360.0)), 0.05)
	rig.waypoints = TerrainFlightRig.polyline(PackedVector3Array([a, b]), 200.0)
	var speed: float = def.v_cruise * rng.range_f(0.7, 1.1)
	rig.speed_cmd = def.v_cruise
	var first: Vector3 = rig.waypoints[0]
	var fwd: Vector3 = (first - a * first.dot(a)).normalized()
	var dive: float = deg_to_rad(rng.range_f(dive_deg.x, dive_deg.y))
	var heading: Vector3 = fwd * cos(dive) - a * sin(dive)
	var s: ShipState = FlightTestKit.spawn(def, a * (R + rng.range_f(agl_m.x, agl_m.y)), heading, a, heading * speed)
	var _ok: bool = rig.fly(s, 12 * rules.tick_hz)
	return Vector3(float(rig.stats_contacts), rig.stats_min_agl, float(rig.stats_pull_ups))
# endregion


# region landing
static func pad_dir() -> Vector3:
	return Ai05Kit.geo(PAD_LAT, PAD_LON)


static func _at(center: Vector3, dist: float, az_deg: float, agl: float) -> Vector3:
	var f: Basis = Sphere.tangent_frame(center)
	var az: float = deg_to_rad(az_deg)
	var bearing: Vector3 = f.y * cos(az) + f.x * sin(az)
	return (center * cos(dist / R) + bearing * sin(dist / R)) * (R + agl)


static func _heading(p: Vector3, to: Vector3, off_deg: float) -> Vector3:
	var n: Vector3 = p.normalized()
	var t: Vector3 = (to - n * to.dot(n)).normalized()
	return t.rotated(n, deg_to_rad(off_deg))


## One SC-04 style landing from seed `k`. Fills `out` (LANDING_COLS) and returns true when it docked within the
## R0 B.5 safe limits, thrust axis within 10 degrees of the pad normal, without a terrain scrape (A-70).
## `thrust_min_approach` / `thrust_low_ticks`: lowest throttle and ticks below 0.2 in APPROACH / TRANSITION (the
## "thrust cut while decelerating" suspicion).
static func landing(su: Setup, base_seed: int, k: int, out: Dictionary) -> bool:
	var rng: Rng = Rng.new(base_seed + 104729 * k)
	var sc: LandingScenario = LandingScenario.new(Terrain.new(), su.model)
	var pad: int = sc.world.add_pad(pad_dir())
	var def: ShipDef = FlightTestKit.ship(&"dart")
	var p: Vector3 = _at(pad_dir(), rng.range_f(2000.0, 4000.0), rng.range_f(0.0, 360.0), rng.range_f(150.0, 450.0))
	var hdg: Vector3 = _heading(p, pad_dir(), rng.range_f(-180.0, 180.0))
	var _id: int = sc.add_ship(&"dart", p, hdg, def.v_cruise, pad, true)
	sc.pilots[0] = su.pilot(def, sc.world)
	var thr_min: float = INF
	var low_ticks: int = 0
	var phase_end: int = 0
	for t: int in 180 * sc.world.rules.tick_hz:
		if not sc.world.flying(0):
			break
		sc.step()
		phase_end = sc.phase(0)
		if phase_end == LandingController.Phase.APPROACH or phase_end == LandingController.Phase.TRANSITION:
			thr_min = minf(thr_min, sc.inputs[0].thrust)
			if sc.inputs[0].thrust < 0.2:
				low_ticks += 1
	var w: LandingWorld = sc.world
	var td: Vector4 = w.touchdown[0]
	var s: ShipState = w.ss[0]
	var ok: bool = w.outcome[0] == LandingWorld.Outcome.LANDED and td.z <= TILT_MAX_DEG and w.scrapes[0] == 0
	out["outcome"] = "docked" if ok else OUTCOMES[w.outcome[0]]
	out["gate_to_dock_s"] = sc.gate_to_dock_s(0)
	out["go_arounds"] = sc.go_arounds[0]
	out["scrapes"] = w.scrapes[0]
	out["phase_end"] = phase_end
	out["speed_end"] = s.v.length()
	out["agl_end"] = Ai05Kit.agl(s, w.terrain)
	out["thrust_min_approach"] = thr_min if thr_min != INF else -1.0
	out["thrust_low_ticks"] = low_ticks
	out["td_sink"] = td.x
	out["td_hspeed"] = td.y
	out["td_tilt"] = td.z
	return ok
# endregion
