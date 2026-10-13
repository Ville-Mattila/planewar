class_name InputBuffer extends RefCounted
## Server-side per-player jitter buffer for INPUT (04 s2.4, s5.1, V-INP; R0 C2-08). A 64-tick ring of wire-form
## inputs. `submit` validates a packet and files each input whose tick lies in [current - 2, current + 8];
## `take(tick)` yields the input the sim consumes: the stored one, else the previous input with stick axes
## halved per missing tick (thrust held, edge buttons dropped) for up to 10 ticks, then `bridge` (the LINK_BRIDGE
## overlay, Assist.link_bridge) is raised once and stays up until the next fresh input. The unit stays possessed.
## Epoch change (`begin_epoch`) clears everything and starts in bridge, because A's input is never replayed for B.

const RING: int = 64
const WINDOW_PAST: int = 2
const WINDOW_FUTURE: int = 8
const DECAY_TICKS: int = 10
const DECAY_FACTOR: float = 0.5
const KEEP_BUTTONS: int = PilotInput.BOOST | PilotInput.BRAKE
const STRIKE_EVERY: int = 100

var epoch: int = 0
var bridge: bool = true                     # LINK_BRIDGE overlay requested for the sim this tick
var miss_run: int = 0                       # consecutive ticks `take` found no input
var ack_tick: int = 0                       # newest snapshot tick the client reported seen
var accepted: int = 0
var duplicates: int = 0
var late: int = 0                           # accepted but behind the current tick (too late to fly)
var rejected_window: int = 0                # inputs outside [current - 2, current + 8]
var rejected_epoch: int = 0                 # packets from a stale possession
var rejected_malformed: int = 0
var bridge_raised: int = 0                  # rising edges of `bridge` after a silence (ALERT LINK_WEAK once each)
var strikes: int = 0                        # one per 100 bad packets (V-INP)
var current: PilotInput = PilotInput.new()  # result of the latest `take`; reused, copy before keeping
var _ticks: PackedInt32Array = PackedInt32Array()
var _bytes: PackedByteArray = PackedByteArray()
var _bad: int = 0
var _has_last: bool = false


func _init() -> void:
	var _e: Error = _ticks.resize(RING)
	_e = _bytes.resize(RING * PilotWire.BYTES)
	_clear()


func begin_epoch(new_epoch: int) -> void:
	epoch = new_epoch & 0xFFFF
	_clear()


## Files the inputs of one INPUT packet. Returns how many were stored, -1 when the packet is rejected whole.
func submit(packet: PackedByteArray, current_tick: int) -> int:
	if InputCodec.validate(packet) != InputCodec.Status.OK:
		rejected_malformed += 1
		_strike()
		return -1
	if InputCodec.epoch_of(packet) != epoch:
		rejected_epoch += 1
		_strike()
		return -1
	var base: int = InputCodec.base_tick_of(packet)
	var stored: int = 0
	for i: int in InputCodec.count_of(packet):
		stored += _file(packet, InputCodec.HEADER_BYTES + i * PilotWire.BYTES, base + i, current_tick)
	ack_tick = maxi(ack_tick, InputCodec.ack_tick_of(packet))
	return stored


## The input for `tick`. Call once per tick, ticks ascending. Sets `bridge` and returns `current`.
func take(tick: int) -> PilotInput:
	var slot: int = tick % RING
	if _ticks[slot] == tick:
		var _p: PilotInput = PilotWire.from_wire(_bytes, slot * PilotWire.BYTES, current)
		miss_run = 0
		bridge = false
		_has_last = true
		return current
	miss_run += 1
	if not _has_last:
		_neutral()
		bridge = true
		return current
	_decay()
	if miss_run > DECAY_TICKS:
		if not bridge:
			bridge_raised += 1
		bridge = true
	return current


func _file(packet: PackedByteArray, at: int, tick: int, current_tick: int) -> int:
	if tick < current_tick - WINDOW_PAST or tick > current_tick + WINDOW_FUTURE:
		rejected_window += 1
		return 0
	var slot: int = tick % RING
	if _ticks[slot] == tick:
		duplicates += 1
		return 0
	_ticks[slot] = tick
	for k: int in PilotWire.BYTES:
		_bytes[slot * PilotWire.BYTES + k] = packet[at + k]
	accepted += 1
	if tick < current_tick:
		late += 1
	return 1


func _decay() -> void:
	current.pitch *= DECAY_FACTOR
	current.yaw *= DECAY_FACTOR
	current.roll *= DECAY_FACTOR
	current.buttons &= KEEP_BUTTONS


func _neutral() -> void:
	current.thrust = 0.0
	current.pitch = 0.0
	current.yaw = 0.0
	current.roll = 0.0
	current.buttons = 0


func _strike() -> void:
	_bad += 1
	if _bad % STRIKE_EVERY == 0:
		strikes += 1


func _clear() -> void:
	_ticks.fill(-1)
	bridge = true
	miss_run = 0
	_has_last = false
	_neutral()
