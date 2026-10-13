class_name InputSender extends RefCounted
## Client side of INPUT (04 s2.4, s5.1): remembers the last three quantised inputs and builds one packet per
## send holding up to the 3 newest consecutive ticks, newest last, so a single or double lost packet loses nothing.
## A slow client that sends every other tick still covers every tick (count 3 spans 3 ticks).

var epoch: int = 0
var packets_built: int = 0
var _ring: Array[PilotInput] = [PilotInput.new(), PilotInput.new(), PilotInput.new()]
var _newest_tick: int = -1
var _held: int = 0
var _scratch: Array[PilotInput] = [null, null, null]


## Records the input for `tick` (ticks must be consecutive; a gap restarts the redundancy window). Returns the
## quantised input: apply it to local prediction.
func push(tick: int, input: PilotInput) -> PilotInput:
	if _newest_tick >= 0 and tick != _newest_tick + 1:
		_held = 0
	var slot: PilotInput = _ring[tick % 3]
	var _q: PilotInput = PilotWire.from_wire(PilotWire.to_wire(input, tick), 0, slot)
	_newest_tick = tick
	_held = mini(_held + 1, Protocol.INPUT_MAX_COUNT)
	return slot


func reset(new_epoch: int) -> void:
	epoch = new_epoch
	_held = 0
	_newest_tick = -1


func build(ack_tick: int) -> PackedByteArray:
	if _held == 0:
		return PackedByteArray()
	var base: int = _newest_tick - _held + 1
	for i: int in _held:
		_scratch[i] = _ring[(base + i) % 3]
	packets_built += 1
	return InputCodec.encode(epoch, base, ack_tick, _scratch, _held)
