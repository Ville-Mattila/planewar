extends GdUnitTestSuite
## AI-11: FormationParams, Formation slot geometry (05 s5.6) and Separation (05 s5.4, SwarmWorld as the SimView).

const R: float = Sphere.PLANET_RADIUS
const ALT: float = 300.0


func _lead_p() -> Vector3:
	return Vector3(R + ALT, 0.0, 0.0)


# Level flight east (+Y) over (R + ALT, 0, 0): local up = +X, right = fwd x up = -Z.
func _basis_east() -> Basis:
	return Basis(Vector3(0, 1, 0).cross(Vector3(1, 0, 0)), Vector3(1, 0, 0), -Vector3(0, 1, 0))


func test_params_build_and_reject_a_missing_key() -> void:
	var prm: FormationParams = FormationKit.params()
	assert_float(prm.sep_radius_m).is_equal(60.0)
	assert_float(prm.k_form).is_equal(0.5)
	assert_float(prm.engage_radius_m).is_equal(FormationKit.engage_m())
	assert_int(prm.slot_count(false)).is_equal(4)
	assert_int(prm.slot_count(true)).is_equal(3)
	var sep: Dictionary = FormationKit.block("separation").duplicate()
	var _e: bool = sep.erase("gain")
	assert_object(FormationParams.from_dict(sep, FormationKit.block("formation"), null, 1500.0, 1000.0)).is_null()
	var form: Dictionary = FormationKit.block("formation").duplicate()
	form["class_slots_m"] = []
	assert_object(FormationParams.from_dict(FormationKit.block("separation"), form, null, 1500.0, 1000.0)).is_null()
	form["class_slots_m"] = [[1, 2]]
	assert_object(FormationParams.from_dict(FormationKit.block("separation"), form, null, 1500.0, 1000.0)).is_null()


func test_query_radius_stays_on_the_hash_ring_path() -> void:
	var ring2: float = FormationKit.ring2_m()
	assert_float(FormationKit.params().query_radius_m).is_less_equal(ring2)
	var wide: Dictionary = FormationKit.block("separation").duplicate()
	wide["query_radius_m"] = 500
	var clamped: FormationParams = FormationParams.from_dict(wide, FormationKit.block("formation"), null, 1500.0, 1000.0, ring2)
	assert_float(clamped.query_radius_m).is_equal(ring2)


func test_wing_slots_convert_back_right_up_to_right_forward_up() -> void:
	var prm: FormationParams = FormationKit.params()
	# wing.json rows are (back, right, up); the table keeps (right, forward, up), so forward = -back
	var w: WingDef = FormationKit.content().wing
	var row: Array = w.slots_brf_m[0]
	var b: float = row[0]
	var r: float = row[1]
	var u: float = row[2]
	assert_vector(prm.wing_slots[0]).is_equal(Vector3(r, -b, u))
	assert_float(prm.wing_tolerance_m).is_equal(w.slot_tolerance_m)


func test_class_slot_is_in_the_tangent_frame_of_the_velocity_heading() -> void:
	var prm: FormationParams = FormationKit.params()
	var lp: Vector3 = _lead_p()
	var lv: Vector3 = Vector3(0, 70, 0)
	# slot 0: 40 m left (right = -Z, so -40 right = +Z 40), 30 m behind (-Y), 20 m up (+X)
	var s0: Vector3 = Formation.slot_world(lp, lv, _basis_east(), 0, false, prm)
	assert_vector(s0 - lp).is_equal_approx(Vector3(20, -30, 40), Vector3(0.01, 0.01, 0.01))
	var s1: Vector3 = Formation.slot_world(lp, lv, _basis_east(), 1, false, prm)
	assert_vector(s1 - lp).is_equal_approx(Vector3(20, -30, -40), Vector3(0.01, 0.01, 0.01))
	# a climbing leader: the slot frame is still the tangent plane, not the velocity vector
	var s2: Vector3 = Formation.slot_world(lp, Vector3(30, 70, 0), _basis_east(), 2, false, prm)
	assert_vector(s2 - lp).is_equal_approx(Vector3(40, -60, 0), Vector3(0.01, 0.01, 0.01))


func test_a_nearly_stopped_leader_uses_its_nose_for_forward() -> void:
	var prm: FormationParams = FormationKit.params()
	var s: Vector3 = Formation.slot_world(_lead_p(), Vector3(0, 1, 0), _basis_east(), 2, false, prm)
	assert_vector(s - _lead_p()).is_equal_approx(Vector3(40, -60, 0), Vector3(0.01, 0.01, 0.01))


func test_wing_slot_is_in_the_leader_body_frame() -> void:
	var prm: FormationParams = FormationKit.params()
	var lp: Vector3 = _lead_p()
	var off: Vector3 = prm.wing_slots[1]   # (right, forward, up)
	# a leader pitched up 90 degrees to its velocity still defines the frame by its body: nose = +X (up), body up = -Y
	var nose: Vector3 = Vector3(1, 0, 0)
	var up_b: Vector3 = Vector3(0, -1, 0)
	var b: Basis = Basis(nose.cross(up_b), up_b, -nose)
	var s: Vector3 = Formation.slot_world(lp, Vector3(0, 70, 0), b, 1, true, prm)
	assert_vector(s - lp).is_equal_approx(b.x * off.x + nose * off.y + up_b * off.z, Vector3(0.01, 0.01, 0.01))


func test_a_slot_above_the_soft_ceiling_is_pulled_down_to_it() -> void:
	var prm: FormationParams = FormationKit.params()
	var lp: Vector3 = Vector3(R + prm.ceiling_m - 5.0, 0.0, 0.0)
	var w: Vector3 = Formation.slot_world(lp, Vector3(0, 70, 0), _basis_east(), 2, false, prm)   # +40 up
	assert_float(w.length()).is_less_equal(R + prm.ceiling_m + 0.01)


func test_v_cmd_is_leader_velocity_plus_k_form_times_error_capped_at_cruise_plus_10_percent() -> void:
	var prm: FormationParams = FormationKit.params()
	var lv: Vector3 = Vector3(0, 70, 0)
	var slot: Vector3 = Vector3(R, 0.0, 0.0)
	assert_vector(Formation.v_cmd(slot, slot, lv, 110.0, prm)).is_equal(lv)
	var v: Vector3 = Formation.v_cmd(slot + Vector3(0, -20, 0), slot, lv, 110.0, prm)   # 20 m behind its slot
	assert_vector(v).is_equal_approx(Vector3(0, 80, 0), Vector3(0.001, 0.001, 0.001))
	var capped: Vector3 = Formation.v_cmd(slot + Vector3(0, -2000, 0), slot, lv, 110.0, prm)
	assert_float(capped.length()).is_equal_approx(110.0 * prm.speed_cap_mult, 0.001)


func test_at_most_half_the_escorts_break_and_the_lower_slots_stay() -> void:
	var prm: FormationParams = FormationKit.params()
	assert_int(Formation.max_breakers(1, prm)).is_equal(1)   # a lone wingman still defends
	assert_int(Formation.max_breakers(2, prm)).is_equal(1)
	assert_int(Formation.max_breakers(4, prm)).is_equal(2)
	assert_bool(Formation.may_break(0, 2, prm)).is_false()
	assert_bool(Formation.may_break(1, 2, prm)).is_true()
	assert_bool(Formation.may_break(0, 1, prm)).is_true()
	assert_bool(Formation.may_break(1, 4, prm)).is_false()
	assert_bool(Formation.may_break(2, 4, prm)).is_true()


func test_free_slot_is_the_lowest_unused() -> void:
	assert_int(Formation.free_slot(0, 4)).is_equal(0)
	assert_int(Formation.free_slot(0b0101, 4)).is_equal(1)
	assert_int(Formation.free_slot(0b1111, 4)).is_equal(AiState.NO_SLOT)


# ---- Separation -------------------------------------------------------------------------------------------------

func _pair(p0: Vector3, v0: Vector3, p1: Vector3, v1: Vector3, team1: int = 0) -> SwarmWorld:
	var w: SwarmWorld = SwarmWorld.new(FlightTestKit.common(), FormationKit.content().rules, FormationKit.params())
	var dart: ShipDef = FormationKit.ship(&"dart")
	var g: FlightGains = FormationKit.gains(&"dart")
	var up0: Vector3 = p0.normalized()
	var up1: Vector3 = p1.normalized()
	var _a: int = w.add_ship(dart, g, FlightTestKit.spawn(dart, p0, Vector3(0, 1, 0), up0, v0), 0)
	var _b: int = w.add_ship(dart, g, FlightTestKit.spawn(dart, p1, Vector3(0, 1, 0), up1, v1), team1)
	return w


func test_proximity_push_follows_the_05_formula() -> void:
	var v: Vector3 = Vector3(0, 100, 0)
	var w: SwarmWorld = _pair(_lead_p(), v, _lead_p() + Vector3(0, 0, 30), v)   # 30 m apart side by side
	var prm: FormationParams = w.prm
	var push: Vector3 = Separation.push(w.ids[0], w.pos(w.ids[0]), v, 0, w, prm)
	var want: float = prm.sep_gain * prm.sep_push_mps * (prm.sep_radius_m - 30.0) / prm.sep_radius_m
	assert_float(push.length()).is_equal_approx(want, 0.05)
	assert_float(push.dot(Vector3(0, 0, -1))).is_greater(0.0)   # away from the neighbour
	var other: Vector3 = Separation.push(w.ids[1], w.pos(w.ids[1]), v, 0, w, prm)
	assert_vector(other + push).is_equal_approx(Vector3.ZERO, Vector3(0.01, 0.01, 0.01))


func test_enemies_and_distant_ships_are_not_avoided() -> void:
	var v: Vector3 = Vector3(0, 100, 0)
	var enemy: SwarmWorld = _pair(_lead_p(), v, _lead_p() + Vector3(0, 0, 20), v, 1)
	assert_vector(Separation.push(enemy.ids[0], enemy.pos(enemy.ids[0]), v, 0, enemy, enemy.prm)).is_equal(Vector3.ZERO)
	var far: SwarmWorld = _pair(_lead_p(), v, _lead_p() + Vector3(0, 0, 150), v)
	assert_vector(Separation.push(far.ids[0], far.pos(far.ids[0]), v, 0, far, far.prm)).is_equal(Vector3.ZERO)


func test_coincident_ships_split_in_opposite_directions() -> void:
	var v: Vector3 = Vector3(0, 100, 0)
	var w: SwarmWorld = _pair(_lead_p(), v, _lead_p(), v)
	var a: Vector3 = Separation.push(w.ids[0], w.pos(w.ids[0]), v, 0, w, w.prm)
	var b: Vector3 = Separation.push(w.ids[1], w.pos(w.ids[1]), v, 0, w, w.prm)
	assert_float(a.length()).is_greater(1.0)
	assert_vector(a + b).is_equal_approx(Vector3.ZERO, Vector3(0.01, 0.01, 0.01))


func test_look_ahead_splits_a_head_on_pair_sideways_before_the_ring() -> void:
	var w: SwarmWorld = _pair(_lead_p(), Vector3(0, 100, 0), _lead_p() + Vector3(0, 170, 4), Vector3(0, -100, 0))
	var a: Vector3 = Separation.push(w.ids[0], w.pos(w.ids[0]), w.vel(w.ids[0]), 0, w, w.prm)
	var b: Vector3 = Separation.push(w.ids[1], w.pos(w.ids[1]), w.vel(w.ids[1]), 0, w, w.prm)
	var up: Vector3 = Vector3(1, 0, 0)
	assert_float(a.length()).is_greater(5.0)
	assert_float(absf(a.dot(up))).is_less(0.01)    # horizontal
	assert_float(absf(a.z)).is_greater(5.0)        # sideways, not only along the line of closing
	assert_float(a.z * b.z).is_less(0.0)           # opposite sides
	assert_float(a.y).is_less(0.0)                 # and it sheds speed: the neighbour is ahead and closing
	# the pair is 170 m apart: only the look-ahead can have produced it
	assert_float(w.pos(w.ids[0]).distance_to(w.pos(w.ids[1]))).is_greater(w.prm.sep_radius_m)


func test_diverging_pair_gets_no_look_ahead_push() -> void:
	var w: SwarmWorld = _pair(_lead_p(), Vector3(0, -100, 0), _lead_p() + Vector3(0, 150, 4), Vector3(0, 100, 0))
	assert_vector(Separation.push(w.ids[0], w.pos(w.ids[0]), w.vel(w.ids[0]), 0, w, w.prm)).is_equal(Vector3.ZERO)


func test_pair_that_will_pass_wide_gets_no_look_ahead_push() -> void:
	var w: SwarmWorld = _pair(_lead_p(), Vector3(0, 100, 0), _lead_p() + Vector3(0, 170, 120), Vector3(0, -100, 0))
	assert_vector(Separation.push(w.ids[0], w.pos(w.ids[0]), w.vel(w.ids[0]), 0, w, w.prm)).is_equal(Vector3.ZERO)
