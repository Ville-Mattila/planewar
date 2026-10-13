extends GdUnitTestSuite
## Unit tests for sim/entity_store.gd (03 s3.1-3.2, TA-11): alloc/free/reuse, quarantine (S2),
## field round trips, capacity exhaustion, the 150-byte layout, live lists, memory flat.

const StoreLayout := preload("res://test/unit/sim/store_layout.gd")
const Q: int = EntityStore.QUARANTINE_TICKS
const MAIN_SLOTS: int = EntityId.WRECK_SLOT_MIN - 1
const WRECK_SLOTS: int = EntityId.WRECK_SLOT_END - EntityId.WRECK_SLOT_MIN


func test_byte_layout_is_38_arrays_and_150_bytes_per_slot() -> void:
	var s: EntityStore = EntityStore.new()
	var layout: PackedInt32Array = StoreLayout.layout_of(s, EntityStore.SLOT_COUNT)
	assert_int(layout[0]).is_equal(38)
	assert_int(layout[1]).is_equal(150)
	assert_int(EntityStore.SLOT_COUNT).is_equal(EntityId.WRECK_SLOT_END)


func test_fresh_alloc_returns_slot_1_generation_1() -> void:
	var s: EntityStore = EntityStore.new()
	var id: int = s.alloc(EntityStore.K_SHIP, 10)
	assert_int(EntityId.slot(id)).is_equal(1)
	assert_int(EntityId.gen(id)).is_equal(1)
	assert_bool(s.alive(id)).is_true()
	assert_int(s.kind[1]).is_equal(EntityStore.K_SHIP)
	assert_int(s.flags[1]).is_equal(EntityStore.F_ALIVE)
	assert_int(s.spawn_tick[1]).is_equal(10)
	assert_int(s.dirty[1]).is_equal(EntityStore.DIRTY_SPAWNED)
	assert_int(s.id_of(1)).is_equal(id)


func test_null_and_foreign_ids_are_not_alive() -> void:
	var s: EntityStore = EntityStore.new()
	assert_bool(s.alive(EntityId.NULL_ID)).is_false()
	assert_bool(s.alive(EntityId.make(EntityId.PROJECTILE_SLOT_MIN, 1))).is_false()
	assert_bool(s.alive(EntityId.make(5, 1))).is_false()
	assert_bool(s.alive(-1)).is_false()


func test_invalid_kind_is_rejected() -> void:
	var s: EntityStore = EntityStore.new()
	assert_int(s.alloc(-1, 0)).is_equal(EntityId.NULL_ID)
	assert_int(s.alloc(EntityStore.K_WRECK + 1, 0)).is_equal(EntityId.NULL_ID)


func test_free_bumps_generation_kills_stale_id_and_clears_fields() -> void:
	var s: EntityStore = EntityStore.new()
	var id: int = s.alloc(EntityStore.K_GROUND, 0)
	var slot: int = EntityId.slot(id)
	s.hp[slot] = 50.0
	s.owner[slot] = 3
	s.pos[slot] = Vector3(1.0, 2.0, 2.0)
	assert_bool(s.free_slot(slot, 5)).is_true()
	assert_bool(s.alive(id)).is_false()
	assert_int(s.generation[slot]).is_equal(2)
	assert_int(s.flags[slot]).is_equal(0)
	assert_float(s.hp[slot]).is_equal(0.0)
	assert_int(s.owner[slot]).is_equal(EntityStore.NONE_U8)
	assert_that(s.pos[slot]).is_equal(Vector3.ZERO)
	assert_int(s.dirty[slot]).is_equal(EntityStore.DIRTY_DIED)


func test_double_free_and_out_of_range_free_fail() -> void:
	var s: EntityStore = EntityStore.new()
	var slot: int = EntityId.slot(s.alloc(EntityStore.K_SHIP, 0))
	assert_bool(s.free_slot(slot, 1)).is_true()
	assert_bool(s.free_slot(slot, 2)).is_false()
	assert_int(s.generation[slot]).is_equal(2)
	assert_bool(s.free_slot(0, 2)).is_false()
	assert_bool(s.free_slot(EntityStore.SLOT_COUNT, 2)).is_false()


func test_quarantine_slot_reusable_exactly_after_64_ticks() -> void:
	# Exhaust the main range so the only candidate is the freed slot.
	var s: EntityStore = EntityStore.new()
	for i: int in MAIN_SLOTS:
		var _id: int = s.alloc(EntityStore.K_STRUCTURE, 0)
	assert_bool(s.free_slot(7, 100)).is_true()
	assert_int(s.quarantined_count(EntityStore.RANGE_MAIN)).is_equal(1)
	assert_int(s.alloc(EntityStore.K_SHIP, 100)).is_equal(EntityId.NULL_ID)
	assert_int(s.alloc(EntityStore.K_SHIP, 100 + Q - 1)).is_equal(EntityId.NULL_ID)
	var id: int = s.alloc(EntityStore.K_SHIP, 100 + Q)
	assert_int(EntityId.slot(id)).is_equal(7)
	assert_int(EntityId.gen(id)).is_equal(2)
	assert_int(s.quarantined_count(EntityStore.RANGE_MAIN)).is_equal(0)


func test_quarantine_is_fifo_and_tolerates_non_monotonic_free_ticks() -> void:
	var s: EntityStore = EntityStore.new()
	for i: int in MAIN_SLOTS:
		var _id: int = s.alloc(EntityStore.K_SHIP, 0)
	assert_bool(s.free_slot(3, 10)).is_true()
	assert_bool(s.free_slot(4, 5)).is_true()   # earlier tick than the ring tail: held as tick 10
	assert_int(s.alloc(EntityStore.K_SHIP, 5 + Q)).is_equal(EntityId.NULL_ID)
	assert_int(EntityId.slot(s.alloc(EntityStore.K_SHIP, 10 + Q))).is_equal(4)
	assert_int(EntityId.slot(s.alloc(EntityStore.K_SHIP, 10 + Q))).is_equal(3)


func test_capacity_exhaustion_per_range() -> void:
	var s: EntityStore = EntityStore.new()
	var last: int = 0
	for i: int in MAIN_SLOTS:
		last = s.alloc(EntityStore.K_GROUND, 0)
	assert_int(EntityId.slot(last)).is_equal(EntityId.WRECK_SLOT_MIN - 1)
	assert_int(s.alloc(EntityStore.K_SHIP, 0)).is_equal(EntityId.NULL_ID)
	assert_int(s.free_count(EntityStore.RANGE_MAIN)).is_equal(0)
	# The wreck range is independent.
	for i: int in WRECK_SLOTS:
		last = s.alloc(EntityStore.K_WRECK, 0)
		assert_bool(EntityId.is_wreck(last)).is_true()
	assert_int(s.alloc(EntityStore.K_WRECK, 0)).is_equal(EntityId.NULL_ID)
	assert_int(s.live_count()).is_equal(MAIN_SLOTS + WRECK_SLOTS)


func test_live_lists_are_sorted_and_per_kind() -> void:
	var s: EntityStore = EntityStore.new()
	var a: int = EntityId.slot(s.alloc(EntityStore.K_SHIP, 0))
	var b: int = EntityId.slot(s.alloc(EntityStore.K_STRUCTURE, 0))
	var c: int = EntityId.slot(s.alloc(EntityStore.K_SHIP, 0))
	var d: int = EntityId.slot(s.alloc(EntityStore.K_GROUND, 0))
	var w: int = EntityId.slot(s.alloc(EntityStore.K_WRECK, 0))
	assert_that(s.ships).is_equal(PackedInt32Array([a, c]))
	assert_that(s.structures).is_equal(PackedInt32Array([b]))
	assert_that(s.ground).is_equal(PackedInt32Array([d]))
	assert_that(s.wrecks).is_equal(PackedInt32Array([w]))
	assert_bool(s.free_slot(a, 1)).is_true()
	assert_that(s.ships).is_equal(PackedInt32Array([c]))
	# Reuse after quarantine keeps the list sorted.
	for i: int in 3:
		var _id: int = s.alloc(EntityStore.K_SHIP, 1)
	assert_that(s.ships).is_equal(PackedInt32Array([c, d + 1, d + 2, d + 3]))


func test_field_round_trips() -> void:
	var s: EntityStore = EntityStore.new()
	var slot: int = EntityId.slot(s.alloc(EntityStore.K_SHIP, 0))
	var v: Vector3 = Vector3(1.0, -1.0, 0.5)
	s.def_id[slot] = 77
	s.owner[slot] = 7
	s.team[slot] = 3
	s.pos[slot] = v
	s.vel[slot] = v * 2.0
	s.fwd[slot] = Vector3.FORWARD
	s.up[slot] = Vector3.UP
	s.rates[slot] = v
	s.radius[slot] = 2.0
	s.hash_cell[slot] = 24576
	s.control_state[slot] = 2
	s.possessor[slot] = 4
	s.order_kind[slot] = 9
	s.hp[slot] = 0.5
	s.fuel[slot] = 1.0
	s.ammo[slot] = 400
	s.bombs[slot] = 6
	s.rockets[slot] = 4
	s.cd_primary[slot] = 0.5
	s.cd_secondary[slot] = 1.0
	s.boost_time[slot] = -1.0
	s.flip_time[slot] = 2.0
	s.last_damage_tick[slot] = 99
	s.attacker[slot] = EntityId.make(9, 3)
	s.cargo[slot] = 2.0
	s.cargo_kind[slot] = 2
	s.link[slot] = EntityId.make(11, 1)
	s.timer_a[slot] = 0.5
	s.timer_b[slot] = 1.0
	s.ai_tag[slot] = 200
	s.overlay[slot] = 3
	s.visible_mask[slot] = 0xFF
	s.anchor_cell[slot] = 123456
	assert_int(s.def_id[slot]).is_equal(77)
	assert_int(s.owner[slot]).is_equal(7)
	assert_int(s.team[slot]).is_equal(3)
	assert_that(s.pos[slot]).is_equal(v)
	assert_that(s.vel[slot]).is_equal(v * 2.0)
	assert_that(s.rates[slot]).is_equal(v)
	assert_float(s.radius[slot]).is_equal(2.0)
	assert_int(s.hash_cell[slot]).is_equal(24576)
	assert_int(s.possessor[slot]).is_equal(4)
	assert_int(s.order_kind[slot]).is_equal(9)
	assert_int(s.ammo[slot]).is_equal(400)
	assert_int(s.bombs[slot]).is_equal(6)
	assert_float(s.boost_time[slot]).is_equal(-1.0)
	assert_int(s.attacker[slot]).is_equal(EntityId.make(9, 3))
	assert_int(s.link[slot]).is_equal(EntityId.make(11, 1))
	assert_int(s.ai_tag[slot]).is_equal(200)
	assert_int(s.overlay[slot]).is_equal(3)
	assert_int(s.visible_mask[slot]).is_equal(0xFF)
	assert_int(s.anchor_cell[slot]).is_equal(123456)
	# clear_slot restores zero values and the none sentinels.
	s.clear_slot(slot)
	assert_int(s.def_id[slot]).is_equal(0)
	assert_int(s.possessor[slot]).is_equal(EntityStore.NONE_U8)
	assert_int(s.order_kind[slot]).is_equal(EntityStore.NONE_U8)
	assert_int(s.team[slot]).is_equal(EntityStore.NONE_U8)
	assert_int(s.anchor_cell[slot]).is_equal(-1)
	assert_int(s.ai_tag[slot]).is_equal(0)
	assert_int(s.overlay[slot]).is_equal(0)
	assert_that(s.up[slot]).is_equal(Vector3.ZERO)
	assert_float(s.timer_b[slot]).is_equal(0.0)


## Acceptance (TA-11): 100k random alloc/free ops; no slot reuse within 64 ticks of its free,
## generation increments by exactly one step per reuse, stale ids never alive, memory flat (S2).
func test_fuzz_100k_ops_s2_generation_and_memory_flat() -> void:
	var s: EntityStore = EntityStore.new()
	var rng: Rng = Rng.new(1234, 11)
	var n: int = EntityStore.SLOT_COUNT
	var freed_at: PackedInt32Array = PackedInt32Array()
	var _r: int = freed_at.resize(n)
	freed_at.fill(-1000000)
	var last_gen: PackedInt32Array = PackedInt32Array()
	_r = last_gen.resize(n)
	var live_ids: PackedInt32Array = PackedInt32Array()
	var stale_ids: PackedInt32Array = PackedInt32Array()
	var bad_reuse: int = 0
	var bad_gen: int = 0
	var bad_alive: int = 0
	var null_allocs: int = 0
	var tick: int = 0
	var sizes_before: PackedInt32Array = PackedInt32Array()
	var mem_before: int = 0
	for op: int in 100000:
		if op == 20000:
			sizes_before = StoreLayout.layout_of(s, n)
			mem_before = OS.get_static_memory_usage()
		if rng.range_i(0, 3) == 0:
			tick += 1
		# Alternate a high and a low live target so both ranges hit exhaustion under quarantine.
		var target: int = 1500 if (op / 5000) % 2 == 0 else 200
		var p_alloc: int = 70 if live_ids.size() < target else 30
		var want_alloc: bool = rng.range_i(0, 99) < p_alloc
		if want_alloc or live_ids.is_empty():
			var k: int = rng.range_i(EntityStore.K_STRUCTURE, EntityStore.K_WRECK)
			var id: int = s.alloc(k, tick)
			if id == EntityId.NULL_ID:
				null_allocs += 1
				continue
			var slot: int = EntityId.slot(id)
			if tick - freed_at[slot] < Q:
				bad_reuse += 1
			var g: int = EntityId.gen(id)
			if last_gen[slot] != 0 and g != EntityId.bump_gen(last_gen[slot]):
				bad_gen += 1
			last_gen[slot] = g
			var _a: bool = live_ids.push_back(id)
		else:
			var at: int = rng.range_i(0, live_ids.size() - 1)
			var id: int = live_ids[at]
			live_ids[at] = live_ids[live_ids.size() - 1]
			_r = live_ids.resize(live_ids.size() - 1)
			if not s.free_slot(EntityId.slot(id), tick):
				bad_alive += 1
			freed_at[EntityId.slot(id)] = tick
			if stale_ids.size() < 4096:
				var _b: bool = stale_ids.push_back(id)
	for id: int in live_ids:
		if not s.alive(id):
			bad_alive += 1
	for id: int in stale_ids:
		if s.alive(id):
			bad_alive += 1
	var mem_after: int = OS.get_static_memory_usage()
	assert_int(null_allocs).is_greater(0)   # exhaustion was exercised
	assert_int(bad_reuse).is_equal(0)
	assert_int(bad_gen).is_equal(0)
	assert_int(bad_alive).is_equal(0)
	assert_that(StoreLayout.layout_of(s, n)).is_equal(sizes_before)
	assert_int(s.live_count()).is_equal(live_ids.size())
	# Conservation: every slot is live, free or quarantined.
	var main_total: int = s.free_count(EntityStore.RANGE_MAIN) + s.quarantined_count(EntityStore.RANGE_MAIN)
	var wreck_total: int = s.free_count(EntityStore.RANGE_WRECK) + s.quarantined_count(EntityStore.RANGE_WRECK)
	assert_int(main_total + wreck_total + s.live_count()).is_equal(MAIN_SLOTS + WRECK_SLOTS)
	# Static memory is 0 in release builds; in debug the store must not grow (live lists are bounded).
	assert_int(mem_after - mem_before).is_less(256 * 1024)
