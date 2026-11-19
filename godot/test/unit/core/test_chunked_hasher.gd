extends GdUnitTestSuite
## Unit tests for core/chunked_hasher.gd (TA-36; 03 s11.1: SHA-256 in 256 KB pieces, one budgeted job per frame).

const FACE_BYTES: int = 2 * 1024 * 1024
const FRAME_LIMIT_USEC: float = 33000.0
const CITE: String = "TA-36; 03 s11.1 (no frame > 33 ms)"


func _data(n: int) -> PackedByteArray:
	var b: PackedByteArray = PackedByteArray()
	var _r: int = b.resize(n)
	for i: int in range(0, n, 4099):
		b[i] = i & 0xFF
	return b


func _one_shot(data: PackedByteArray) -> PackedByteArray:
	var ctx: HashingContext = HashingContext.new()
	var _s: int = ctx.start(HashingContext.HASH_SHA256)
	var _u: int = ctx.update(data)
	return ctx.finish()


func test_chunk_size_is_256_kib() -> void:
	assert_int(ChunkedHasher.CHUNK_BYTES).is_equal(262144)
	assert_int(ChunkedHasher.chunk_count(FACE_BYTES)).is_equal(8)
	assert_int(ChunkedHasher.chunk_count(0)).is_equal(0)
	assert_int(ChunkedHasher.chunk_count(1)).is_equal(1)


func test_digest_matches_one_shot() -> void:
	var data: PackedByteArray = _data(FACE_BYTES + 77)
	var h: ChunkedHasher = ChunkedHasher.new()
	h.begin(data)
	var guard: int = 0
	while not h.step(0):
		guard += 1
		assert_int(guard).is_less(100)
	assert_bool(h.is_done()).is_true()
	assert_array(h.digest()).is_equal(_one_shot(data))


func test_zero_budget_hashes_exactly_one_chunk_per_step() -> void:
	var h: ChunkedHasher = ChunkedHasher.new()
	h.begin(_data(FACE_BYTES))
	var steps: int = 0
	while not h.step(0):
		steps += 1
	assert_int(steps + 1).is_equal(8)


func test_progress_is_monotonic_from_zero_to_one() -> void:
	var h: ChunkedHasher = ChunkedHasher.new()
	h.begin(_data(FACE_BYTES))
	assert_float(h.progress()).is_equal(0.0)
	var last: float = 0.0
	while not h.step(0):
		assert_float(h.progress()).is_greater(last)
		last = h.progress()
	assert_float(h.progress()).is_equal(1.0)


func test_digest_empty_until_done() -> void:
	var h: ChunkedHasher = ChunkedHasher.new()
	h.begin(_data(FACE_BYTES))
	assert_bool(h.step(0)).is_false()
	assert_int(h.digest().size()).is_equal(0)


func test_empty_input_is_done_with_sha256_of_nothing() -> void:
	var h: ChunkedHasher = ChunkedHasher.new()
	h.begin(PackedByteArray())
	assert_bool(h.step(0)).is_true()
	assert_array(h.digest()).is_equal(_one_shot(PackedByteArray()))


func test_no_step_exceeds_one_frame() -> void:
	var data: PackedByteArray = _data(FACE_BYTES * 6)
	var h: ChunkedHasher = ChunkedHasher.new()
	h.begin(data)
	var worst: int = 0
	var done: bool = false
	while not done:
		var t0: int = Time.get_ticks_usec()
		done = h.step(ChunkedHasher.DEFAULT_BUDGET_USEC)
		worst = maxi(worst, Time.get_ticks_usec() - t0)
	assert_bool(PerfGate.check("chunked_hasher.worst_step", float(worst), FRAME_LIMIT_USEC, CITE)).is_true()
	assert_array(h.digest()).is_equal(_one_shot(data))


func test_begin_restarts() -> void:
	var h: ChunkedHasher = ChunkedHasher.new()
	h.begin(_data(FACE_BYTES))
	var _s: bool = h.step(0)
	var other: PackedByteArray = _data(1000)
	h.begin(other)
	assert_bool(h.step(0)).is_true()
	assert_array(h.digest()).is_equal(_one_shot(other))
