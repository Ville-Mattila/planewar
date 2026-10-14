class_name RulesDef extends Def
## rules.json: world constants only (R0 B.1). Read by sim Kinematics.

const LIFT_SPEED_SCALED: StringName = &"speed_scaled"
const LIFT_DAMPING_ONLY: StringName = &"damping_only"

var gravity: float = 0.0
var ceiling_soft_m: float = 0.0
var ceiling_hard_m: float = 0.0
var tick_hz: int = 0
var lift_model: StringName = LIFT_SPEED_SCALED
var path_expansions_per_tick: int = 0
var sim_budget_profile: PackedInt32Array = PackedInt32Array()
var friendly_fire: bool = false
var debug_commands: bool = false
var profile_enabled: bool = false
## R0 B.11 A-51 sim rule constants (ADR-09). Field defaults are the documented values the sim named consts carried
## before TA-49, so a hand-built RulesDef without them behaves as before; the shipped rules.json requires every one.
var command_rate_per_s: int = 10          ## 04 s11.3 token bucket refill, commands per second
var command_burst: int = 30               ## 04 s11.3 bucket depth, commands
var uplink_margin_m: int = 50             ## 05 C6: POSSESS refused at >= ceiling_hard_m - margin
var request_ttl_s: int = 10               ## 05 C10 / C17 hand-over request lifetime
var override_echo_s: int = 10             ## 05 s3.4 OVERRIDDEN echo window
var shooter_grace_ticks: int = 10         ## 03 s6.1 shooter skipped for this many ticks
var path_heuristic_pct: int = 25          ## 03 s3.6 A* heuristic inflation
var rung_1_think_period_ticks: int = 15   ## cut_ladder (03 s4.3), rung ordinal = sim_budget_profile entry
var rung_2_vision_hz: int = 5
var rung_3_projectile_cap: int = 1400
var rung_4_ship_pairs_tier_a_only: bool = true
var rung_5_tier_b_hz: int = 10
var rung_6_unit_cap: int = 60
var rung_8_path_expansions_per_tick: int = 60

const SPEC: Dictionary = {
	"f": "gravity ceiling_soft_m ceiling_hard_m",
	"i": "tick_hz path_expansions_per_tick command_rate_per_s command_burst uplink_margin_m request_ttl_s override_echo_s shooter_grace_ticks path_heuristic_pct",
	"n": "lift_model",
	"p": "sim_budget_profile",
	"b": "friendly_fire debug_commands profile_enabled",
	"extra": "cut_ladder",
	"req": "gravity ceiling_soft_m ceiling_hard_m tick_hz lift_model path_expansions_per_tick sim_budget_profile friendly_fire debug_commands profile_enabled",
}


const CUT_LADDER_SPEC: Dictionary = {
	"i": "rung_1_think_period_ticks rung_2_vision_hz rung_3_projectile_cap rung_5_tier_b_hz rung_6_unit_cap rung_8_path_expansions_per_tick",
	"b": "rung_4_ship_pairs_tier_a_only",
}


static func from_dict(d: Dictionary) -> RulesDef:
	var r: RulesDef = RulesDef.new()
	r._read_singleton(d, &"rules")
	r._fill(d, SPEC)
	var ladder: Variant = d.get("cut_ladder")
	if typeof(ladder) == TYPE_DICTIONARY:
		var lad: Dictionary = ladder
		r._fill(lad, CUT_LADDER_SPEC)
	return r
