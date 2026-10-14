class_name EventRig extends RefCounted
## Test helper (NET-10): a roster of own-team entities (slots 1-20, generation 1, team 0, owner 2), an enemy block
## (slots 30-39, team 1) that is NOT in the roster, one audience for player 2 possessing slot 5, and event builders.

const OWN_FIRST: int = 1
const OWN_LAST: int = 20
const ENEMY_FIRST: int = 30
const ENEMY_LAST: int = 39

var roster: Roster = Roster.new()
var aud: EventAudience = null
var cell: int = 0
var site: Vector3 = Vector3.ZERO


func _init() -> void:
	for s: int in range(OWN_FIRST, OWN_LAST + 1):
		var _ok: bool = roster.add(s, 1, 100 + s, 2, 0, "")
	aud = EventAudience.new(roster)
	aud.team = 0
	aud.player = 2
	aud.possessed_slot = 5
	site = Codec.cell_centre(10)
	cell = Codec.pos_cell(Codec.quantize_pos(site))
	aud.set_cells(PackedInt32Array([cell]))


static func id(slot: int, gen: int = 1) -> int:
	return EntityId.make(slot, gen)


static func ev(kind: SimEvent.Kind, a: int, b: int, value: float = 0.0, team: int = 0,
		extra: PackedByteArray = PackedByteArray(), pos: Vector3 = Vector3.ZERO) -> SimEvent:
	var e: SimEvent = SimEvent.new()
	e.kind = kind
	e.tick = 7
	e.a = a
	e.b = b
	e.value = value
	e.team = team
	e.extra = extra
	e.pos = pos
	return e


## Routes `events` for tick 7 to `audience`, decodes the outbox and returns the WireEvents in order.
static func roundtrip(events: Array[SimEvent], audience: EventAudience) -> Array[WireEvent]:
	var router: EventRouter = EventRouter.new()
	var auds: Array[EventAudience] = [audience]
	router.route(7, events, auds)
	var out: Array[WireEvent] = []
	for p: PackedByteArray in audience.outbox:
		var _n: int = EventCodec.decode(p, out)
	audience.outbox.clear()
	return out
