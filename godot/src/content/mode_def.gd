class_name ModeDef extends Def
## modes.json entry (R0 B.1, 02 s14, field typing R0 B.8 A-4). JSON null becomes the sentinel noted per field.

const NONE_S: float = -1.0

var humans: PackedInt32Array = PackedInt32Array()  ## [min, max]
var teams: String = ""
var fill_after_s: float = NONE_S  ## NONE_S = null (host / per slot / mission)
var fill_rating_weight: float = 1.0  ## optional; omitted = 1.0
var doctrine_pick: StringName = &""
var adjutant: PackedStringArray = PackedStringArray()
var moving_sun: StringName = &"off"
var pause_save: bool = false
var caps: StringName = &"standard"  ## standard | reduced | lite | host
var rating: StringName = &"none"
var core_exposure_s: float = NONE_S  ## NONE_S = null (per mission)
var hard_end_s: float = NONE_S
var maps: StringName = &"rotation"
var hosting: PackedStringArray = PackedStringArray()

const SPEC: Dictionary = {
	"p": "humans",
	"s": "teams",
	"f": "fill_rating_weight",
	"n": "doctrine_pick moving_sun caps rating maps",
	"a": "adjutant hosting",
	"b": "pause_save",
	"extra": "fill_after_s core_exposure_s hard_end_s",
	"req": "humans teams fill_after_s doctrine_pick adjutant moving_sun pause_save caps rating core_exposure_s hard_end_s maps hosting",
}


static func from_dict(d: Dictionary) -> ModeDef:
	var m: ModeDef = ModeDef.new()
	m._read_common(d)
	m._fill(d, SPEC)
	m.fill_after_s = _num_or_none(d.get("fill_after_s"))
	m.core_exposure_s = _num_or_none(d.get("core_exposure_s"))
	m.hard_end_s = _num_or_none(d.get("hard_end_s"))
	return m


static func _num_or_none(v: Variant) -> float:
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		return Def.num(v)
	return NONE_S
