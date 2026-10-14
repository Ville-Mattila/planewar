extends GdUnitTestSuite
## Unit tests for sim/steer/landing_controller.gd and its structs (AI-09; 05 s5.5, R0 B.5): parameter loading,
## every phase transition of the L1-L6 table, every abort rule, the go-around geometry, bearing choice (alignment,
## terrain, threat, ties), the L4-L6 law's floor and tilt limits, purity, determinism and cost per call.
## Closed-loop success rates live in test/sim/ai (test_landing_dock_sets.gd, test_sc_landing.gd).

const R: float = Sphere.PLANET_RADIUS

var _rules: RulesDef
var _common: FlightCommonDef
var _dart: ShipDef
var _prm: LandingParams
var _g: FlightGains
var _pad: PadSnapshot
var _ship: ShipSnapshot
var _st: LandingState
var _out: PilotInput


## A ridge `h` high crossing the great circle from `origin` along `along` at `at_m`, `half_w` m half-width.
class RidgeTerrain extends Terrain:
	var origin: Vector3 = Vector3.RIGHT
	var along: Vector3 = Vector3.UP
	var at_m: float = 600.0
	var half_w: float = 150.0
	var h: float = 200.0

	func height_at(dir: Vector3) -> float:
		var u: Vector3 = dir.normalized()
		var d: float = atan2(u.dot(along), u.dot(origin)) * Sphere.PLANET_RADIUS
		var lateral: float = absf(origin.cross(along).dot(u)) * Sphere.PLANET_RADIUS
		return h * maxf(0.0, 1.0 - absf(d - at_m) / half_w) if lateral < 100.0 else 0.0


func before_test() -> void:
	_rules = FlightTestKit.rules()
	_common = FlightTestKit.common()
	_dart = FlightTestKit.ship(&"dart")
	_prm = Ai09Kit.landing(_rules)
	_g = Ai05Kit.gains(_dart, _rules)
	_pad = PadSnapshot.new()
	_pad.p = Vector3.RIGHT * R
	_pad.n = Vector3.RIGHT
	_pad.radius_m = 10.0
	_pad.valid = true
	_ship = ShipSnapshot.new()
	_st = LandingState.new()
	_out = PilotInput.new()


## Puts the snapshot `dist` m from the pad along tangent `dir` (unit, at the pad), `h` m above the pad (bottom of
## the ship), velocity `v`, nose `fwd` (up = any orthogonal).
func _place(dist: float, dir: Vector3, h: float, v: Vector3, fwd: Vector3 = Vector3.RIGHT) -> void:
	var p_dir: Vector3 = Vector3.RIGHT * cos(dist / R) + dir * sin(dist / R)
	var s: ShipState = FlightTestKit.spawn(_dart, p_dir * (R + h + _dart.bounding_radius), fwd,
		fwd.cross(Vector3.FORWARD) if absf(fwd.dot(Vector3.FORWARD)) < 0.9 else Vector3.UP, v)
	Ai09Kit.snapshot(s, _dart, _common, _rules, _ship)


# region params
func test_params_from_dict_and_missing_key() -> void:
	assert_object(_prm).is_not_null()
	assert_float(_prm.gravity).is_equal(_rules.gravity)
	assert_float(_prm.tan_glide).is_equal_approx(tan(deg_to_rad(8.0)), 1e-6)
	assert_int(_prm.max_attempts).is_equal(3)
	for k: String in LandingParams.KEYS:
		var d: Dictionary = Ai09Kit.block("landing")
		var _e: bool = d.erase(k)
		assert_object(LandingParams.from_dict(d, _rules.gravity)).override_failure_message(k).is_null()
	var bad: Dictionary = Ai09Kit.block("landing")
	bad["kp_pos"] = "fast"
	assert_object(LandingParams.from_dict(bad, _rules.gravity)).is_null()
# endregion


# region transitions
func test_transit_needs_gate_and_bearing() -> void:
	_place(2000.0, Vector3.UP, 300.0, Vector3.DOWN * 100.0, Vector3.DOWN)
	assert_int(LandingController.step(_st, _ship, _pad, _prm, _g, _out)).is_equal(LandingController.Phase.TRANSIT)
	_place(1100.0, Vector3.UP, 200.0, Vector3.DOWN * 100.0, Vector3.DOWN)
	assert_int(LandingController.step(_st, _ship, _pad, _prm, _g, _out)).is_equal(LandingController.Phase.TRANSIT)
	_st.bearing = Vector3.UP
	assert_int(LandingController.step(_st, _ship, _pad, _prm, _g, _out)).is_equal(LandingController.Phase.APPROACH)


func test_busy_pad_holds_and_free_pad_resumes() -> void:
	_place(1100.0, Vector3.UP, 200.0, Vector3.DOWN * 100.0, Vector3.DOWN)
	_st.bearing = Vector3.UP
	_pad.busy = true
	assert_int(LandingController.step(_st, _ship, _pad, _prm, _g, _out)).is_equal(LandingController.Phase.HOLD)
	assert_int(LandingController.step(_st, _ship, _pad, _prm, _g, _out)).is_equal(LandingController.Phase.HOLD)
	_pad.busy = false
	assert_int(LandingController.step(_st, _ship, _pad, _prm, _g, _out)).is_equal(LandingController.Phase.TRANSIT)
	assert_vector(_st.bearing).is_equal(Vector3.ZERO)   # re-chosen by the caller from the orbit


func test_approach_to_transition_on_glide_else_glide_go_around() -> void:
	var d: float = 240.0
	_st.phase = LandingController.Phase.APPROACH
	_st.bearing = Vector3.UP
	_place(d, Vector3.UP, d * _prm.tan_glide, Vector3.DOWN * 40.0, Vector3.DOWN)
	assert_int(LandingController.step(_st, _ship, _pad, _prm, _g, _out)).is_equal(LandingController.Phase.TRANSITION)
	_st.phase = LandingController.Phase.APPROACH
	_place(d, Vector3.UP, d * _prm.tan_glide + _prm.glide_tol_m + 5.0, Vector3.DOWN * 40.0, Vector3.DOWN)
	assert_int(LandingController.step(_st, _ship, _pad, _prm, _g, _out)).is_equal(LandingController.Phase.GO_AROUND)
	assert_int(_st.abort_reason).is_equal(LandingController.Abort.GLIDE)


func test_approach_overflight_outbound_is_not_a_transition() -> void:
	# over the pad region on the approach side but flying away from the pad (to the gate fix): no L4, no abort
	_st.phase = LandingController.Phase.APPROACH
	_st.bearing = Vector3.UP
	_place(150.0, Vector3.UP, 200.0, Vector3.UP * 100.0, Vector3.UP)
	assert_int(LandingController.step(_st, _ship, _pad, _prm, _g, _out)).is_equal(LandingController.Phase.APPROACH)


func test_go_around_counts_attempt_after_extension_and_height() -> void:
	_st.phase = LandingController.Phase.HOVER
	_st.bearing = Vector3.UP
	_place(0.0, Vector3.UP, 12.0, Vector3.ZERO)
	LandingController.go_around(_st, _ship, _pad, LandingController.Abort.HORIZ_ERR)
	assert_int(_st.phase).is_equal(LandingController.Phase.GO_AROUND)
	assert_vector(_st.ga_dir).is_equal_approx(Vector3.DOWN, Vector3.ONE * 1e-6)   # over the pad, away from the bearing
	_place(_prm.goaround_extend_m - 10.0, Vector3.DOWN, _prm.goaround_agl_m, Vector3.DOWN * 100.0, Vector3.DOWN)
	assert_int(LandingController.step(_st, _ship, _pad, _prm, _g, _out)).is_equal(LandingController.Phase.GO_AROUND)
	_place(_prm.goaround_extend_m + 10.0, Vector3.DOWN, 100.0, Vector3.DOWN * 100.0, Vector3.DOWN)
	assert_int(LandingController.step(_st, _ship, _pad, _prm, _g, _out)).is_equal(LandingController.Phase.GO_AROUND)
	_place(_prm.goaround_extend_m + 10.0, Vector3.DOWN, _prm.goaround_agl_m, Vector3.DOWN * 100.0, Vector3.DOWN)
	assert_int(LandingController.step(_st, _ship, _pad, _prm, _g, _out)).is_equal(LandingController.Phase.TRANSIT)
	assert_int(_st.attempts).is_equal(1)
	assert_vector(_st.bearing).is_equal(Vector3.ZERO)


func test_transition_to_hover_needs_slow_close_upright_and_clear() -> void:
	_st.phase = LandingController.Phase.TRANSITION
	_place(20.0, Vector3.UP, 30.0, Vector3.DOWN * 5.0, Vector3.FORWARD)   # nose level: not upright
	assert_int(LandingController.step(_st, _ship, _pad, _prm, _g, _out)).is_equal(LandingController.Phase.TRANSITION)
	_place(20.0, Vector3.UP, 30.0, Vector3.DOWN * 20.0)                   # too fast
	assert_int(LandingController.step(_st, _ship, _pad, _prm, _g, _out)).is_equal(LandingController.Phase.TRANSITION)
	_place(20.0, Vector3.UP, 10.0, Vector3.DOWN * 5.0)                    # low and off-centre: L5 abort envelope
	assert_int(LandingController.step(_st, _ship, _pad, _prm, _g, _out)).is_equal(LandingController.Phase.TRANSITION)
	_place(20.0, Vector3.UP, 30.0, Vector3.DOWN * 5.0)
	assert_int(LandingController.step(_st, _ship, _pad, _prm, _g, _out)).is_equal(LandingController.Phase.HOVER)


func test_hover_to_flare_needs_height_and_centre() -> void:
	_st.phase = LandingController.Phase.HOVER
	_place(1.0, Vector3.UP, _prm.flare_agl_m + 2.0, Vector3.ZERO)
	assert_int(LandingController.step(_st, _ship, _pad, _prm, _g, _out)).is_equal(LandingController.Phase.HOVER)
	_place(5.5, Vector3.UP, _prm.flare_agl_m - 1.0, Vector3.ZERO)
	assert_int(LandingController.step(_st, _ship, _pad, _prm, _g, _out)).is_equal(LandingController.Phase.HOVER)
	_place(1.0, Vector3.UP, _prm.flare_agl_m - 1.0, Vector3.ZERO)
	assert_int(LandingController.step(_st, _ship, _pad, _prm, _g, _out)).is_equal(LandingController.Phase.FLARE)


func test_done_zeroes_the_output() -> void:
	_st.phase = LandingController.Phase.DONE
	_out.thrust = 1.0
	_out.pitch = 0.5
	_out.buttons = PilotInput.BRAKE | PilotInput.DOCK
	_place(0.0, Vector3.UP, 0.0, Vector3.ZERO)
	assert_int(LandingController.step(_st, _ship, _pad, _prm, _g, _out)).is_equal(LandingController.Phase.DONE)
	assert_float(_out.thrust).is_equal(0.0)
	assert_float(_out.pitch).is_equal(0.0)
	assert_int(_out.buttons).is_equal(PilotInput.DOCK)
# endregion


# region aborts
func _abort(phase: int) -> int:
	_st.phase = phase
	return LandingController.should_abort(_st, _ship, _pad, _prm)


func test_abort_rules() -> void:
	_place(5.0, Vector3.UP, 20.0, Vector3.ZERO)
	assert_int(_abort(LandingController.Phase.HOVER)).is_equal(LandingController.Abort.NONE)
	_pad.valid = false
	for ph: int in [LandingController.Phase.TRANSIT, LandingController.Phase.HOLD, LandingController.Phase.APPROACH,
			LandingController.Phase.FLARE]:
		assert_int(_abort(ph)).is_equal(LandingController.Abort.PAD_INVALID)
	assert_int(_abort(LandingController.Phase.GO_AROUND)).is_equal(LandingController.Abort.NONE)
	assert_int(_abort(LandingController.Phase.DONE)).is_equal(LandingController.Abort.NONE)
	_pad.valid = true
	_pad.threat = true
	assert_int(_abort(LandingController.Phase.TRANSIT)).is_equal(LandingController.Abort.NONE)
	assert_int(_abort(LandingController.Phase.APPROACH)).is_equal(LandingController.Abort.PAD_THREAT)
	_pad.threat = false
	_pad.busy = true
	assert_int(_abort(LandingController.Phase.APPROACH)).is_equal(LandingController.Abort.NONE)   # holds instead
	assert_int(_abort(LandingController.Phase.TRANSITION)).is_equal(LandingController.Abort.PAD_BUSY)
	_pad.busy = false
	_place(0.0, Vector3.UP, _prm.abort_vz_agl_m - 1.0, Vector3.LEFT * (_prm.abort_vz + 1.0))
	assert_int(_abort(LandingController.Phase.TRANSITION)).is_equal(LandingController.Abort.SINK)
	_place(0.0, Vector3.UP, _prm.abort_vz_agl_m + 1.0, Vector3.LEFT * (_prm.abort_vz + 1.0))
	assert_int(_abort(LandingController.Phase.HOVER)).is_equal(LandingController.Abort.NONE)
	_place(_prm.abort_horiz_err_m + 1.0, Vector3.UP, _prm.abort_horiz_agl_m - 1.0, Vector3.ZERO)
	assert_int(_abort(LandingController.Phase.HOVER)).is_equal(LandingController.Abort.HORIZ_ERR)
	assert_int(_abort(LandingController.Phase.FLARE)).is_equal(LandingController.Abort.HORIZ_ERR)
	assert_int(_abort(LandingController.Phase.TRANSITION)).is_equal(LandingController.Abort.NONE)
	_place(_prm.abort_horiz_err_m + 1.0, Vector3.UP, _prm.abort_horiz_agl_m + 1.0, Vector3.ZERO)
	assert_int(_abort(LandingController.Phase.HOVER)).is_equal(LandingController.Abort.NONE)


func test_tti_abort_only_when_the_impact_is_off_the_pad() -> void:
	_place(100.0, Vector3.UP, 20.0, Vector3.DOWN * 40.0 + Vector3.LEFT * 30.0, Vector3.DOWN)
	_ship.tti_s = 0.5        # impact 80 m from the pad
	assert_int(_abort(LandingController.Phase.APPROACH)).is_equal(LandingController.Abort.TTI)
	assert_int(_abort(LandingController.Phase.TRANSIT)).is_equal(LandingController.Abort.NONE)
	_place(0.0, Vector3.UP, 3.0, Vector3.LEFT * 3.0)
	_ship.tti_s = 0.5        # settling onto the pad itself
	assert_int(_abort(LandingController.Phase.FLARE)).is_equal(LandingController.Abort.NONE)
	_ship.tti_s = _prm.abort_tti_s + 0.1
	_place(100.0, Vector3.UP, 20.0, Vector3.DOWN * 40.0 + Vector3.LEFT * 30.0, Vector3.DOWN)
	assert_int(_abort(LandingController.Phase.APPROACH)).is_equal(LandingController.Abort.NONE)


func test_step_applies_the_abort_as_a_go_around() -> void:
	_st.phase = LandingController.Phase.HOVER
	_st.bearing = Vector3.UP
	_pad.valid = false
	_place(5.0, Vector3.UP, 20.0, Vector3.ZERO)
	assert_int(LandingController.step(_st, _ship, _pad, _prm, _g, _out)).is_equal(LandingController.Phase.GO_AROUND)
	assert_int(_st.abort_reason).is_equal(LandingController.Abort.PAD_INVALID)
	assert_vector(_st.mark).is_equal_approx(_ship.p.normalized(), Vector3.ONE * 1e-6)
# endregion


# region bearing
func test_bearing_aligns_with_track_on_flat_ground() -> void:
	var f: Basis = Sphere.tangent_frame(Vector3.RIGHT)
	for k: int in 8:
		var ang: float = TAU * float(k) / 8.0
		var b: Vector3 = f.y * cos(ang) + f.x * sin(ang)
		_place(1100.0, b, 200.0, -b * 100.0, -b)   # on bearing b, flying toward the pad
		var got: Vector3 = LandingController.choose_bearing(Terrain.new(), _pad, _ship, PackedFloat32Array(), _prm)
		assert_vector(got).override_failure_message("k=%d" % k).is_equal_approx(b, Vector3.ONE * 1e-4)


func test_bearing_avoids_a_ridge_on_the_aligned_line() -> void:
	var f: Basis = Sphere.tangent_frame(Vector3.RIGHT)
	var ridge: RidgeTerrain = RidgeTerrain.new()
	ridge.along = f.y      # ridge across the north line, 600 m out, 200 m high
	_place(1100.0, f.y, 200.0, -f.y * 100.0, -f.y)
	var got: Vector3 = LandingController.choose_bearing(ridge, _pad, _ship, PackedFloat32Array(), _prm)
	assert_float(got.dot(f.y)).is_less(0.9)
	assert_float(got.dot(f.y)).is_greater(0.5)   # the nearest clear neighbour (45 degrees off), not a reversal


func test_bearing_threat_penalty_and_ties() -> void:
	var f: Basis = Sphere.tangent_frame(Vector3.RIGHT)
	_place(1100.0, f.y, 200.0, -f.y * 100.0, -f.y)
	var threat: PackedFloat32Array = PackedFloat32Array([5.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var got: Vector3 = LandingController.choose_bearing(Terrain.new(), _pad, _ship, threat, _prm)
	assert_float(absf(got.dot(f.y) - cos(PI / 4.0))).is_less(1e-4)   # index 0 (north) penalised: a 45 degree neighbour
	_ship.p = Vector3.RIGHT * (R + 200.0)                               # over the pad, no track: a tie
	_ship.v = Vector3.ZERO
	var tie: Vector3 = LandingController.choose_bearing(Terrain.new(), _pad, _ship, PackedFloat32Array(), _prm)
	assert_vector(tie).is_equal_approx(f.y, Vector3.ONE * 1e-6)         # ties keep the lowest index (north)


# endregion


# region L4-L6 law
func test_hover_law_holds_weight_upright() -> void:
	_place(0.0, Vector3.UP, 40.0, Vector3.ZERO)   # above the hover_agl_m floor
	LandingController.thrust_law(LandingController.Phase.TRANSITION, _ship, _pad, _prm, _g, _out)
	assert_float(_out.thrust * _dart.a_thrust).is_equal_approx(_rules.gravity, 0.05)
	assert_float(_out.roll).is_equal(0.0)
	assert_int(_out.buttons & PilotInput.BRAKE).is_equal(0)


func test_flare_thrust_axis_within_flare_tilt() -> void:
	# a horizontal error in L6 never tilts the commanded thrust axis past flare_tilt_deg (05: 10 degrees)
	for dist: float in [2.0, 4.0]:
		for vh: float in [0.0, 3.0, 8.0]:
			_place(dist, Vector3.UP, 4.0, Vector3.UP * vh)
			var t: Vector3 = LandingController.thrust_vector(LandingController.Phase.FLARE, _ship, _pad, _prm)
			assert_float(rad_to_deg(t.angle_to(Vector3.RIGHT))).is_less_equal(10.0 + 1e-3)


func test_floor_climbs_in_l4_and_off_the_pad_in_l5() -> void:
	# below hover_agl_m (R0 B.12 A-70) L5 off the pad climbs, within floor_tilt_deg
	_place(60.0, Vector3.UP, _prm.hover_agl_m - 8.0, Vector3.ZERO)
	var low: Vector3 = LandingController.thrust_vector(LandingController.Phase.HOVER, _ship, _pad, _prm)
	assert_float(low.dot(Vector3.RIGHT)).is_greater(_rules.gravity + 1.0)
	assert_float(rad_to_deg(low.angle_to(Vector3.RIGHT))).is_less_equal(rad_to_deg(atan(_prm.tan_floor_tilt)) + 1e-3)
	_place(60.0, Vector3.UP, _prm.hover_agl_m + 8.0, Vector3.ZERO)
	var high: Vector3 = LandingController.thrust_vector(LandingController.Phase.HOVER, _ship, _pad, _prm)
	assert_float(high.dot(Vector3.RIGHT)).is_less(low.dot(Vector3.RIGHT))
	_place(5.0, Vector3.UP, _prm.hover_agl_m - 8.0, Vector3.ZERO)   # L5 over the pad: no floor, it sinks
	var pad_t: Vector3 = LandingController.thrust_vector(LandingController.Phase.HOVER, _ship, _pad, _prm)
	assert_float(pad_t.dot(Vector3.RIGHT)).is_less(_rules.gravity)
	# A-70: in L4 the floor holds over the pad too (vz_cmd >= 0 below hover_agl_m), sinking or not
	for vz: float in [0.0, -3.0]:
		_place(5.0, Vector3.UP, _prm.hover_agl_m - 8.0, Vector3.RIGHT * vz)
		var l4: Vector3 = LandingController.thrust_vector(LandingController.Phase.TRANSITION, _ship, _pad, _prm)
		assert_float(l4.dot(Vector3.RIGHT)).is_greater(_rules.gravity)


func test_vertical_first_allocation_never_exceeds_thrust() -> void:
	# a fast entry (90 m/s across, sinking) saturates: horizontal gets only what the vertical demand leaves
	_place(100.0, Vector3.UP, 12.0, Vector3.DOWN * 90.0 + Vector3.LEFT * 5.0)
	var t: Vector3 = LandingController.thrust_vector(LandingController.Phase.TRANSITION, _ship, _pad, _prm)
	assert_float(t.length()).is_less_equal(_dart.a_thrust + 1e-3)
	assert_float(t.dot(Vector3.RIGHT)).is_greater(_rules.gravity)


# endregion


# region purity, determinism, cost
func test_source_has_no_state() -> void:
	for path: String in ["res://src/sim/steer/landing_controller.gd"]:
		var src: String = FileAccess.get_file_as_string(path)
		assert_bool(src.contains("\nvar ")).is_false()
		assert_bool(src.contains("static var")).is_false()
		for line: String in src.split("\n"):
			if line.begins_with("func "):
				fail("non-static func in %s: %s" % [path, line])
			if line.contains("Rng") or line.contains("Time.") or line.contains("randf"):
				fail("clock or RNG in %s: %s" % [path, line])


func test_pure_and_deterministic() -> void:
	# identical inputs -> identical outputs and state; inputs untouched
	_st.phase = LandingController.Phase.APPROACH
	_st.bearing = Vector3.UP
	_place(900.0, Vector3.UP, 140.0, Vector3.DOWN * 90.0 + Vector3.LEFT * 3.0, Vector3.DOWN)
	var p0: Vector3 = _ship.p
	var a: LandingState = LandingState.new()
	var b: LandingState = LandingState.new()
	for s: LandingState in [a, b]:
		s.phase = _st.phase
		s.bearing = _st.bearing
	var oa: PilotInput = PilotInput.new()
	var ob: PilotInput = PilotInput.new()
	for i: int in 50:
		var _x: int = LandingController.step(a, _ship, _pad, _prm, _g, oa)
		var _y: int = LandingController.step(b, _ship, _pad, _prm, _g, ob)
		assert_bool(oa.thrust == ob.thrust and oa.pitch == ob.pitch and oa.yaw == ob.yaw and oa.roll == ob.roll
			and oa.buttons == ob.buttons and a.integ == b.integ and a.phase == b.phase).is_true()
	assert_vector(_ship.p).is_equal(p0)


func test_perf_cost_per_call() -> void:
	# Perf note (05 s10 act row, 6 us per ship; think row 25 us): LandingController.step per tick per landing ship
	# (velocity phase: guidance + track_velocity; thrust phase: law + track_thrust_vector) and choose_bearing once
	# per approach. Best of 6 batches; printed for the PR, loose bound for CI.
	var n: int = 3000
	var us: PackedFloat32Array = PackedFloat32Array([INF, INF, INF])
	for batch: int in 6:
		_st.phase = LandingController.Phase.APPROACH
		_st.bearing = Vector3.UP
		_place(900.0, Vector3.UP, 140.0, Vector3.DOWN * 90.0, Vector3.DOWN)
		var t0: int = Time.get_ticks_usec()
		for i: int in n:
			var _p: int = LandingController.step(_st, _ship, _pad, _prm, _g, _out)
		us[0] = minf(us[0], float(Time.get_ticks_usec() - t0) / float(n))
		_st.phase = LandingController.Phase.HOVER
		_place(3.0, Vector3.UP, 25.0, Vector3.LEFT * 2.0)
		t0 = Time.get_ticks_usec()
		for i: int in n:
			var _p: int = LandingController.step(_st, _ship, _pad, _prm, _g, _out)
		us[1] = minf(us[1], float(Time.get_ticks_usec() - t0) / float(n))
		t0 = Time.get_ticks_usec()
		for i: int in n / 10:
			var _b: Vector3 = LandingController.choose_bearing(Terrain.new(), _pad, _ship, PackedFloat32Array(), _prm)
		us[2] = minf(us[2], float(Time.get_ticks_usec() - t0) / float(n / 10))
	print("PERF LandingController.step approach %.2f us/call, hover %.2f us/call; choose_bearing %.1f us/call" % [
		us[0], us[1], us[2]])
	assert_float(us[0]).is_less(200.0)
	assert_float(us[1]).is_less(200.0)
	assert_float(us[2]).is_less(2000.0)
# endregion
