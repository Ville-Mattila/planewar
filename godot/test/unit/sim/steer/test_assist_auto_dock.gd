extends GdUnitTestSuite
## Unit tests for sim/steer/assist.gd `Assist.auto_dock` (AI-10; 05 s5.5, R0 B.12 A-33 horizontal radius, A-34 latch
## x5 and the 75 degree L4 tilt): engage rules, the horizontal radius, the latch, abort hand-back, the tilt limit,
## button handling, purity and determinism. Closed-loop success rates: test/sim/ai/test_sc16_auto_dock.gd.

const R: float = Sphere.PLANET_RADIUS
const RADIUS: float = 150.0
const LATCH: float = 5.0

var _rules: RulesDef
var _common: FlightCommonDef
var _dart: ShipDef
var _prm: LandingParams
var _g: FlightGains
var _pad: PadSnapshot
var _ship: ShipSnapshot
var _st: LandingState
var _inp: PilotInput


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
	_inp = FlightTestKit.input(0.6, 0.1, 0.2, 0.3, PilotInput.DOCK)


## Ship `dist` m from the pad (horizontal), `h` m above the pad plane, velocity `v`, nose `fwd`.
func _place(dist: float, h: float, v: Vector3, fwd: Vector3 = Vector3.UP) -> void:
	var p_dir: Vector3 = Vector3.RIGHT * cos(dist / R) + Vector3.UP * sin(dist / R)
	var s: ShipState = FlightTestKit.spawn(_dart, p_dir * (R + h + _dart.bounding_radius), fwd, Vector3.RIGHT, v)
	Ai09Kit.snapshot(s, _dart, _common, _rules, _ship)


func _dock() -> bool:
	return Assist.auto_dock(_st, _ship, _pad, _prm, _g, RADIUS, LATCH, _inp)


func test_config_matches_content() -> void:
	assert_float(_common.auto_dock_radius_m).is_equal(RADIUS)
	assert_float(_common.auto_dock_latch_mult).is_equal(LATCH)


func test_engages_inside_horizontal_radius_and_substitutes() -> void:
	_place(RADIUS - 5.0, 60.0, Vector3.UP * 30.0)
	assert_bool(_dock()).is_true()
	assert_int(_st.phase).is_equal(LandingController.Phase.TRANSITION)
	assert_float(_inp.thrust).is_not_equal(0.6)
	assert_int(_inp.buttons & PilotInput.DOCK).is_equal(PilotInput.DOCK)


func test_radius_is_horizontal_not_3d() -> void:
	# 3D distance 150 m + 300 m of height: still engages (A-33); 5 m beyond the radius horizontally: does not
	_place(RADIUS - 30.0, 300.0, Vector3.UP * 30.0)
	assert_bool(_dock()).is_true()
	_st.reset()
	_inp = FlightTestKit.input(0.6, 0.1, 0.2, 0.3, PilotInput.DOCK)
	_place(RADIUS + 5.0, 20.0, Vector3.UP * 30.0)
	assert_bool(_dock()).is_false()
	assert_float(_inp.thrust).is_equal(0.6)
	assert_float(_inp.pitch).is_equal(0.1)
	assert_int(_st.phase).is_equal(LandingController.Phase.TRANSIT)


func test_no_dock_no_assist_and_release_hands_back() -> void:
	_place(50.0, 60.0, Vector3.UP * 30.0)
	_inp.buttons = 0
	assert_bool(_dock()).is_false()
	assert_float(_inp.thrust).is_equal(0.6)
	_inp.buttons = PilotInput.DOCK
	assert_bool(_dock()).is_true()
	_inp.buttons = 0
	_inp.thrust = 0.7
	assert_bool(_dock()).is_false()
	assert_float(_inp.thrust).is_equal(0.7)
	assert_int(_st.phase).is_equal(LandingController.Phase.TRANSIT)


func test_busy_invalid_or_below_pad_does_not_engage() -> void:
	_place(50.0, 60.0, Vector3.UP * 30.0)
	_pad.busy = true
	assert_bool(_dock()).is_false()
	_pad.busy = false
	_pad.valid = false
	assert_bool(_dock()).is_false()
	_pad.valid = true
	_place(50.0, -20.0, Vector3.UP * 30.0)
	assert_bool(_dock()).is_false()


func test_latch_holds_out_to_five_radii_then_releases() -> void:
	_place(100.0, 60.0, Vector3.UP * 30.0)
	assert_bool(_dock()).is_true()
	_place(RADIUS * LATCH - 50.0, 60.0, Vector3.UP * 30.0)
	assert_bool(_dock()).is_true()
	_place(RADIUS * LATCH + 50.0, 60.0, Vector3.UP * 30.0)
	assert_bool(_dock()).is_false()
	assert_int(_st.phase).is_equal(LandingController.Phase.TRANSIT)
	# disengaged: back inside the engage radius it engages afresh; outside it (but inside the latch) it does not
	_place(RADIUS * 2.0, 60.0, Vector3.UP * 30.0)
	assert_bool(_dock()).is_false()
	_place(RADIUS - 30.0, 60.0, Vector3.UP * 30.0)
	assert_bool(_dock()).is_true()


func test_abort_hands_the_stick_back_until_dock_is_released() -> void:
	_place(100.0, 60.0, Vector3.UP * 30.0)
	assert_bool(_dock()).is_true()
	_pad.busy = true   # taken by another ship
	_inp = FlightTestKit.input(0.6, 0.1, 0.2, 0.3, PilotInput.DOCK)
	assert_bool(_dock()).is_false()
	assert_float(_inp.pitch).is_equal(0.1)
	assert_bool(_st.assist_off).is_true()
	_pad.busy = false
	assert_bool(_dock()).is_false()   # stays off while DOCK is held
	_inp.buttons = 0
	assert_bool(_dock()).is_false()
	_inp.buttons = PilotInput.DOCK
	assert_bool(_dock()).is_true()    # re-press engages again


func test_boost_and_flip_cleared_other_buttons_kept() -> void:
	_place(50.0, 60.0, Vector3.UP * 30.0)
	_inp.buttons = PilotInput.DOCK | PilotInput.BOOST | PilotInput.FLIP | PilotInput.FIRE1
	assert_bool(_dock()).is_true()
	assert_int(_inp.buttons & (PilotInput.BOOST | PilotInput.FLIP)).is_equal(0)
	assert_int(_inp.buttons & PilotInput.FIRE1).is_equal(PilotInput.FIRE1)


func test_transition_tilt_limit_is_75_degrees_while_braking() -> void:
	# fast, off-centre entry: the law's thrust vector in TRANSITION stays within the 75 degree transition tilt of
	# the pad normal and is the larger limit (A-34) compared with the 30 degree hover limit
	_place(100.0, 80.0, Vector3.UP * 90.0, Vector3.UP)
	var pad_up: Vector3 = _pad.n
	var t: Vector3 = LandingController.thrust_vector(LandingController.Phase.TRANSITION, _ship, _pad, _prm)
	var tilt: float = rad_to_deg(t.angle_to(pad_up))
	assert_float(tilt).is_less_equal(75.0 + 0.01)
	assert_float(tilt).is_greater(30.0)
	assert_float(_prm.tan_transition_tilt).is_equal_approx(tan(deg_to_rad(75.0)), 1e-5)
	var h: Vector3 = LandingController.thrust_vector(LandingController.Phase.HOVER, _ship, _pad, _prm)
	assert_float(rad_to_deg(h.angle_to(pad_up))).is_less_equal(30.0 + 0.01)
	# the assist sets BRAKE while the nose is further than transition_nose_deg from the normal and moving forward
	assert_bool(_dock()).is_true()
	assert_int(_inp.buttons & PilotInput.BRAKE).is_equal(PilotInput.BRAKE)


func test_pure_and_deterministic() -> void:
	_place(100.0, 60.0, Vector3(20.0, 40.0, -30.0), Vector3(0.3, 0.9, 0.1))
	var a: PilotInput = FlightTestKit.input(0.6, 0.1, 0.2, 0.3, PilotInput.DOCK)
	var b: PilotInput = FlightTestKit.input(0.6, 0.1, 0.2, 0.3, PilotInput.DOCK)
	var st2: LandingState = LandingState.new()
	var sp: Vector3 = _ship.p
	var sv: Vector3 = _ship.v
	var sb: Basis = _ship.b
	var pp: Vector3 = _pad.p
	assert_bool(Assist.auto_dock(_st, _ship, _pad, _prm, _g, RADIUS, LATCH, a)).is_true()
	assert_bool(Assist.auto_dock(st2, _ship, _pad, _prm, _g, RADIUS, LATCH, b)).is_true()
	assert_float(a.thrust).is_equal(b.thrust)
	assert_float(a.pitch).is_equal(b.pitch)
	assert_float(a.yaw).is_equal(b.yaw)
	assert_float(a.roll).is_equal(b.roll)
	assert_int(a.buttons).is_equal(b.buttons)
	# inputs untouched
	assert_vector(_ship.p).is_equal(sp)
	assert_vector(_ship.v).is_equal(sv)
	assert_bool(_ship.b == sb).is_true()
	assert_vector(_pad.p).is_equal(pp)
	# a state copy carries everything: a second tick from equal states gives equal output
	assert_int(st2.phase).is_equal(_st.phase)
	assert_vector(Vector3(st2.integ.x, st2.integ.y, 0.0)).is_equal(Vector3(_st.integ.x, _st.integ.y, 0.0))


func test_no_abort_for_tti_or_sink_a_human_has_no_go_around() -> void:
	_place(100.0, 60.0, Vector3.UP * 30.0)
	assert_bool(_dock()).is_true()
	_place(100.0, 6.0, Vector3.LEFT * 12.0)
	_ship.tti_s = 0.1
	assert_bool(_dock()).is_true()
	assert_int(_st.phase).is_not_equal(LandingController.Phase.GO_AROUND)


func test_continues_the_autopilots_phase_and_never_drops_to_l4() -> void:
	# possessed in L5 (autopilot state passed in): the assist stays in L5, it does not restart in TRANSITION
	_st.phase = LandingController.Phase.HOVER
	_place(8.0, 20.0, Vector3.DOWN * 3.0, Vector3.RIGHT)
	assert_bool(_dock()).is_true()
	assert_int(_st.phase).is_equal(LandingController.Phase.HOVER)
	_st.phase = LandingController.Phase.FLARE
	_place(2.0, 6.0, Vector3.DOWN * 2.0, Vector3.RIGHT)
	assert_bool(_dock()).is_true()
	assert_int(_st.phase).is_equal(LandingController.Phase.FLARE)


func test_other_phases_cold_start_in_transition_and_done_is_off() -> void:
	_st.phase = LandingController.Phase.APPROACH
	_place(100.0, 60.0, Vector3.UP * 30.0)
	assert_bool(_dock()).is_true()
	assert_int(_st.phase).is_equal(LandingController.Phase.TRANSITION)
	_st.phase = LandingController.Phase.DONE
	assert_bool(_dock()).is_false()


func test_assist_near_marks_acting_ticks_within_the_radius_and_survives_release() -> void:
	_place(RADIUS * 2.0, 60.0, Vector3.UP * 30.0)
	assert_bool(_dock()).is_false()
	assert_bool(_st.assist_near).is_false()
	_place(RADIUS - 30.0, 60.0, Vector3.UP * 30.0)
	assert_bool(_dock()).is_true()
	_place(RADIUS * 2.0, 60.0, Vector3.UP * 30.0)   # latched, outside the grading radius: no new mark, old one stays
	assert_bool(_dock()).is_true()
	assert_bool(_st.assist_near).is_true()
	_inp.buttons = 0
	assert_bool(_dock()).is_false()
	assert_bool(_st.assist_near).is_true()          # a manual finish after assisted approach is still AUTO
	_st.reset()
	assert_bool(_st.assist_near).is_false()
	# an engagement only outside the grading radius leaves it unset
	_inp.buttons = PilotInput.DOCK
	_place(RADIUS - 30.0, 60.0, Vector3.UP * 30.0)
	_st.phase = LandingController.Phase.TRANSITION
	_place(RADIUS * 3.0, 60.0, Vector3.UP * 30.0)
	assert_bool(_dock()).is_true()
	assert_bool(_st.assist_near).is_false()
