class_name ScoutParams extends RefCounted
## The Scout brain's own numbers (05 s6.4, AI-14), read-only, beside its DartParams. From `ap_scout`: `flee_radius_m`
## (1,000; 05 s4.4) and the `search` block (`agl_m` 500: the search altitude; `flee_s` 6 and `flee_clear_m` 1,800: FLEE
## ends after this long or once the threat is this far); `rtb.fuel_reserve_s` bounds the fuel radius of the cell
## choice (out to the cell and back home at cruise). `armed_by_def` marks the ship defs with a weapon (the "armed enemy"
## of the flee rule). **Needs content (AI-19):** the fixture `test/sim/ai/ai14_autopilots.json` carries the keys.

const KEYS: PackedStringArray = ["flee_radius_m"]
const SEARCH_KEYS: PackedStringArray = ["agl_m", "flee_s", "flee_clear_m"]

var flee_radius: float = 0.0
var search_agl: float = 0.0
var flee_ticks: int = 0
var flee_clear: float = 0.0
var fuel_reserve_s: float = 0.0
var fuel_s: float = 0.0          ## ShipDef.fuel_s
var armed_by_def: PackedByteArray = PackedByteArray()   ## by def id: 1 = a ship def with a primary or secondary weapon


## Null on a missing key (ADR-09: no defaults).
static func from_content(ap: Dictionary, def: ShipDef, c: ContentSet) -> ScoutParams:
	var sb: Dictionary = DartParams.block(ap, "search")
	var rtb: Dictionary = DartParams.block(ap, "rtb")
	for k: String in KEYS:
		if not (ap.get(k) is float or ap.get(k) is int):
			return null
	for k: String in SEARCH_KEYS:
		if not (sb.get(k) is float or sb.get(k) is int):
			return null
	if not (rtb.get("fuel_reserve_s") is float or rtb.get("fuel_reserve_s") is int) or c.rules == null:
		return null
	var p: ScoutParams = ScoutParams.new()
	p.flee_radius = TargetParams.num(ap, "flee_radius_m", 0.0)
	p.search_agl = TargetParams.num(sb, "agl_m", 0.0)
	p.flee_ticks = maxi(1, roundi(TargetParams.num(sb, "flee_s", 0.0) * float(c.rules.tick_hz)))
	p.flee_clear = TargetParams.num(sb, "flee_clear_m", 0.0)
	p.fuel_reserve_s = TargetParams.num(rtb, "fuel_reserve_s", 0.0)
	p.fuel_s = def.fuel_s
	var _r: int = p.armed_by_def.resize(DefRanges.END)
	p.armed_by_def.fill(0)
	for sd: ShipDef in c.ships:
		var d: int = c.entity_index.get(sd.id, -1)
		if d >= 0 and d < DefRanges.END and (sd.primary_weapon != &"" or sd.secondary_weapon != &""):
			p.armed_by_def[d] = 1
	return p
