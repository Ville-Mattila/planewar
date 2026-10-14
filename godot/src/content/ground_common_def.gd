class_name GroundCommonDef extends RefCounted
## Top-level `ground_common` object of ground_units.json (A-63, R0 C2-09, C2-11), the ground twin of FlightCommonDef.
## Read by sim GroundMotion.

var ground_turn_rate_dps: float = 0.0       ## heading rate at full yaw stick
var ground_reverse_speed_mps: float = 0.0   ## reverse speed after BRAKE has been held
var ground_reverse_hold_s: float = 0.0      ## BRAKE hold that turns stop into reverse
var ground_slope_speed_loss: float = 0.0    ## speed x (1 - loss x slope_deg / max_slope_deg)
var raw: Dictionary = {}
var errors: Array[String] = []
var unknown: Array[String] = []

const KEYS: PackedStringArray = [
	"ground_turn_rate_dps", "ground_reverse_speed_mps", "ground_reverse_hold_s", "ground_slope_speed_loss",
]


static func from_dict(d: Dictionary) -> GroundCommonDef:
	var c: GroundCommonDef = GroundCommonDef.new()
	c.raw = d.duplicate(true)
	for key: String in KEYS:
		var v: Variant = d.get(key)
		if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
			c.errors.append("ground_common.%s missing or not a number" % key)
			continue
		c.set(key, Def.num(v))
	for k: Variant in d.keys():
		if not KEYS.has(str(k)):
			c.unknown.append(str(k))
	return c
