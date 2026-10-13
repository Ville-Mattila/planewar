class_name RosterSync extends RefCounted
## Client-side roster maintenance with the held-record logic (04 s3.1). A SNAPSHOT (channel 2) can arrive
## before the ENTITY_META (channel 3) that defines an index it references; the client then holds the raw
## bytes, keyed by tick, until the meta arrives. A record still held HOLD_TICKS (30 = 1 s) after it arrived
## is dropped and triggers one REQUEST_KEYFRAME(ROSTER_GAP), rate-limited to one per 5 s (04 s2.3).
## All time is the caller's tick counter; nothing reads a clock. No Nodes.

const HOLD_TICKS: int = 30                  # 1 s at 30 Hz
const REQUEST_MIN_TICKS: int = 150          # REQUEST_KEYFRAME is <= 1 per 5 s
const MAX_HELD: int = 64                    # bounds memory under a flood of unmatched snapshots

var roster: Roster = Roster.new()
var requests_sent: int = 0
var removed_slots: PackedInt32Array = PackedInt32Array()   # slots removed by the last on_remove
var added_slots: PackedInt32Array = PackedInt32Array()     # slots added by the last on_meta

var _snap_tick: PackedInt32Array = PackedInt32Array()
var _arrival: PackedInt32Array = PackedInt32Array()
var _bytes: Array[PackedByteArray] = []
var _missing: Array[PackedInt32Array] = []
var _last_request: int = -REQUEST_MIN_TICKS
var _overflow: bool = false


func held_count() -> int:
	return _snap_tick.size()


## Applies an ENTITY_META packet; returns the entry count or -1 when malformed.
func on_meta(bytes: PackedByteArray) -> int:
	added_slots.clear()
	return RosterCodec.decode_meta(bytes, roster, added_slots)


## Applies a ROSTER_REMOVE packet; returns the entry count or -1 when malformed.
func on_remove(bytes: PackedByteArray) -> int:
	removed_slots.clear()
	return RosterCodec.decode_remove(bytes, roster, removed_slots)


## Holds a snapshot packet of server tick `snap_tick` that references roster indices not yet in the roster.
## `now_tick` is the local tick of arrival; the hold expires HOLD_TICKS later. At MAX_HELD the oldest is evicted
## and a request is forced at the next poll.
func hold(now_tick: int, snap_tick: int, bytes: PackedByteArray, missing: PackedInt32Array) -> void:
	if _snap_tick.size() >= MAX_HELD:
		_remove_at(0)
		_overflow = true
	var _a: bool = _snap_tick.append(snap_tick)
	_a = _arrival.append(now_tick)
	_bytes.append(bytes)
	_missing.append(missing)


## Moves every held record whose indices are now all in the roster to the outputs, oldest first. Returns the count.
func take_ready(out_ticks: PackedInt32Array, out_bytes: Array[PackedByteArray]) -> int:
	var n: int = 0
	var i: int = 0
	while i < _snap_tick.size():
		if _all_present(_missing[i]):
			var _a: bool = out_ticks.append(_snap_tick[i])
			out_bytes.append(_bytes[i])
			_remove_at(i)
			n += 1
		else:
			i += 1
	return n


## Drops records held >= HOLD_TICKS. Returns a REQUEST_KEYFRAME(ROSTER_GAP) packet when something expired and
## none was sent within REQUEST_MIN_TICKS; otherwise an empty array. At most one request per expiry batch.
func poll(now_tick: int) -> PackedByteArray:
	var expired: bool = _overflow
	_overflow = false
	var i: int = 0
	while i < _snap_tick.size():
		if now_tick - _arrival[i] >= HOLD_TICKS:
			_remove_at(i)
			expired = true
		else:
			i += 1
	if not expired or now_tick - _last_request < REQUEST_MIN_TICKS:
		return PackedByteArray()
	_last_request = now_tick
	requests_sent += 1
	return RosterCodec.encode_request_keyframe(Protocol.KeyframeRequest.ROSTER_GAP)


func _all_present(missing: PackedInt32Array) -> bool:
	for slot: int in missing:
		if not roster.has(slot):
			return false
	return true


func _remove_at(i: int) -> void:
	_snap_tick.remove_at(i)
	_arrival.remove_at(i)
	_bytes.remove_at(i)
	_missing.remove_at(i)
