class_name ScoringDef extends Def
## scoring.json (R0 B.1, 02 s17.1 with the 08 SL-1 landing block). Singleton file. Nested tables stay
## Dictionaries: kill_points (unit id -> points), assist, landing, relay.

var kill_points: Dictionary = {}
var kill_hauler_loaded_bonus: int = 0
var structure_destroyed_ratio: float = 0.0
var core_destroyed: int = 0
var structure_damage_points_per_hp: float = 0.0
var assist: Dictionary = {}
var landing: Dictionary = {}
var salvage_points_per_ore: float = 0.0
var ice_possessed_points_per_ice: float = 0.0
var relay: Dictionary = {}
var commander_points_per_ore_spent: float = 0.0
var commander_auto_kill_share: float = 0.0
var match_win: int = 0

const SPEC: Dictionary = {
	"d": "kill_points assist landing relay",
	"i": "kill_hauler_loaded_bonus core_destroyed match_win",
	"f": "structure_destroyed_ratio structure_damage_points_per_hp salvage_points_per_ore ice_possessed_points_per_ice commander_points_per_ore_spent commander_auto_kill_share",
	"req": "kill_points kill_hauler_loaded_bonus structure_destroyed_ratio core_destroyed assist landing match_win",
}


static func from_dict(d: Dictionary) -> ScoringDef:
	var s: ScoringDef = ScoringDef.new()
	s._read_singleton(d, &"scoring")
	s._fill(d, SPEC)
	return s
