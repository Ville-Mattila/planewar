class_name AiHitLog extends RefCounted
## The last HIT each AI-registered entity landed (AI-17, 05 s6.8): by attacker slot the tick, the victim, the victim's
## team and where it was hit. The tower choice point reads it for "attacking a friendly structure within 600 m" (x1.5)
## and the GUARD order's attackers of the guarded thing (x2). `AiDriver.on_event` writes it (HIT, b = attacker); it is
## AI state, so it is in the S4 bytes of `AiState` (FORMAT 7) and a restored run scores the same targets. Arrays are
## indexed by entity slot and preallocated; `NO_TEAM` = no hit recorded.

const NO_TEAM: int = 255
const RECORD_BYTES: int = 21

var tick: PackedInt32Array = PackedInt32Array()
var victim: PackedInt32Array = PackedInt32Array()
var team: PackedByteArray = PackedByteArray()
var pos: PackedVector3Array = PackedVector3Array()


func resize(slots: int) -> void:
	var _r: Array[int] = [tick.resize(slots), victim.resize(slots), team.resize(slots), pos.resize(slots)]


func clear(s: int) -> void:
	tick[s] = 0
	victim[s] = 0
	team[s] = NO_TEAM
	pos[s] = Vector3.ZERO


## Attacker slot `s` hit `victim_id` of team `victim_team` at `at` on `hit_tick`.
func record(s: int, hit_tick: int, victim_id: int, victim_team: int, at: Vector3) -> void:
	tick[s] = hit_tick
	victim[s] = victim_id
	team[s] = victim_team if victim_team >= 0 and victim_team < NO_TEAM else NO_TEAM
	pos[s] = at


## True when attacker slot `s` hit an asset of `of_team` within the last `window` ticks, inside `r2` (squared) of `near`.
func attacking(s: int, of_team: int, now: int, window: int, near: Vector3, r2: float) -> bool:
	return team[s] == of_team and tick[s] + window > now and pos[s].distance_squared_to(near) <= r2


## True when attacker slot `s` hit `guarded` within the last `window` ticks.
func guarding(s: int, guarded: int, now: int, window: int) -> bool:
	return victim[s] == guarded and tick[s] + window > now and team[s] != NO_TEAM


func write(b: StreamPeerBuffer, s: int) -> void:
	b.put_32(tick[s])
	b.put_32(victim[s])
	b.put_u8(team[s])
	b.put_float(pos[s].x)
	b.put_float(pos[s].y)
	b.put_float(pos[s].z)


func read(b: StreamPeerBuffer, s: int) -> void:
	tick[s] = b.get_32()
	victim[s] = b.get_32()
	team[s] = b.get_u8()
	var x: float = b.get_float()
	var y: float = b.get_float()
	pos[s] = Vector3(x, y, b.get_float())
