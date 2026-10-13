class_name WeaponDef extends Def
## weapons.json entry (R0 B.1, 02 s4.1, B.8 A-2/A-3). `projectile` is a projectile id: resolve it with
## ContentDB.projectile_index (A-1).

var kind: StringName = &"gun"  ## gun | bomb | rocket | flak | rail | artillery
var weapon_mount: StringName = &"ship"  ## ship | tower | ground
var projectile: StringName = &""
var damage_min: int = 0
var damage_max: int = 0
var structure_mult: float = 1.0
var ground_mult: float = 1.0
var rof: float = 0.0
var burst: int = 0
var burst_interval_s: float = 0.0
var salvo: int = 0
var reload_s: float = 0.0
var range_m: float = 0.0
var range_min_m: float = 0.0
var spread_deg: float = 0.0
var lock_cone_deg: float = 0.0
var lock_time_s: float = 0.0
var turn_rate_dps: float = 0.0
var rearm_ice: int = 0
var ammo_per_shot: int = 1

const SPEC: Dictionary = {
	"f": "structure_mult ground_mult rof burst_interval_s reload_s range_m range_min_m spread_deg lock_cone_deg lock_time_s turn_rate_dps",
	"i": "damage_min damage_max burst salvo rearm_ice ammo_per_shot",
	"n": "kind weapon_mount projectile",
	"req": "kind weapon_mount projectile damage_min damage_max rearm_ice ammo_per_shot",
}


static func from_dict(d: Dictionary) -> WeaponDef:
	var w: WeaponDef = WeaponDef.new()
	w._read_common(d)
	w._fill(d, SPEC)
	return w
