class_name RollingRefresh extends RefCounted
## Rolling tier-C refresh (04 s4.3, R0 C1-15): every tick, FULL records for ceil(C_count / 300) entities of the
## client's C set, chosen round-robin by roster index, so every C entity is refreshed within 300 ticks with no periodic
## keyframe and no burst. The caller passes the result to SnapshotCodec.encode(..., refresh): FULLs in section C on the
## unreliable channel (a lost record is refreshed on the next cycle). An entity refreshed less than 5 s (150 ticks) ago is
## skipped, which only matters below 150 C entities; a skipped entry still uses its slot, so the worst interval stays
## under 300 ticks (2 x C_count <= 298). One instance per client; scratch is preallocated, nothing allocates per entity.

const PERIOD_TICKS: int = 300
const MIN_REFRESH_TICKS: int = 150
const NEVER: int = -1000000

var picked: int = 0                         # cumulative entities returned
var skipped: int = 0                        # cumulative entries passed over because they were refreshed < 5 s ago
var _last: PackedInt32Array = PackedInt32Array()   # by roster index: tick of the last FULL sent, NEVER = none
var _cursor: int = -1                       # roster index of the last entry visited


func _init() -> void:
	var _r: int = _last.resize(Roster.CAPACITY)
	_last.fill(NEVER)


## FULL records per tick for a C set of `c_count` entities: ceil(c_count / 300).
static func per_tick(c_count: int) -> int:
	return 0 if c_count <= 0 else MathX.floori_div(c_count + PERIOD_TICKS - 1, PERIOD_TICKS)


## The entries of `c` (ascending roster indices, the client's C set) to send as FULL this tick, into `out` (cleared).
## Returns out.size(). Visits per_tick(c.size()) consecutive entries after the cursor, wrapping.
func pick(c: PackedInt32Array, tick: int, out: PackedInt32Array) -> int:
	out.clear()
	var n: int = c.size()
	if n == 0:
		return 0
	var p: int = _first_after(c, n)
	for j: int in per_tick(n):
		var s: int = c[(p + j) % n]
		_cursor = s
		if s < 0 or s >= Roster.CAPACITY:
			continue
		if tick - _last[s] < MIN_REFRESH_TICKS:
			skipped += 1
			continue
		_last[s] = tick
		var _ok: bool = out.push_back(s)
		picked += 1
	return out.size()


## FULLs sent by other means (a KEYFRAME) count as refreshed at `tick`.
func note_full(indices: PackedInt32Array, tick: int) -> void:
	for s: int in indices:
		if s >= 0 and s < Roster.CAPACITY:
			_last[s] = tick


func reset() -> void:
	_last.fill(NEVER)
	_cursor = -1
	picked = 0
	skipped = 0


## Position in `c` of the first entry above the cursor (binary search); 0 when there is none.
func _first_after(c: PackedInt32Array, n: int) -> int:
	var lo: int = 0
	var hi: int = n
	while lo < hi:
		var mid: int = (lo + hi) >> 1
		if c[mid] <= _cursor:
			lo = mid + 1
		else:
			hi = mid
	return lo if lo < n else 0
