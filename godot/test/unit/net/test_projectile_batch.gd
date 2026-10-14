extends GdUnitTestSuite
## NET-10 projectile_batch_test (R0 C2-35): PROJECTILE_BATCH round trip incl. the flak fuse byte, direction
## quantisation, roster filtering, the one-tick re-send, client dedupe by (shooter, seed, tick), flak burst at its
## fuse tick, HIT retirement, malformed rejection.

var _rig: EventRig


func before_test() -> void:
	_rig = EventRig.new()


func _shots(tick: int) -> ShotBuffer:
	var s: ShotBuffer = ShotBuffer.new()
	s.clear(tick)
	s.add_q(EventRig.id(5), 1, 11, 10, -5)
	s.add_q(EventRig.id(6), 2, 12, -127, 127, 9)                  # flak, fuse 9 ticks
	s.add_q(EventRig.id(EventRig.ENEMY_FIRST), 1, 13, 0, 0)       # enemy outside the roster: never sent
	return s


func test_encode_decode_round_trip_with_fuse_byte() -> void:
	var s: ShotBuffer = _shots(50)
	var refs: PackedInt32Array = PackedInt32Array([5, 6, 30])
	var bytes: PackedByteArray = ProjectileBatch.encode(50, s, refs, 0, 2)
	assert_int(bytes.size()).is_equal(ProjectileBatch.HEADER_BYTES + ProjectileBatch.ITEM_BYTES + ProjectileBatch.ITEM_FUSE_BYTES)
	var out: ShotBuffer = ShotBuffer.new()
	assert_int(ProjectileBatch.decode(bytes, out)).is_equal(2)
	assert_int(out.tick).is_equal(50)
	assert_array(out.shooter).is_equal(PackedInt32Array([5, 6]))
	assert_array(out.weapon_slot).is_equal(PackedInt32Array([1, 2]))
	assert_array(out.seed_byte).is_equal(PackedInt32Array([11, 12]))
	assert_array(out.yaw_q).is_equal(PackedInt32Array([10, -127]))
	assert_array(out.pitch_q).is_equal(PackedInt32Array([-5, 127]))
	assert_array(out.fuse).is_equal(PackedInt32Array([-1, 9]))


func test_direction_quantisation_error_under_a_quarter_degree() -> void:
	var b: Basis = Basis(Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, 1.0))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	for _n: int in 500:
		var yaw: float = deg_to_rad(rng.randf_range(-60.0, 60.0))
		var pitch: float = deg_to_rad(rng.randf_range(-60.0, 60.0))
		var d: Vector3 = (b.x * (sin(yaw) * cos(pitch)) + b.y * sin(pitch) + b.z * (cos(yaw) * cos(pitch))).normalized()
		var back: Vector3 = ProjectileBatch.dequantize_dir(b, ProjectileBatch.quantize_yaw(b, d), ProjectileBatch.quantize_pitch(b, d))
		assert_float(rad_to_deg(d.angle_to(back))).is_less(0.4)


func test_router_sends_only_roster_shooters_and_resends_next_tick() -> void:
	var router: EventRouter = EventRouter.new()
	var auds: Array[EventAudience] = [_rig.aud]
	router.route_shots(50, _shots(50), auds)
	assert_int(_rig.aud.shot_out.size()).is_equal(1)
	var out: ShotBuffer = ShotBuffer.new()
	assert_int(ProjectileBatch.decode(_rig.aud.shot_out[0], out)).is_equal(2)       # the enemy shot is filtered
	_rig.aud.shot_out.clear()
	router.route_shots(51, ShotBuffer.new(), auds)
	assert_int(_rig.aud.shot_out.size()).is_equal(1)                                 # tick 50 batch again
	assert_int(ProjectileBatch.decode(_rig.aud.shot_out[0], out)).is_equal(2)
	assert_int(out.tick).is_equal(50)
	_rig.aud.shot_out.clear()
	router.route_shots(52, ShotBuffer.new(), auds)
	assert_int(_rig.aud.shot_out.size()).is_equal(0)                                 # sent exactly twice


func test_duplicate_batch_never_spawns_twice() -> void:
	var router: EventRouter = EventRouter.new()
	var auds: Array[EventAudience] = [_rig.aud]
	var tracker: ShotTracker = ShotTracker.new()
	router.route_shots(50, _shots(50), auds)
	router.route_shots(51, _shots(51), auds)
	var spawned: int = 0
	for round_n: int in 3:                                                           # also feed every packet three times
		for p: PackedByteArray in _rig.aud.shot_out:
			var n: int = tracker.accept(p, 51)
			spawned += maxi(n, 0)
	assert_int(spawned).is_equal(4)                      # tick 50 x2 shots + tick 51 x2 shots; the resend and repeats add nothing
	assert_int(tracker.count()).is_equal(4)
	assert_int(tracker.duplicates).is_greater(0)


func test_flak_bursts_at_its_fuse_tick() -> void:
	var tracker: ShotTracker = ShotTracker.new()
	var s: ShotBuffer = ShotBuffer.new()
	s.clear(100)
	s.add_q(EventRig.id(5), 3, 77, 0, 0, 12)
	var bytes: PackedByteArray = ProjectileBatch.encode(100, s, PackedInt32Array([5]), 0, 1)
	assert_int(tracker.accept(bytes, 100)).is_equal(1)
	var due: PackedInt32Array = PackedInt32Array()
	tracker.take_due_bursts(111, due)
	assert_int(due.size()).is_equal(0)
	tracker.take_due_bursts(112, due)
	assert_int(due.size()).is_equal(1)
	assert_int(due[0]).is_equal(5 | (77 << 16))
	assert_int(tracker.count()).is_equal(0)


func test_hit_retires_the_named_shot() -> void:
	var tracker: ShotTracker = ShotTracker.new()
	var s: ShotBuffer = _shots(50)
	var bytes: PackedByteArray = ProjectileBatch.encode(50, s, PackedInt32Array([5, 6, 30]), 0, 2)
	var _n: int = tracker.accept(bytes, 50)
	assert_bool(tracker.remove_hit(5, 11)).is_true()
	assert_bool(tracker.remove_hit(5, 11)).is_false()
	assert_int(tracker.count()).is_equal(1)
	tracker.expire(100, 10)
	assert_int(tracker.count()).is_equal(0)


func test_batches_split_under_1200_bytes() -> void:
	var s: ShotBuffer = ShotBuffer.new()
	s.clear(9)
	for n: int in 400:
		s.add_q(EventRig.id(5), 1, n & 0xFF, 0, 0, 5 if n % 2 == 0 else -1)
	var router: EventRouter = EventRouter.new()
	var auds: Array[EventAudience] = [_rig.aud]
	router.route_shots(9, s, auds)
	var total: int = 0
	var out: ShotBuffer = ShotBuffer.new()
	for p: PackedByteArray in _rig.aud.shot_out:
		assert_int(p.size()).is_less_equal(Protocol.MAX_UNRELIABLE_BYTES)
		total += ProjectileBatch.decode(p, out)
	assert_int(total).is_equal(400)


func test_malformed_batches_rejected_and_fuzz_safe() -> void:
	var s: ShotBuffer = _shots(50)
	var good: PackedByteArray = ProjectileBatch.encode(50, s, PackedInt32Array([5, 6, 30]), 0, 2)
	var out: ShotBuffer = ShotBuffer.new()
	assert_int(ProjectileBatch.decode(good.slice(0, good.size() - 1), out)).is_equal(-1)
	assert_int(out.count).is_equal(0)
	var longer: PackedByteArray = good.duplicate()
	longer.append(0)
	assert_int(ProjectileBatch.decode(longer, out)).is_equal(-1)
	var zero: PackedByteArray = good.duplicate()
	zero[5] = 0
	assert_int(ProjectileBatch.decode(zero, out)).is_equal(-1)
	assert_int(ProjectileBatch.decode(PackedByteArray(), out)).is_equal(-1)
	var tracker: ShotTracker = ShotTracker.new()
	assert_int(tracker.accept(longer, 50)).is_equal(-1)
	assert_int(tracker.rejected).is_equal(1)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 8
	for _n: int in 3000:
		var p: PackedByteArray = good.duplicate()
		p[rng.randi() % p.size()] = rng.randi() & 0xFF
		if rng.randi() % 3 == 0:
			p = p.slice(0, rng.randi() % p.size())
		var r: int = ProjectileBatch.decode(p, out)
		assert_int(out.count).is_equal(maxi(r, 0))
