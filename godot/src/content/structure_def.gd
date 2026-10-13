class_name StructureDef extends Def
## structures.json and towers.json entry (R0 B.1, 02 s5). Towers carry a `tower` block and the
## shield_projector a `shield` block; both stay Dictionaries (read once per match by the sim).

var hp: int = 0
var cost_ore: int = 0
var cost_ice: int = 0
var build_time_s: float = 0.0
var power: float = 0.0  ## signed
var requires: PackedStringArray = PackedStringArray()
var footprint: PackedInt32Array = PackedInt32Array()  ## [w, h] build cells
var build_radius: float = 0.0
var sensor_radius: float = 0.0
var deck_reveal_radius: float = 0.0
var storage_ore: int = 0
var storage_ice: int = 0
var construction_slots: int = 0
var pads: int = 0
var pad_radius_m: float = 0.0
var pad_roofed: bool = false
var max_per_player: int = 0  ## 0 = unlimited
var buildable: bool = true
var invulnerable: bool = false
var upgrade_from: StringName = &""
var upgrade_cost_ore: int = 0
var upgrade_time_s: float = 0.0
var possessable: bool = false
var on_node: StringName = &""
var buffer_ice: int = 0
var pipe_radius_m: float = 0.0
var docks: int = 0
var solar: bool = false
var explode: Dictionary = {}
var integrated_shield: Dictionary = {}
var shield: Dictionary = {}
var tower: Dictionary = {}  ## empty for non-towers

const SPEC: Dictionary = {
	"f": "build_time_s power build_radius sensor_radius deck_reveal_radius pad_radius_m upgrade_time_s pipe_radius_m",
	"i": "hp cost_ore cost_ice storage_ore storage_ice construction_slots pads max_per_player upgrade_cost_ore buffer_ice docks",
	"b": "pad_roofed buildable invulnerable possessable solar",
	"n": "upgrade_from on_node",
	"a": "requires",
	"p": "footprint",
	"d": "explode integrated_shield shield tower",
	"req": "hp cost_ore cost_ice build_time_s power requires footprint sensor_radius",
}


static func from_dict(d: Dictionary) -> StructureDef:
	var s: StructureDef = StructureDef.new()
	s._read_common(d)
	s._fill(d, SPEC)
	return s


func is_tower() -> bool:
	return not tower.is_empty()
