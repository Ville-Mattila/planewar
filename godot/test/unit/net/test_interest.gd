extends GdUnitTestSuite
## NET-08 interest_test (04 s4.1): tier A (possessed, target, 600 m great-circle disc, cap 40 by distance), tier B
## (focus cell + ring 1, ring 2 at the Commander camera, cap 200, not A), tier C (V \ A \ B, cap), the 30 Hz / 15 Hz /
## 2 Hz schedule offset by the client key, hysteresis (15 ticks), team visibility and spectators, ghost retention and
## re-entry (30 s), DEATH / slot reuse / LEFT_INTEREST removals, ring tables covering the 600 m disc, determinism.

const ALT: float = 100.0

var _centre: Vector3 = Sphere.from_lat_lon(0.31, 1.17, Sphere.PLANET_RADIUS + ALT)
var _f: SnapshotFrame
var _it: Interest


func before_test() -> void:
	_f = SnapshotFrame.new()
	_it = Interest.new()


## Point `east`, `north` metres from the scene centre along the tangent plane, back on the ALT shell.
func _at(east: float, north: float) -> Vector3:
	var b: Basis = Sphere.tangent_frame(_centre)
	return (_centre + b.x * east + b.y * north).normalized() * (Sphere.PLANET_RADIUS + ALT)


func _add(slot: int, p: Vector3, team_id: int, visible: int = 0, generation: int = 1) -> int:
	var i: int = _f.count
	_f.resize(i + 1)
	_f.set_entity(i, slot, p, Vector3.ZERO, Quaternion.IDENTITY, 1.0, 0, team_id, 0, false, visible)
	_f.gen[i] = generation
	return i


func _step(clients: Array[InterestClient], tick: int) -> void:
	_f.tick = tick
	_it.begin_tick(_f, null)
	for cl: InterestClient in clients:
		_it.assign(cl)


func _one(cl: InterestClient, tick: int) -> void:
	var cls: Array[InterestClient] = [cl]
	_step(cls, tick)


## Key 0 at tick 30: A, B and C all scheduled ((30 + 0) % 2 == 0, % 15 == 0).
func test_tier_a_disc_forced_and_cap() -> void:
	var _p: int = _add(1, _at(0.0, 0.0), 0)
	for k: int in 60:                                   # own entities 100-490 m out, every 6.5 m
		var r: float = 100.0 + 6.5 * k
		var _i: int = _add(10 + k, _at(r * cos(k * 0.7), r * sin(k * 0.7)), 0)
	var _o: int = _add(200, _at(640.0, 0.0), 0)          # outside the disc
	var _t: int = _add(300, _at(2000.0, 0.0), 1, 0x1)    # visible enemy target, 2 km
	var cl: InterestClient = InterestClient.new(0, 0)
	cl.possessed = 1
	cl.target = 300
	_one(cl, 30)
	assert_int(cl.a.size()).is_equal(InterestClient.A_CAP)
	assert_bool(cl.a.has(1) and cl.a.has(300)).is_true()
	for k: int in 38:                                   # the 38 nearest fill the rest
		assert_bool(cl.a.has(10 + k)).override_failure_message("slot %d" % (10 + k)).is_true()
	assert_bool(cl.a.has(200) or cl.a.has(10 + 59)).is_false()
	assert_bool(cl.b.has(200) and cl.b.has(10 + 59)).is_true()    # B takes the rest of the focus area
	for s: int in cl.a:
		assert_bool(cl.b.has(s) or cl.c.has(s)).is_false()


func test_tier_b_focus_ring_cap_and_commander_ring2() -> void:
	var focus: int = Sphere.cell_of(_centre, Sphere.GRID_INTEREST)
	var slot: int = 1
	for k: int in 250:                                  # spiral out to ~3.4 km: ring 1 and ring 2 cells
		var r: float = 40.0 + 13.5 * k
		var _i: int = _add(slot, _at(r * cos(k * 2.4), r * sin(k * 2.4)), 0)
		slot += 1
	var cl: InterestClient = InterestClient.new(0, 0)
	cl.camera_tier = InterestClient.CameraTier.COMMANDER
	cl.focus_cell = focus
	_one(cl, 30)
	assert_int(cl.a.size()).is_equal(0)                 # Commander camera, nothing possessed: no A disc
	assert_int(cl.b.size()).is_equal(InterestClient.B_CAP)
	assert_int(cl.b.size() + cl.c.size()).is_equal(250)
	var fdir: Vector3 = Sphere.cell_center_dir(focus, Sphere.GRID_INTEREST)
	var worst_b: float = 0.0
	for s: int in cl.b:
		worst_b = maxf(worst_b, _it.dir[s].distance_squared_to(fdir))
	for s: int in cl.c:                                 # every C entity is farther from the focus than every B
		if _in_ring(focus, _it.cell[s], true):
			assert_float(_it.dir[s].distance_squared_to(fdir)).is_greater_equal(worst_b)
	assert_int(cl.cells.size()).is_equal(1 + _ring_count(focus, true))
	cl = InterestClient.new(0, 0)
	cl.camera_tier = InterestClient.CameraTier.TACTICAL
	cl.focus_cell = focus
	_one(cl, 60)
	assert_int(cl.a.size()).is_greater(0)               # Tactical: the 600 m disc around the focus point
	for s: int in cl.b:
		assert_bool(_in_ring(focus, _it.cell[s], false)).is_true()
	assert_int(cl.cells.size()).is_equal(1 + _ring_count(focus, false))


func _in_ring(focus: int, c: int, two: bool) -> bool:
	if c == focus:
		return true
	var stride: int = Interest.RING2_STRIDE if two else Interest.RING1_STRIDE
	var ring: PackedInt32Array = _it.ring2 if two else _it.ring1
	for j: int in stride:
		if ring[focus * stride + j] == c:
			return true
	return false


func _ring_count(focus: int, two: bool) -> int:
	var n: int = 0
	var stride: int = Interest.RING2_STRIDE if two else Interest.RING1_STRIDE
	var ring: PackedInt32Array = _it.ring2 if two else _it.ring1
	for j: int in stride:
		n += 1 if ring[focus * stride + j] >= 0 else 0
	return n


func test_schedule_follows_client_key() -> void:
	var _p: int = _add(1, _at(0.0, 0.0), 0)
	var _q: int = _add(2, _at(300.0, 0.0), 0)
	var _r: int = _add(3, _at(700.0, 0.0), 0)           # outside the disc, inside ring 1
	var _s: int = _add(4, _at(4000.0, 0.0), 0)
	var clients: Array[InterestClient] = []
	for k: int in 8:
		var cl: InterestClient = InterestClient.new(k, 0)
		cl.possessed = 1
		clients.append(cl)
	for t: int in range(1, 61):
		_step(clients, t)
		for cl: InterestClient in clients:
			assert_bool(cl.a.has(1) and cl.a.has(2)).is_true()
			assert_bool(cl.b_tick).is_equal((t + cl.key) % 2 == 0)
			assert_bool(cl.c_tick).is_equal((t + cl.key) % 15 == 0)
			assert_bool(cl.b.has(3)).is_equal(cl.b_tick)
			assert_bool(cl.c.is_empty()).is_equal(not cl.c_tick)
			if cl.c_tick:
				assert_bool(cl.c.has(4)).is_true()


func test_team_visibility_and_spectator() -> void:
	var _p: int = _add(1, _at(0.0, 0.0), 0)
	var hidden: int = _add(2, _at(200.0, 0.0), 1, 0x2)   # team 1, visible to team 1 only
	var _v: int = _add(3, _at(250.0, 0.0), 1, 0x3)       # team 1, spotted by team 0
	var cl: InterestClient = InterestClient.new(0, 0)
	cl.possessed = 1
	cl.target = 2                                       # a target the team cannot see is not forced
	var spec: InterestClient = InterestClient.new(0, 0)
	spec.spectator = true
	spec.follow = 2
	var both: Array[InterestClient] = [cl, spec]
	for t: int in range(1, 31):
		_step(both, t)
		assert_bool(cl.a.has(2) or cl.b.has(2) or cl.c.has(2) or cl.in_roster(2)).is_false()
	assert_bool(cl.a.has(3) and cl.in_roster(3)).is_true()
	assert_bool(spec.a.has(1) and spec.a.has(2) and spec.a.has(3)).is_true()   # spectator: everything, A around the followed entity
	_f.visible_mask[hidden] = 0x3
	_step(both, 31)
	assert_bool(cl.a.has(2) and cl.added.has(2)).is_true()


func test_hysteresis_holds_a_tier_for_15_ticks() -> void:
	var _p: int = _add(1, _at(0.0, 0.0), 0)
	var edge: int = _add(2, _at(590.0, 0.0), 0)
	var cl: InterestClient = InterestClient.new(1, 0)
	cl.possessed = 1
	var changes: int = 0
	var was_a: bool = false
	var entered: int = -100
	for t: int in range(1, 121):
		_f.pos[edge] = _at(590.0 if t % 2 == 1 else 615.0, 0.0)   # flips across the 600 m edge every tick
		_one(cl, t)
		var now_a: bool = cl.a.has(2)
		if now_a and not was_a:
			assert_int(t - entered).is_greater_equal(InterestClient.STICKY_TICKS)
			entered = t
		if now_a != was_a:
			changes += 1
		if not now_a and was_a:
			assert_int(t - entered).is_greater_equal(InterestClient.STICKY_TICKS)
		was_a = now_a
	assert_int(changes).is_greater(2)                   # it does move, but at most once per sticky window
	assert_int(changes).is_less_equal(ceili(240.0 / float(InterestClient.STICKY_TICKS + 1)) + 2)   # vs 120 without hysteresis


func test_ghost_retention_reentry_and_expiry() -> void:
	var _p: int = _add(1, _at(0.0, 0.0), 0)
	var foe: int = _add(2, _at(3000.0, 0.0), 1, 0x3)
	var cl: InterestClient = InterestClient.new(0, 0)
	cl.possessed = 1
	var t: int = 1
	while t <= 15:
		_one(cl, t)
		t += 1
	assert_bool(cl.in_roster(2)).is_true()
	_f.visible_mask[foe] = 0x2                           # leaves V: a ghost
	var gone_at: int = 15
	while t <= gone_at + 600:                            # 20 s later: still a ghost, never sent
		_one(cl, t)
		assert_bool(cl.c.has(2) or cl.removed.has(2)).is_false()
		t += 1
	assert_bool(cl.in_roster(2)).is_true()
	_f.visible_mask[foe] = 0x3                           # re-entry inside 30 s: no new ENTITY_META
	var seen: bool = false
	for _k: int in 15:
		_one(cl, t)
		assert_bool(cl.added.has(2)).is_false()
		seen = seen or cl.a.has(2) or cl.b.has(2) or cl.c.has(2)
		t += 1
	assert_bool(seen).is_true()
	_f.visible_mask[foe] = 0x2
	gone_at = t - 1
	var removed_at: int = -1
	while t <= gone_at + InterestClient.GHOST_TICKS + InterestClient.C_PERIOD:
		_one(cl, t)
		if cl.removed.has(2):
			assert_int(removed_at).is_equal(-1)
			removed_at = t
			assert_int(cl.removed_reason[cl.removed.find(2)]).is_equal(Protocol.RosterRemoveReason.OUT_OF_VISION)
		t += 1
	# last seen on one of its tier ticks (<= 15 before it left), checked on C ticks: 30 s +- 0.5 s
	assert_int(removed_at - gone_at).is_between(InterestClient.GHOST_TICKS - InterestClient.C_PERIOD,
			InterestClient.GHOST_TICKS + InterestClient.C_PERIOD)
	assert_bool(cl.in_roster(2)).is_false()
	_f.visible_mask[foe] = 0x3
	for _k: int in InterestClient.C_PERIOD:
		_one(cl, t)
		t += 1
	assert_bool(cl.added.has(2) and cl.in_roster(2)).is_true()   # after expiry it joins again with ENTITY_META


func test_death_slot_reuse_and_left_interest() -> void:
	var _p: int = _add(1, _at(0.0, 0.0), 0)
	var dying: int = _add(2, _at(100.0, 0.0), 0)
	var _far: int = _add(3, _at(3500.0, 0.0), 0)
	var _far2: int = _add(4, _at(3600.0, 0.0), 0)
	var cl: InterestClient = InterestClient.new(0, 0)
	cl.possessed = 1
	_one(cl, 15)
	assert_bool(cl.in_roster(2) and cl.in_roster(3) and cl.in_roster(4)).is_true()
	_f.gen[dying] = 2                                    # slot re-used inside A: ENTITY_META again at once
	_one(cl, 16)
	assert_bool(cl.added.has(2)).is_true()
	_f.slot[dying] = 9                                   # the entity in slot 2 is gone from the frame
	var t: int = 17
	while true:
		_one(cl, t)
		t += 1
		if cl.c_tick:
			break
	assert_int(cl.removed_reason[cl.removed.find(2)]).is_equal(Protocol.RosterRemoveReason.DEATH)
	cl.c_cap = 1                                         # slot 4 is visible but never tiered again
	var gone_at: int = t - 1
	var reason: int = -1
	while t <= gone_at + InterestClient.GHOST_TICKS + InterestClient.C_PERIOD:
		_one(cl, t)
		if cl.removed.has(4):
			reason = cl.removed_reason[cl.removed.find(4)]
		t += 1
	assert_int(reason).is_equal(Protocol.RosterRemoveReason.LEFT_INTEREST)
	assert_bool(cl.in_roster(3)).is_true()


## The 600 m disc around any point lies in its cell or ring 1 (cells are wider than 600 m everywhere).
func test_ring1_covers_the_600m_disc() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 8
	for _n: int in 4000:
		var d: Vector3 = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
		if _n % 4 == 0:                                  # near a cube corner, where cells are smallest
			d = Vector3(signf(d.x) * 0.58, signf(d.y) * 0.58, signf(d.z) * 0.58) + d * 0.02
		d = d.normalized()
		var c: int = Sphere.cell_of(d, Sphere.GRID_INTEREST)
		var b: Basis = Sphere.tangent_frame(d)
		var ang: float = rng.randf() * TAU
		var q: Vector3 = Sphere.slerp_dir(d, (d + (b.x * cos(ang) + b.y * sin(ang)) * 0.2).normalized(),
				InterestClient.A_RADIUS_M / (0.2 * Sphere.PLANET_RADIUS))
		var qc: int = Sphere.cell_of(q, Sphere.GRID_INTEREST)
		assert_bool(_in_ring(c, qc, false)).override_failure_message("cell %d -> %d" % [c, qc]).is_true()


func _run(seed_value: int) -> String:
	before_test()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	for s: int in 400:
		var _i: int = _add(s, _at(rng.randf_range(-4000.0, 4000.0), rng.randf_range(-4000.0, 4000.0)), s % 3,
				rng.randi() & 0x7)
	var clients: Array[InterestClient] = []
	for k: int in 8:
		var cl: InterestClient = InterestClient.new(k, k % 3)
		cl.possessed = k * 3 + k % 3
		cl.target = (k * 7 + 1) % 400
		cl.camera_tier = k % 3
		clients.append(cl)
	var ctx: HashingContext = HashingContext.new()
	var _s: int = ctx.start(HashingContext.HASH_SHA256)
	for t: int in range(1, 121):
		for i: int in _f.count:
			_f.pos[i] = Sphere.slerp_dir(_f.pos[i], _at(0.0, 0.0), 0.002) * (Sphere.PLANET_RADIUS + ALT)
			_f.visible_mask[i] = _f.visible_mask[i] ^ (1 if (i + t) % 97 == 0 else 0)
		_step(clients, t)
		for cl: InterestClient in clients:
			for arr: PackedInt32Array in [cl.a, cl.b, cl.c, cl.added, cl.removed, cl.removed_reason]:
				var _u: int = ctx.update(PackedInt32Array([arr.size()]).to_byte_array())
				if not arr.is_empty():
					_u = ctx.update(arr.to_byte_array())
	return ctx.finish().hex_encode()


func test_determinism() -> void:
	assert_str(_run(5)).is_equal(_run(5))
	assert_str(_run(5)).is_not_equal(_run(6))
