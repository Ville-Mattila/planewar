extends GdUnitTestSuite
## NET-07 KeyframePolicy (net/keyframe/MODULE.md K1, 04 s4.3): a keyframe on join / reconnect, on an accepted
## REQUEST_KEYFRAME (one per 5 s), and after an ack gap of 33 ticks (older than the 32-frame ring), exactly once per
## episode; never periodically; never again for a keyframe the client has not acked.

var _p: KeyframePolicy
var _store: BaselineStore


func before_test() -> void:
	_p = KeyframePolicy.new()
	_store = BaselineStore.new(0)


## What the server does when the client's ack for tick t arrives: the mirror frame exists, the ack advances.
func _ack(t: int) -> void:
	var _f: BaselineFrame = _store.begin(t, 0)
	_store.ack(t)


## What KeyframeCodec.encode does to the mirror.
func _sent_keyframe(t: int) -> void:
	_store.reset()
	var _f: BaselineFrame = _store.begin(t, 0)


func test_nothing_before_start() -> void:
	for t: int in range(1, 200):
		assert_int(_p.poll(_store, t)).is_equal(KeyframePolicy.NONE)
	assert_bool(_p.request(Protocol.KeyframeRequest.DESYNC, 5)).is_false()
	assert_int(_p.seq).is_equal(0)


func test_join_keyframe_once() -> void:
	_p.start(10)
	assert_int(_p.poll(_store, 10)).is_equal(Protocol.KeyframeScope.ALL)
	assert_int(_p.seq).is_equal(1)
	assert_int(_p.anchor_tick).is_equal(10)
	assert_int(_p.poll(_store, 10)).is_equal(KeyframePolicy.NONE)
	assert_int(_p.poll(_store, 11)).is_equal(KeyframePolicy.NONE)
	assert_int(_p.sent_all).is_equal(1)


func test_constants() -> void:
	assert_int(KeyframePolicy.STALE_TICKS).is_equal(BaselineStore.DEPTH + 1)
	assert_int(KeyframePolicy.REQUEST_MIN_TICKS).is_equal(150)
	assert_int(KeyframePolicy.NONE).is_equal(-1)


## Acceptance: a 33-tick ack gap yields exactly one keyframe; a 32-tick gap none.
func test_33_tick_ack_gap_sends_exactly_one_keyframe() -> void:
	_p.start(1)
	assert_int(_p.poll(_store, 1)).is_equal(Protocol.KeyframeScope.ALL)
	_sent_keyframe(1)
	var keyframes: int = 0
	for t: int in range(2, 51):                            # healthy: the client acks every tick
		_ack(t)
		assert_int(_p.poll(_store, t)).is_equal(KeyframePolicy.NONE)
	assert_int(_store.acked_tick).is_equal(50)
	for t: int in range(51, 83):                           # acks stop: gaps 1 .. 32
		assert_int(_p.poll(_store, t)).is_equal(KeyframePolicy.NONE)
	assert_int(82 - _store.acked_tick).is_equal(32)
	var scope: int = _p.poll(_store, 83)                   # gap 33
	assert_int(scope).is_equal(Protocol.KeyframeScope.ALL)
	keyframes += 1
	_sent_keyframe(83)
	assert_int(_p.sent_stale).is_equal(1)
	assert_int(_p.seq).is_equal(2)
	for t: int in range(84, 600):                          # still silent: the unacked keyframe is not repeated
		if _p.poll(_store, t) != KeyframePolicy.NONE:
			keyframes += 1
	assert_int(keyframes).is_equal(1)


func test_ack_gap_of_32_is_not_stale_and_recovery_after_a_keyframe() -> void:
	_p.start(1)
	var _s: int = _p.poll(_store, 1)
	_sent_keyframe(1)
	_ack(1)
	assert_int(_p.poll(_store, 33)).is_equal(KeyframePolicy.NONE)   # 33 - 1 = 32
	assert_int(_p.poll(_store, 34)).is_equal(Protocol.KeyframeScope.ALL)
	_sent_keyframe(34)
	_ack(36)                                               # the client answers the keyframe
	for t: int in range(37, 400):
		if t % 3 == 0:
			_ack(t)
		assert_int(_p.poll(_store, t)).is_equal(KeyframePolicy.NONE)
	assert_int(_p.sent_stale).is_equal(1)
	# A second silent episode after recovery is a second keyframe.
	assert_int(_p.poll(_store, 399 + 33)).is_equal(Protocol.KeyframeScope.ALL)


func test_no_periodic_keyframe_in_a_long_healthy_session() -> void:
	_p.start(1)
	var _s: int = _p.poll(_store, 1)
	_sent_keyframe(1)
	var total: int = 1
	for t: int in range(2, 3001):
		if t % 3 == 0:
			_ack(t)
		if _p.poll(_store, t) != KeyframePolicy.NONE:
			total += 1
	assert_int(total).is_equal(1)
	assert_int(_p.sent_all + _p.sent_repair).is_equal(1)


func test_request_rate_limit_one_per_5_seconds() -> void:
	_p.start(1)
	var _s: int = _p.poll(_store, 1)
	assert_bool(_p.request(Protocol.KeyframeRequest.DESYNC, 10)).is_true()
	assert_int(_p.poll(_store, 10)).is_equal(Protocol.KeyframeScope.ALL)
	assert_int(_p.sent_requested).is_equal(1)
	assert_bool(_p.request(Protocol.KeyframeRequest.DESYNC, 159)).is_false()      # 149 ticks later
	assert_int(_p.refused).is_equal(1)
	assert_int(_p.poll(_store, 159)).is_equal(KeyframePolicy.NONE)
	assert_bool(_p.request(Protocol.KeyframeRequest.DESYNC, 160)).is_true()       # exactly 150 ticks
	assert_int(_p.poll(_store, 160)).is_equal(Protocol.KeyframeScope.ALL)
	assert_int(_p.seq).is_equal(3)


func test_roster_gap_asks_for_a_repair_resume_and_desync_for_all() -> void:
	_p.start(1)
	var _s: int = _p.poll(_store, 1)
	assert_bool(_p.request(Protocol.KeyframeRequest.ROSTER_GAP, 200)).is_true()
	assert_int(_p.poll(_store, 200)).is_equal(Protocol.KeyframeScope.ROSTER_REPAIR)
	assert_int(_p.sent_repair).is_equal(1)
	assert_bool(_p.request(Protocol.KeyframeRequest.RESUME, 400)).is_true()
	assert_int(_p.poll(_store, 400)).is_equal(Protocol.KeyframeScope.ALL)
	assert_bool(_p.request(99, 600)).is_false()                                   # unknown reason
	assert_bool(_p.request(-1, 600)).is_false()
	assert_int(_p.poll(_store, 600)).is_equal(KeyframePolicy.NONE)


func test_all_beats_a_pending_repair_and_collapses_to_one_keyframe() -> void:
	_p.start(1)                                            # ALL pending from the join
	assert_bool(_p.request(Protocol.KeyframeRequest.ROSTER_GAP, 1)).is_true()
	assert_int(_p.poll(_store, 1)).is_equal(Protocol.KeyframeScope.ALL)
	assert_int(_p.poll(_store, 1)).is_equal(KeyframePolicy.NONE)
	assert_int(_p.seq).is_equal(1)


func test_start_again_for_a_reconnect() -> void:
	_p.start(1)
	var _s: int = _p.poll(_store, 1)
	_sent_keyframe(1)
	_p.start(500)
	assert_int(_p.poll(_store, 500)).is_equal(Protocol.KeyframeScope.ALL)
	assert_int(_p.seq).is_equal(2)
	assert_bool(_p.request(Protocol.KeyframeRequest.DESYNC, 501)).is_true()       # a fresh start clears the request limit
