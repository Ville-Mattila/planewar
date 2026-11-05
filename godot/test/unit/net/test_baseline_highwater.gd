extends GdUnitTestSuite
## NET-59: BaselineFrame's high-water mark. clear / copy_from move only [0, hi); every entry at or above the mark
## is a default, so a frame never reads stale data past it (adds, shrink after clear, recycled high index).

const HIGH: int = Roster.CAPACITY - 1


func _full(f: BaselineFrame, i: int, t: int) -> void:
	f.set_full(i, t, 1000 + i, 0x12345678, 77, 200, 3, 5)


func _is_default(f: BaselineFrame, i: int) -> bool:
	return f.present[i] == 0 and f.pos[i] == 0 and f.ori[i] == 0 and f.ori_c[i] == 0 and f.vel[i] == 0 \
			and f.hp[i] == 0 and f.flags[i] == 0 and f.ai[i] == 0 and f.blip[i] == DeadReckon.BLIP_UNKNOWN \
			and f.etick[i] == 0


func test_mark_tracks_every_setter() -> void:
	var f: BaselineFrame = BaselineFrame.new()
	assert_int(f.hi).is_equal(0)
	_full(f, 3, 1)
	assert_int(f.hi).is_equal(4)
	f.set_full_cached(9, 1, 5, 6, 7, 8, 9, 10, 11)
	assert_int(f.hi).is_equal(10)
	f.set_delta(15, 2, false, 0, 1, 2, 3, 4, 5, -1)     # each setter raises the mark above its current value
	assert_int(f.hi).is_equal(16)
	f.set_blip(20, 2, 4)
	assert_int(f.hi).is_equal(21)
	f.set_blip_at(30, 2, 4, 99)
	assert_int(f.hi).is_equal(31)
	f.set_delta(2, 3, true, 0, 1, 2, 3, 4, 5, -1)       # a lower index never lowers it
	assert_int(f.hi).is_equal(31)


func test_copy_of_empty_source_clears_stale_destination() -> void:
	var dst: BaselineFrame = BaselineFrame.new()
	_full(dst, 40, 1)
	_full(dst, HIGH, 1)
	var empty: BaselineFrame = BaselineFrame.new()
	dst.copy_from(empty, 9)
	assert_int(dst.hi).is_equal(0)
	assert_int(dst.present[40]).is_equal(0)
	assert_bool(dst.same_state(empty)).is_true()
	for i: int in [0, 40, HIGH]:
		assert_bool(_is_default(dst, i)).is_true()


func test_clear_after_removals_shrinks_mark_and_resets_all() -> void:
	var f: BaselineFrame = BaselineFrame.new()
	_full(f, 10, 1)
	_full(f, HIGH, 1)
	assert_int(f.hi).is_equal(Roster.CAPACITY)
	f.clear(2)
	assert_int(f.hi).is_equal(0)
	for i: int in [0, 10, HIGH]:
		assert_bool(_is_default(f, i)).is_true()
	_full(f, 4, 3)
	assert_int(f.hi).is_equal(5)
	assert_bool(_is_default(f, 10)).is_true()       # the old high entries never reappear
	assert_bool(_is_default(f, HIGH)).is_true()


func test_copy_matches_full_copy_and_defaults_past_mark() -> void:
	var src: BaselineFrame = BaselineFrame.new()
	for i: int in [0, 7, 100, 1600]:
		_full(src, i, 4)
	src.set_blip(7, 5, 3)
	var dst: BaselineFrame = BaselineFrame.new()
	_full(dst, HIGH, 1)                                # stale high entry in the destination
	_full(dst, 2000, 1)
	dst.copy_from(src, 6)
	assert_int(dst.hi).is_equal(1601)
	assert_int(dst.base_tick).is_equal(src.tick)
	assert_bool(dst.same_state(src)).is_true()
	for i: int in range(dst.hi, Roster.CAPACITY):
		assert_bool(_is_default(dst, i)).is_true()
	_full(dst, 5, 7)                                   # copies are independent
	assert_bool(dst.same_state(src)).is_false()
	assert_int(src.present[5]).is_equal(0)


func test_recycled_high_index_raises_mark_again() -> void:
	var a: BaselineFrame = BaselineFrame.new()
	_full(a, 50, 1)
	var b: BaselineFrame = BaselineFrame.new()
	b.copy_from(a, 2)
	assert_int(b.hi).is_equal(51)
	_full(b, HIGH, 2)                                  # a projectile slot recycled far above the mark
	assert_int(b.hi).is_equal(Roster.CAPACITY)
	var c: BaselineFrame = BaselineFrame.new()
	c.copy_from(b, 3)
	assert_int(c.hi).is_equal(Roster.CAPACITY)
	assert_int(c.pos[HIGH]).is_equal(1000 + HIGH)
	assert_bool(c.same_state(b)).is_true()
	assert_int(a.hi).is_equal(51)                      # the earlier frame is untouched
	assert_int(a.present[HIGH]).is_equal(0)


func test_fresh_frame_blip_default() -> void:
	var f: BaselineFrame = BaselineFrame.new()
	assert_bool(_is_default(f, 0)).is_true()
	assert_bool(_is_default(f, HIGH)).is_true()
	var g: BaselineFrame = BaselineFrame.new()
	g.copy_from(f, 1)
	assert_bool(_is_default(g, HIGH)).is_true()
