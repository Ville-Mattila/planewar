class_name FormationParams extends RefCounted
## Numbers of separation and formation keeping (05 s5.4, s5.6): the autopilot def's `separation` block, a `formation`
## block and the SL-2 `wing.json` slots. Slots are stored as (right, forward, up) offsets in metres; the wing file's
## (back, right, up) is converted on load. No numeric defaults live here (ADR-09): build it with `from_dict`.
## **Needs content (AI-19):** `autopilots.json` gains `separation.push_mps` and a `formation` block with
## `FORM_KEYS` (fixture `test/sim/ai/ai11_params.json` carries the 05 values until then).

const SEP_KEYS: PackedStringArray = ["radius_m", "gain", "push_mps", "lookahead_s", "lookahead_miss_m", "lookahead_lag_s", "lookahead_eff", "lookahead_min_s", "lookahead_max_mps", "lookahead_brake", "query_radius_m"]
const FORM_KEYS: PackedStringArray = ["class_slots_m", "k_form", "speed_cap_mult", "engage_radius_m", "rejoin_radius_m",
	"break_utility", "max_break_frac", "slot_scan_m", "min_heading_speed_mps"]

var sep_radius_m: float = 0.0          ## neighbours inside this radius push
var sep_gain: float = 0.0
var sep_push_mps: float = 0.0          ## velocity added at distance 0 (05 s5.4: 20 m/s)
var look_s: float = 0.0                ## AI-11 look-ahead: converging pairs whose closest approach is within this time
var look_miss_m: float = 0.0           ## ... and passes closer than this are pushed apart before the proximity ring is reached
var look_lag_s: float = 0.0            ## controller lag: the deficit is closed in the time left after this
var look_eff: float = 0.0            ## lateral displacement gained per m/s of push per second after the lag (flight model: 0.7-1.0)
var look_min_s: float = 0.0            ## floor of that time
var look_max_mps: float = 0.0          ## cap of the look-ahead push
var look_brake: float = 0.0            ## share of the closing speed shed by a ship whose neighbour is ahead
var query_radius_m: float = 0.0        ## neighbour query radius (<= the collision hash's ring2, 208 m, to stay cheap)
var class_slots: PackedVector3Array = PackedVector3Array()   ## (right, forward, up) in the escortee's tangent frame
var wing_slots: PackedVector3Array = PackedVector3Array()    ## (right, forward, up) in the leader's body frame (SL-2)
var k_form: float = 0.0                ## 1/s: slot error to velocity
var speed_cap_mult: float = 0.0        ## escort speed cap = ShipDef.v_cruise x this
var engage_radius_m: float = 0.0       ## FORM: threats within this of the escortee may pull an escort out
var rejoin_radius_m: float = 0.0       ## FORM: an engaging escort farther than this from the escortee rejoins
var break_utility: float = 0.0         ## a threat must exceed this utility to break formation
var max_break_frac: float = 0.0        ## at most this share of the escorts (at least one) engage at once
var slot_scan_m: int = 0               ## neighbourhood of the escortee scanned for free slots
var min_heading_speed: float = 0.0     ## below this escortee speed the nose is the formation forward
var wing_tolerance_m: float = 0.0      ## SL-2 slot tolerance
var focus_timeout_s: float = 0.0       ## SL-2 FOCUS: attack the focus target this long, then FORM
var focus_leash_m: float = 0.0
var break_radius_m: float = 0.0        ## SL-2 BREAK: engage freely within this of the escortee
var break_s: float = 0.0
var ceiling_m: float = 0.0             ## wingmen never follow above rules.ceiling_soft_m


static func from_dict(sep: Dictionary, form: Dictionary, wing: WingDef, ceiling_soft_m: float) -> FormationParams:
	for k: String in SEP_KEYS:
		if not _is_num(sep.get(k)):
			return null
	for k: String in FORM_KEYS:
		if not form.has(k) or (k != "class_slots_m" and not _is_num(form[k])):
			return null
	var p: FormationParams = FormationParams.new()
	p.sep_radius_m = _f(sep, "radius_m")
	p.sep_gain = _f(sep, "gain")
	p.sep_push_mps = _f(sep, "push_mps")
	p.look_s = _f(sep, "lookahead_s")
	p.look_miss_m = _f(sep, "lookahead_miss_m")
	p.look_lag_s = _f(sep, "lookahead_lag_s")
	p.look_eff = _f(sep, "lookahead_eff")
	p.look_min_s = _f(sep, "lookahead_min_s")
	p.look_max_mps = _f(sep, "lookahead_max_mps")
	p.look_brake = _f(sep, "lookahead_brake")
	p.query_radius_m = _f(sep, "query_radius_m")
	p.k_form = _f(form, "k_form")
	p.speed_cap_mult = _f(form, "speed_cap_mult")
	p.engage_radius_m = _f(form, "engage_radius_m")
	p.rejoin_radius_m = _f(form, "rejoin_radius_m")
	p.break_utility = _f(form, "break_utility")
	p.max_break_frac = _f(form, "max_break_frac")
	p.slot_scan_m = roundi(_f(form, "slot_scan_m"))
	p.min_heading_speed = _f(form, "min_heading_speed_mps")
	p.ceiling_m = ceiling_soft_m
	if typeof(form["class_slots_m"]) != TYPE_ARRAY:
		return null
	var cs: Array = form["class_slots_m"]
	if cs.is_empty() or cs.size() >= AiState.NO_SLOT:
		return null
	for row: Variant in cs:
		if typeof(row) != TYPE_ARRAY:
			return null
		var r: Array = row
		if r.size() != 3:
			return null
		var _b: bool = p.class_slots.push_back(Vector3(_v(r[0]), _v(r[1]), _v(r[2])))
	if wing != null:
		for row: Variant in wing.slots_brf_m:
			var r: Array = row
			var _b: bool = p.wing_slots.push_back(Vector3(_v(r[1]), -_v(r[0]), _v(r[2])))   # (back, right, up) -> (right, fwd, up)
		p.wing_tolerance_m = wing.slot_tolerance_m
		p.focus_timeout_s = wing.focus_timeout_s
		p.focus_leash_m = wing.focus_leash_m
		p.break_radius_m = wing.break_radius_m
		p.break_s = wing.break_s
	return p


## Slots of the class table (`wing` false) or the SL-2 table.
func slot_count(wing: bool) -> int:
	return wing_slots.size() if wing else class_slots.size()


static func _is_num(x: Variant) -> bool:
	return x is float or x is int


static func _v(x: Variant) -> float:
	var f: float = x if _is_num(x) else 0.0
	return f


static func _f(d: Dictionary, k: String) -> float:
	return _v(d[k])
