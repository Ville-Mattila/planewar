class_name WingDef extends Def
## wing.json (08 SL-2 Form on Me, FEAT-01). Singleton file: the SL-2 data block as typed fields.

var max_wingmen: int = 0
var recruit_radius_m: float = 0.0
var min_fuel01: float = 0.0
var min_hp01: float = 0.0
var min_speed_ratio: float = 0.0
var recruit_states: PackedStringArray = PackedStringArray()
var armed_classes: PackedStringArray = PackedStringArray()
var slots_brf_m: Array = []  ## [[back, right, up], ...] metres in the leader frame (08 SL-2 rule 2)
var slot_tolerance_m: float = 0.0
var focus_timeout_s: float = 0.0
var focus_leash_m: float = 0.0
var break_radius_m: float = 0.0
var break_s: float = 0.0
var transfer_window_s: float = 0.0
var transfer_radius_m: float = 0.0

const SPEC: Dictionary = {
	"i": "max_wingmen",
	"f": "recruit_radius_m min_fuel01 min_hp01 min_speed_ratio slot_tolerance_m focus_timeout_s focus_leash_m break_radius_m break_s transfer_window_s transfer_radius_m",
	"a": "recruit_states armed_classes",
	"l": "slots_brf_m",
	"req": "max_wingmen recruit_radius_m min_fuel01 min_hp01 min_speed_ratio recruit_states armed_classes slots_brf_m slot_tolerance_m focus_timeout_s focus_leash_m break_radius_m break_s transfer_window_s transfer_radius_m",
}


static func from_dict(d: Dictionary) -> WingDef:
	var w: WingDef = WingDef.new()
	w._read_singleton(d, &"wing")
	w._fill(d, SPEC)
	return w
