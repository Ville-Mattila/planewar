class_name FaultModel extends RefCounted
## Deterministic link impairment for LocalTransport (04 s15.1). One model is applied per direction; every random
## draw comes from an Rng forked from `seed_value`, so a fixed seed reproduces the identical delivery order.
## Ticks are 30 Hz sim ticks of the LocalClock. Reliable channels emulate ENet: delayed, never lost.

enum Preset { LAN, GOOD, TARGET, BAD, MOBILE_SWITCH, TAB_STALL }       # append-only

const TICK_HZ: int = 30
const QUEUE_CAP_MS: float = 250.0           # bandwidth limiter: unreliable packets queued longer than this are dropped
const MOBILE_SWITCH_TICK: int = 900
const MOBILE_SWITCH_TICKS: int = 120        # 4 s
const TAB_STALL_TICK: int = 1200
const TAB_STALL_MS: float = 45000.0

var seed_value: int = 1                 # 04 names this `seed`; renamed, `seed` is a GDScript global function
var latency_ms: float = 0.0             # one-way base delay
var jitter_ms: float = 0.0              # uniform +- jitter
var loss: float = 0.0                   # 0..1 per packet, unreliable channels only
var reorder: float = 0.0                # probability that an unreliable packet is delivered after the next one
var duplicate: float = 0.0              # probability of a duplicate delivery (unreliable channels)
var bandwidth_kbps: float = 0.0         # 0 = unlimited; else serialisation delay, queue, then drop
var burst_loss: Array[Vector2i] = []    # [from_tick, to_tick) windows of 100 % loss (reliable: held until the end)
var _stall_start_ms: PackedFloat64Array = PackedFloat64Array()
var _stall_end_ms: PackedFloat64Array = PackedFloat64Array()


## Emulates a background tab: from `tick`, nothing moves on the link for `ms`; everything held is released at the end.
func stall_at(tick: int, ms: float) -> void:
	var start: float = tick_to_ms(tick)
	var _a: bool = _stall_start_ms.append(start)
	_a = _stall_end_ms.append(start + ms)


static func tick_to_ms(tick: int) -> float:
	return float(tick) * 1000.0 / float(TICK_HZ)


func in_burst(tick: int) -> bool:
	return burst_end_tick(tick) >= 0


## End tick (exclusive) of the burst window containing `tick`, or -1.
func burst_end_tick(tick: int) -> int:
	for w: Vector2i in burst_loss:
		if tick >= w.x and tick < w.y:
			return w.y
	return -1


## Moves `at_ms` to the end of any stall window that holds the send time or the arrival time.
func stall_adjust(send_ms: float, at_ms: float) -> float:
	var at: float = at_ms
	for i: int in _stall_start_ms.size():
		var s: float = _stall_start_ms[i]
		var e: float = _stall_end_ms[i]
		if (send_ms >= s and send_ms < e) or (at >= s and at < e):
			at = maxf(at, e)
	return at


func has_stall() -> bool:
	return not _stall_start_ms.is_empty()


static func preset(which: Preset, seed_arg: int = 1) -> FaultModel:
	var m: FaultModel = FaultModel.new()
	m.seed_value = seed_arg
	match which:
		Preset.LAN:
			pass
		Preset.GOOD:
			_fill(m, 40.0, 5.0, 0.005, 0.0, 0.0)
		Preset.TARGET:
			_fill(m, 100.0, 15.0, 0.03, 0.01, 0.0)
		Preset.BAD:
			_fill(m, 250.0, 40.0, 0.05, 0.02, 0.005)
		Preset.MOBILE_SWITCH:
			_fill(m, 100.0, 15.0, 0.03, 0.01, 0.0)
			m.burst_loss.append(Vector2i(MOBILE_SWITCH_TICK, MOBILE_SWITCH_TICK + MOBILE_SWITCH_TICKS))
		Preset.TAB_STALL:
			_fill(m, 40.0, 5.0, 0.005, 0.0, 0.0)
			m.stall_at(TAB_STALL_TICK, TAB_STALL_MS)
	return m


static func _fill(m: FaultModel, lat: float, jit: float, los: float, reo: float, dup: float) -> void:
	m.latency_ms = lat
	m.jitter_ms = jit
	m.loss = los
	m.reorder = reo
	m.duplicate = dup
