class_name ProjectileMembers extends RefCounted
## The projectile entities in one InterestClient's roster (roster indices >= Roster.PROJECTILE_INDEX_MIN; R0 B.22 A-112),
## swept every tick before selection with no 30 s ghost. A member that died (absent from the frame, or its slot holds a
## new generation), left V, or went untiered for GHOST_TICKS is removed HOLD_TICKS after it first failed, so the
## reliable ROSTER_REMOVE trails the member's last snapshot record; once a member is dead (whatever failed first), its
## index is held (not listed, not admitted) until HOLD_TICKS after that REMOVE, so the REMOVE also leads the next
## generation's ENTITY_META and first record. Both margins exceed the arrival spread of the 04 s15.1 presets (BAD: +-40 ms jitter): a recycled slot (0-tick
## quarantine, A-20) never reaches the client while its old entry, possibly of another team, could still parse it.
## Allocation-free; packed members only.

const HOLD_TICKS: int = 3                   # NET-58 (not in 04): 100 ms > the 80 ms BAD jitter spread
const NONE: int = -1

var count: int = 0
var _mem: PackedInt32Array = PackedInt32Array()
var _gone: PackedInt32Array = PackedInt32Array()     # by roster index: first failing tick of a pending removal, -1


func _init() -> void:
	var e: int = _mem.resize(Roster.CAPACITY - Roster.PROJECTILE_INDEX_MIN) | _gone.resize(Roster.CAPACITY)
	assert(e == OK)
	reset()


func reset() -> void:
	count = 0
	_gone.fill(NONE)


func add(s: int) -> void:
	_mem[count] = s
	count += 1
	_gone[s] = NONE


## One sweep at tick `t` for the client's visible team `vt` (-1 spectator): appends the removals to `out_s` /
## `out_reason` (Protocol.RosterRemoveReason), writes `hold` (by index: first tick the index may be listed again) and
## drops a newly failing member from `c_set` (the rolling-refresh pool). `rgen` / `last_tier` are the client's arrays.
func sweep(it: Interest, t: int, vt: int, rgen: PackedInt32Array, last_tier: PackedInt32Array, hold: PackedInt32Array,
		c_set: PackedInt32Array, out_s: PackedInt32Array, out_reason: PackedInt32Array) -> void:
	var m: int = 0
	for i: int in count:
		var s: int = _mem[i]
		var reason: int = NONE
		if it.stamp[s] != t or it.gen[s] != rgen[s]:
			reason = Protocol.RosterRemoveReason.DEATH
		elif not it.visible(s, vt):
			reason = Protocol.RosterRemoveReason.OUT_OF_VISION
		elif t - last_tier[s] >= InterestClient.GHOST_TICKS:
			reason = Protocol.RosterRemoveReason.LEFT_INTEREST
		if reason != NONE and _gone[s] == NONE:
			_gone[s] = t
			var at: int = c_set.bsearch(s)
			if at < c_set.size() and c_set[at] == s:
				c_set.remove_at(at)
		if reason == Protocol.RosterRemoveReason.DEATH:  # whatever failed first: held until HOLD_TICKS after the REMOVE
			hold[s] = maxi(hold[s], maxi(_gone[s] + HOLD_TICKS, t) + HOLD_TICKS)
		if reason == NONE or t - _gone[s] < HOLD_TICKS:
			_gone[s] = _gone[s] if reason != NONE else NONE   # NONE implies the same generation (a change is DEATH)
			_mem[m] = s
			m += 1
			continue
		_gone[s] = NONE
		var _p: bool = out_s.push_back(s)
		var _q: bool = out_reason.push_back(reason)
	count = m
