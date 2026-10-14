extends GdUnitTestSuite
## Unit tests for core/entity_id.gd (03 s3.1).


func test_make_and_unpack_roundtrip() -> void:
	var id: int = EntityId.make(1234, 77)
	assert_int(EntityId.slot(id)).is_equal(1234)
	assert_int(EntityId.gen(id)).is_equal(77)


func test_null_id_is_zero_and_live_ids_are_not() -> void:
	assert_int(EntityId.NULL_ID).is_equal(0)
	assert_int(EntityId.make(1, 1)).is_not_equal(EntityId.NULL_ID)


func test_generation_wraps_gen_max_to_1() -> void:
	# TA-46 (R0 B.10 A-48): 11-bit generation, 1..2047, wraps 2047 -> 1, never 0.
	assert_int(EntityId.GEN_MAX).is_equal(2047)
	assert_int(EntityId.GEN_MASK).is_equal(EntityId.GEN_MAX)
	assert_int(EntityId.bump_gen(EntityId.GEN_MAX - 1)).is_equal(EntityId.GEN_MAX)
	assert_int(EntityId.bump_gen(EntityId.GEN_MAX)).is_equal(1)
	assert_int(EntityId.bump_gen(1)).is_equal(2)


func test_bump_gen_cycle_stays_in_1_to_gen_max() -> void:
	var g: int = 1
	for _k: int in 3 * EntityId.GEN_MAX:
		g = EntityId.bump_gen(g)
		assert_bool(g >= 1 and g <= EntityId.GEN_MAX).is_true()


## Bit 31 is never set, so an id survives a PackedInt32Array round trip (no sign extension) and the u32 wire
## form (04) equals the int. Every generation, at the slot range edges.
func test_stored_and_read_ids_compare_equal_for_every_gen() -> void:
	var slots: PackedInt32Array = PackedInt32Array([1, EntityId.WRECK_SLOT_END - 1, EntityId.PROJECTILE_SLOT_MIN,
			EntityId.PROJECTILE_SLOT_END - 1, EntityId.SLOT_MASK])
	var stored: PackedInt32Array = PackedInt32Array()
	var _r: int = stored.resize(1)
	var bad: int = 0
	for s: int in slots:
		for g: int in range(1, EntityId.GEN_MAX + 1):
			var id: int = EntityId.make(s, g)
			stored[0] = id
			var back: int = stored[0]
			if back != id or id < 0 or id > 0x7FFFFFFF or EntityId.gen(back) != g or EntityId.slot(back) != s:
				bad += 1
	assert_int(bad).is_equal(0)


func test_make_masks_generation_to_gen_mask() -> void:
	assert_int(EntityId.gen(EntityId.make(7, EntityId.GEN_MAX + 1))).is_equal(0)
	assert_int(EntityId.make(7, EntityId.GEN_MAX + 1)).is_equal(7)


func test_projectile_slot_boundary() -> void:
	assert_bool(EntityId.is_projectile(EntityId.make(4096, 1))).is_true()
	assert_bool(EntityId.is_projectile(EntityId.make(4095, 1))).is_false()


func test_projectile_slot_end_bounds_the_03_range() -> void:
	# 03 s3.1: projectile slots 4,096 .. 6,143; END is exclusive and the range fits SLOT_MASK (TA-46, A-20).
	assert_int(EntityId.PROJECTILE_SLOT_END).is_equal(6144)
	assert_int(EntityId.PROJECTILE_SLOT_END - EntityId.PROJECTILE_SLOT_MIN).is_equal(2048)
	assert_int(EntityId.PROJECTILE_SLOT_END - 1).is_less_equal(EntityId.SLOT_MASK)
	var last: int = EntityId.make(EntityId.PROJECTILE_SLOT_END - 1, 1)
	assert_bool(EntityId.is_projectile(last)).is_true()
	assert_int(EntityId.slot(last)).is_equal(6143)


func test_wreck_slot_range_is_1280_to_1535_inclusive() -> void:
	assert_bool(EntityId.is_wreck(EntityId.make(1280, 1))).is_true()
	assert_bool(EntityId.is_wreck(EntityId.make(1535, 1))).is_true()
	assert_bool(EntityId.is_wreck(EntityId.make(1279, 1))).is_false()
	assert_bool(EntityId.is_wreck(EntityId.make(1536, 1))).is_false()
