extends GdUnitTestSuite
## AI-17 review: the 05 s6.8 crowd term (x0.7 above 2 friendly towers) counts towers only. `AiState.tower_target_count`
## is derived like `target_count` (maintained by `set_target`, rebuilt by `deserialize`) for the one class a brain
## declares with `AiBrain.counts_targets` (`AiDriver.set_brain` sets `AiState.counted_class`).

const TOWER_CLS: int = 3
const SHIP_CLS: int = 1


func _id(slot: int) -> int:
	return EntityId.make(slot, 1)


func _reg(st: AiState, slot: int, cls: int) -> void:
	st.cls[slot] = cls
	st.eid[slot] = _id(slot)


func test_only_the_counted_class_enters_the_tower_count() -> void:
	var st: AiState = AiState.new(32)
	st.counted_class = TOWER_CLS
	for s: int in [2, 3, 4]:
		_reg(st, s, TOWER_CLS)
	for s: int in [5, 6]:
		_reg(st, s, SHIP_CLS)
	for s: int in [2, 3, 5, 6]:
		st.set_target(s, _id(9))
	assert_int(st.target_count[9]).is_equal(4)
	assert_int(st.tower_target_count[9]).is_equal(2)
	st.set_target(3, _id(10))                       # a retarget moves the tower's count
	assert_int(st.tower_target_count[9]).is_equal(1)
	assert_int(st.tower_target_count[10]).is_equal(1)
	st.set_target(5, 0)
	assert_int(st.tower_target_count[9]).is_equal(1)   # a ship dropping its target is not a tower
	st.clear_slot(2)                                # an unregistered tower no longer counts
	assert_int(st.tower_target_count[9]).is_equal(0)


func test_tower_count_is_rebuilt_by_deserialize_and_not_in_the_bytes() -> void:
	var st: AiState = AiState.new(32)
	st.counted_class = TOWER_CLS
	for s: int in [2, 3, 5]:
		_reg(st, s, TOWER_CLS if s != 5 else SHIP_CLS)
		st.set_target(s, _id(9))
	var bytes: PackedByteArray = st.serialize()
	var r: AiState = AiState.new(32)
	r.counted_class = TOWER_CLS
	assert_bool(r.deserialize(bytes)).is_true()
	assert_int(r.tower_target_count[9]).is_equal(2)
	assert_int(r.target_count[9]).is_equal(3)
	assert_bool(r.serialize() == bytes).is_true()
	var plain: AiState = AiState.new(32)            # no counted class: the tower count stays zero
	assert_bool(plain.deserialize(bytes)).is_true()
	assert_int(plain.tower_target_count[9]).is_equal(0)


func test_set_brain_declares_the_counted_class_for_a_brain_that_asks() -> void:
	var d: AiDriver = AiDriver.new(Rng.new(1))
	assert_int(d.state.counted_class).is_equal(AiState.NO_CLASS)
	d.set_brain(2, AiBrain.new())
	assert_int(d.state.counted_class).is_equal(AiState.NO_CLASS)
	assert_bool(AiBrain.new().counts_targets()).is_false()
	var tb: TowerBrain = Ai17Kit.brain()
	assert_bool(tb.counts_targets()).is_true()
	d.set_brain(TOWER_CLS, tb)
	assert_int(d.state.counted_class).is_equal(TOWER_CLS)
