extends GdUnitTestSuite
## Unit tests for sim/projectile_store.gd (03 s3.3, R0 C2-01/C2-11, TA-11): pooling, ids in the
## 4,096.. slot range, live cap (MatchRules.caps.projectiles), quarantine, 62-byte layout.

const StoreLayout := preload("res://test/unit/sim/store_layout.gd")
const Q: int = ProjectileStore.QUARANTINE_TICKS


func test_byte_layout_is_14_arrays_and_62_bytes_per_slot() -> void:
	var p: ProjectileStore = ProjectileStore.new(2000)
	var layout: PackedInt32Array = StoreLayout.layout_of(p, ProjectileStore.SLOT_COUNT)
	assert_int(layout[0]).is_equal(14)
	assert_int(layout[1]).is_equal(62)


func test_slot_count_is_derived_from_entity_id_range() -> void:
	# TA-46 (R0 B.9 A-20): SLOT_COUNT spans EntityId.PROJECTILE_SLOT_MIN .. PROJECTILE_SLOT_END - 1.
	assert_int(ProjectileStore.SLOT_COUNT).is_equal(EntityId.PROJECTILE_SLOT_END - EntityId.PROJECTILE_SLOT_MIN)
	var p: ProjectileStore = ProjectileStore.new(ProjectileStore.SLOT_COUNT)
	var last: int = p.id_of(ProjectileStore.SLOT_COUNT - 1)
	assert_int(EntityId.slot(last)).is_equal(EntityId.PROJECTILE_SLOT_END - 1)
	assert_int(p.index_of(EntityId.make(EntityId.PROJECTILE_SLOT_END, 1))).is_equal(-1)


func test_alloc_returns_projectile_id_and_sets_fields() -> void:
	var p: ProjectileStore = ProjectileStore.new(2000)
	var id: int = p.alloc(ProjectileStore.ROCKET, 4)
	assert_bool(EntityId.is_projectile(id)).is_true()
	assert_int(EntityId.slot(id)).is_equal(EntityId.PROJECTILE_SLOT_MIN)
	assert_int(EntityId.gen(id)).is_equal(1)
	assert_int(p.index_of(id)).is_equal(0)
	assert_int(p.id_of(0)).is_equal(id)
	assert_bool(p.alive(id)).is_true()
	assert_int(p.kind[0]).is_equal(ProjectileStore.ROCKET)
	assert_int(p.flags[0]).is_equal(ProjectileStore.F_ALIVE)
	assert_that(p.live).is_equal(PackedInt32Array([0]))


func test_entity_ids_are_not_projectiles() -> void:
	var p: ProjectileStore = ProjectileStore.new(2000)
	var _id: int = p.alloc(ProjectileStore.SLUG, 0)
	assert_bool(p.alive(EntityId.make(1, 1))).is_false()
	assert_bool(p.alive(EntityId.NULL_ID)).is_false()
	assert_int(p.index_of(EntityId.make(1, 1))).is_equal(-1)
	assert_bool(p.alive(EntityId.make(EntityId.PROJECTILE_SLOT_MIN + ProjectileStore.SLOT_COUNT, 1))).is_false()


func test_field_round_trips_and_clear() -> void:
	var p: ProjectileStore = ProjectileStore.new(2000)
	var i: int = p.index_of(p.alloc(ProjectileStore.BOMB, 0))
	var v: Vector3 = Vector3(2.0, 0.5, -1.0)
	p.pos[i] = v
	p.vel[i] = -v
	p.prev_pos[i] = v * 0.5
	p.projectile_def[i] = 6
	p.weapon_def[i] = 9
	p.owner[i] = 2
	p.team[i] = 1
	p.flags[i] = ProjectileStore.F_ALIVE | ProjectileStore.F_ARMED
	p.shooter[i] = EntityId.make(42, 7)
	p.target[i] = EntityId.make(43, 1)
	p.ttl[i] = 0.5
	p.hash_cell[i] = 777
	assert_that(p.pos[i]).is_equal(v)
	assert_that(p.vel[i]).is_equal(-v)
	assert_that(p.prev_pos[i]).is_equal(v * 0.5)
	assert_int(p.projectile_def[i]).is_equal(6)
	assert_int(p.weapon_def[i]).is_equal(9)
	assert_int(p.owner[i]).is_equal(2)
	assert_int(p.team[i]).is_equal(1)
	assert_int(p.shooter[i]).is_equal(EntityId.make(42, 7))
	assert_int(p.target[i]).is_equal(EntityId.make(43, 1))
	assert_float(p.ttl[i]).is_equal(0.5)
	assert_int(p.hash_cell[i]).is_equal(777)
	assert_bool(p.free_slot(i, 1)).is_true()
	assert_int(p.projectile_def[i]).is_equal(0)
	assert_int(p.owner[i]).is_equal(ProjectileStore.NONE_U8)
	assert_int(p.flags[i]).is_equal(0)
	assert_that(p.pos[i]).is_equal(Vector3.ZERO)
	assert_int(p.generation[i]).is_equal(2)


func test_live_cap_limits_allocation_not_layout() -> void:
	var p: ProjectileStore = ProjectileStore.new(600, 64)
	for k: int in 600:
		assert_int(p.alloc(ProjectileStore.SLUG, 0)).is_not_equal(EntityId.NULL_ID)
	assert_int(p.alloc(ProjectileStore.SLUG, 0)).is_equal(EntityId.NULL_ID)
	assert_int(p.live_count()).is_equal(600)
	assert_int(p.pos.size()).is_equal(ProjectileStore.SLOT_COUNT)
	assert_bool(p.free_slot(p.live[0], 0)).is_true()
	# With a non-zero quarantine (64 here) the freed slot waits, but other slots remain, so the cap frees one alloc.
	assert_int(p.index_of(p.alloc(ProjectileStore.SLUG, 0))).is_equal(600)


func test_slot_exhaustion_with_quarantine() -> void:
	var p: ProjectileStore = ProjectileStore.new(ProjectileStore.SLOT_COUNT)
	for k: int in ProjectileStore.SLOT_COUNT:
		var _id: int = p.alloc(ProjectileStore.FLAK, 0)
	assert_int(p.alloc(ProjectileStore.FLAK, 0)).is_equal(EntityId.NULL_ID)
	assert_bool(p.free_slot(17, 3)).is_true()
	assert_int(p.alloc(ProjectileStore.FLAK, 3 + Q - 1)).is_equal(EntityId.NULL_ID)
	var id: int = p.alloc(ProjectileStore.FLAK, 3 + Q)
	assert_int(p.index_of(id)).is_equal(17)
	assert_int(EntityId.gen(id)).is_equal(2)


func test_live_cap_above_slot_count_is_clamped() -> void:
	var p: ProjectileStore = ProjectileStore.new(ProjectileStore.SLOT_COUNT + 100)
	assert_int(p.live_cap).is_equal(ProjectileStore.SLOT_COUNT)


## Pooling: 50k fire/expire ops at a steady population reuse slots, never inside quarantine,
## generations step by one, and no array changes size.
func test_pooling_fuzz_no_reuse_in_quarantine_and_flat() -> void:
	var p: ProjectileStore = ProjectileStore.new(1000)
	var rng: Rng = Rng.new(99, 3)
	var n: int = ProjectileStore.SLOT_COUNT
	var freed_at: PackedInt32Array = PackedInt32Array()
	var _r: int = freed_at.resize(n)
	freed_at.fill(-1000000)
	var last_gen: PackedInt32Array = PackedInt32Array()
	_r = last_gen.resize(n)
	var bad: int = 0
	var reused: int = 0
	var tick: int = 0
	var layout_before: PackedInt32Array = StoreLayout.layout_of(p, n)
	for op: int in 50000:
		if rng.range_i(0, 7) == 0:
			tick += 1
		if rng.range_i(0, 99) < 52 or p.live.is_empty():
			var id: int = p.alloc(rng.range_i(ProjectileStore.SLUG, ProjectileStore.SIEGE_SHELL), tick)
			if id == EntityId.NULL_ID:
				continue
			var i: int = p.index_of(id)
			if tick - freed_at[i] < Q:
				bad += 1
			if last_gen[i] != 0:
				reused += 1
				if EntityId.gen(id) != EntityId.bump_gen(last_gen[i]):
					bad += 1
			last_gen[i] = EntityId.gen(id)
		else:
			var i: int = p.live[rng.range_i(0, p.live.size() - 1)]
			if not p.free_slot(i, tick):
				bad += 1
			freed_at[i] = tick
	assert_int(bad).is_equal(0)
	assert_int(reused).is_greater(1000)
	assert_that(StoreLayout.layout_of(p, n)).is_equal(layout_before)
	assert_int(p.live_count() + p.free_count() + p.quarantined_count()).is_equal(n)


## Owner decision 2026-10-13: a 2,000-projectile steady state with ~35-tick lifetimes fits the
## 2,048-slot range (it did not with a 64-tick quarantine).
func test_steady_state_2000_live_with_35_tick_lifetime() -> void:
	var p: ProjectileStore = ProjectileStore.new(2000)
	var born: PackedInt32Array = PackedInt32Array()
	var _r: int = born.resize(ProjectileStore.SLOT_COUNT)
	var failed: int = 0
	var peak: int = 0
	for tick: int in 400:
		var expired: PackedInt32Array = PackedInt32Array()
		for i: int in p.live:
			if tick - born[i] >= 35:
				var _b: bool = expired.push_back(i)
		for i: int in expired:
			var _ok: bool = p.free_slot(i, tick)
		for _k: int in 57:
			var id: int = p.alloc(ProjectileStore.SLUG, tick)
			if id == EntityId.NULL_ID:
				failed += 1
			else:
				born[p.index_of(id)] = tick
		peak = maxi(peak, p.live_count())
	assert_int(failed).is_equal(0)
	assert_int(peak).is_greater_equal(1990)


## Default quarantine is 0 (owner 2026-10-13): a freed slot is reusable the same tick, with a new generation.
func test_default_quarantine_reuses_slot_immediately() -> void:
	var p: ProjectileStore = ProjectileStore.new(600)
	var first: int = p.alloc(ProjectileStore.SLUG, 0)
	assert_bool(p.free_slot(p.index_of(first), 5)).is_true()
	var again: int = p.alloc(ProjectileStore.SLUG, 5)
	assert_int(EntityId.slot(again)).is_equal(EntityId.slot(first))
	assert_int(EntityId.gen(again)).is_equal(EntityId.bump_gen(EntityId.gen(first)))


## TA-46: 100k alloc/free cycles on one slot with the 0-tick quarantine run the generation through several
## wraps; an id kept in a PackedInt32Array field (`target`, `shooter`) must still validate while live.
func test_long_churn_one_slot_keeps_alive_and_index_of_consistent() -> void:
	var p: ProjectileStore = ProjectileStore.new(1, 0)
	var held: PackedInt32Array = PackedInt32Array()
	var _r: int = held.resize(1)
	var bad: int = 0
	var prev: int = EntityId.NULL_ID
	for t: int in 100000:
		var id: int = p.alloc(ProjectileStore.SLUG, t)
		held[0] = id
		var back: int = held[0]
		if id == EntityId.NULL_ID or back != id or not p.alive(back) or p.index_of(back) != 0:
			bad += 1
		if prev != EntityId.NULL_ID and (p.alive(prev) or EntityId.gen(id) != EntityId.bump_gen(EntityId.gen(prev))):
			bad += 1
		if not p.free_slot(p.index_of(back), t) or p.alive(back):
			bad += 1
		prev = back
	assert_int(bad).is_equal(0)
	assert_int(p.live_count()).is_equal(0)
