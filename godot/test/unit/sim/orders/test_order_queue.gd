extends GdUnitTestSuite
## OrderQueue (R0 C2-06, 05 s2.1/s3.1, AI-01): push/pop/replace with QUEUE, PREPEND and LOW, cap of 8, the
## order_kind head cache after every mutation, pending queue and commit, patrol block pool, determinism,
## serialize round-trip.

const S: int = OrderQueue.STANDING
const P: int = OrderQueue.PENDING
const NONE: int = EntityStore.NONE_U8

var _store: EntityStore
var _q: OrderQueue
var _slot: int = 0


func before_test() -> void:
	_store = EntityStore.new()
	_q = OrderQueue.new(_store)
	_slot = EntityId.slot(_store.alloc(EntityStore.K_SHIP, 0))


func _spec(kind: OrderSpec.Kind, flags: int = 0, target: int = 0) -> OrderSpec:
	return OrderSpec.make(kind, target, Vector3(1.0, 2.0, 3.0), flags)


func _patrol(n: int, flags: int = 0) -> OrderSpec:
	var s: OrderSpec = _spec(OrderSpec.Kind.PATROL, flags)
	for i: int in n:
		s.points.append(Vector3(float(i), 0.0, 1.0))
	return s


func _head() -> int:
	return _store.order_kind[_slot]


func test_fresh_slot_has_no_orders_and_cache_is_none() -> void:
	assert_int(_q.count(_slot, S)).is_equal(0)
	assert_int(_head()).is_equal(NONE)
	assert_bool(_q.head_cache_ok()).is_true()
	assert_int(_q.head_issuer(_slot)).is_equal(-1)


func test_replace_sets_single_head() -> void:
	assert_int(_q.push(_slot, S, _spec(OrderSpec.Kind.MOVE))).is_equal(OrderQueue.Push.OK)
	assert_int(_q.push(_slot, S, _spec(OrderSpec.Kind.HOLD))).is_equal(OrderQueue.Push.OK)
	assert_int(_q.count(_slot, S)).is_equal(1)
	assert_int(_head()).is_equal(OrderSpec.Kind.HOLD)
	assert_bool(_q.head_cache_ok()).is_true()


func test_queue_flag_appends_and_head_stays() -> void:
	var _r: int = _q.push(_slot, S, _spec(OrderSpec.Kind.MOVE))
	_r = _q.push(_slot, S, _spec(OrderSpec.Kind.ATTACK, OrderSpec.FLAG_QUEUE))
	_r = _q.push(_slot, S, _spec(OrderSpec.Kind.RETURN, OrderSpec.FLAG_QUEUE))
	assert_int(_q.count(_slot, S)).is_equal(3)
	assert_int(_head()).is_equal(OrderSpec.Kind.MOVE)
	assert_int(_q.kind_at(_slot, S, 1)).is_equal(OrderSpec.Kind.ATTACK)
	assert_int(_q.kind_at(_slot, S, 2)).is_equal(OrderSpec.Kind.RETURN)
	assert_int(_q.kind_at(_slot, S, 3)).is_equal(NONE)


func test_queue_flag_on_empty_queue_becomes_head() -> void:
	var _r: int = _q.push(_slot, S, _spec(OrderSpec.Kind.GUARD, OrderSpec.FLAG_QUEUE))
	assert_int(_head()).is_equal(OrderSpec.Kind.GUARD)
	assert_bool(_q.head_cache_ok()).is_true()


func test_non_queue_push_replaces_a_whole_queue() -> void:
	for k: OrderSpec.Kind in [OrderSpec.Kind.MOVE, OrderSpec.Kind.HOLD, OrderSpec.Kind.GUARD]:
		var _r: int = _q.push(_slot, S, _spec(k, OrderSpec.FLAG_QUEUE))
	var _r2: int = _q.push(_slot, S, _spec(OrderSpec.Kind.RETURN))
	assert_int(_q.count(_slot, S)).is_equal(1)
	assert_int(_head()).is_equal(OrderSpec.Kind.RETURN)


func test_low_flag_is_stored_and_survives_queueing() -> void:
	var _r: int = _q.push(_slot, S, _spec(OrderSpec.Kind.MOVE, OrderSpec.FLAG_LOW))
	_r = _q.push(_slot, S, _spec(OrderSpec.Kind.ATTACK, OrderSpec.FLAG_QUEUE | OrderSpec.FLAG_LOW))
	var out: OrderSpec = OrderSpec.new()
	assert_bool(_q.read(_slot, S, 0, out)).is_true()
	assert_int(out.flags).is_equal(OrderSpec.FLAG_LOW)
	assert_bool(_q.read(_slot, S, 1, out)).is_true()
	assert_int(out.flags).is_equal(OrderSpec.FLAG_QUEUE | OrderSpec.FLAG_LOW)


func test_cap_of_eight_rejects_the_ninth_and_keeps_the_queue() -> void:
	for i: int in 8:
		assert_int(_q.push(_slot, S, _spec(OrderSpec.Kind.MOVE, OrderSpec.FLAG_QUEUE, i + 1))).is_equal(OrderQueue.Push.OK)
	assert_int(_q.push(_slot, S, _spec(OrderSpec.Kind.HOLD, OrderSpec.FLAG_QUEUE))).is_equal(OrderQueue.Push.FULL)
	assert_int(_q.count(_slot, S)).is_equal(8)
	var out: OrderSpec = OrderSpec.new()
	assert_bool(_q.read(_slot, S, 7, out)).is_true()
	assert_int(out.target).is_equal(8)
	assert_bool(_q.head_cache_ok()).is_true()


func test_pending_queue_has_its_own_cap_and_does_not_touch_the_head() -> void:
	var _r: int = _q.push(_slot, S, _spec(OrderSpec.Kind.HOLD))
	for i: int in 8:
		assert_int(_q.push(_slot, P, _spec(OrderSpec.Kind.MOVE, OrderSpec.FLAG_QUEUE))).is_equal(OrderQueue.Push.OK)
	assert_int(_q.push(_slot, P, _spec(OrderSpec.Kind.MOVE, OrderSpec.FLAG_QUEUE))).is_equal(OrderQueue.Push.FULL)
	assert_int(_head()).is_equal(OrderSpec.Kind.HOLD)
	assert_int(_q.count(_slot, P)).is_equal(8)
	assert_int(_q.count(_slot, S)).is_equal(1)


func test_lower_limit_tightens_the_cap() -> void:
	_q.limit = 2
	var _r: int = _q.push(_slot, S, _spec(OrderSpec.Kind.MOVE, OrderSpec.FLAG_QUEUE))
	_r = _q.push(_slot, S, _spec(OrderSpec.Kind.MOVE, OrderSpec.FLAG_QUEUE))
	assert_int(_q.push(_slot, S, _spec(OrderSpec.Kind.MOVE, OrderSpec.FLAG_QUEUE))).is_equal(OrderQueue.Push.FULL)


func test_prepend_goes_to_front_and_drops_tail_when_full() -> void:
	for i: int in 8:
		var _r: int = _q.push(_slot, S, _spec(OrderSpec.Kind.MOVE, OrderSpec.FLAG_QUEUE, i + 1))
	assert_int(_q.push(_slot, S, _spec(OrderSpec.Kind.RETURN, OrderSpec.FLAG_PREPEND))).is_equal(OrderQueue.Push.OK)
	assert_int(_q.count(_slot, S)).is_equal(8)
	assert_int(_head()).is_equal(OrderSpec.Kind.RETURN)
	var out: OrderSpec = OrderSpec.new()
	assert_bool(_q.read(_slot, S, 1, out)).is_true()
	assert_int(out.target).is_equal(1)
	assert_bool(_q.read(_slot, S, 7, out)).is_true()
	assert_int(out.target).is_equal(7)
	assert_bool(_q.head_cache_ok()).is_true()


func test_prepend_on_short_queue_resumes_interrupted_order() -> void:
	var _r: int = _q.push(_slot, S, _spec(OrderSpec.Kind.ATTACK, 0, 5))
	_r = _q.push(_slot, S, _spec(OrderSpec.Kind.RETURN, OrderSpec.FLAG_PREPEND))
	assert_int(_head()).is_equal(OrderSpec.Kind.RETURN)
	assert_bool(_q.pop_head(_slot, S)).is_true()
	assert_int(_head()).is_equal(OrderSpec.Kind.ATTACK)
	var out: OrderSpec = OrderSpec.new()
	assert_bool(_q.read(_slot, S, 0, out)).is_true()
	assert_int(out.target).is_equal(5)


func test_pop_head_advances_and_empties() -> void:
	var _r: int = _q.push(_slot, S, _spec(OrderSpec.Kind.MOVE))
	_r = _q.push(_slot, S, _spec(OrderSpec.Kind.HOLD, OrderSpec.FLAG_QUEUE))
	assert_bool(_q.pop_head(_slot, S)).is_true()
	assert_int(_head()).is_equal(OrderSpec.Kind.HOLD)
	assert_bool(_q.pop_head(_slot, S)).is_true()
	assert_int(_head()).is_equal(NONE)
	assert_bool(_q.pop_head(_slot, S)).is_false()
	assert_bool(_q.head_cache_ok()).is_true()


func test_remove_at_middle_keeps_order() -> void:
	for i: int in 4:
		var _r: int = _q.push(_slot, S, _spec(OrderSpec.Kind.MOVE, OrderSpec.FLAG_QUEUE, i + 1))
	assert_bool(_q.remove_at(_slot, S, 1)).is_true()
	var out: OrderSpec = OrderSpec.new()
	var seen: PackedInt32Array = PackedInt32Array()
	for i: int in _q.count(_slot, S):
		var _ok: bool = _q.read(_slot, S, i, out)
		seen.append(out.target)
	assert_array(seen).contains_exactly([1, 3, 4])


func test_mutations_mark_dirty_control_only_for_standing() -> void:
	_store.dirty[_slot] = 0
	var _r: int = _q.push(_slot, P, _spec(OrderSpec.Kind.MOVE))
	assert_int(_store.dirty[_slot]).is_equal(0)
	_r = _q.push(_slot, S, _spec(OrderSpec.Kind.MOVE))
	assert_int(_store.dirty[_slot] & EntityStore.DIRTY_CONTROL).is_equal(EntityStore.DIRTY_CONTROL)


func test_commit_pending_replaces_standing() -> void:
	var _r: int = _q.push(_slot, S, _spec(OrderSpec.Kind.HOLD))
	_r = _q.push(_slot, P, _patrol(3))
	_r = _q.push(_slot, P, _spec(OrderSpec.Kind.RETURN, OrderSpec.FLAG_QUEUE))
	assert_bool(_q.commit_pending(_slot)).is_true()
	assert_int(_q.count(_slot, P)).is_equal(0)
	assert_int(_q.count(_slot, S)).is_equal(2)
	assert_int(_head()).is_equal(OrderSpec.Kind.PATROL)
	var out: OrderSpec = OrderSpec.new()
	assert_bool(_q.read(_slot, S, 0, out)).is_true()
	assert_int(out.points.size()).is_equal(3)
	assert_bool(_q.head_cache_ok()).is_true()
	assert_bool(_q.commit_pending(_slot)).is_false()


func test_clear_slot_resets_both_queues_cache_and_blocks() -> void:
	var _r: int = _q.push(_slot, S, _patrol(4))
	_r = _q.push(_slot, P, _patrol(2))
	assert_int(_q.free_blocks()).is_equal(OrderQueue.BLOCK_COUNT - 2)
	_q.clear_slot(_slot)
	assert_int(_q.count(_slot, S) + _q.count(_slot, P)).is_equal(0)
	assert_int(_head()).is_equal(NONE)
	assert_int(_q.free_blocks()).is_equal(OrderQueue.BLOCK_COUNT)


func test_read_round_trips_every_field() -> void:
	var s: OrderSpec = _patrol(5, OrderSpec.FLAG_LOW)
	s.target = 77
	s.haul_mode = OrderSpec.HaulMode.CAPTURE
	s.escort_slot = 3
	s.focus = 99
	s.escort_mode = OrderSpec.EscortMode.BREAK
	s.issuer = 4
	s.issue_tick = 1234
	s.progress = 2
	var _r: int = _q.push(_slot, S, s)
	var out: OrderSpec = OrderSpec.new()
	assert_bool(_q.read(_slot, S, 0, out)).is_true()
	assert_bool(out.equals(s)).is_true()
	assert_int(_q.head_issuer(_slot)).is_equal(4)
	assert_int(_q.head_tick(_slot)).is_equal(1234)
	assert_bool(_q.set_progress(_slot, S, 0, 3)).is_true()
	assert_int(_q.progress(_slot, S, 0)).is_equal(3)


func test_patrol_points_survive_shifts() -> void:
	var _r: int = _q.push(_slot, S, _patrol(3, OrderSpec.FLAG_QUEUE))
	_r = _q.push(_slot, S, _patrol(5, OrderSpec.FLAG_QUEUE))
	_r = _q.push(_slot, S, _spec(OrderSpec.Kind.RETURN, OrderSpec.FLAG_PREPEND))
	var out: OrderSpec = OrderSpec.new()
	assert_bool(_q.read(_slot, S, 2, out)).is_true()
	assert_int(out.points.size()).is_equal(5)
	assert_vector(out.points[4]).is_equal(Vector3(4.0, 0.0, 1.0))
	assert_bool(_q.pop_head(_slot, S)).is_true()
	assert_bool(_q.pop_head(_slot, S)).is_true()
	assert_bool(_q.read(_slot, S, 0, out)).is_true()
	assert_int(out.points.size()).is_equal(5)
	assert_int(_q.free_blocks()).is_equal(OrderQueue.BLOCK_COUNT - 1)


## Spends every free patrol block on other slots (standing then pending queues), never on `_slot`.
func _drain_pool() -> void:
	for w: int in 2:
		for s: int in range(2, OrderQueue.SLOTS):
			if _q.free_blocks() == 0:
				return
			var _r: int = _q.push(s, w, _patrol(2))


func test_block_pool_exhaustion_rejects_without_corrupting() -> void:
	_drain_pool()
	assert_int(_q.free_blocks()).is_equal(0)
	assert_int(_q.push(_slot, S, _patrol(2))).is_equal(OrderQueue.Push.NO_POINTS)
	assert_int(_q.count(_slot, S)).is_equal(0)
	assert_int(_q.push(_slot, S, _spec(OrderSpec.Kind.HOLD))).is_equal(OrderQueue.Push.OK)
	assert_int(_q.push(_slot, S, _patrol(2, OrderSpec.FLAG_QUEUE))).is_equal(OrderQueue.Push.NO_POINTS)
	assert_int(_q.count(_slot, S)).is_equal(1)
	assert_bool(_q.head_cache_ok()).is_true()


func test_replace_by_patrol_reuses_its_own_blocks_when_pool_is_empty() -> void:
	var _r: int = _q.push(_slot, S, _patrol(2))
	_drain_pool()
	assert_int(_q.free_blocks()).is_equal(0)
	assert_int(_q.push(_slot, S, _patrol(3))).is_equal(OrderQueue.Push.OK)
	assert_int(_q.count(_slot, S)).is_equal(1)
	assert_int(_q.free_blocks()).is_equal(0)


func test_bad_inputs() -> void:
	assert_int(_q.push(0, S, _spec(OrderSpec.Kind.MOVE))).is_equal(OrderQueue.Push.BAD_SLOT)
	assert_int(_q.push(OrderQueue.SLOTS, S, _spec(OrderSpec.Kind.MOVE))).is_equal(OrderQueue.Push.BAD_SLOT)
	assert_int(_q.push(_slot, 2, _spec(OrderSpec.Kind.MOVE))).is_equal(OrderQueue.Push.BAD_SLOT)
	assert_int(_q.push(_slot, S, _patrol(OrderSpec.WIRE_MAX_POINTS + 1))).is_equal(OrderQueue.Push.BAD_SPEC)
	assert_int(_q.count(-1, S)).is_equal(0)
	assert_bool(_q.read(_slot, S, 0, OrderSpec.new())).is_false()


func test_head_cache_consistent_after_every_mutation_of_a_random_sequence() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20261013
	var slots: PackedInt32Array = PackedInt32Array([_slot])
	for _i: int in 5:
		slots.append(EntityId.slot(_store.alloc(EntityStore.K_GROUND, 0)))
	for _step: int in 600:
		_random_op(rng, slots[rng.randi() % slots.size()])
		assert_bool(_q.head_cache_ok()).is_true()


func _random_op(rng: RandomNumberGenerator, slot: int) -> void:
	var which: int = rng.randi() % 2
	var op: int = rng.randi() % 7
	var kind: OrderSpec.Kind = (rng.randi() % 9) as OrderSpec.Kind
	var flags: int = [0, OrderSpec.FLAG_QUEUE, OrderSpec.FLAG_PREPEND, OrderSpec.FLAG_LOW][rng.randi() % 4]
	match op:
		0, 1, 2:
			var s: OrderSpec = _patrol(2 + rng.randi() % 5, flags) if kind == OrderSpec.Kind.PATROL else _spec(kind, flags)
			var _r: int = _q.push(slot, which, s)
		3:
			var _b: bool = _q.pop_head(slot, which)
		4:
			var _b2: bool = _q.remove_at(slot, which, rng.randi() % 8)
		5:
			var _b3: bool = _q.commit_pending(slot)
		_:
			_q.clear(slot, which)


func test_same_operations_give_identical_bytes() -> void:
	var a: PackedByteArray = _run_sequence(7)
	var b: PackedByteArray = _run_sequence(7)
	var c: PackedByteArray = _run_sequence(8)
	assert_array(a).is_equal(b)
	assert_bool(a == c).is_false()


func _run_sequence(seed_value: int) -> PackedByteArray:
	var st: EntityStore = EntityStore.new()
	var q: OrderQueue = OrderQueue.new(st)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var slots: PackedInt32Array = PackedInt32Array()
	for _i: int in 4:
		slots.append(EntityId.slot(st.alloc(EntityStore.K_SHIP, 0)))
	var prev_q: OrderQueue = _q
	_q = q
	for _step: int in 300:
		_random_op(rng, slots[rng.randi() % slots.size()])
	_q = prev_q
	return OrderQueueCodec.serialize(q)


func test_serialize_round_trip_restores_queues_and_head_cache() -> void:
	var s: OrderSpec = _patrol(6, OrderSpec.FLAG_QUEUE)
	s.issuer = 2
	s.issue_tick = 55
	s.progress = 4
	var _r: int = _q.push(_slot, S, _spec(OrderSpec.Kind.ESCORT, 0, 9))
	_r = _q.push(_slot, S, s)
	_r = _q.push(_slot, P, _spec(OrderSpec.Kind.HAUL, OrderSpec.FLAG_LOW, 11))
	var bytes: PackedByteArray = OrderQueueCodec.serialize(_q)
	var st2: EntityStore = EntityStore.new()
	var q2: OrderQueue = OrderQueue.new(st2)
	assert_bool(OrderQueueCodec.deserialize(q2, bytes)).is_true()
	assert_array(OrderQueueCodec.serialize(q2)).is_equal(bytes)
	assert_int(q2.count(_slot, S)).is_equal(2)
	assert_int(q2.count(_slot, P)).is_equal(1)
	assert_int(st2.order_kind[_slot]).is_equal(OrderSpec.Kind.ESCORT)
	var a: OrderSpec = OrderSpec.new()
	var b: OrderSpec = OrderSpec.new()
	assert_bool(_q.read(_slot, S, 1, a)).is_true()
	assert_bool(q2.read(_slot, S, 1, b)).is_true()
	assert_bool(a.equals(b)).is_true()
	assert_int(q2.free_blocks()).is_equal(_q.free_blocks())


func test_deserialize_rejects_malformed_and_leaves_empty() -> void:
	var _r: int = _q.push(_slot, S, _patrol(3))
	var bytes: PackedByteArray = OrderQueueCodec.serialize(_q)
	var st2: EntityStore = EntityStore.new()
	var q2: OrderQueue = OrderQueue.new(st2)
	var cut: PackedByteArray = bytes.slice(0, bytes.size() - 1)
	assert_bool(OrderQueueCodec.deserialize(q2, cut)).is_false()
	assert_int(q2.count(_slot, S)).is_equal(0)
	assert_int(q2.free_blocks()).is_equal(OrderQueue.BLOCK_COUNT)
	var bad: PackedByteArray = bytes.duplicate()
	bad[0] = 9
	assert_bool(OrderQueueCodec.deserialize(q2, bad)).is_false()
	var trailing: PackedByteArray = bytes.duplicate()
	trailing.append(0)
	assert_bool(OrderQueueCodec.deserialize(q2, trailing)).is_false()
	assert_bool(OrderQueueCodec.deserialize(q2, PackedByteArray())).is_false()
	assert_bool(q2.head_cache_ok()).is_true()
