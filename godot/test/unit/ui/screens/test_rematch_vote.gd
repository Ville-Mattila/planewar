extends GdUnitTestSuite
## UX-27 REMATCH_VOTE (06 s8): 20 s, unanimity.


func test_unanimous_yes_passes() -> void:
	var v: RematchVote = RematchVote.new()
	v.open(PackedInt32Array([0, 2]), true)
	assert_float(v.left_s).is_equal(20.0)
	assert_bool(v.cast(0, true)).is_true()
	assert_int(v.status).is_equal(RematchVote.Status.PENDING)
	assert_bool(v.cast(2, true)).is_true()
	assert_int(v.status).is_equal(RematchVote.Status.PASSED)
	assert_int(v.yes_count()).is_equal(2)


func test_any_no_fails() -> void:
	var v: RematchVote = RematchVote.new()
	v.open(PackedInt32Array([0, 2]), true)
	var _c: bool = v.cast(2, false)
	assert_int(v.status).is_equal(RematchVote.Status.FAILED)
	assert_bool(v.cast(0, true)).is_false()   # closed


func test_timeout_without_unanimity_fails() -> void:
	var v: RematchVote = RematchVote.new()
	v.open(PackedInt32Array([0, 2]), true)
	var _c: bool = v.cast(0, true)
	v.tick(19.0)
	assert_int(v.status).is_equal(RematchVote.Status.PENDING)
	v.tick(2.0)
	assert_int(v.status).is_equal(RematchVote.Status.FAILED)
	assert_float(v.left_s).is_equal(0.0)


func test_disabled_when_not_allowed_or_nobody_votes() -> void:
	var v: RematchVote = RematchVote.new()
	v.open(PackedInt32Array([0]), false)
	assert_int(v.status).is_equal(RematchVote.Status.DISABLED)
	v.open(PackedInt32Array(), true)
	assert_int(v.status).is_equal(RematchVote.Status.DISABLED)
	assert_bool(v.cast(0, true)).is_false()


func test_non_eligible_slot_cannot_vote() -> void:
	var v: RematchVote = RematchVote.new()
	v.open(PackedInt32Array([0, 2]), true)
	assert_bool(v.cast(5, true)).is_false()
	assert_int(v.vote_of(5)).is_equal(RematchVote.Vote.NONE)
