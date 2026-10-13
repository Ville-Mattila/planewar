extends GdUnitTestSuite
## Unit tests for core/entity_id.gd (03 s3.1).


func test_make_and_unpack_roundtrip() -> void:
	var id: int = EntityId.make(1234, 77)
	assert_int(EntityId.slot(id)).is_equal(1234)
	assert_int(EntityId.gen(id)).is_equal(77)


func test_null_id_is_zero_and_live_ids_are_not() -> void:
	assert_int(EntityId.NULL_ID).is_equal(0)
	assert_int(EntityId.make(1, 1)).is_not_equal(EntityId.NULL_ID)


func test_generation_wraps_4095_to_1() -> void:
	assert_int(EntityId.bump_gen(4095)).is_equal(1)
	assert_int(EntityId.bump_gen(1)).is_equal(2)


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
