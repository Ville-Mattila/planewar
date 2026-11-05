class_name ScoreHits extends RefCounted
## The damage window behind the assist rule (02 s17.1: a player with >= `assist.min_share` of a victim's damage within the
## last `assist.window_s` seconds earns `assist.kill_share` of the kill value): a ring of the latest enemy hits as
## (victim EntityId, attacker owner, whether that attacker was possessed, tick, damage). Fixed capacity, oldest dropped;
## records older than the window are retired on each `record`. Part of S4.

const CAP: int = 4096
const _STATE: PackedStringArray = ["victim", "owner", "pilot", "tick", "dmg", "head", "count"]

var victim: PackedInt32Array = PackedInt32Array()
var owner: PackedByteArray = PackedByteArray()
var pilot: PackedByteArray = PackedByteArray()
var tick: PackedInt32Array = PackedInt32Array()
var dmg: PackedFloat32Array = PackedFloat32Array()
var head: int = 0      ## index of the oldest record
var count: int = 0


func _init() -> void:
	var e: int = victim.resize(CAP) | owner.resize(CAP) | pilot.resize(CAP) | tick.resize(CAP) | dmg.resize(CAP)
	assert(e == OK)
	victim.fill(0)
	owner.fill(0)
	pilot.fill(0)
	tick.fill(0)
	dmg.fill(0.0)


## Appends one hit at tick `t`; records older than `window_ticks` leave the ring first, a full ring drops its oldest.
func record(victim_id: int, by_owner: int, by_pilot: bool, amount: float, t: int, window_ticks: int) -> void:
	while count > 0 and t - tick[head] > window_ticks:
		head = (head + 1) % CAP
		count -= 1
	if count == CAP:
		head = (head + 1) % CAP
		count -= 1
	var at: int = (head + count) % CAP
	victim[at] = victim_id
	owner[at] = by_owner
	pilot[at] = 1 if by_pilot else 0
	tick[at] = t
	dmg[at] = amount
	count += 1


## Sums the damage `victim_id` took within `window_ticks` of `t` into `total[owner]` and `by_pilot[owner]` (both
## caller-sized to `PlayerTable.SLOTS` and zeroed here) and returns the grand total.
func shares(victim_id: int, t: int, window_ticks: int, total: PackedFloat32Array, by_pilot: PackedFloat32Array) -> float:
	total.fill(0.0)
	by_pilot.fill(0.0)
	var sum: float = 0.0
	for k: int in count:
		var i: int = (head + k) % CAP
		if victim[i] != victim_id or t - tick[i] > window_ticks:
			continue
		total[owner[i]] += dmg[i]
		if pilot[i] != 0:
			by_pilot[owner[i]] += dmg[i]
		sum += dmg[i]
	return sum


func write_state(buf: StreamPeerBuffer) -> void:
	StateIO.put_props(buf, self, _STATE)


func read_state(buf: StreamPeerBuffer) -> bool:
	if not StateIO.get_props(buf, self, _STATE) or not StateIO.sizes_ok(self, _STATE.slice(0, 5), CAP):
		return false
	return head >= 0 and head < CAP and count >= 0 and count <= CAP
