extends GdUnitTestSuite
## GD-27 landing points (02 s17.1, R0 B.24 A-121 / A-122): one test per `landing_*` event, the hot x1.5 read from LANDING
## flags bit1, the dead-stick +20 read from bit2, manual landings only, the Pilot side only, and `LandingGrade.from_def`
## reading the typed `ScoringDef.landing_grade` (no `raw`).

var _w: SimWorld
var _d: ScoringDef
var _ship: int


func before_test() -> void:
	_w = ScoringTestKit.world()
	_d = ScoringTestKit.def()
	_ship = ScoringTestKit.spawn(_w, &"dart", 0, 0)


func _points(grade: String) -> float:
	return Def.num((_d.landing["points"] as Dictionary)[grade])


func _land(grade: int, flags: int) -> Vector2i:
	var before: Vector2i = ScoringTestKit.score(_w, 0)
	ScoringTestKit.landing(_w, _ship, grade, flags)
	return ScoringTestKit.score(_w, 0) - before


func test_landing_hard() -> void:
	assert_object(_land(LandingGrade.Grade.HARD, ScoringTestKit.MANUAL)).is_equal(Vector2i(floori(_points("hard")), 0))


func test_landing_fair() -> void:
	assert_object(_land(LandingGrade.Grade.FAIR, ScoringTestKit.MANUAL)).is_equal(Vector2i(floori(_points("fair")), 0))


func test_landing_clean() -> void:
	assert_object(_land(LandingGrade.Grade.CLEAN, ScoringTestKit.MANUAL)).is_equal(Vector2i(floori(_points("clean")), 0))


func test_landing_ace() -> void:
	assert_object(_land(LandingGrade.Grade.ACE, ScoringTestKit.MANUAL)).is_equal(Vector2i(floori(_points("ace")), 0))


func test_landing_hot_multiplies_by_the_def_mult_from_flags_bit1() -> void:
	var want: int = floori(_points("clean") * Def.num(_d.landing["hot_mult"]))
	assert_object(_land(LandingGrade.Grade.CLEAN, ScoringTestKit.MANUAL | ScoringTestKit.HOT)).is_equal(Vector2i(want, 0))


func test_landing_dead_stick_adds_the_bonus_from_flags_bit2() -> void:
	var want: int = floori(_points("fair")) + roundi(Def.num(_d.landing["dead_stick_bonus"]))
	assert_object(_land(LandingGrade.Grade.FAIR, ScoringTestKit.MANUAL | ScoringTestKit.DEAD_STICK)).is_equal(Vector2i(want, 0))


func test_hot_and_dead_stick_together_multiply_first_then_add() -> void:
	var f: int = ScoringTestKit.MANUAL | ScoringTestKit.HOT | ScoringTestKit.DEAD_STICK
	var want: int = floori(_points("ace") * Def.num(_d.landing["hot_mult"]) + Def.num(_d.landing["dead_stick_bonus"]))
	assert_object(_land(LandingGrade.Grade.ACE, f)).is_equal(Vector2i(want, 0))


func test_auto_bent_and_crash_score_nothing_and_a_non_manual_flag_scores_nothing() -> void:
	var f: int = ScoringTestKit.MANUAL | ScoringTestKit.HOT | ScoringTestKit.DEAD_STICK
	assert_object(_land(LandingGrade.Grade.AUTO, f)).is_equal(Vector2i.ZERO)
	assert_object(_land(LandingGrade.Grade.BENT, f)).is_equal(Vector2i.ZERO)
	assert_object(_land(LandingGrade.Grade.CRASH, f)).is_equal(Vector2i.ZERO)
	assert_object(_land(LandingGrade.Grade.CLEAN, ScoringTestKit.HOT | ScoringTestKit.DEAD_STICK)).is_equal(Vector2i.ZERO)


func test_manual_landings_count_only_graded_manual_touchdowns() -> void:
	var _a: Vector2i = _land(LandingGrade.Grade.FAIR, ScoringTestKit.MANUAL)
	var _b: Vector2i = _land(LandingGrade.Grade.AUTO, 0)
	var _c: Vector2i = _land(LandingGrade.Grade.CRASH, ScoringTestKit.MANUAL)
	assert_int(ScoringTestKit.keeper(_w).ledger.manual_landings[0]).is_equal(1)


func test_a_real_manual_touchdown_scores_through_the_tick() -> void:
	var pad: int = DockingTestKit.pad(_w)
	var id: int = DockingTestKit.ship_over(_w, &"dart", 0, 0, pad, DockingTestKit.HIGH, 0.0)
	DockingTestKit.pose(_w, id, pad, 100.0, _w.economy().docking.grade.manual_window_m * 3.0, Vector3.ZERO)
	assert_bool(DockingTestKit.possess(_w, id)).is_true()
	DockingTestKit.pose(_w, id, pad, 6.0, 0.0, Vector3.ZERO)
	_w.store().fuel[EntityId.slot(id)] = 0.0
	var _d0: Array[SimEvent] = _w.drain_events()
	var _b: int = DockingTestKit.contact(_w, id, pad, 1.0, 0.0, 0.0, 0.0)
	_w.step()                                                            # the keeper scans the LANDING of the contact
	var s: Vector2i = ScoringTestKit.score(_w, 0)
	assert_int(s.x).is_greater_equal(floori(_points("hard")) + roundi(Def.num(_d.landing["dead_stick_bonus"])))
	assert_int(s.y).is_equal(0)


func test_from_def_reads_the_typed_landing_grade_block() -> void:
	var tweaked: ScoringDef = ScoringDef.from_dict(_d.raw.duplicate(true))
	tweaked.landing_grade = {"manual_window_m": 321.0}                  # raw still says 150: the typed field wins
	assert_float(LandingGrade.from_def(tweaked).manual_window_m).is_equal(321.0)
	tweaked.landing_grade = {}
	assert_object(LandingGrade.from_def(tweaked)).is_null()            # no block: refused


func test_landing_grade_no_longer_reads_scoring_raw() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/sim/scoring/landing_grade.gd")
	assert_bool(src.contains(".raw")).is_false()
