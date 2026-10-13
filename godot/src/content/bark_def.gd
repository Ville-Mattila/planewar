class_name BarkDef extends Def
## One entry of barks.json (08 SL-3 rule 3, FEAT-01). Text lives in the locale CSV domain `barks` (R0 C2-33).

var source: StringName = &""  ## derivation key, e.g. LAUNCHED, RTB_FUEL, ALERT_STRUCTURE_LOST (08 SL-3 table)
var scope: PackedStringArray = PackedStringArray()  ## SELF, WING, NEAR, ALERT
var priority: int = 0
var cooldown_s: float = 0.0

const SPEC: Dictionary = {
	"n": "source",
	"a": "scope",
	"i": "priority",
	"f": "cooldown_s",
	"req": "source scope priority cooldown_s",
}


static func from_dict(d: Dictionary) -> BarkDef:
	var b: BarkDef = BarkDef.new()
	b._read_common(d)
	b._fill(d, SPEC)
	return b
