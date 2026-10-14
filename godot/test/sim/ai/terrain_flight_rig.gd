class_name TerrainFlightRig extends RefCounted
## Guidance harness for SC-09 / SC-10 (05 s5.1, s5.3, s11.2): the think / act split of a Dart brain on a MOVE
## order, reduced to what the scenarios exercise. Think (every think_period_ticks): waypoint heading, deck-band
## altitude hold, TerrainProbe.probe once (6 samples) for the lift and the cached TTI. Act (every tick):
## FlightController.track_velocity on the cached guidance velocity; every pull_up_check_ticks one
## TerrainProbe.sample_clearance at 1.0 s and, below 0, PULL_UP (nose to local up through track_thrust_vector,
## thrust 1) until the think's TTI is >= pull_up_clear_tti_s. Not a contract: the Dart brain ports this.

var def: ShipDef
var common: FlightCommonDef
var rules: RulesDef
var terrain: Terrain
var g: FlightGains
var probe_params: ProbeParams
var waypoints: PackedVector3Array = PackedVector3Array()   ## unit directions, flown in order
var speed_cmd: float = 0.0
var alt_cmd: float = 0.0
var stats_min_agl: float = INF
var stats_contacts: int = 0
var stats_low_ticks: int = 0          ## ticks at or below `low_band_m` AGL
var stats_ticks: int = 0
var stats_pull_ups: int = 0
var low_band_m: float = INF
var trace: bool = false                ## print a line every think (debugging the scenarios)
var _gd: Dictionary
var _probe: ProbeResult = ProbeResult.new()
var _v_cmd: Vector3 = Vector3.ZERO
var _integ: Vector2 = Vector2.ZERO
var _wp: int = 0
var _pull_up: bool = false
var _pull_up_tick: int = 0
var _tick: int = 0


func _init(ship: ShipDef, flight_common: FlightCommonDef, rules_def: RulesDef, t: Terrain) -> void:
	def = ship
	common = flight_common
	rules = rules_def
	terrain = t
	g = Ai05Kit.gains(def, rules)
	_gd = Ai05Kit.block("guidance")
	var times: PackedFloat32Array = PackedFloat32Array()
	for x: Variant in _gd["probe_times_s"] as Array:
		var f: float = x
		var _b: bool = times.push_back(f)
	probe_params = ProbeParams.make(_n("min_clearance_m"), _n("clearance_per_mps"), times, rules.gravity,
		_n("lift_max_frac"), _n("lift_min_time_s"))
	alt_cmd = _n("deck_alt_agl_m")


func _n(k: String) -> float:
	return Ai05Kit.num(_gd, k)


## True once the last waypoint is reached.
func done() -> bool:
	return _wp >= waypoints.size()


## Flies until the last waypoint or `max_ticks`; returns false on a timeout.
func fly(s: ShipState, max_ticks: int) -> bool:
	var inp: PilotInput = PilotInput.new()
	for i: int in max_ticks:
		if done():
			return true
		step(s, inp)
	return done()


func step(s: ShipState, inp: PilotInput) -> void:
	var _t: bool = think_if_due(s)
	act(s, inp)
	advance(s, inp)


## Think when the tick is due (every think_period_ticks); true if it ran.
func think_if_due(s: ShipState) -> bool:
	if _tick % int(_n("think_period_ticks")) != 0:
		return false
	_think(s)
	return true


## Kinematics for one tick plus the scenario statistics.
func advance(s: ShipState, inp: PilotInput) -> void:
	Ai05Kit.step(s, inp, def, common, rules, terrain)
	_tick += 1
	var h: float = Ai05Kit.agl(s, terrain)
	stats_min_agl = minf(stats_min_agl, h)
	stats_ticks += 1
	if h <= low_band_m:
		stats_low_ticks += 1
	if s.terrain_hit:
		stats_contacts += 1
	if trace and (_tick % 5 == 0 or s.terrain_hit):
		var n: Vector3 = s.p.normalized()
		print("t=%.2f lat=%.2f agl=%.1f ground=%.0f vz=%.1f cmd_vz=%.1f lift=%.1f tti=%.2f minc=%.0f pull=%s u=%.0f thr=%.2f p=%.2f hit=%s" % [
			float(_tick) / 30.0, rad_to_deg(asin(n.z)), h, terrain.height_at(n), s.v.dot(n), _v_cmd.dot(n),
			_probe.lift_mps, _probe.tti_s, _probe.min_clearance_m, _pull_up, s.v.length(), inp.thrust, inp.pitch,
			s.terrain_hit])


func _think(s: ShipState) -> void:
	var n: Vector3 = s.p.normalized()
	while not done() and Sphere.great_circle(n, waypoints[_wp]) < _n("waypoint_radius_m"):
		_wp += 1
	if done():
		return
	var to: Vector3 = waypoints[_wp] - n * waypoints[_wp].dot(n)
	to = to.normalized()
	var u: float = s.v.length()
	TerrainProbe.probe(terrain, s.p, s.v, probe_params, probe_params.required_clearance(u), _probe)
	var h: float = Ai05Kit.agl(s, terrain)
	var alt: float = s.p.length() - Sphere.PLANET_RADIUS
	var vz: float = clampf(_n("kp_alt") * (alt_cmd - h), -_n("vz_max_mps"), _n("vz_max_mps"))
	var lift: float = _flown_lift(rules.gravity)
	if lift > 0.0:   # the lift is the climb beyond the current path that clears the worst sample
		vz = maxf(vz, s.v.dot(n) + lift)
	if alt >= _n("max_alt_m"):
		vz = minf(vz, 0.0)
	# direction from the current speed (so the vertical rate is met while the speed loop still converges),
	# magnitude = the commanded speed
	_v_cmd = (to * maxf(u, 1.0) + n * vz).normalized() * speed_cmd
	if _pull_up and _probe.tti_s >= _n("pull_up_clear_tti_s") 			and float(_tick - _pull_up_tick) >= _n("pull_up_min_hold_s") * float(rules.tick_hz):
		_pull_up = false
		_integ = Vector2.ZERO


# TerrainProbe predicts a ballistic path (05 s5.3: gravity drop 0.5 g t^2), but the controller holds the
# commanded path against gravity, so the drop is taken back out of the lift: at the 60 m deck the 4 s sample
# alone would read 48 m of drop and lift the ship above the band over flat ground.
func _flown_lift(gravity: float) -> float:
	var t: float = _probe.worst_t_s
	var drop: float = 0.5 * gravity * t * t / maxf(t, probe_params.lift_min_time_s)
	return maxf(_probe.lift_mps - drop, 0.0)


## Act for one tick: the PULL_UP re-check and the controller output into `inp`.
func act(s: ShipState, inp: PilotInput) -> void:
	var n: Vector3 = s.p.normalized()
	if not _pull_up and _tick % int(_n("pull_up_check_ticks")) == 0:
		if TerrainProbe.sample_clearance(terrain, s.p, s.v, rules.gravity, _n("pull_up_sample_s")) < 0.0:
			_pull_up = true
			_pull_up_tick = _tick
			stats_pull_ups += 1
	if _pull_up:   # 05 s5.3 PULL_UP: nose to local up at max rate, thrust 1, brake off
		FlightController.track_thrust_vector(Ai05Kit.basis(s), n, 1.0, n, g, inp)
		inp.thrust = 1.0
		return
	_integ = FlightController.track_velocity(Ai05Kit.basis(s), s.v, _v_cmd, n, g, _integ, inp)


## Waypoints every `step_m` along the great-circle polyline through `corners` (unit directions).
static func polyline(corners: PackedVector3Array, step_m: float) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	for k: int in corners.size() - 1:
		var a: Vector3 = corners[k]
		var b: Vector3 = corners[k + 1]
		var m: int = maxi(1, ceili(Sphere.great_circle(a, b) / step_m))
		for j: int in m:
			var _b: bool = out.push_back(Sphere.slerp_dir(a, b, float(j + 1) / float(m)))
	return out
