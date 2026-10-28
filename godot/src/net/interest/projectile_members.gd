class_name ProjectileMembers extends RefCounted
## The projectile entities in one InterestClient's roster (roster indices >= Roster.PROJECTILE_INDEX_MIN; R0 B.22 A-112),
## swept every tick before selection with no 30 s ghost. A member that died (absent from the frame, or its slot holds a
## new generation), left V, or went untiered for GHOST_TICKS is removed HOLD_TICKS after it first failed, so the
## reliable ROSTER_REMOVE trails the member's last snapshot record; once a member is dead (whatever failed first), its
## index is held (not listed, not admitted) for READMIT_TICKS from the death, which is also >= HOLD_TICKS after the
## REMOVE, so the REMOVE leads the next generation's ENTITY_META and first record. Both margins exceed the arrival
## spread of the 04 s15.1 presets (BAD: +-40 ms jitter): a recycled slot (0-tick quarantine, A-20) never reaches the
## client while its old entry, possibly of another team, could still parse it. 04 s4.1, R0 B.25 A-132.
## Allocation-free; packed members only.

## 04 s4.1 / R0 B.25 A-132: ROSTER_REMOVE follows a projectile's death or exit from V by 3 ticks (100 ms > the 80 ms
## BAD jitter spread; below the NET-05 1 s held-record timeout).
const HOLD_TICKS: int = 3
## 04 s4.1 / R0 B.25 A-132: a dead projectile's roster index is neither listed nor re-admitted for 6 ticks after the death.
const READMIT_TICKS: int = 2 * HOLD_TICKS
const NONE: int = -1

var count: int = 0
var _mem: PackedInt32Array = PackedInt32Array()
var _gone: PackedInt32Array = PackedInt32Array()     # by roster index: first failing tick of a pending removal, -1
var _died: PackedInt32Array = PackedInt32Array()     # by roster index: first tick the pending member was dead, -1


func _init() -> void:
	var e: int = _mem.resize(Roster.CAPACITY - Roster.PROJECTILE_INDEX_MIN) | _gone.resize(Roster.CAPACITY) | _died.resize(Roster.CAPACITY)
	assert(e == OK)
	reset()


func reset() -> void:
	count = 0
	_gone.fill(NONE)
	_died.fill(NONE)


func add(s: int) -> void:
	_mem[count] = s
	count += 1
	_gone[s] = NONE
	_died[s] = NONE


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
		if reason == Protocol.RosterRemoveReason.DEATH and _died[s] == NONE:   # whatever failed first (A-132)
			_died[s] = t
			hold[s] = maxi(hold[s], t + READMIT_TICKS)
		if reason == NONE or t - _gone[s] < HOLD_TICKS:
			_gone[s] = _gone[s] if reason != NONE else NONE   # NONE implies the same generation (a change is DEATH)
			_mem[m] = s
			m += 1
			continue
		_gone[s] = NONE
		_died[s] = NONE
		var _p: bool = out_s.push_back(s)
		var _q: bool = out_reason.push_back(reason)
	count = m
