extends GdUnitTestSuite
## AI-46 (GD-26 C-08, R0 B.27 A-140) unit tests of the Dart's air-to-air aim and merge rules (05 s6.2): `nose_on` puts
## the 05 s5.2 nose target on the aim direction (the AI-13 form left 1 / (1 + kp_path) of the angle of attack on the
## nose), `lag_lead` leads the sight line by its rate over `kp_att`, `break_side` breaks away from the closest
## approach, `engage_speed` holds a head-on pass's closing speed at fire_range / (2 break_ttc).

const UP: Vector3 = Vector3(0, 1, 0)


# The 05 s5.2 nose target of FlightController.track_velocity for command direction `d` (uncapped lead): the velocity
# turned by kp_path x the path error, in the frame of the body right about the velocity, plus the pitch integrator.
static func _nose_target(b: Basis, v: Vector3, d: Vector3, ix: float, up: Vector3, kp: float) -> Vector3:
	var vh: Vector3 = v.normalized()
	var hr: Vector3 = (b.x - vh * b.x.dot(vh)).normalized()
	var vu: Vector3 = hr.cross(vh)
	var dl: float = d.dot(vh)
	var e_p: float = atan2(d.dot(vu), Vector2(dl, d.dot(hr)).length())
	var e_l: float = atan2(d.dot(hr), dl)
	var vn: Vector3 = (up - vh * vh.dot(up)).normalized()
	var lead: Vector3 = vu * (kp * e_p) + hr * (kp * e_l) + vn * ix
	var la: float = lead.length()
	return vh * cos(la) + lead.normalized() * sin(la) if la > 0.0 else vh


static func _ship_basis(fwd: Vector3, up: Vector3) -> Basis:
	var right: Vector3 = fwd.cross(up).normalized()
	return Basis(right, right.cross(fwd).normalized(), -fwd)


func test_nose_on_solves_the_nose_lead_law_for_the_aim_direction() -> void:
	var g: FlightGains = DartKit.gains()
	var cos20: float = cos(deg_to_rad(20.0))
	var v: Vector3 = Vector3(0, -0.05, -1).normalized() * 110.0       # sinking a little, heading -Z
	for case: Array in [[Vector3(0.08, 0.1, -1.0), 0.05], [Vector3(-0.15, -0.02, -1.0), -0.1], [Vector3(0.02, 0.2, -1.0), 0.0]]:
		var dir: Vector3 = (case[0] as Vector3).normalized()
		var ix: float = case[1]
		var b: Basis = _ship_basis(Vector3(0.03, 0.12, -1.0).normalized(), UP)   # nose ~7 degrees above the velocity
		var d: Vector3 = DartCombat.nose_on(dir, v, b, ix, UP, g.kp_path, cos20)
		assert_float(d.length()).is_equal_approx(1.0, 1e-5)
		var nose: Vector3 = _nose_target(b, v, d, ix, UP, g.kp_path)
		assert_float(rad_to_deg(nose.angle_to(dir))).is_less(0.05)
		# the AI-13 form `dir - (nose - v)` leaves part of the angle of attack on the nose target
		var old: Vector3 = (dir - (-b.z - v.normalized())).normalized()
		assert_float(rad_to_deg(_nose_target(b, v, old, ix, UP, g.kp_path).angle_to(dir))).is_greater(0.3)


func test_nose_on_hands_large_turns_to_the_velocity() -> void:
	var g: FlightGains = DartKit.gains()
	var v: Vector3 = Vector3(0, 0, -110)
	var b: Basis = _ship_basis(Vector3(0, 0, -1), UP)
	var dir: Vector3 = Vector3(1, 0, -1).normalized()                   # 45 degrees off: past aoa_comp_max_deg 20
	assert_vector(DartCombat.nose_on(dir, v, b, 0.0, UP, g.kp_path, cos(deg_to_rad(20.0)))).is_equal(dir)
	assert_vector(DartCombat.nose_on(dir, Vector3(0, 0, -0.5), b, 0.0, UP, g.kp_path, 0.0)).is_equal(dir)   # no speed


func test_lag_lead_adds_the_sight_line_rate_over_the_pointing_gain() -> void:
	var r: Vector3 = Vector3(0, 0, -400)
	var dir: Vector3 = r.normalized()
	assert_vector(DartCombat.lag_lead(dir, r, Vector3(0, 0, 30), 6.0)).is_equal_approx(dir, Vector3.ONE * 1e-6)   # no crossing
	var led: Vector3 = DartCombat.lag_lead(dir, r, Vector3(40, 0, 0), 6.0)   # target crossing to +X at 40 m/s
	assert_float(led.angle_to(dir)).is_equal_approx(atan((40.0 / 400.0) / 6.0), 1e-4)
	assert_float(led.x).is_greater(0.0)                                  # led toward the motion
	assert_vector(DartCombat.lag_lead(dir, r, Vector3(40, 0, 0), 0.0)).is_equal(dir)


func test_break_side_turns_away_from_the_closest_approach() -> void:
	var h: Vector3 = Vector3(0, 0, -1)
	# target dead ahead and slightly left now, crossing to the right: its closest approach is on the right -> break left
	var r: Vector3 = Vector3(-10, 0, -500)
	var v_rel: Vector3 = Vector3(60, 0, 220)
	var side: float = DartCombat.break_side(h, r, v_rel, UP, 2.0)
	var turned: Vector3 = h.rotated(UP, side * PI * 0.5)
	var cpa: Vector3 = r + v_rel * clampf(-r.dot(v_rel) / v_rel.length_squared(), 0.0, 2.0)
	assert_float(turned.dot(cpa)).is_less(0.0)
	assert_float(turned.dot(r)).is_greater(0.0)                           # where the AI-13 bearing rule broke the other way
	# a mirrored head-on pair turns opposite ways in the world: the two paths diverge
	var s0: float = DartCombat.break_side(h, Vector3(-20, 0, -500), Vector3(0, 0, 220), UP, 2.0)
	var s1: float = DartCombat.break_side(-h, Vector3(20, 0, 500), Vector3(0, 0, -220), UP, 2.0)
	var t0: Vector3 = h.rotated(UP, s0 * PI * 0.5)
	var t1: Vector3 = (-h).rotated(UP, s1 * PI * 0.5)
	assert_float(t0.dot(t1)).is_less(0.0)
	assert_float(t0.x).is_greater(0.0)                                    # the left-side target: break right


func test_engage_speed_holds_the_head_on_closing_speed() -> void:
	var prm: DartParams = DartKit.params()
	var c: DartCombat = DartCombat.new(prm, DartKit.gains())
	var p: Vector3 = Vector3.ZERO
	var nose: Vector3 = Vector3(0, 0, -1)
	var pt: Vector3 = Vector3(0, 0, -600)
	var cmax: float = prm.fire_range / (2.0 * prm.break_ttc)
	assert_float(cmax).is_equal_approx(162.5, 1e-3)                       # 650 / (2 x 2.0)
	assert_float(c.engage_speed(p, nose, pt, Vector3(0, 0, 110), 600.0)).is_equal_approx(cmax - 110.0, 1e-3)   # head-on
	assert_float(c.engage_speed(p, nose, pt, Vector3(0, 0, 160), 600.0)).is_equal(prm.engage_margin)            # never below
	assert_float(c.engage_speed(p, nose, pt, Vector3(0, 0, -110), 600.0)).is_equal_approx(110.0 + prm.engage_margin, 1e-3)   # tail
	assert_float(c.engage_speed(p, nose, Vector3(0, 0, -150), Vector3(0, 0, -110), 150.0)).is_equal_approx(110.0 - prm.engage_margin, 1e-3)
	assert_float(c.engage_speed(p, -nose, pt, Vector3(0, 0, 110), 600.0)).is_equal_approx(110.0 + prm.engage_margin, 1e-3)   # behind


# AI-46 round 2 (review of #150): the head-on rule caps the A-93 speed; it never replaces it.
func test_engage_speed_caps_a93_and_never_exceeds_it() -> void:
	var prm: DartParams = DartKit.params()
	var c: DartCombat = DartCombat.new(prm, DartKit.gains())
	var p: Vector3 = Vector3.ZERO
	var nose: Vector3 = Vector3(0, 0, -1)
	# a Bomber crossing ahead inside standoff_m (180 m), 5 m/s toward the shooter: A-93 = its speed - 15
	var vt: Vector3 = Vector3(59.8, 0, 5.0)
	assert_float(c.engage_speed(p, nose, Vector3(0, 0, -180), vt, 180.0)).is_equal_approx(vt.length() - prm.engage_margin, 1e-3)
	# oblique outside standoff_m, barely approaching: A-93 = its speed + 15
	var po: Vector3 = Vector3(200, 0, -500)
	var vo: Vector3 = Vector3(-10, 0, -100)
	assert_float(c.engage_speed(p, nose, po, vo, po.length())).is_equal_approx(vo.length() + prm.engage_margin, 1e-3)
	# never above A-93 in any heading of the target
	for k: int in 36:
		var a: float = deg_to_rad(10.0 * k)
		var v2: Vector3 = Vector3(sin(a), 0, cos(a)) * 110.0
		assert_float(c.engage_speed(p, nose, Vector3(0, 0, -500), v2, 500.0)).is_less_equal(110.0 + prm.engage_margin + 1e-3)


func test_engage_speed_is_continuous_where_the_target_turns_toward() -> void:
	var prm: DartParams = DartKit.params()
	var c: DartCombat = DartCombat.new(prm, DartKit.gains())
	var pt: Vector3 = Vector3(0, 0, -400)
	var opening: float = c.engage_speed(Vector3.ZERO, Vector3(0, 0, -1), pt, Vector3(100, 0, -0.01), 400.0)
	var closing: float = c.engage_speed(Vector3.ZERO, Vector3(0, 0, -1), pt, Vector3(100, 0, 0.01), 400.0)
	assert_float(absf(opening - closing)).is_less(0.1)


func test_head_on_pass_needs_ahead_approaching_and_closing_past_the_limit() -> void:
	var c: DartCombat = DartCombat.new(DartKit.params(), DartKit.gains())
	assert_bool(c.head_on_pass(1.0, 110.0, 110.0)).is_true()               # 220 > 162.5
	assert_bool(c.head_on_pass(1.0, 19.0, 10.0)).is_false()                # crossing, barely closing
	assert_bool(c.head_on_pass(-1.0, 110.0, 110.0)).is_false()             # behind
	assert_bool(c.head_on_pass(1.0, 170.0, 0.0)).is_false()                # not approaching


# INTERCEPT keeps the 05 s6.2 boost for a crossing target that is barely closing and drops it only in a head-on pass.
func test_intercept_boosts_on_a_crossing_target_not_into_a_head_on_pass() -> void:
	assert_bool(_intercept_boosts(true)).override_failure_message("crossing target, barely closing: boost").is_true()
	assert_bool(_intercept_boosts(false)).override_failure_message("head-on pass: no boost").is_false()


# One INTERCEPT think of a Dart at 300 m AGL on an enemy Dart 1,300 m away (team-visible, past boost_close_m 600):
# crossing = the Dart heads 80 degrees off the sight line, the target crosses at 100 m/s closing at 10 m/s;
# otherwise nose to nose at cruise. True when the think asks for BOOST.
func _intercept_boosts(crossing: bool) -> bool:
	var w: SimWorld = DartKit.world(9)
	var b: DartBrain = DartKit.brain(w)
	var d: AiDriver = DartKit.driver(w, b)
	var c0: Vector3 = Vector3(1, 0, 0)
	var fr: Basis = Sphere.tangent_frame(c0)
	var ha: Vector3 = (fr.y * cos(deg_to_rad(80.0)) + fr.x * sin(deg_to_rad(80.0))) if crossing else fr.y
	var a: int = DartKit.spawn(w, &"dart", 0, DartKit.above(w, c0, 300.0), ha * 110.0, ha)
	var pt: Vector3 = DartKit.above(w, DartKit.offset(c0, 1300.0, 0.0) if crossing else DartKit.offset(c0, 0.0, 1300.0), 300.0)
	var vt: Vector3 = (fr.y * 100.0 - fr.x * 10.0) if crossing else -fr.y * 110.0
	var t: int = DartKit.spawn(w, &"dart", DartKit.FOE, pt, vt, vt.normalized())
	for _k: int in 9:                                                       # three Vision passes
		w.step()
	var v: SimView = w.view()
	var st: AiState = d.state
	var s: int = EntityId.slot(a)
	st.set_target(s, t)
	st.goal[s] = v.pos(t)
	st.seen_tick[s] = v.tick()
	assert_bool(v.visible_to(0, t)).is_true()
	assert_int(b.modes.combat.think(a, AiTag.Tag.INTERCEPT, v, st, v.tick())).is_equal(AiTag.Tag.INTERCEPT)
	return (st.bflags[s] & DartCombat.F_BOOST) != 0
