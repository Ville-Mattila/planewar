extends GdUnitTestSuite
## Unit tests for core/rng.gd (PCG32; C6 reference sequence; fork; serialisation).

const REFERENCE_SEED_42_STREAM_54: Array[int] = [
	0xa15c02b7, 0x7b47f409, 0xba1d3330, 0x83d2f293, 0xbfa4784b,
	0xcbed606e, 0xbfc6a3ad, 0x812fff6d, 0xe61f305a, 0xf9384b90,
]


func test_c6_reference_sequence_seed_42_stream_54() -> void:
	var r := Rng.new(42, 54)
	for expected: int in REFERENCE_SEED_42_STREAM_54:
		assert_int(r.next_u32()).is_equal(expected)


func test_same_seed_and_stream_are_deterministic() -> void:
	var a := Rng.new(7, 3)
	var b := Rng.new(7, 3)
	for i in 1000:
		assert_int(a.next_u32()).is_equal(b.next_u32())


func test_state_roundtrip_continues_identically() -> void:
	var s := Rng.new(99, 5)
	for i in 17:
		var _x: int = s.next_u32()
	var restored: Rng = Rng.from_state(s.state())
	for i in 500:
		assert_int(restored.next_u32()).is_equal(s.next_u32())


func test_state_is_24_bytes() -> void:
	assert_int(Rng.new(1).state().size()).is_equal(24)


func test_fork_ai_is_deterministic() -> void:
	var f1: Rng = Rng.new(1234, 1).fork(&"ai")
	var f2: Rng = Rng.new(1234, 1).fork(&"ai")
	for i in 200:
		assert_int(f1.next_u32()).is_equal(f2.next_u32())


func test_fork_does_not_advance_parent() -> void:
	var p := Rng.new(1234, 1)
	var base := Rng.new(1234, 1)
	var _f: Rng = p.fork(&"ai")
	assert_int(p.next_u32()).is_equal(base.next_u32())


func test_fork_survives_parent_serialisation() -> void:
	var p := Rng.new(1234, 1)
	var f1: Rng = p.fork(&"ai")
	var f2: Rng = Rng.from_state(Rng.new(1234, 1).state()).fork(&"ai")
	for i in 100:
		assert_int(f1.next_u32()).is_equal(f2.next_u32())


func test_forked_child_state_serialises() -> void:
	var child: Rng = Rng.new(1234, 1).fork(&"ai")
	var copy: Rng = Rng.from_state(child.state())
	for i in 100:
		assert_int(copy.next_u32()).is_equal(child.next_u32())


func test_different_fork_names_differ() -> void:
	var p := Rng.new(1, 1)
	var a: Rng = p.fork(&"ai")
	var b: Rng = p.fork(&"terrain")
	assert_int(a.next_u32()).is_not_equal(b.next_u32())


func test_range_i_is_inclusive_and_bounded() -> void:
	var r := Rng.new(5, 5)
	var seen_lo := false
	var seen_hi := false
	for i in 5000:
		var v: int = r.range_i(3, 9)
		assert_bool(v >= 3 and v <= 9).is_true()
		seen_lo = seen_lo or v == 3
		seen_hi = seen_hi or v == 9
	assert_bool(seen_lo and seen_hi).is_true()
	assert_int(r.range_i(4, 4)).is_equal(4)


func test_next_float_and_range_f_bounds() -> void:
	var r := Rng.new(5, 5)
	for i in 1000:
		var f: float = r.next_float()
		assert_bool(f >= 0.0 and f < 1.0).is_true()
		var g: float = r.range_f(-2.0, 2.0)
		assert_bool(g >= -2.0 and g < 2.0).is_true()
