class_name EventRouter extends RefCounted
## Server side of EVENTS (04 s3.6, R0 C2-03): turns the tick's `SimWorld.drain_events()` into one reliable EVENTS
## packet stream per client. A kind's scope decides who receives it; entity references in the payload are roster
## indices and become 0xFFFF for any entity the client's roster does not hold (so an enemy outside vision never
## appears in any event). Field use per kind (the `SimEvent` convention the sim emits, see events/MODULE.md): `a`, `b`
## EntityIds or small ints, `value` damage / ore / ratio / severity, `team`, `extra` bytes. Scratch buffers are
## members: nothing is allocated per event except the finished packets.

enum Scope { ROSTER, TEAM, ALL, CELL, TEAM_ROSTER, LOCK, POSSESSOR, NEVER }
enum Src { ZERO, REF_A, REF_B, RAW_A, RAW_B, X0, X1, X2, X3, X4, VALUE, VALUE255, TEAM, POS, XU16, OWNER_A }

const SCOPES: PackedInt32Array = [
	Scope.ROSTER, Scope.ROSTER, Scope.ROSTER, Scope.CELL, Scope.ROSTER, Scope.TEAM, Scope.ROSTER, Scope.TEAM,
	Scope.TEAM, Scope.ROSTER, Scope.ROSTER, Scope.TEAM, Scope.TEAM, Scope.TEAM_ROSTER, Scope.TEAM, Scope.TEAM,
	Scope.ALL, Scope.NEVER, Scope.TEAM, Scope.ROSTER, Scope.ROSTER, Scope.TEAM, Scope.TEAM, Scope.ALL,
	Scope.LOCK, Scope.LOCK, Scope.ROSTER, Scope.ALL, Scope.TEAM, Scope.TEAM_ROSTER, Scope.ROSTER, Scope.POSSESSOR,
	Scope.TEAM, Scope.TEAM,
]
## Field sources per kind, same stride and order as `EventCodec.SCHEMA`.
const SOURCES: PackedInt32Array = [
	Src.REF_A, Src.RAW_B, Src.OWNER_A, 0, 0, 0, 0, 0,                       # 0 SPAWN
	Src.REF_A, Src.REF_B, Src.X0, 0, 0, 0, 0, 0,                            # 1 DEATH (cause)
	Src.REF_A, Src.REF_B, Src.X1, Src.VALUE, Src.X0, 0, 0, 0,               # 2 HIT (part x0, seed x1, damage value)
	Src.POS, Src.RAW_B, Src.RAW_A, 0, 0, 0, 0, 0,                           # 3 BOMB_IMPACT (a = owner, b = def)
	Src.REF_A, Src.REF_B, 0, 0, 0, 0, 0, 0,                                 # 4 DOCKED
	Src.REF_A, Src.REF_B, Src.X0, 0, 0, 0, 0, 0,                            # 5 SERVICED
	Src.REF_A, Src.REF_B, 0, 0, 0, 0, 0, 0,                                 # 6 LAUNCHED
	Src.REF_A, Src.RAW_B, 0, 0, 0, 0, 0, 0,                                 # 7 ORDER_DONE
	Src.REF_A, Src.RAW_B, Src.X0, 0, 0, 0, 0, 0,                            # 8 ORDER_FAILED
	Src.REF_A, Src.RAW_B, 0, 0, 0, 0, 0, 0,                                 # 9 POSSESSED
	Src.REF_A, Src.RAW_B, Src.X0, 0, 0, 0, 0, 0,                            # 10 RELEASED
	Src.REF_A, Src.RAW_B, Src.X0, 0, 0, 0, 0, 0,                            # 11 BUILD_STARTED (player x0)
	Src.REF_A, Src.RAW_B, 0, 0, 0, 0, 0, 0,                                 # 12 BUILD_DONE
	Src.REF_A, Src.XU16, Src.REF_B, 0, 0, 0, 0, 0,                          # 13 STRUCTURE_LOST (def x0-x1)
	Src.TEAM, Src.VALUE255, 0, 0, 0, 0, 0, 0,                               # 14 LOW_POWER
	Src.RAW_A, Src.REF_B, Src.POS, Src.VALUE, 0, 0, 0, 0,                   # 15 ALERT
	Src.TEAM, 0, 0, 0, 0, 0, 0, 0,                                          # 16 CORE_EXPOSURE
	0, 0, 0, 0, 0, 0, 0, 0,                                                 # 17 MATCH_END
	Src.RAW_A, Src.RAW_B, 0, 0, 0, 0, 0, 0,                                 # 18 CAP_REACHED
	Src.REF_A, Src.RAW_B, Src.VALUE, 0, 0, 0, 0, 0,                         # 19 WRECK_SPAWNED
	Src.REF_A, Src.REF_B, Src.VALUE, 0, 0, 0, 0, 0,                         # 20 WRECK_SALVAGED
	Src.REF_A, Src.RAW_B, 0, 0, 0, 0, 0, 0,                                 # 21 CEILING_RELEASE
	Src.REF_A, Src.RAW_B, Src.X0, 0, 0, 0, 0, 0,                            # 22 HANDOVER (to x0)
	Src.RAW_A, Src.RAW_B, 0, 0, 0, 0, 0, 0,                                 # 23 PLAYER_ELIMINATED
	Src.REF_A, Src.REF_B, 0, 0, 0, 0, 0, 0,                                 # 24 LOCK_ACQUIRED
	Src.REF_A, Src.REF_B, 0, 0, 0, 0, 0, 0,                                 # 25 LOCK_BROKEN
	Src.REF_A, Src.RAW_B, Src.VALUE255, 0, 0, 0, 0, 0,                      # 26 CAPTURE_PROGRESS
	Src.REF_A, Src.RAW_B, 0, 0, 0, 0, 0, 0,                                 # 27 CAPTURED
	Src.REF_A, Src.REF_B, Src.VALUE, 0, 0, 0, 0, 0,                         # 28 SALVAGE_DELIVERED
	Src.REF_A, Src.REF_B, Src.X0, Src.X1, Src.X2, Src.X3, Src.X4, 0,        # 29 LANDING
	Src.REF_A, 0, 0, 0, 0, 0, 0, 0,                                         # 30 SHIELD_COLLAPSE
	Src.REF_A, Src.RAW_B, 0, 0, 0, 0, 0, 0,                                 # 31 POSSESS_REQUESTED
	Src.REF_A, Src.RAW_B, 0, 0, 0, 0, 0, 0,                                 # 32 CANISTER_DEPLOYED
	Src.REF_A, Src.REF_B, 0, 0, 0, 0, 0, 0,                                 # 33 CANISTER_COLLECTED
]

var packets_made: int = 0
var events_sent: int = 0
var events_dropped: int = 0                 # events no audience wanted (counted per audience x event)
var _buf: PackedByteArray = PackedByteArray()
var _v: PackedInt32Array = PackedInt32Array()
var _pos_q: int = 0
var _shots: ShotRouter = ShotRouter.new()


func _init() -> void:
	var _r: Error = _buf.resize(Protocol.MAX_UNRELIABLE_BYTES)
	var _s: int = _v.resize(EventCodec.ROW)


## Routes `events` (one tick, sim order) to every audience: EVENTS packets are appended to `aud.outbox` in order.
func route(tick: int, events: Array[SimEvent], audiences: Array[EventAudience]) -> void:
	for aud: EventAudience in audiences:
		var at: int = EventCodec.write_header(_buf, tick)
		for e: SimEvent in events:
			if not _fill(e, aud):
				events_dropped += 1
				continue
			var next: int = EventCodec.write_event(_buf, at, e.kind, _v, _pos_q)
			if next < 0 or _buf[5] == EventCodec.COUNT_MAX:
				at = _flush(aud, at, tick)
				next = EventCodec.write_event(_buf, at, e.kind, _v, _pos_q)
			at = next
			_buf[5] += 1
			events_sent += 1
		var _f: int = _flush(aud, at, tick)


## Routes this tick's shots (see ShotRouter) into `aud.shot_out`.
func route_shots(tick: int, shots: ShotBuffer, audiences: Array[EventAudience]) -> void:
	for aud: EventAudience in audiences:
		_shots.route(tick, shots, aud)


## Applies scope and fills `_v` / `_pos_q`; false when `aud` should not receive `e`.
func _fill(e: SimEvent, aud: EventAudience) -> bool:
	var k: int = e.kind
	if k < 0 or k >= EventCodec.KIND_COUNT or not EventCodec.is_valid_kind(k):
		return false
	if not _in_scope(e, aud):
		return false
	var n: int = EventCodec.field_count(k)
	for i: int in n:
		_v[i] = _source(e, aud, SOURCES[k * EventCodec.ROW + i])
	_pos_q = Codec.quantize_pos(e.pos) if k == SimEvent.Kind.BOMB_IMPACT or k == SimEvent.Kind.ALERT else 0
	return true


func _in_scope(e: SimEvent, aud: EventAudience) -> bool:
	if aud.unfiltered:
		return true
	match SCOPES[e.kind]:
		Scope.ROSTER:
			return _known(e.a, aud)
		Scope.TEAM:
			if e.team < 0 and e.kind == SimEvent.Kind.CAP_REACHED:
				return aud.player == e.a
			return e.team >= 0 and e.team == aud.team
		Scope.ALL:
			return true
		Scope.CELL:
			return aud.sees_cell(Codec.pos_cell(Codec.quantize_pos(e.pos)))
		Scope.TEAM_ROSTER:
			return (e.team >= 0 and e.team == aud.team) or _known(e.a, aud)
		Scope.LOCK:
			return (e.team >= 0 and e.team == aud.team) or (aud.possessed_slot >= 0 and aud.possessed_slot == EntityId.slot(e.b))
		Scope.POSSESSOR:
			return aud.possessed_slot >= 0 and aud.possessed_slot == EntityId.slot(e.a)
	return false


func _source(e: SimEvent, aud: EventAudience, src: int) -> int:
	match src:
		Src.REF_A:
			return ref_of(e.a, aud)
		Src.REF_B:
			return ref_of(e.b, aud)
		Src.RAW_A:
			return e.a & 0xFFFF
		Src.RAW_B:
			return e.b & 0xFFFF
		Src.X0, Src.X1, Src.X2, Src.X3, Src.X4:
			var i: int = src - Src.X0
			return e.extra[i] if i < e.extra.size() else 0
		Src.VALUE:
			return clampi(roundi(e.value), 0, 0xFFFF)
		Src.VALUE255:
			return clampi(roundi(e.value * 255.0), 0, 255)
		Src.TEAM:
			return e.team & 0xFF
		Src.XU16:
			return (e.extra[0] | (e.extra[1] << 8)) if e.extra.size() >= 2 else 0
		Src.OWNER_A:
			var s: int = EntityId.slot(e.a)
			return aud.roster.owner_of(s) if aud.roster.has(s) else 0xFF
	return 0


## Roster index of `id` for `aud`, or 0xFFFF when the entity is not in its roster (stale generation included).
## Unfiltered audiences get the slot whenever it fits the 1,536-entry index space (wrecks included, A-54).
static func ref_of(id: int, aud: EventAudience) -> int:
	if id <= 0:
		return EventCodec.NONE_REF
	var s: int = EntityId.slot(id)
	if aud.unfiltered:
		return s if s < Roster.CAPACITY else EventCodec.NONE_REF
	if aud.roster.has(s) and aud.roster.generation_of(s) == EntityId.gen(id):
		return s
	return EventCodec.NONE_REF


static func _known(id: int, aud: EventAudience) -> bool:
	return ref_of(id, aud) != EventCodec.NONE_REF


func _flush(aud: EventAudience, at: int, tick: int) -> int:
	if _buf[5] > 0:
		aud.outbox.append(_buf.slice(0, at))
		packets_made += 1
	return EventCodec.write_header(_buf, tick)
