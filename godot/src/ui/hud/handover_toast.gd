class_name HandoverToast extends RefCounted
## The hand-over request toast (docs/06 s7.6, 01 s4.4, UX-19): a teammate asks for the unit the local player pilots;
## shown hud.json `toast_s` (8 s). Accept builds the HANDOVER Command; the host submits it through ClientSession.

var entity: int = 0
var requester: int = -1
var requester_name: String = ""
var left_s: float = 0.0


## Opens on POSSESS_REQUESTED (a = entity, b = requesting slot) when the local player pilots `a`; closes when the entity
## is released or handed over. Returns whether the event changed the toast.
func on_event(e: SimEvent, v: SimView, local_slot: int, names: Dictionary) -> bool:
	match e.kind:
		SimEvent.Kind.POSSESS_REQUESTED:
			if not v.alive(e.a) or v.possessor(e.a) != local_slot:
				return false
			entity = e.a
			requester = e.b
			requester_name = PilotedBadges.name_of(e.b, names)
			left_s = HudMath.param("toast_s")
			return true
		SimEvent.Kind.RELEASED, SimEvent.Kind.HANDOVER:
			if active() and e.a == entity:
				dismiss()
				return true
	return false


func tick(dt: float) -> void:
	if left_s > 0.0:
		left_s = maxf(left_s - dt, 0.0)


func active() -> bool:
	return left_s > 0.0 and entity != 0


func dismiss() -> void:
	left_s = 0.0


## HANDOVER of the entity to the requester (payload u8 slot, as ControlMachine reads it); null when no toast is open.
func accept(local_slot: int) -> Command:
	if not active():
		return null
	var c: Command = Command.new()
	c.player = local_slot
	c.kind = Command.Kind.HANDOVER
	c.target = entity
	c.payload = PackedByteArray([requester & 0xFF])
	dismiss()
	return c


func text() -> String:
	return tr(&"hud.toast.request").format({"name": requester_name})
