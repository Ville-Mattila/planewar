extends GdUnitTestSuite
## NET-07 RollingRefresh (net/keyframe/MODULE.md K5, 04 s4.3, R0 C1-15): ceil(C_count / 300) FULL records per tick,
## round-robin over the client's C set; every C entity refreshed within 300 ticks; an entity refreshed less than 5 s
## (150 ticks) ago is skipped, which only matters below 150 C entities.

var _r: RollingRefresh
var _out: PackedInt32Array = PackedInt32Array()


func before_test() -> void:
	_r = RollingRefresh.new()


func _cs(n: int, step: int = 2, first: int = 40) -> PackedInt32Array:
	var c: PackedInt32Array = PackedInt32Array()
	for i: int in n:
		c.append(first + i * step)
	return c


func test_per_tick_is_ceil_of_count_over_300() -> void:
	assert_int(RollingRefresh.PERIOD_TICKS).is_equal(300)
	assert_int(RollingRefresh.MIN_REFRESH_TICKS).is_equal(150)
	assert_int(RollingRefresh.per_tick(0)).is_equal(0)
	assert_int(RollingRefresh.per_tick(1)).is_equal(1)
	assert_int(RollingRefresh.per_tick(300)).is_equal(1)
	assert_int(RollingRefresh.per_tick(301)).is_equal(2)
	assert_int(RollingRefresh.per_tick(700)).is_equal(3)
	assert_int(RollingRefresh.per_tick(900)).is_equal(3)
	assert_int(RollingRefresh.per_tick(901)).is_equal(4)
	assert_int(RollingRefresh.per_tick(-5)).is_equal(0)


func test_700_c_entities_three_per_tick_each_within_300_ticks() -> void:
	var c: PackedInt32Array = _cs(700)
	var last: Dictionary[int, int] = {}
	var worst: int = 0
	for t: int in range(1, 1201):
		assert_int(_r.pick(c, t, _out)).is_equal(3)
		assert_int(_out.size()).is_equal(3)
		for s: int in _out:
			assert_bool(c.has(s)).is_true()
			if last.has(s):
				worst = maxi(worst, t - last[s])
			last[s] = t
	assert_int(last.size()).is_equal(700)
	assert_int(worst).is_less_equal(300)
	assert_int(worst).is_greater_equal(233)                # a full cycle is ~7.8 s of ticks (04 s4.3)
	assert_int(_r.picked).is_equal(3 * 1200)
	assert_int(_r.skipped).is_equal(0)


func test_300_and_301_and_899_c_entities_cover_in_300_ticks() -> void:
	for n: int in [300, 301, 899, 1000, 1536]:
		var rr: RollingRefresh = RollingRefresh.new()
		var c: PackedInt32Array = _cs(n, 1, 0)
		var seen: Dictionary[int, int] = {}
		for t: int in range(1, 301):
			var _k: int = rr.pick(c, t, _out)
			assert_int(_out.size()).is_less_equal(RollingRefresh.per_tick(n))
			for s: int in _out:
				seen[s] = t
		assert_int(seen.size()).is_equal(n)


func test_small_set_one_per_tick_skips_the_recently_refreshed() -> void:
	var c: PackedInt32Array = _cs(100)
	var last: Dictionary[int, int] = {}
	var worst: int = 0
	var best: int = 1000
	for t: int in range(1, 1001):
		var n: int = _r.pick(c, t, _out)
		assert_int(n).is_less_equal(1)
		for s: int in _out:
			if last.has(s):
				worst = maxi(worst, t - last[s])
				best = mini(best, t - last[s])
			last[s] = t
	assert_int(best).is_greater_equal(RollingRefresh.MIN_REFRESH_TICKS)   # never twice inside 5 s
	assert_int(worst).is_less_equal(RollingRefresh.PERIOD_TICKS)          # and still within 300 ticks
	assert_int(_r.skipped).is_greater(0)
	assert_int(last.size()).is_equal(100)


func test_149_entities_still_covered_within_300() -> void:
	var c: PackedInt32Array = _cs(149)
	var last: Dictionary[int, int] = {}
	var worst: int = 0
	for t: int in range(1, 1500):
		var _n: int = _r.pick(c, t, _out)
		for s: int in _out:
			if last.has(s):
				worst = maxi(worst, t - last[s])
			last[s] = t
	assert_int(worst).is_less_equal(300)


func test_note_full_counts_as_refreshed() -> void:
	var c: PackedInt32Array = _cs(20)
	_r.note_full(c, 10)
	for t: int in range(11, 150):                          # everything refreshed at 10: nothing due before tick 160
		assert_int(_r.pick(c, t, _out)).is_equal(0)
	var due: int = 0
	for t: int in range(160, 200):
		due += _r.pick(c, t, _out)
	assert_int(due).is_greater(0)


func test_cursor_survives_set_changes_and_empty_sets() -> void:
	var c: PackedInt32Array = _cs(600)
	var _n: int = _r.pick(c, 1, _out)
	var first: PackedInt32Array = _out.duplicate()
	assert_int(_r.pick(PackedInt32Array(), 2, _out)).is_equal(0)           # no C set: nothing, cursor kept
	assert_int(_out.size()).is_equal(0)
	var shrunk: PackedInt32Array = c.slice(100)                            # the first 100 left the set
	var seen: Dictionary[int, bool] = {}
	for t: int in range(3, 305):
		var _k: int = _r.pick(shrunk, t, _out)
		for s: int in _out:
			assert_bool(shrunk.has(s)).is_true()
			seen[s] = true
	assert_int(seen.size()).is_equal(500)
	assert_int(first.size()).is_equal(2)


func test_unsorted_or_duplicate_c_never_throws_and_output_is_cleared() -> void:
	var c: PackedInt32Array = PackedInt32Array([90, 4, 4, 70, -3, 2000, 12])
	_out.append(777)
	for t: int in range(1, 100):
		var n: int = _r.pick(c, t, _out)
		assert_int(_out.size()).is_equal(n)
		for s: int in _out:
			assert_bool(s >= 0 and s < Roster.CAPACITY).is_true()


func test_reset_forgets_everything() -> void:
	var c: PackedInt32Array = _cs(50)
	for t: int in range(1, 60):
		var _n: int = _r.pick(c, t, _out)
	_r.reset()
	assert_int(_r.picked).is_equal(0)
	assert_int(_r.pick(c, 100, _out)).is_equal(1)
	assert_int(_out[0]).is_equal(c[0])


func test_deterministic() -> void:
	var c: PackedInt32Array = _cs(500, 3, 7)
	var a: RollingRefresh = RollingRefresh.new()
	var b: RollingRefresh = RollingRefresh.new()
	var oa: PackedInt32Array = PackedInt32Array()
	var ob: PackedInt32Array = PackedInt32Array()
	for t: int in range(1, 400):
		var _x: int = a.pick(c, t, oa)
		var _y: int = b.pick(c, t, ob)
		assert_array(oa).is_equal(ob)
