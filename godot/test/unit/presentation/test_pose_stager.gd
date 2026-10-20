extends GdUnitTestSuite
## TA-55: PoseStager splits a tick's ids into head and tail halves and owns the read_poses scratch.


func _ids(n: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for i: int in n:
		var _a: bool = out.push_back(EntityId.make(i + 1, 1))
	return out


func test_small_lists_are_not_staggered() -> void:
	var st: PoseStager = PoseStager.new()
	st.begin(_ids(PoseStager.STAGGER_MIN - 1))
	assert_bool(st.pending).is_false()
	assert_int(st.split).is_equal(PoseStager.STAGGER_MIN - 1)
	assert_int(st.ids_hi.size()).is_equal(0)


func test_large_lists_split_in_half_and_the_tail_ends_pending() -> void:
	var st: PoseStager = PoseStager.new()
	var ids: PackedInt32Array = _ids(100)
	st.begin(ids)
	assert_bool(st.pending).is_true()
	assert_int(st.ids_lo.size()).is_equal(50)
	assert_int(st.ids_hi[0]).is_equal(ids[50])
	var v: StubSimView = StubSimView.new()
	st.read_tail(v)
	assert_bool(st.pending).is_false()
	assert_int(st.split).is_equal(100)


func test_begin_while_pending_reads_everything_at_once() -> void:
	var st: PoseStager = PoseStager.new()
	st.begin(_ids(100))
	st.begin(_ids(100))
	assert_bool(st.pending).is_false()
	assert_int(st.ids_lo.size()).is_equal(100)


func test_reset_clears_pending() -> void:
	var st: PoseStager = PoseStager.new()
	st.begin(_ids(100))
	st.reset()
	assert_bool(st.pending).is_false()
