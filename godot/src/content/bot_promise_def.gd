class_name BotPromiseDef extends Def
## bot_promises.json entry (R0 B.1, 02 s15, typing R0 B.8 A-4). Ranges are [lo, hi] Arrays with null for an
## open end (null stays null inside the Array); an absent range is the empty Array; poles_by_s null = -1.0.

var audience_key: String = ""
var first_dart_s: Array = []
var first_outpost_s: float = 0.0
var first_attack_s: Array = []
var raid_targets: PackedStringArray = PackedStringArray()
var bombers_from_s: float = 0.0
var uses_shields: StringName = &"no"  ## no | rarely | yes
var uses_rail_lance: StringName = &"no"
var poles_by_s: float = -1.0  ## -1 = never
var command_rate_cap: int = 0
var think_s: float = 0.0
var reaction_s: float = 0.0
var win_vs_lower: Array = []
var human_target_key: String = ""

const SPEC: Dictionary = {
	"s": "audience_key human_target_key",
	"l": "first_dart_s first_attack_s win_vs_lower",
	"f": "first_outpost_s bombers_from_s think_s reaction_s",
	"a": "raid_targets",
	"n": "uses_shields uses_rail_lance",
	"i": "command_rate_cap",
	"extra": "poles_by_s",
	"req": "audience_key first_dart_s first_outpost_s first_attack_s raid_targets bombers_from_s uses_shields uses_rail_lance poles_by_s command_rate_cap think_s reaction_s win_vs_lower human_target_key",
}


static func from_dict(d: Dictionary) -> BotPromiseDef:
	var b: BotPromiseDef = BotPromiseDef.new()
	b._read_common(d)
	b._fill(d, SPEC)
	b.poles_by_s = ModeDef._num_or_none(d.get("poles_by_s"))
	return b
