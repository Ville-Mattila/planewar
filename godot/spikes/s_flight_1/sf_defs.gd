class_name SfDefs extends RefCounted
## S-FLIGHT-1 def loader. Game values come from the real def files under the R0 B.1 names, through content's
## `*Def` types (TA-45): `rules.json` and `structures.json` from res://content/defs, and
## `ships.json`, `projectiles.json`, `weapons.json` from res://content/defs once GD-02 lands them, else from the
## schema-validated canonical fixture copies in this folder. Spike-only knobs live in defs/spike_flight.json.

const CONTENT_DIR: String = "res://content/defs/"
const SPIKE_DIR: String = "res://spikes/s_flight_1/defs/"

var rules: RulesDef
var common: FlightCommonDef
var ship: ShipDef                 # the flown ship (arena.ship, the Dart)
var ships: Dictionary[StringName, ShipDef] = {}
var slug: ProjectileDef
var bomb: ProjectileDef
var pad_radius_m: float
# gun_dart (weapons.json)
var gun_rof: float
var gun_damage_min: float
var gun_damage_max: float
var gun_spread_deg: float
var gun_range_m: float
var gun_structure_mult: float
var gun_ammo: int
# bomb weapon (weapons.json) and the ship's secondary count (ships.json)
var bomb_rof: float
var bomb_damage: float
var bomb_count: int
var blast_radius_m: float
var blast_radius_structure_m: float
var hp_max: float
var refuel_time_s: float
var rearm_time_s: float
var repair_time_s: float
# spike_flight.json blocks
var arena: Dictionary = {}
var targets: Dictionary = {}
var landing: Dictionary = {}
var approach: Dictionary = {}
var assist: Dictionary = {}
var input: Dictionary = {}
var camera: Dictionary = {}
var render: Dictionary = {}
var telemetry: Dictionary = {}
var harness: Dictionary = {}
var sources: PackedStringArray = PackedStringArray()   # which file each def came from (REPORT, telemetry)


static func load_all() -> SfDefs:
	var d: SfDefs = SfDefs.new()
	d._load()
	return d


static func arr(block: Dictionary, key: String) -> Array:
	var v: Array = block[key]
	return v


static func dict(block: Dictionary, key: String) -> Dictionary:
	var v: Dictionary = block[key]
	return v


static func num(block: Dictionary, key: String) -> float:
	assert(block.has(key), "spike_flight.json: missing " + key)
	var v: float = block[key]
	return v


func dt() -> float:
	return 1.0 / float(rules.tick_hz)


## Ship ids available for the flight test (Dart flown; Bomber for the hover check).
func ship_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for k: StringName in ships:
		var _a: bool = out.push_back(str(k))
	return out


func _load() -> void:
	var spike: Dictionary = _json(SPIKE_DIR + "spike_flight.json")
	arena = spike["arena"]
	targets = spike["targets"]
	landing = spike["landing"]
	approach = spike["approach"]
	assist = spike["assist"]
	input = spike["input"]
	camera = spike["camera"]
	render = spike["render"]
	telemetry = spike["telemetry"]
	harness = spike["harness"]
	rules = RulesDef.from_dict(_json(_pick("rules.json")))
	var ships_doc: Dictionary = _json(_pick("ships.json"))
	common = FlightCommonDef.from_dict(SfDefs.dict(ships_doc, "flight_common"))
	var ship_id: StringName = StringName(str(arena["ship"]))
	var ship_entry: Dictionary = {}
	for e: Variant in SfDefs.arr(ships_doc, "ships"):
		var sd: Dictionary = e
		var sid: StringName = StringName(str(sd["id"]))
		if sid == &"dart" or sid == &"bomber":
			ships[sid] = ShipDef.from_dict(sd)
		if sid == ship_id:
			ship_entry = sd
	ship = ships[ship_id]
	hp_max = num(ship_entry, "hp")
	refuel_time_s = num(ship_entry, "refuel_time_s")
	rearm_time_s = num(ship_entry, "rearm_time_s")
	repair_time_s = num(ship_entry, "repair_time_s")
	var primary: Dictionary = ship_entry["primary"]
	var secondary: Dictionary = ship_entry["secondary"]
	gun_ammo = roundi(num(primary, "ammo"))
	bomb_count = roundi(num(secondary, "count"))
	_load_weapons(str(primary["weapon"]), str(secondary["weapon"]))
	_load_pad(str(arena["pad_structure"]))


func _load_weapons(gun_id: String, bomb_id: String) -> void:
	var gun: Dictionary = _find(arr(_json(_pick("weapons.json")), "weapons"), gun_id)
	var bw: Dictionary = _find(arr(_json(_pick("weapons.json")), "weapons"), bomb_id)
	gun_rof = num(gun, "rof")
	gun_damage_min = num(gun, "damage_min")
	gun_damage_max = num(gun, "damage_max")
	gun_spread_deg = num(gun, "spread_deg")
	gun_range_m = num(gun, "range_m")
	gun_structure_mult = num(gun, "structure_mult")
	bomb_rof = num(bw, "rof")
	bomb_damage = num(bw, "damage_max")
	var plist: Array = arr(_json(_pick("projectiles.json")), "projectiles")
	slug = ProjectileDef.from_dict(_find(plist, str(gun["projectile"])))
	var bomb_d: Dictionary = _find(plist, str(bw["projectile"]))
	bomb = ProjectileDef.from_dict(bomb_d)
	blast_radius_m = num(bomb_d, "blast_radius_m")
	blast_radius_structure_m = num(bomb_d, "blast_radius_structure_m")


func _load_pad(pad_id: String) -> void:
	var s: Dictionary = _find(arr(_json(_pick("structures.json")), "structures"), pad_id)
	pad_radius_m = num(s, "pad_radius_m")


func _pick(file: String) -> String:
	var path: String = CONTENT_DIR + file
	if FileAccess.file_exists(path):
		var _a: bool = sources.push_back(path)
		return path
	var _b: bool = sources.push_back(SPIKE_DIR + file)
	return SPIKE_DIR + file


static func _find(list: Array, id: String) -> Dictionary:
	for e: Variant in list:
		var d: Dictionary = e
		if str(d["id"]) == id:
			return d
	assert(false, "def not found: " + id)
	return {}


static func _json(path: String) -> Dictionary:
	var text: String = FileAccess.get_file_as_string(path)
	assert(not text.is_empty(), "missing def file " + path)
	var parsed: Variant = JSON.parse_string(text)
	var out: Dictionary = parsed
	return out
