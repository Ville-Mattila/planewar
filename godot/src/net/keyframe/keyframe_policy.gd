class_name KeyframePolicy extends RefCounted
## When a client gets a KEYFRAME (04 s4.3): on join / reconnect (`start`), on an accepted REQUEST_KEYFRAME (one per 5 s),
## and when its ack is older than the 32-frame baseline ring (a gap of 33 ticks). Never periodically. A stale-ack
## keyframe is sent once per episode: while the last keyframe is unacked the (reliable) channel is trusted and no
## further stale keyframe is sent. One instance per client; the caller resets the BaselineStore through
## KeyframeCodec.encode and sends no SNAPSHOT to the client in the keyframe's tick.

const STALE_TICKS: int = BaselineStore.DEPTH + 1
const REQUEST_MIN_TICKS: int = 150
const NONE: int = -1

var seq: int = 0                            # keyframe_seq of the last keyframe `poll` returned (u16)
var anchor_tick: int = 0                    # tick of that keyframe
var sent_all: int = 0                       # keyframes by scope (any cause)
var sent_repair: int = 0
var sent_stale: int = 0                     # keyframes caused by a stale ack
var sent_requested: int = 0                 # keyframes caused by an accepted REQUEST_KEYFRAME
var refused: int = 0                        # requests refused by the 5 s limit
var _started: bool = false
var _pending: int = NONE
var _requested: bool = false
var _last_request: int = -REQUEST_MIN_TICKS


## Join or reconnect: a KEYFRAME(ALL) is due at the next poll; the request limit starts fresh.
func start(tick: int) -> void:
	_started = true
	_pending = Protocol.KeyframeScope.ALL
	_requested = false
	_last_request = tick - REQUEST_MIN_TICKS


## REQUEST_KEYFRAME(reason). False when not started, the reason is unknown, or the last accepted request is < 5 s old.
func request(reason: int, tick: int) -> bool:
	if not _started or reason < Protocol.KeyframeRequest.DESYNC or reason > Protocol.KeyframeRequest.RESUME:
		return false
	if tick - _last_request < REQUEST_MIN_TICKS:
		refused += 1
		return false
	_last_request = tick
	_requested = true
	if _pending != Protocol.KeyframeScope.ALL:
		_pending = Protocol.KeyframeScope.ROSTER_REPAIR if reason == Protocol.KeyframeRequest.ROSTER_GAP \
				else Protocol.KeyframeScope.ALL
	return true


## The scope due this tick (Protocol.KeyframeScope) or NONE. Consumes the trigger and advances `seq`.
func poll(store: BaselineStore, tick: int) -> int:
	if not _started:
		return NONE
	var scope: int = _pending
	var stale: bool = false
	if scope == NONE and anchor_tick > 0 and store.acked_tick >= anchor_tick and tick - store.acked_tick >= STALE_TICKS:
		scope = Protocol.KeyframeScope.ALL
		stale = true
	if scope == NONE:
		return NONE
	_pending = NONE
	seq = (seq + 1) & 0xFFFF
	anchor_tick = tick
	if scope == Protocol.KeyframeScope.ALL:
		sent_all += 1
	else:
		sent_repair += 1
	if stale:
		sent_stale += 1
	elif _requested:
		sent_requested += 1
	_requested = false
	return scope
