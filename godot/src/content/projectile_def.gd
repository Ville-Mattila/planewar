class_name ProjectileDef extends Def
## projectiles.json entry (R0 B.1, 02 s4.2). Read by sim Kinematics.
## Resolved through ContentDB.projectile_index, never def_index (R0 B.8 A-1).

const BEHAVIOUR_STRAIGHT: StringName = &"straight"
const BEHAVIOUR_BALLISTIC: StringName = &"ballistic"
const BEHAVIOUR_GUIDED: StringName = &"guided"
const BEHAVIOUR_RENDEZVOUS: StringName = &"rendezvous"

var behaviour: StringName = &"straight"
var speed_mps: float = 0.0  ## 0 = carrier velocity
var eject_down_mps: float = 0.0
var lifetime_s: float = 0.0
var gravity: bool = false  ## falls under rules.gravity
var transport: bool = false  ## velocity parallel-transported (03 s5.4)
var radius_m: float = 0.0
var blast_radius_m: float = 0.0
var blast_radius_structure_m: float = 0.0
var fuse: StringName = &"contact"
var fuse_radius_m: float = 0.0
var arm_s: float = 0.0
var shield_absorbed: bool = false
var hp: int = 0  ## 0 = indestructible

const SPEC: Dictionary = {
	"f": "speed_mps eject_down_mps lifetime_s radius_m blast_radius_m blast_radius_structure_m fuse_radius_m arm_s",
	"i": "hp",
	"b": "gravity transport shield_absorbed",
	"n": "behaviour fuse",
	"req": "behaviour transport shield_absorbed hp",
}


static func from_dict(d: Dictionary) -> ProjectileDef:
	var p: ProjectileDef = ProjectileDef.new()
	p._read_common(d)
	p._fill(d, SPEC)
	return p
