class_name LocalPipe extends RefCounted
## One direction of a LocalTransport link (04 s6.2, s15.1): the impairment pipeline and the pending queue.
## Reliable-ordered channels are delayed, never lost, and delivered in send order; unreliable channels may be
## lost, duplicated and reordered; unreliable-sequenced channels drop anything older than the newest delivered.

const REORDER_RELEASE_MS: float = 200.0
const RELIABLE_RETRY_MS: float = 33.4

class _Pkt extends RefCounted:
	var channel: int = 0
	var seq: int = 0
	var at: float = 0.0
	var bytes: PackedByteArray = PackedByteArray()

var model: FaultModel = null
var sent_unreliable: int = 0
var dropped_unreliable: int = 0
var stale_dropped: int = 0
var _rng: Rng = null
var _clock: LocalClock = null
var _pending: Array[_Pkt] = []
var _due: Array[_Pkt] = []
var _held: _Pkt = null
var _held_since: float = 0.0
var _seq: int = 0
var _chan_last_at: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _chan_newest_seq: PackedInt64Array = PackedInt64Array([-1, -1, -1, -1])
var _busy_until: float = 0.0


func _init(clock: LocalClock) -> void:
	_clock = clock


func configure(m: FaultModel, stream: StringName) -> void:
	model = m
	_rng = Rng.new(m.seed_value).fork(stream) if m != null else null


func pending_count() -> int:
	return _pending.size() + (1 if _held != null else 0)


func push(channel: int, bytes: PackedByteArray) -> void:
	var reliable: bool = Protocol.CHANNEL_MODE[channel] == Protocol.ChannelMode.RELIABLE_ORDERED
	var now: float = _clock.now_ms()
	if not reliable:
		sent_unreliable += 1
	var p: _Pkt = _Pkt.new()
	p.channel = channel
	p.bytes = bytes
	p.seq = _seq
	_seq += 1
	p.at = now
	if model != null and not _impair(p, reliable, now):
		dropped_unreliable += 1
		return
	if reliable:
		p.at = maxf(p.at, _chan_last_at[channel])
		_chan_last_at[channel] = p.at
	if p != _held:
		_pending.append(p)


## Applies the model to `p`; false when the packet is lost.
func _impair(p: _Pkt, reliable: bool, now: float) -> bool:
	var burst_end: int = model.burst_end_tick(_clock.tick())
	if not reliable:
		if burst_end >= 0 or (model.loss > 0.0 and _rng.next_float() < model.loss):
			return false
	var at: float = now + model.latency_ms
	if model.jitter_ms > 0.0:
		at += _rng.range_f(-model.jitter_ms, model.jitter_ms)
	at = maxf(at, now)
	if model.bandwidth_kbps > 0.0:
		var start: float = maxf(now, _busy_until)
		if not reliable and start - now > FaultModel.QUEUE_CAP_MS:
			return false
		_busy_until = start + float(p.bytes.size()) * 8.0 / model.bandwidth_kbps
		at = maxf(at, _busy_until + model.latency_ms)
	if reliable and burst_end >= 0:
		at = maxf(at, FaultModel.tick_to_ms(burst_end) + model.latency_ms + RELIABLE_RETRY_MS)
	p.at = model.stall_adjust(now, at)
	if not reliable:
		_unreliable_extras(p, now)
	return true


func _unreliable_extras(p: _Pkt, now: float) -> void:
	if model.duplicate > 0.0 and _rng.next_float() < model.duplicate:
		var d: _Pkt = _Pkt.new()
		d.channel = p.channel
		d.bytes = p.bytes
		d.seq = p.seq
		d.at = p.at + _rng.range_f(0.0, maxf(model.jitter_ms, 20.0))
		_pending.append(d)
	if _held != null:
		_held.at = p.at + 0.001
		_pending.append(_held)
		_held = null
	elif model.reorder > 0.0 and _rng.next_float() < model.reorder:
		_held = p
		_held_since = now
		p.at = INF


## Appends every packet due by now to the outputs, in delivery order.
func collect(out_channels: PackedInt32Array, out_bytes: Array[PackedByteArray]) -> void:
	var now: float = _clock.now_ms()
	if _held != null and now >= _held_since + REORDER_RELEASE_MS:
		_held.at = now
		_pending.append(_held)
		_held = null
	if _pending.is_empty():
		return
	_due.clear()
	var keep: Array[_Pkt] = []
	for p: _Pkt in _pending:
		if p.at <= now:
			_due.append(p)
		else:
			keep.append(p)
	_pending = keep
	_due.sort_custom(_before)
	for p: _Pkt in _due:
		if Protocol.CHANNEL_MODE[p.channel] == Protocol.ChannelMode.UNRELIABLE_SEQUENCED:
			if p.seq <= _chan_newest_seq[p.channel]:
				stale_dropped += 1
				continue
			_chan_newest_seq[p.channel] = p.seq
		var _a: bool = out_channels.append(p.channel)
		out_bytes.append(p.bytes)


static func _before(a: _Pkt, b: _Pkt) -> bool:
	if a.at != b.at:
		return a.at < b.at
	return a.seq < b.seq
