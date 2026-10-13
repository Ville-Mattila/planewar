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

const SPEC: Dictionary = {
	"f": "gravity ceiling_soft_m ceiling_hard_m",
	"i": "tick_hz path_expansions_per_tick",
	"n": "lift_model",
	"p": "sim_budget_profile",
	"b": "friendly_fire debug_commands profile_enabled",
	"req": "gravity ceiling_soft_m ceiling_hard_m tick_hz lift_model path_expansions_per_tick sim_budget_profile friendly_fire debug_commands profile_enabled",
}


static func from_dict(d: Dictionary) -> RulesDef:
	var r: RulesDef = RulesDef.new()
	r._read_singleton(d, &"rules")
	r._fill(d, SPEC)
	return r
