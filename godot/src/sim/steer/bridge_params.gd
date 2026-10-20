class_name BridgeParams extends RefCounted
## Parameter struct of `Assist.link_bridge` and of the SAFETY law the `sim_ai` overlays share with it (05 s2.4,
## AI-08): the class's `FlightGains`, its `ProbeParams`, the pull-up threshold `safety_pull_up_tti_s`, and the ship
## def and world rules the trim feed-forward reads (`Assist.trim_lead`, `Kinematics.k_up_effective`). One
## instance per ship class, read-only. Built from the class's autopilot def (`ShipDef.autopilot` -> `autopilots.json`
## entry) so the server's step 4 and the client's prediction read the same numbers (ADR-09: no defaults here).

## Top-level autopilot keys `from_autopilot` requires (besides the `flight` block, FlightGains.KEYS).
const KEYS: PackedStringArray = ["min_clearance_m", "clearance_per_mps", "probe_times_s", "lift_max_frac",
	"lift_min_time_s", "safety_pull_up_tti_s"]

var gains: FlightGains = null
var probe: ProbeParams = null
var pull_up_tti_s: float = 0.0      ## LINK_BRIDGE / SAFETY pull up below this time to impact (05 s2.4: 2.0 s)
var ship: ShipDef = null            ## the base (not doctrine-resolved) class def: rates, lift law constants
var rules: RulesDef = null          ## gravity, lift_model


## From one autopilot def dictionary (`AutopilotDef.raw`), the ship class, the world constants and flight_common.
## Null when a key is missing or not a number (a broken def is a load error, not a default), or a def is null.
static func from_autopilot(ap: Dictionary, def: ShipDef, rules_def: RulesDef, tick_hz: int,
		flight_common: FlightCommonDef) -> BridgeParams:
	if def == null or rules_def == null or not (ap.get("flight") is Dictionary) or not (ap.get("probe_times_s") is Array):
		return null
	for k: String in KEYS:
		if k != "probe_times_s" and not (ap.get(k) is float or ap.get(k) is int):
			return null
	var flight: Dictionary = ap["flight"]
	var g: FlightGains = FlightGains.from_dict(flight, def, tick_hz, rules_def, flight_common)
	if g == null:
		return null
	var times: PackedFloat32Array = PackedFloat32Array()
	var listed: Array = ap["probe_times_s"]
	for x: Variant in listed:
		if not (x is float or x is int):
			return null
		var _b: bool = times.push_back(_as_float(x))
	if times.is_empty():
		return null
	var r: BridgeParams = BridgeParams.new()
	r.gains = g
	r.probe = ProbeParams.make(_as_float(ap["min_clearance_m"]), _as_float(ap["clearance_per_mps"]), times, rules_def.gravity,
		_as_float(ap["lift_max_frac"]), _as_float(ap["lift_min_time_s"]))
	r.pull_up_tti_s = _as_float(ap["safety_pull_up_tti_s"])
	r.ship = def
	r.rules = rules_def
	return r


## One entry per `content.ships` (the local ship index, `def_id - DefRanges.SHIP_BASE`), null where the class has no
## complete autopilot def. Built once per match (SimWorld) or per session (client prediction).
static func table(content: ContentSet, rules_def: RulesDef, tick_hz: int) -> Array[BridgeParams]:
	var out: Array[BridgeParams] = []
	for sd: ShipDef in content.ships:
		out.append(from_autopilot(autopilot_raw(content, sd.autopilot), sd, rules_def, tick_hz, content.flight_common))
	return out


## The raw dictionary of autopilot def `id`, empty when absent.
static func autopilot_raw(content: ContentSet, id: StringName) -> Dictionary:
	for a: AutopilotDef in content.autopilots:
		if a.id == id:
			return a.raw
	return {}


static func _as_float(x: Variant) -> float:
	if x is int:
		var i: int = x
		return float(i)
	var f: float = x
	return f
