extends GdUnitTestSuite
## GD-08 determinism: damage rolls draw only from SimWorld.rng (S7), in contact order, so a fixed seed gives an
## identical event stream and entity state; a serialized world resumes onto the same stream; another seed rolls
## different damage. The scenario fires slugs, a bomb and a flak shell every few ticks at a mixed group.

const R: float = Sphere.PLANET_RADIUS
const TICKS: int = 24


func _at(alt: float, east: float = 0.0, north: float = 0.0) -> Vector3:
	return Vector3(R + alt, east, north)


## Builds the group and returns its EntityIds (ships in the air, a structure and a ground unit on the ground).
func _setup(w: SimWorld) -> PackedInt32Array:
	var ids: PackedInt32Array = PackedInt32Array()
	for k: int in 4:
		ids.append(CombatTestKit.spawn(w, &"lancer", 0, 0, _at(500.0, 40.0 * float(k))))
	ids.append(CombatTestKit.spawn(w, &"refinery", 0, 0, _at(0.0, -200.0)))
	ids.append(CombatTestKit.spawn(w, &"harvester", 0, 0, _at(0.0, 200.0)))
	return ids


## Fires this tick's shots (a pure function of `tick` and the store) and steps; returns the event log lines.
func _tick(w: SimWorld, ids: PackedInt32Array, log: PackedStringArray) -> void:
	var t: int = w.tick()
	for k: int in ids.size():
		if (t + k) % 3 == 0 and w.store().alive(ids[k]):
			var p: Vector3 = w.store().pos[EntityId.slot(ids[k])]
			var owner: int = 3 if k % 2 == 0 else 1
			var _s: int = CombatTestKit.shot(w, &"slug_light", &"gun_dart", p, owner, 1, 5 + k)
	if t % 7 == 0:
		var _f: int = CombatTestKit.shot(w, &"flak_shell", &"flak_gun", _at(500.0, 20.0), 1, 1)
	if t % 11 == 0:
		var _b: int = CombatTestKit.shot(w, &"bomb", &"bomb", _at(0.5, -190.0), 1, 1)
	w.step()
	for e: SimEvent in w.drain_events():
		log.append("%d:%d:%d:%d:%.3f" % [e.tick, e.kind, e.a, e.b, e.value])


func _run(seed_value: int, ticks: int) -> PackedStringArray:
	var w: SimWorld = CombatTestKit.world(seed_value)
	var ids: PackedInt32Array = _setup(w)
	var log: PackedStringArray = PackedStringArray()
	for _t: int in ticks:
		_tick(w, ids, log)
	log.append(str(WorldTestKit.store_bytes(w).hex_encode().sha256_text()))
	return log


func test_fixed_seed_gives_identical_events_and_state() -> void:
	var a: PackedStringArray = _run(1234, TICKS)
	var b: PackedStringArray = _run(1234, TICKS)
	assert_int(a.size()).is_greater(8)
	assert_bool(a == b).is_true()
	var hits: int = 0
	for line: String in a:
		if line.split(":").size() > 2 and int(line.split(":")[1]) == SimEvent.Kind.HIT:
			hits += 1
	assert_int(hits).is_greater(5)


func test_another_seed_rolls_other_damage() -> void:
	var a: PackedStringArray = _run(1234, TICKS)
	var b: PackedStringArray = _run(4321, TICKS)
	assert_bool(a == b).is_false()


func test_resume_from_serialized_state_continues_the_same_stream() -> void:
	var w: SimWorld = CombatTestKit.world(99)
	var ids: PackedInt32Array = _setup(w)
	var log_a: PackedStringArray = PackedStringArray()
	for _t: int in 8:
		_tick(w, ids, log_a)
	var copy: SimWorld = SimWorld.deserialize(w.serialize(), WorldTestKit.content(), null)
	assert_object(copy).is_not_null()
	var rest_a: PackedStringArray = PackedStringArray()
	var rest_b: PackedStringArray = PackedStringArray()
	for _t: int in 16:
		_tick(w, ids, rest_a)
		_tick(copy, ids, rest_b)
	assert_bool(rest_a == rest_b).is_true()
	assert_bool(WorldTestKit.store_bytes(w) == WorldTestKit.store_bytes(copy)).is_true()
	assert_bool(w.rng.state() == copy.rng.state()).is_true()


func test_combat_draws_from_the_world_rng_only() -> void:
	var w: SimWorld = CombatTestKit.world(5)
	var _t: int = CombatTestKit.spawn(w, &"lancer", 0, 0, _at(500.0))
	var _s: int = CombatTestKit.shot(w, &"slug_light", &"gun_dart", _at(500.0), 1, 1)
	var before: PackedByteArray = w.rng.state()
	w.step()
	assert_bool(w.rng.state() == before).is_false()           # one roll drawn from SimWorld.rng
	var mirror: Rng = Rng.from_state(before)
	var d: int = Combat.roll_gun_damage(CombatTestKit.weapon(&"", &"gun_dart"), EntityStore.K_SHIP, mirror)
	assert_bool(mirror.state() == w.rng.state()).is_true()    # exactly that one draw, nothing else
	assert_float(CombatTestKit.hp(w, _t)).is_equal(220.0 - float(d))
