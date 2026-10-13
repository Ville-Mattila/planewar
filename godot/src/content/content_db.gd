extends Node
## Autoload `ContentDB` (03 s15.3, R0 B.1/B.8, content/MODULE.md). No class_name: it would hide the autoload
## singleton. Loads and validates every def file (fail-fast, N3), indexes ids (N2, A-1), hashes the hash scope
## (N1) and resolves doctrines as a pure function (N7). Defs are immutable by convention after loaded(true) (N4).

signal loaded(ok: bool)

const DEFS_ROOT: String = "res://content/defs/"
const MODS_ROOT: String = "user://mods/"
const K_SHIP: int = DefRanges.K_SHIP
const K_GROUND: int = DefRanges.K_GROUND
const K_STRUCTURE: int = DefRanges.K_STRUCTURE
const K_WEAPON: int = DefRanges.K_WEAPON
const K_PROJECTILE: int = DefRanges.K_PROJECTILE

var rules: RulesDef = null
var flight_common: FlightCommonDef = null
var ships: Array[ShipDef] = []
var ground_units: Array[GroundUnitDef] = []
var structures: Array[StructureDef] = []  ## incl. towers
var weapons: Array[WeaponDef] = []
var projectiles: Array[ProjectileDef] = []
var doctrines: Array[DoctrineDef] = []
var economy: EconomyDef = null
var match_rules: MatchRulesDef = null
var modes: Array[ModeDef] = []
var slots_by_player_count: Dictionary = {}  ## modes.json: "2" | "4" | "6" | "8" -> slot ids
var bot_promises: Array[BotPromiseDef] = []
var bot_profiles: Array[BotProfileDef] = []
var autopilots: Array[AutopilotDef] = []
var order_rules: OrderRulesDef = null
var build_orders: Array[BuildOrderDef] = []
var assists: AssistDef = null
var scoring: ScoringDef = null
var medals: Array[MedalDef] = []
var progression: ProgressionDef = null
var quality_tiers: Array[QualityTierDef] = []
var maps: Array[MapDef] = []
var wing: WingDef = null  ## wing.json (08 SL-2); null until shipped (N8)
var callsigns: CallsignDef = null  ## callsigns.json (08 SL-3)
var barks: Array[BarkDef] = []  ## barks.json (08 SL-3)
var supply_canister: SupplyCanisterDef = null  ## commander_verbs.json (08 SL-5, candidate)

var _is_loaded: bool = false
var _set: ContentSet = null
var _texts: Dictionary = {}
var _map_texts: Dictionary = {}


## Synchronous load of every def file under `root` (and maps/ next to it). Emits loaded(ok).
func load_all(root: String = DEFS_ROOT) -> Result:
	var texts: Dictionary = {}
	var err: String = _read_dir(root, texts)
	if not err.is_empty():
		return _fail(ERR_FILE_NOT_FOUND, err)
	return _ingest(texts, _read_maps(root))


## Same outcome as load_all; on web it yields a frame between files so the first frame is not blocked.
func load_all_async(root: String = DEFS_ROOT) -> void:
	if not (OS.has_feature("web") and is_inside_tree()):
		var _r: Result = load_all(root)
		return
	var texts: Dictionary = {}
	for f: String in _json_files(root):
		texts[f] = FileAccess.get_file_as_string(root.path_join(f))
		await get_tree().process_frame
	if texts.is_empty():
		var _f: Result = _fail(ERR_FILE_NOT_FOUND, "def directory not found or empty: %s" % root)
		return
	var maps_t: Dictionary = _read_maps(root)
	await get_tree().process_frame
	var _i: Result = _ingest(texts, maps_t)


func is_loaded() -> bool:
	return _is_loaded


func def_index(id: StringName) -> int:
	return _set.entity_index.get(id, -1) if _set != null else -1


func weapon_index(id: StringName) -> int:
	return _set.weapon_index.get(id, -1) if _set != null else -1


func projectile_index(id: StringName) -> int:
	return _set.projectile_index.get(id, -1) if _set != null else -1


func ship(def_id: int) -> ShipDef:
	var i: int = def_id - DefRanges.SHIP_BASE
	return ships[i] if i >= 0 and i < ships.size() else null


func ground_unit(def_id: int) -> GroundUnitDef:
	var i: int = def_id - DefRanges.GROUND_BASE
	return ground_units[i] if i >= 0 and i < ground_units.size() else null


func structure(def_id: int) -> StructureDef:
	var i: int = def_id - DefRanges.STRUCTURE_BASE
	return structures[i] if i >= 0 and i < structures.size() else null


func weapon(def_id: int) -> WeaponDef:
	var i: int = def_id - DefRanges.WEAPON_BASE
	return weapons[i] if i >= 0 and i < weapons.size() else null


func projectile(def_id: int) -> ProjectileDef:
	var i: int = def_id - DefRanges.PROJECTILE_BASE
	return projectiles[i] if i >= 0 and i < projectiles.size() else null


func kind_of(def_id: int) -> int:
	return DefRanges.kind_of(def_id)


func map(id: StringName) -> MapDef:
	for d: MapDef in maps:
		if d.id == id:
			return d
	return null


func mode(id: StringName) -> ModeDef:
	for d: ModeDef in modes:
		if d.id == id:
			return d
	return null


func doctrine(id: StringName) -> DoctrineDef:
	for d: DoctrineDef in doctrines:
		if d.id == id:
			return d
	return null


## One caps profile of match_rules.json (A-8); null when unknown or not loaded.
func caps(profile: StringName) -> CapsDef:
	if match_rules == null:
		return null
	return match_rules.caps.get(profile)


func content_hash() -> PackedByteArray:
	return _set.content_hash if _set != null else PackedByteArray()


func content_hash_hex() -> String:
	return content_hash().hex_encode()


## Pure (N7): copies of the gameplay defs with the doctrine applied. &"" resolves to unmodified copies.
## Unknown id: null.
func resolve_for_doctrine(doctrine_id: StringName) -> ResolvedDefs:
	var d: DoctrineDef = null
	if doctrine_id != &"":
		d = doctrine(doctrine_id)
		if d == null:
			Log.error(&"content", "resolve_for_doctrine: unknown doctrine '%s'" % doctrine_id)
			return null
	return DoctrineResolver.resolve(d, ships, ground_units, structures, weapons, projectiles)


## Custom lobbies and offline only (ADR-09). Overlays the pack's top-level *.json files over the stock defs
## (same file names replace), re-validates and re-hashes. Stub: pack manifests and signing arrive with the
## mod-pack task; the loader only accepts directories under user://mods/.
func load_mod_pack(dir: String) -> Result:
	if not dir.begins_with(MODS_ROOT) or dir.contains(".."):
		return Result.failure(ERR_INVALID_PARAMETER, "mod packs live under %s" % MODS_ROOT)
	var overlay: Dictionary = {}
	var err: String = _read_dir(dir, overlay)
	if not err.is_empty():
		return Result.failure(ERR_FILE_NOT_FOUND, err)
	var merged: Dictionary = _texts.duplicate()
	merged.merge(overlay, true)
	return _ingest(merged, _map_texts)


func _ingest(texts: Dictionary, map_texts: Dictionary) -> Result:
	var s: ContentSet = ContentLoader.build(texts, map_texts)
	for w: String in s.warnings:
		Log.warn(&"content", w)
	if not s.ok():
		for e: String in s.errors:
			Log.error(&"content", e)
		return _fail(ERR_INVALID_DATA, s.errors[0])
	_adopt(s, texts)
	_is_loaded = true
	loaded.emit(true)
	return Result.success(s)


func _fail(code: int, msg: String) -> Result:
	_clear()
	loaded.emit(false)
	return Result.failure(code, msg)


func _clear() -> void:
	_adopt(ContentSet.new(), {})
	_is_loaded = false
	_set = null


func _adopt(s: ContentSet, texts: Dictionary) -> void:
	_set = s
	_texts = texts
	rules = s.rules
	flight_common = s.flight_common
	ships = s.ships
	ground_units = s.ground_units
	structures = s.structures
	weapons = s.weapons
	projectiles = s.projectiles
	doctrines = s.doctrines
	economy = s.economy
	match_rules = s.match_rules
	modes = s.modes
	slots_by_player_count = s.slots_by_player_count
	bot_promises = s.bot_promises
	bot_profiles = s.bot_profiles
	autopilots = s.autopilots
	order_rules = s.order_rules
	build_orders = s.build_orders
	assists = s.assists
	scoring = s.scoring
	medals = s.medals
	progression = s.progression
	quality_tiers = s.quality_tiers
	maps = s.maps
	wing = s.wing
	callsigns = s.callsigns
	barks = s.barks
	supply_canister = s.supply_canister


static func _json_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	if DirAccess.dir_exists_absolute(dir):
		for f: String in DirAccess.get_files_at(dir):
			if f.ends_with(".json"):
				out.append(f)
	return out


## Reads every top-level *.json under `dir` into `into`; returns an error text or "".
static func _read_dir(dir: String, into: Dictionary) -> String:
	var names: Array[String] = _json_files(dir)
	if names.is_empty():
		return "def directory not found or empty: %s" % dir
	for f: String in names:
		into[f] = FileAccess.get_file_as_string(dir.path_join(f))
	return ""


## maps/<map_id>/recipe.json next to the defs directory: map id -> text.
static func _read_maps(root: String) -> Dictionary:
	var out: Dictionary = {}
	var maps_dir: String = root.trim_suffix("/").get_base_dir().path_join("maps")
	for dir_name: String in DirAccess.get_directories_at(maps_dir):
		var path: String = maps_dir.path_join(dir_name).path_join("recipe.json")
		if FileAccess.file_exists(path):
			out[dir_name] = FileAccess.get_file_as_string(path)
	return out
