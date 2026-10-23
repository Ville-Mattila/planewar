extends GdUnitTestSuite
## AI-17 contract tests: `AiHitLog` (the last HIT each AI entity landed, for the tower choice point), AiState FORMAT 7
## (the hit record in the S4 bytes; FORMAT 6 bytes refused), and `AiDriver.on_event(HIT)` writing it for registered
## attackers only.

const TEAM: int = 0
const WINDOW: int = 150


func _id(slot: int) -> int:
	return EntityId.make(slot, 1)


func test_record_attacking_and_guarding_windows() -> void:
	var log: AiHitLog = AiHitLog.new()
	log.resize(16)
	for s: int in 16:
		log.clear(s)
	assert_int(log.team[3]).is_equal(AiHitLog.NO_TEAM)
	var at: Vector3 = Vector3(100.0, 0.0, 0.0)
	log.record(3, 500, _id(9), TEAM, at)
	assert_bool(log.attacking(3, TEAM, 600, WINDOW, at + Vector3(0, 590, 0), 600.0 * 600.0)).is_true()
	assert_bool(log.attacking(3, TEAM, 600, WINDOW, at + Vector3(0, 610, 0), 600.0 * 600.0)).is_false()   # beyond the radius
	assert_bool(log.attacking(3, TEAM, 650, WINDOW, at, 1.0)).is_false()                                  # window ended (500 + 150)
	assert_bool(log.attacking(3, 1, 600, WINDOW, at, 1.0)).is_false()                                      # another team's asset
	assert_bool(log.attacking(4, TEAM, 600, WINDOW, at, 1.0)).is_false()                                   # no hit by slot 4
	assert_bool(log.guarding(3, _id(9), 600, WINDOW)).is_true()
	assert_bool(log.guarding(3, _id(8), 600, WINDOW)).is_false()
	assert_bool(log.guarding(3, _id(9), 650, WINDOW)).is_false()
	log.clear(3)
	assert_bool(log.guarding(3, _id(9), 600, WINDOW)).is_false()


func test_a_team_outside_u8_is_not_recorded_as_a_team() -> void:
	var log: AiHitLog = AiHitLog.new()
	log.resize(4)
	log.record(1, 10, _id(2), -1, Vector3.ZERO)
	assert_int(log.team[1]).is_equal(AiHitLog.NO_TEAM)


func test_ai_state_format7_round_trips_the_hit_record_and_refuses_format6() -> void:
	assert_int(AiState.FORMAT).is_equal(7)
	var st: AiState = AiState.new(32)
	st.cls[5] = 1
	st.eid[5] = _id(5)
	st.hits.record(5, 321, _id(9), 1, Vector3(1.5, -2.5, 3.5))
	var bytes: PackedByteArray = st.serialize()
	var r: AiState = AiState.new(32)
	assert_bool(r.deserialize(bytes)).is_true()
	assert_int(r.hits.tick[5]).is_equal(321)
	assert_int(r.hits.victim[5]).is_equal(_id(9))
	assert_int(r.hits.team[5]).is_equal(1)
	assert_object(r.hits.pos[5]).is_equal(Vector3(1.5, -2.5, 3.5))
	assert_bool(r.serialize() == bytes).is_true()
	r.clear_slot(5)
	assert_int(r.hits.tick[5]).is_equal(0)
	assert_int(r.hits.team[5]).is_equal(AiHitLog.NO_TEAM)
	var old: PackedByteArray = bytes.duplicate()
	old[0] = 6   # a FORMAT 6 blob (AI-14) is refused, state cleared
	assert_bool(r.deserialize(old)).is_false()
	assert_int(r.registered_count()).is_equal(0)
	assert_int(r.hits.tick[5]).is_equal(0)


func test_ai_state_grows_the_log_with_its_capacity() -> void:
	var st: AiState = AiState.new(8)
	st.ensure_capacity(64)
	assert_int(st.hits.tick.size()).is_equal(64)
	assert_int(st.hits.team[63]).is_equal(AiHitLog.NO_TEAM)


func test_driver_records_a_hit_for_a_registered_attacker_only() -> void:
	var d: AiDriver = AiDriver.new(Rng.new(1))
	assert_bool(d.register(_id(4), 2)).is_true()
	var ev: SimEvent = SimEvent.new()
	ev.kind = SimEvent.Kind.HIT
	ev.tick = 77
	ev.a = _id(9)          # victim
	ev.b = _id(4)          # attacker
	ev.pos = Vector3(5.0, 6.0, 7.0)
	ev.team = 1
	d.on_event(ev)
	assert_int(d.state.hits.tick[4]).is_equal(77)
	assert_int(d.state.hits.victim[4]).is_equal(_id(9))
	assert_int(d.state.hits.team[4]).is_equal(1)
	assert_object(d.state.hits.pos[4]).is_equal(Vector3(5.0, 6.0, 7.0))
	ev.b = _id(6)          # not registered
	ev.tick = 90
	d.on_event(ev)
	assert_int(d.state.hits.tick[6]).is_equal(0)
	ev.b = EntityId.make(4, 2)   # a stale generation of slot 4
	d.on_event(ev)
	assert_int(d.state.hits.tick[4]).is_equal(77)
	assert_bool(d.unregister(_id(4))).is_true()
	assert_int(d.state.hits.tick[4]).is_equal(0)   # a dead attacker's record goes with its slot
