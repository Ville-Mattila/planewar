extends GdUnitTestSuite
## GD-23 (sim/relay/MODULE.md R1-R6; 02 s5.3, R0 C2-20): a Hauler DOCKED on the Relay Station pad for `capture_s` (20 s) with
## no enemy ship or ground unit within `contest_radius_m` (300 m) captures it; contested progress pauses; the Hauler leaving
## resets it; recapture is the same rule.

const K: GDScript = preload("res://test/unit/sim/relay/relay_test_kit.gd")

var _w: SimWorld
var _relay: int


func before_test() -> void:
	_w = K.world()
	_relay = K.relay(_w)


func test_the_rule_numbers_come_from_the_defs() -> void:
	assert_float(K.rule("capture_s")).is_equal(20.0)
	assert_float(K.rule("contest_radius_m")).is_equal(300.0)
	assert_float(K.capture(_w).capture_s).is_equal(K.rule("capture_s"))
	assert_float(K.capture(_w).contest_radius_m).is_equal(K.rule("contest_radius_m"))


func test_an_uncontested_capture_completes_at_twenty_seconds() -> void:
	var _h: int = K.docked(_w, &"hauler", 0, _relay)
	K.pass_n(_w, K.seconds(19.0))
	assert_int(K.team_of(_w, _relay)).is_equal(K.NEUTRAL)
	assert_float(K.progress(_w, _relay)).is_equal_approx(19.0, 0.1)
	K.pass_n(_w, K.seconds(1.0) + 2)
	assert_int(K.team_of(_w, _relay)).is_equal(0)
	assert_int(_w.store().owner[EntityId.slot(_relay)]).is_equal(0)
	assert_float(K.progress(_w, _relay)).is_equal(0.0)


func test_a_capture_raises_one_relay_captured_alert_and_the_score() -> void:
	var _h: int = K.docked(_w, &"hauler", 0, _relay)
	K.pass_n(_w, K.seconds(21.0))
	var alerts: Array[SimEvent] = K.of_kind(_w.drain_events(), SimEvent.Kind.ALERT, AlertKind.Kind.RELAY_CAPTURED)
	assert_int(alerts.size()).is_equal(1)
	assert_int(alerts[0].team).is_equal(0)
	assert_int(alerts[0].b).is_equal(_relay)
	assert_int(_w.economy().score.ledger.commander[0]).is_equal(int(K.rule("capture")))


func test_a_possessed_hauler_scores_the_capture_on_the_pilot_side() -> void:
	var h: int = K.docked(_w, &"hauler", 0, _relay)
	_w.store().possessor[EntityId.slot(h)] = 0
	K.pass_n(_w, K.seconds(21.0))
	assert_int(_w.economy().score.ledger.pilot[0]).is_equal(int(K.rule("capture")))


func test_an_enemy_ship_within_the_contest_radius_pauses_the_capture() -> void:
	var _h: int = K.docked(_w, &"hauler", 0, _relay)
	K.pass_n(_w, K.seconds(10.0))
	var foe: int = K.unit(_w, &"dart", 1, K.rule("contest_radius_m") - 10.0)
	K.pass_n(_w, K.seconds(30.0))
	assert_int(K.team_of(_w, _relay)).is_equal(K.NEUTRAL)
	assert_float(K.progress(_w, _relay)).is_equal_approx(10.0, 0.1)
	assert_bool(K.capture(_w).contested(EntityId.slot(_relay))).is_true()
	_w.store().pos[EntityId.slot(foe)] = DockingTestKit.far(_w)   # it flies off: the clock resumes where it stopped
	K.pass_n(_w, K.seconds(9.0))
	assert_int(K.team_of(_w, _relay)).is_equal(K.NEUTRAL)
	K.pass_n(_w, K.seconds(1.0) + 2)
	assert_int(K.team_of(_w, _relay)).is_equal(0)


func test_an_enemy_ground_unit_within_the_radius_also_contests() -> void:
	var _h: int = K.docked(_w, &"hauler", 0, _relay)
	var _g: int = K.unit(_w, &"harvester", 1, K.rule("contest_radius_m") - 10.0)
	K.pass_n(_w, K.seconds(25.0))
	assert_int(K.team_of(_w, _relay)).is_equal(K.NEUTRAL)
	assert_float(K.progress(_w, _relay)).is_equal(0.0)


func test_an_enemy_beyond_the_radius_does_not_contest() -> void:
	var _h: int = K.docked(_w, &"hauler", 0, _relay)
	var _foe: int = K.unit(_w, &"dart", 1, K.rule("contest_radius_m") + 10.0)
	K.pass_n(_w, K.seconds(21.0))
	assert_int(K.team_of(_w, _relay)).is_equal(0)


func test_a_teammate_does_not_contest() -> void:
	var _h: int = K.docked(_w, &"hauler", 0, _relay)
	var _mate: int = K.unit(_w, &"dart", 2, 50.0)          # player 2 is on team 0
	K.pass_n(_w, K.seconds(21.0))
	assert_int(K.team_of(_w, _relay)).is_equal(0)


func test_contest_raises_one_relay_contested_alert_per_start() -> void:
	var _h: int = K.docked(_w, &"hauler", 0, _relay)
	var _foe: int = K.unit(_w, &"dart", 1, 100.0)
	K.pass_n(_w, K.seconds(3.0))
	var got: Array[SimEvent] = K.of_kind(_w.drain_events(), SimEvent.Kind.ALERT, AlertKind.Kind.RELAY_CONTESTED)
	assert_int(got.size()).is_equal(1)
	assert_int(got[0].team).is_equal(0)


func test_the_hauler_leaving_resets_the_progress() -> void:
	var h: int = K.docked(_w, &"hauler", 0, _relay)
	K.pass_n(_w, K.seconds(15.0))
	assert_float(K.progress(_w, _relay)).is_greater(14.0)
	DockingTestKit.clear(_w, h)
	K.pass_n(_w, 1)
	assert_float(K.progress(_w, _relay)).is_equal(0.0)
	DockingTestKit.dock(_w, h, _relay)
	K.pass_n(_w, K.seconds(19.0))
	assert_int(K.team_of(_w, _relay)).is_equal(K.NEUTRAL)     # a fresh 20 s, not the 5 that were left
	K.pass_n(_w, K.seconds(1.0) + 2)
	assert_int(K.team_of(_w, _relay)).is_equal(0)


func test_only_a_hauler_captures() -> void:
	var _d: int = K.docked(_w, &"dart", 0, _relay)
	K.pass_n(_w, K.seconds(25.0))
	assert_int(K.team_of(_w, _relay)).is_equal(K.NEUTRAL)
	assert_float(K.progress(_w, _relay)).is_equal(0.0)


func test_a_hauler_in_flight_above_the_pad_does_not_capture() -> void:
	var _h: int = K.unit(_w, &"hauler", 0, 0.0)
	K.pass_n(_w, K.seconds(25.0))
	assert_int(K.team_of(_w, _relay)).is_equal(K.NEUTRAL)


func test_recapture_uses_the_same_rule_and_the_holder_keeps_the_pad_until_it_completes() -> void:
	var h0: int = K.docked(_w, &"hauler", 0, _relay)
	K.pass_n(_w, K.seconds(21.0))
	assert_int(K.team_of(_w, _relay)).is_equal(0)
	DockingTestKit.clear(_w, h0)
	var _h1: int = K.docked(_w, &"hauler", 1, _relay)
	K.pass_n(_w, K.seconds(19.0))
	assert_int(K.team_of(_w, _relay)).is_equal(0)
	K.pass_n(_w, K.seconds(1.0) + 2)
	assert_int(K.team_of(_w, _relay)).is_equal(1)
	assert_int(_w.store().owner[EntityId.slot(_relay)]).is_equal(1)
	assert_int(K.of_kind(_w.drain_events(), SimEvent.Kind.ALERT, AlertKind.Kind.RELAY_CAPTURED).size()).is_equal(2)


func test_the_holder_docking_on_its_own_relay_makes_no_progress() -> void:
	var h0: int = K.docked(_w, &"hauler", 0, _relay)
	K.pass_n(_w, K.seconds(21.0))
	DockingTestKit.clear(_w, h0)
	var _again: int = K.docked(_w, &"hauler", 2, _relay)      # a teammate of the holder
	K.pass_n(_w, K.seconds(25.0))
	assert_int(K.team_of(_w, _relay)).is_equal(0)
	assert_float(K.progress(_w, _relay)).is_equal(0.0)


func test_a_held_relay_credits_the_hold_score_per_minute() -> void:
	var h0: int = K.docked(_w, &"hauler", 0, _relay)
	K.pass_n(_w, K.seconds(21.0))
	DockingTestKit.clear(_w, h0)
	var before: int = _w.economy().score.ledger.commander[0]
	K.pass_n(_w, K.seconds(61.0))
	assert_int(_w.economy().score.ledger.commander[0] - before).is_equal(int(K.rule("hold_per_min")))


func test_the_world_tick_runs_the_capture() -> void:
	var _h: int = K.docked(_w, &"hauler", 0, _relay)
	var hz: int = WorldTestKit.content().rules.tick_hz
	for _i: int in 20 * hz + 3:
		_w.step()
	assert_int(K.team_of(_w, _relay)).is_equal(0)
