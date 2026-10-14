class_name SimEvents extends RefCounted
## The event array of one `SimWorld` (03 s3.5, tick-order step 12). `SimWorld.step()` sets `tick` before step 1, so
## every emitted event carries the tick of the step that produced it (S5 by construction). No signals (D2).

var list: Array[SimEvent] = []
var tick: int = 0


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


## Returns the events since the last drain and empties the list.
func drain() -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	out.assign(list)
	list.clear()
	return out
