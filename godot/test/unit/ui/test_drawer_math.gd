extends GdUnitTestSuite
## DrawerMath (UX-22; docs/06 s7.5, R0 C3-08): tile state priority, the early share lock, factory choice, steppers and
## the owner-only cancel rule (mirrors PlayerTable.cancel_delegable).

const S := DrawerMath.State
const V := DrawerMath.Cancel


func before_test() -> void:
	var r: Result = ContentDB.load_all()
	assert_bool(r.ok).is_true()


func test_classify_priority_locked_cap_unaffordable_lock_available() -> void:
	var cost: Vector2i = Vector2i(150, 0)
	var stock: Vector2i = Vector2i(800, 300)
	assert_int(DrawerMath.classify(true, false, cost, stock, -1)).is_equal(S.AVAILABLE)
	assert_int(DrawerMath.classify(false, true, cost, Vector2i.ZERO, 0)).is_equal(S.LOCKED)        # tech beats everything
	assert_int(DrawerMath.classify(true, true, cost, Vector2i.ZERO, 0)).is_equal(S.CAP_REACHED)
	assert_int(DrawerMath.classify(true, false, cost, Vector2i(100, 0), 0)).is_equal(S.UNAFFORDABLE)   # sim checks cost before the lock
	assert_int(DrawerMath.classify(true, false, cost, stock, 100)).is_equal(S.SPEND_LOCKED)
	assert_int(DrawerMath.classify(true, false, cost, stock, 150)).is_equal(S.AVAILABLE)          # spending exactly the share is allowed


func test_short_of_names_the_missing_resource() -> void:
	assert_vector(DrawerMath.short_of(Vector2i(400, 150), Vector2i(500, 100))).is_equal(Vector2i(0, 50))
	assert_vector(DrawerMath.short_of(Vector2i(400, 0), Vector2i(100, 0))).is_equal(Vector2i(300, 0))
	assert_vector(DrawerMath.short_of(Vector2i(10, 10), Vector2i(10, 10))).is_equal(Vector2i.ZERO)


func test_lock_blocks_only_while_left_is_known_and_short() -> void:
	assert_bool(DrawerMath.lock_blocks(-1, 9999)).is_false()      # -1 = lock over or not own team
	assert_bool(DrawerMath.lock_blocks(0, 1)).is_true()
	assert_bool(DrawerMath.lock_blocks(0, 0)).is_false()
	assert_bool(DrawerMath.lock_blocks(300, 300)).is_false()
	assert_bool(DrawerMath.lock_blocks(300, 301)).is_true()


func test_lock_text_params_come_from_economy_json() -> void:
	assert_float(DrawerMath.lock_end_s()).is_equal(120.0)
	assert_int(DrawerMath.share_ore()).is_equal(800)
	assert_int(DrawerMath.queue_max()).is_equal(5)


func test_stepper_clamps_between_zero_and_twelve() -> void:
	assert_int(DrawerMath.stepper(0, -1)).is_equal(0)
	assert_int(DrawerMath.stepper(0, 1)).is_equal(1)
	assert_int(DrawerMath.stepper(11, 1)).is_equal(12)
	assert_int(DrawerMath.stepper(12, 1)).is_equal(12)
	assert_int(DrawerMath.stepper(5, -2)).is_equal(3)


func test_batch_never_passes_the_queue_cap() -> void:
	assert_int(DrawerMath.batch(0)).is_equal(5)
	assert_int(DrawerMath.batch(3)).is_equal(2)
	assert_int(DrawerMath.batch(5)).is_equal(0)
	assert_int(DrawerMath.batch(9)).is_equal(0)


func test_pick_factory_shortest_queue_then_nearest_then_lowest_id() -> void:
	var ids: PackedInt32Array = PackedInt32Array([10, 11, 12])
	assert_int(DrawerMath.pick_factory(ids, PackedInt32Array([2, 1, 3]), PackedFloat32Array([1.0, 9.0, 1.0]))).is_equal(11)
	assert_int(DrawerMath.pick_factory(ids, PackedInt32Array([1, 1, 3]), PackedFloat32Array([9.0, 4.0, 1.0]))).is_equal(11)   # tie: nearest
	assert_int(DrawerMath.pick_factory(ids, PackedInt32Array([1, 1, 1]), PackedFloat32Array([4.0, 4.0, 4.0]))).is_equal(10)   # tie again: lowest id
	assert_int(DrawerMath.pick_factory(ids, PackedInt32Array([5, 5, 5]), PackedFloat32Array([1.0, 1.0, 1.0]))).is_equal(-1)   # all full
	assert_int(DrawerMath.pick_factory(PackedInt32Array(), PackedInt32Array(), PackedFloat32Array())).is_equal(-1)


func test_cancel_verdict_owner_teammate_rules() -> void:
	# (local, local_team, queuer, queuer_team, kind, connected, eliminated)
	assert_int(DrawerMath.cancel_verdict(0, 0, 0, 0, 0, true, false)).is_equal(V.OWNER)
	assert_int(DrawerMath.cancel_verdict(0, 0, 1, 0, 0, true, false)).is_equal(V.DENIED_NOT_OWNER)     # live human teammate
	assert_int(DrawerMath.cancel_verdict(0, 0, 1, 0, 0, false, false)).is_equal(V.DELEGATED)           # disconnected
	assert_int(DrawerMath.cancel_verdict(0, 0, 1, 0, 0, true, true)).is_equal(V.DELEGATED)             # eliminated
	assert_int(DrawerMath.cancel_verdict(0, 0, 1, 0, DrawerMath.KIND_BOT, true, false)).is_equal(V.DELEGATED)
	assert_int(DrawerMath.cancel_verdict(0, 0, 1, 0, DrawerMath.KIND_OPEN, false, false)).is_equal(V.DELEGATED)
	assert_int(DrawerMath.cancel_verdict(0, 0, 2, 1, DrawerMath.KIND_BOT, true, false)).is_equal(V.DENIED_TEAM)   # other team never
	assert_int(DrawerMath.cancel_verdict(0, 0, -1, -1, 0, true, false)).is_equal(V.UNKNOWN)
	assert_bool(DrawerMath.cancel_allowed(V.OWNER)).is_true()
	assert_bool(DrawerMath.cancel_allowed(V.DELEGATED)).is_true()
	assert_bool(DrawerMath.cancel_allowed(V.UNKNOWN)).is_true()         # no queuer read yet: the sim decides
	assert_bool(DrawerMath.cancel_allowed(V.DENIED_NOT_OWNER)).is_false()
	assert_bool(DrawerMath.cancel_allowed(V.DENIED_TEAM)).is_false()
	assert_str(String(DrawerMath.cancel_reason(V.DENIED_NOT_OWNER))).is_equal("ui.prod.cancel.not_owner")
	assert_str(String(DrawerMath.cancel_reason(V.OWNER))).is_equal("")


func test_cancel_rule_equals_the_sims_cancel_delegable() -> void:
	for kind: int in [PlayerTable.KIND_HUMAN, PlayerTable.KIND_BOT]:
		for connected: bool in [true, false]:
			for elim: bool in [true, false]:
				var pt: PlayerTable = PlayerTable.new()
				pt.active[1] = 1
				pt.team[1] = 0
				pt.kind[1] = kind
				pt.connected[1] = 1 if connected else 0
				pt.eliminated[1] = 1 if elim else 0
				var want: bool = pt.cancel_delegable(1)
				var got: bool = DrawerMath.cancel_verdict(0, 0, 1, 0, kind, connected, elim) == V.DELEGATED
				assert_bool(got).is_equal(want)
	assert_int(DrawerMath.KIND_BOT).is_equal(PlayerTable.KIND_BOT)
	assert_int(DrawerMath.KIND_OPEN).is_equal(PlayerTable.KIND_OPEN)
