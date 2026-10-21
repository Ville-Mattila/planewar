extends GdUnitTestSuite
## GD-36 determinism and S4: a skirmish of Darts, Lancers and all three towers firing at each other (spread draws,
## damage rolls, locks, bursts, flak fuses) gives identical events and state for one seed, other spread for another,
## and a world serialized mid-lock / mid-burst / with shells in flight resumes byte for byte (fire state in the bytes).

const TICKS: int = 90
const FIRE1: int = PilotInput.FIRE1
const FIRE2: int = PilotInput.FIRE2


func _at(alt: float, east: float = 0.0, north: float = 0.0) -> Vector3:
	return FireTestKit.at(alt, east, north)


func _setup(w: SimWorld) -> FireTestKit.TriggerHook:
	var h: FireTestKit.TriggerHook = FireTestKit.hook(w)
	CombatTestKit.power(w, 1, 1)
	for k: int in 3:
		h.hold(CombatTestKit.spawn(w, &"dart", 1, 1, _at(450.0 + 20.0 * k, -300.0, 30.0 * k)), FIRE1)
		var _t: int = CombatTestKit.spawn(w, &"lancer", 0, 0, _at(450.0 + 20.0 * k, 200.0, 30.0 * k))
	h.hold(CombatTestKit.spawn(w, &"lancer", 1, 1, _at(500.0, -350.0, 0.0)), FIRE1 | FIRE2)
	h.hold(CombatTestKit.spawn(w, &"autocannon_turret", 1, 1, _at(0.0, -200.0, 0.0)), FIRE1)
	h.hold(CombatTestKit.spawn(w, &"flak_battery", 1, 1, _at(0.0, -200.0, 200.0)), FIRE1)
	h.hold(CombatTestKit.spawn(w, &"missile_tower", 1, 1, _at(0.0, -200.0, -200.0)), FIRE1)
	return h


func _log(w: SimWorld, ticks: int, log: PackedStringArray) -> void:
	for _t: int in ticks:
		w.step()
		for e: SimEvent in w.drain_events():
			log.append("%d:%d:%d:%d:%.3f" % [e.tick, e.kind, e.a, e.b, e.value])


func _run(seed_value: int) -> PackedStringArray:
	var w: SimWorld = CombatTestKit.world(seed_value)
	var _h: FireTestKit.TriggerHook = _setup(w)
	var log: PackedStringArray = PackedStringArray()
	_log(w, TICKS, log)
	log.append(w.serialize().hex_encode().sha256_text())
	return log


func _count(log: PackedStringArray, kind: int) -> int:
	var n: int = 0
	for line: String in log:
		var parts: PackedStringArray = line.split(":")
		if parts.size() > 2 and int(parts[1]) == kind:
			n += 1
	return n


func test_fixed_seed_gives_identical_fire_events_and_state() -> void:
	var a: PackedStringArray = _run(5150)
	var b: PackedStringArray = _run(5150)
	assert_bool(a == b).is_true()
	assert_int(_count(a, SimEvent.Kind.HIT)).is_greater(10)
	assert_int(_count(a, SimEvent.Kind.LOCK_ACQUIRED)).is_greater(0)


func test_another_seed_spreads_the_shots_differently() -> void:
	assert_bool(_run(5150) == _run(6160)).is_false()


func test_s4_round_trip_mid_lock_and_mid_burst_resumes_byte_identical() -> void:
	var a: SimWorld = CombatTestKit.world(77)
	var _h: FireTestKit.TriggerHook = _setup(a)
	var log_a: PackedStringArray = PackedStringArray()
	_log(a, 20, log_a)                                           # lancer and missile tower mid-lock, turret mid-burst
	var hook_b: FireTestKit.TriggerHook = FireTestKit.TriggerHook.new()
	var saved: PackedByteArray = a.serialize()
	var b: SimWorld = SimWorld.deserialize(saved, WorldTestKit.content(), hook_b)
	assert_object(b).is_not_null()
	assert_bool(b.serialize() == saved).is_true()                # TA-65: the step-7 index and hash cells are saved too
	for t: int in TICKS:
		var la: PackedStringArray = PackedStringArray()
		var lb: PackedStringArray = PackedStringArray()
		_log(a, 1, la)
		_log(b, 1, lb)
		if la != lb or a.serialize() != b.serialize():
			fail("S4 divergence at tick %d" % a.tick())
			return
		log_a.append_array(la)
	assert_int(_count(log_a, SimEvent.Kind.LOCK_ACQUIRED)).is_greater(0)
	assert_int(_count(log_a, SimEvent.Kind.HIT)).is_greater(10)


func test_fire_state_bytes_round_trip() -> void:
	var w: SimWorld = CombatTestKit.world()
	var f: WeaponFire = FireTestKit.combat(w).fire
	f.lock_target[5] = 1234
	f.lock_time[5] = 0.5
	f.unsupplied[9] = 1
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	f.write_state(buf)
	var g: WeaponFire = FireTestKit.combat(CombatTestKit.world()).fire
	buf.seek(0)
	assert_bool(g.read_state(buf)).is_true()
	assert_int(g.lock_target[5]).is_equal(1234)
	assert_float(g.lock_time[5]).is_equal(0.5)
	assert_int(g.unsupplied[9]).is_equal(1)
	g.forget(9)
	assert_int(g.unsupplied[9]).is_equal(0)
