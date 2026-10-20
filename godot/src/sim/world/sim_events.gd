class_name SimEvents extends RefCounted
## The event array of one `SimWorld` (03 s3.5, tick-order step 12). `SimWorld.step()` sets `tick` before step 1, so
## every emitted event carries the tick of the step that produced it (S5 by construction). No signals (D2).

const MIN_RECORD_BYTES: int = 45   ## kind 1, tick / a / b / team 16, pos 12, value 8 (double), extra var >= 8
const MAX_PENDING: int = 1 << 20   ## a saved queue claiming more is refused

var list: Array[SimEvent] = []
var tick: int = 0
var pending: Array[SimEvent] = []   ## drained events waiting for the AI hook's next step 3 (A-71); part of the saved state (S4)


## Appends one event stamped with `tick`; `reason` >= 0 goes into `extra[0]` (ReleaseReason, death cause).
func emit(kind: SimEvent.Kind, a: int, b: int, at: Vector3, value: float, team: int, reason: int = -1) -> SimEvent:
	var e: SimEvent = SimEvent.new()
	e.kind = kind
	e.tick = tick
	e.a = a
	e.b = b
	e.pos = at
	e.value = value
	e.team = team
	if reason >= 0:
		e.extra = PackedByteArray([reason & 0xFF])
	list.append(e)
	return e


## Returns the events since the last drain and empties the list. `keep`: also queue them for `forward` (an AI hook is attached).
func drain(keep: bool = false) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	out.assign(list)
	list.clear()
	if keep:
		pending.append_array(out)
	return out


## Step 3 (A-71): hands the queued drained events to `hook.on_event` once each, in emission order, and empties the queue.
func forward(hook: SimAiHook) -> void:
	for e: SimEvent in pending:
		hook.on_event(e)
	pending.clear()


func write_pending(buf: StreamPeerBuffer) -> void:
	buf.put_32(pending.size())
	for e: SimEvent in pending:
		buf.put_u8(e.kind)
		buf.put_32(e.tick)
		buf.put_32(e.a)
		buf.put_32(e.b)
		buf.put_float(e.pos.x)
		buf.put_float(e.pos.y)
		buf.put_float(e.pos.z)
		buf.put_double(e.value)
		buf.put_32(e.team)
		buf.put_var(e.extra)


## False for a malformed queue (count, kind or extra out of range); `pending` is only replaced when it parses.
func read_pending(buf: StreamPeerBuffer) -> bool:
	var n: int = buf.get_32()
	if n < 0 or n > MAX_PENDING:
		return false
	var out: Array[SimEvent] = []
	for _i: int in n:
		if buf.get_available_bytes() < MIN_RECORD_BYTES:
			return false
		var e: SimEvent = SimEvent.new()
		var k: int = buf.get_u8()
		if k >= SimEvent.Kind.size():
			return false
		e.kind = k as SimEvent.Kind
		e.tick = buf.get_32()
		e.a = buf.get_32()
		e.b = buf.get_32()
		e.pos = Vector3(buf.get_float(), buf.get_float(), buf.get_float())
		e.value = buf.get_double()
		e.team = buf.get_32()
		var xv: Variant = buf.get_var()
		if typeof(xv) != TYPE_PACKED_BYTE_ARRAY:
			return false
		e.extra = xv
		out.append(e)
	if not (out.is_empty() and pending.is_empty()):
		pending = out
	return true
