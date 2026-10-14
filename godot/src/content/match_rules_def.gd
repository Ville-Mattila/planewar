class_name MatchRulesDef extends Def
## match_rules.json (R0 B.1, 02 s12.1) incl. the caps profiles (B.7, A-8). Singleton file.

var victory: StringName = &"all_enemy_cores"
var eliminate_on_core_loss: bool = true
var eliminated_selfdestruct_s: float = 0.0
var core_value: int = 0
var core_shield_until_s: float = 0.0
var core_bomb_mult_exposure: float = 1.0
var surrender_min_s: float = 0.0
var surrender_min_s_1v1: float = 0.0
var reconnect_grace_s: float = 0.0
var spectator_delay_ticks: int = 0
var spectators_max: int = 0
var join_window_s: float = 0.0
var load_timeout_s: float = 0.0
var countdown_s: float = 0.0
var arc_open_divisor: int = 6    ## R0 B.11 A-51: 01 s3.3 arc bands as divisors of core_exposure_s (Open ends at /6)
var arc_expand_divisor: int = 2  ## Expand ends at /2; Siege to the exposure, Overtime after
var caps: Dictionary = {}  ## StringName profile id -> CapsDef

const SPEC: Dictionary = {
	"f": "eliminated_selfdestruct_s core_shield_until_s core_bomb_mult_exposure surrender_min_s surrender_min_s_1v1 reconnect_grace_s join_window_s load_timeout_s countdown_s",
	"i": "core_value spectator_delay_ticks spectators_max arc_open_divisor arc_expand_divisor",
	"b": "eliminate_on_core_loss",
	"n": "victory",
	"extra": "caps",
	"req": "victory eliminate_on_core_loss core_value core_shield_until_s surrender_min_s caps",
}


static func from_dict(d: Dictionary) -> MatchRulesDef:
	var m: MatchRulesDef = MatchRulesDef.new()
	m._read_singleton(d, &"match_rules")
	m._fill(d, SPEC)
	var c: Variant = d.get("caps")
	if typeof(c) == TYPE_DICTIONARY:
		var cd: Dictionary = c
		for k: Variant in cd.keys():
			var profile: StringName = StringName(str(k))
			var body: Variant = cd[k]
			if typeof(body) == TYPE_DICTIONARY:
				var bd: Dictionary = body
				m.caps[profile] = CapsDef.from_dict(profile, bd)
	for needed: StringName in [&"standard", &"reduced", &"lite"]:
		if not m.caps.has(needed):
			m.errors.append("caps profile '%s' missing" % needed)
	return m
