extends GdUnitTestSuite
## GD-15 / LandingGrade (02 s17.1, 03 s6.4, R0 C3-13): the q formula with the shipped `scoring.json` weights and norms,
## the grade table over the Collision landing bands of `flight_common`, the 8 m/s, 15 m/s, 25 degree and
## `pad_radius_m` boundaries (and the 15 / 25 m/s, 45 degree damage limits), the q thresholds, AUTO and the repair bonus.
## Every number comes from the defs; the table rows only scale them.

var _g: LandingGrade
var _c: FlightCommonDef


func before_test() -> void:
	_g = LandingGrade.from_def(WorldTestKit.content().scoring)
	_c = WorldTestKit.content().flight_common


func _grade(v_vert: float, v_hor: float, tilt: float, offset: float, pad_r: float, manual: bool) -> int:
	var band: int = Collision.landing_band(v_vert, v_hor, tilt, _c)
	return _g.grade(band, _g.q(v_vert, v_hor, tilt, offset, pad_r), manual)


func test_from_def_reads_the_shipped_landing_block() -> void:
	var l: Dictionary = WorldTestKit.content().scoring.landing
	assert_object(_g).is_not_null()
	assert_float(_g.w_vert + _g.w_horiz + _g.w_tilt + _g.w_offset).is_equal_approx(1.0, 1e-9)
	assert_float(_g.n_vert).is_equal(_c.landing_safe_v_vert)          # the q norms are the safe limits
	assert_float(_g.n_horiz).is_equal(_c.landing_safe_v_hor)
	assert_float(_g.n_tilt).is_equal(_c.landing_safe_pitch_deg)
	assert_float(_g.t_fair).is_equal(Def.num((l["q_thresholds"] as Dictionary)["fair"]))
	assert_float(_g.t_ace).is_equal(Def.num((l["q_thresholds"] as Dictionary)["ace"]))
	assert_float(_g.hot_radius_m).is_equal(Def.num(l["hot_enemy_range_m"]))
	assert_float(_g.repair_time_mult).is_equal(Def.num(l["repair_time_mult"]))
	assert_float(_g.manual_window_m).is_equal(_c.auto_dock_radius_m)  # "final 150 m" = the auto-dock radius
	assert_object(LandingGrade.from_def(null)).is_null()
	var broken: ScoringDef = ScoringDef.from_dict(WorldTestKit.content().scoring.raw.duplicate(true))
	var _e: bool = broken.landing.erase("q_norms")
	assert_object(LandingGrade.from_def(broken)).is_null()


func test_q_formula_terms_and_clamps() -> void:
	var r: float = 10.0
	assert_float(_g.q(0.0, 0.0, 0.0, 0.0, r)).is_equal_approx(1.0, 1e-9)
	assert_float(_g.q(_g.n_vert, _g.n_horiz, _g.n_tilt, r, r)).is_equal_approx(0.0, 1e-9)
	assert_float(_g.q(_g.n_vert * 0.5, 0.0, 0.0, 0.0, r)).is_equal_approx(1.0 - _g.w_vert * 0.5, 1e-9)
	assert_float(_g.q(0.0, _g.n_horiz * 0.5, 0.0, 0.0, r)).is_equal_approx(1.0 - _g.w_horiz * 0.5, 1e-9)
	assert_float(_g.q(0.0, 0.0, _g.n_tilt * 0.5, 0.0, r)).is_equal_approx(1.0 - _g.w_tilt * 0.5, 1e-9)
	assert_float(_g.q(0.0, 0.0, 0.0, r * 0.5, r)).is_equal_approx(1.0 - _g.w_offset * 0.5, 1e-9)
	assert_float(_g.q(-5.0, 0.0, 0.0, 0.0, r)).is_equal_approx(1.0, 1e-9)                      # climbing: term clamped to 1
	assert_float(_g.q(_g.n_vert * 3.0, 0.0, 0.0, 0.0, r)).is_equal_approx(1.0 - _g.w_vert, 1e-9)   # term clamped to 0
	assert_float(_g.q(0.0, 0.0, 0.0, r * 2.0, r)).is_equal_approx(1.0 - _g.w_offset, 1e-9)
	assert_float(_g.q(0.0, 0.0, 0.0, 0.0, 0.0)).is_equal_approx(1.0 - _g.w_offset, 1e-9)       # no pad radius: offset term 0


## 24 rows: (v_vert, v_horiz, tilt, offset as a share of pad_radius_m, manual, expected grade). sv/sh/st = the safe
## limits, dv/dh/dt = the damage limits; e = 0.01.
func test_grade_table_24_cases_with_the_boundaries() -> void:
	var sv: float = _c.landing_safe_v_vert
	var sh: float = _c.landing_safe_v_hor
	var st: float = _c.landing_safe_pitch_deg
	var dv: float = _c.landing_damage_v_vert
	var dh: float = _c.landing_damage_v_hor
	var dt: float = _c.landing_damage_tilt_deg
	var e: float = 0.01
	var rows: Array = [
		[0.0, 0.0, 0.0, 0.0, true, LandingGrade.Grade.ACE],                 # 1 perfect
		[sv, sh * 0.2, 0.0, 0.0, true, LandingGrade.Grade.FAIR],          # 2 exactly 8 m/s: safe, q 0.60
		[sv + e, 0.0, 0.0, 0.0, true, LandingGrade.Grade.BENT],             # 3 just over 8 m/s: damage band
		[0.0, sh, 0.0, 0.0, true, LandingGrade.Grade.CLEAN],                # 4 exactly 15 m/s: safe, q 0.75
		[0.0, sh + e, 0.0, 0.0, true, LandingGrade.Grade.BENT],             # 5 just over 15 m/s
		[0.0, 0.0, st, 0.0, true, LandingGrade.Grade.CLEAN],                # 6 exactly 25 degrees: safe, q 0.80
		[0.0, 0.0, st + e, 0.0, true, LandingGrade.Grade.BENT],             # 7 just over 25 degrees
		[0.0, 0.0, 0.0, 1.0, true, LandingGrade.Grade.CLEAN],               # 8 offset = pad_radius_m: inside, q 0.80
		[sv, sh, st, 1.0, true, LandingGrade.Grade.HARD],                   # 9 every limit at once: q 0
		[sv * 0.5, sh * 0.5, st * 0.5, 0.5, true, LandingGrade.Grade.FAIR], # 10 every term 0.5: q 0.50
		[sv * 0.25, 0.0, 0.0, 0.0, true, LandingGrade.Grade.ACE],           # 11 q 0.9125
		[sv * 0.5, 0.0, 0.0, 0.5, true, LandingGrade.Grade.CLEAN],          # 12 q 0.725
		[sv, sh * 0.5, st * 0.5, 0.5, true, LandingGrade.Grade.HARD],       # 13 q 0.325
		[-5.0, 0.0, 0.0, 0.0, true, LandingGrade.Grade.ACE],                # 14 climbing through the volume
		[0.0, 0.0, 0.0, 0.0, false, LandingGrade.Grade.AUTO],               # 15 perfect but assisted
		[sv, sh, st, 1.0, false, LandingGrade.Grade.AUTO],                  # 16 q 0, assisted
		[sv + e, 0.0, 0.0, 0.0, false, LandingGrade.Grade.BENT],            # 17 assisted damage band: the outcome outranks AUTO
		[dv, 0.0, 0.0, 0.0, true, LandingGrade.Grade.BENT],                 # 18 exactly the 15 m/s damage limit: still lands
		[dv + e, 0.0, 0.0, 0.0, true, LandingGrade.Grade.CRASH],            # 19 beyond it: destroyed
		[0.0, dh, 0.0, 0.0, true, LandingGrade.Grade.BENT],                 # 20 exactly the 25 m/s damage limit
		[0.0, dh + e, 0.0, 0.0, true, LandingGrade.Grade.CRASH],            # 21 beyond it
		[0.0, 0.0, dt, 0.0, true, LandingGrade.Grade.BENT],                 # 22 exactly 45 degrees
		[0.0, 0.0, dt + e, 0.0, false, LandingGrade.Grade.CRASH],           # 23 beyond it, assisted: still CRASH
		[sv - e, sh - e, st - e, 1.0, true, LandingGrade.Grade.HARD],       # 24 just inside every safe limit
	]
	var r: float = 10.0
	for i: int in rows.size():
		var row: Array = rows[i]
		var got: int = _grade(float(row[0]), float(row[1]), float(row[2]), float(row[3]) * r, r, bool(row[4]))
		assert_int(got).override_failure_message("row %d %s: got %d" % [i + 1, str(row), got]).is_equal(int(row[5]))
	assert_int(rows.size()).is_greater_equal(20)


func test_q_threshold_edges_are_inclusive() -> void:
	var safe: int = Collision.L_SAFE
	assert_int(_g.grade(safe, _g.t_ace, true)).is_equal(LandingGrade.Grade.ACE)
	assert_int(_g.grade(safe, _g.t_ace - 1e-6, true)).is_equal(LandingGrade.Grade.CLEAN)
	assert_int(_g.grade(safe, _g.t_clean, true)).is_equal(LandingGrade.Grade.CLEAN)
	assert_int(_g.grade(safe, _g.t_clean - 1e-6, true)).is_equal(LandingGrade.Grade.FAIR)
	assert_int(_g.grade(safe, _g.t_fair, true)).is_equal(LandingGrade.Grade.FAIR)
	assert_int(_g.grade(safe, _g.t_fair - 1e-6, true)).is_equal(LandingGrade.Grade.HARD)
	assert_int(_g.grade(safe, 0.0, true)).is_equal(LandingGrade.Grade.HARD)
	assert_int(_g.grade(Collision.L_DAMAGE, 1.0, true)).is_equal(LandingGrade.Grade.BENT)
	assert_int(_g.grade(Collision.L_DESTROY, 1.0, true)).is_equal(LandingGrade.Grade.CRASH)


func test_repair_bonus_only_for_fair_or_better() -> void:
	var want: Dictionary = {LandingGrade.Grade.CRASH: false, LandingGrade.Grade.BENT: false, LandingGrade.Grade.HARD: false,
		LandingGrade.Grade.FAIR: true, LandingGrade.Grade.CLEAN: true, LandingGrade.Grade.ACE: true, LandingGrade.Grade.AUTO: false}
	for g: int in want:
		assert_bool(LandingGrade.repair_bonus(g)).override_failure_message("grade %d" % g).is_equal(bool(want[g]))
	assert_bool(LandingGrade.repair_bonus(-1)).is_false()


func test_landing_log_records_per_entity_and_survives_s4() -> void:
	var log_a: LandingLog = LandingLog.new()
	var id: int = EntityId.make(5, 3)
	assert_int(log_a.grade_of(id)).is_equal(-1)
	assert_float(log_a.q_of(id)).is_equal(-1.0)
	log_a.record(id, LandingGrade.Grade.CLEAN, 0.7)
	assert_int(log_a.grade_of(id)).is_equal(LandingGrade.Grade.CLEAN)
	assert_float(log_a.q_of(id)).is_equal_approx(0.7, 1e-6)
	assert_int(log_a.grade_of(EntityId.make(5, 4))).is_equal(-1)         # the slot's next entity has no landing
	assert_int(log_a.grade_of(0)).is_equal(-1)
	assert_int(log_a.grade_of(EntityId.make(EntityId.WRECK_SLOT_MIN + 3, 1))).is_equal(-1)
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	log_a.write_state(buf)
	var log_b: LandingLog = LandingLog.new()
	buf.seek(0)
	assert_bool(log_b.read_state(buf)).is_true()
	assert_int(log_b.grade_of(id)).is_equal(LandingGrade.Grade.CLEAN)
	log_b.g_grade[9] = LandingGrade.Grade.AUTO + 1                      # out of range: refused
	var buf2: StreamPeerBuffer = StreamPeerBuffer.new()
	log_b.write_state(buf2)
	buf2.seek(0)
	assert_bool(LandingLog.new().read_state(buf2)).is_false()
