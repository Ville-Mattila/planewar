class_name PerceptionParams extends RefCounted
## One observer's information profile (05 s7.8 "Information" and "Cadence: reaction_delay_s"; AI-22), read from a
## `bot_profiles.json` entry by its R0 B.1 field names: `vision` (`own` | `team`), `ghost_memory_s`, `reaction_delay_s`
## (which mirrors the tier's `bot_promises.json` `reaction_s`, R0 C2-13). The AI driver's team intel uses the same
## shape (05 s6: the autopilots' shared map; vision `team`, no delay). Difficulty can only reduce information
## (05 s7.1 rule 2): `own` keeps fewer contacts than `team`, a delay only postpones them.

const KEYS: PackedStringArray = ["vision", "ghost_memory_s", "reaction_delay_s"]

var own_vision: bool = false      ## `vision` == "own": only contacts the observer's own slot's sensors cover
var memory_ticks: int = 0         ## ghost_memory_s: a ghost is forgotten this long after its last sight
var delay_ticks: int = 0          ## reaction_delay_s: a new contact becomes usable this long after its first sight


## Null on a missing key or a `vision` other than own / team.
static func from_dict(d: Dictionary, tick_hz: int) -> PerceptionParams:
	for k: String in KEYS:
		if not d.has(k):
			return null
	var v: String = str(d["vision"])
	if v != "own" and v != "team":
		return null
	var p: PerceptionParams = PerceptionParams.new()
	p.own_vision = v == "own"
	p.memory_ticks = roundi(TargetParams.num(d, "ghost_memory_s", 0.0) * float(tick_hz))
	p.delay_ticks = roundi(TargetParams.num(d, "reaction_delay_s", 0.0) * float(tick_hz))
	return p
