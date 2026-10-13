class_name ContentSet extends RefCounted
## Result of one ContentLoader run: every typed def, the id indexes and the hash. ContentDB copies a
## successful set into its public members; a set with errors is discarded whole (N3).

var rules: RulesDef = null
var flight_common: FlightCommonDef = null
var ships: Array[ShipDef] = []
var ground_units: Array[GroundUnitDef] = []
var structures: Array[StructureDef] = []  ## structures.json then towers.json
var weapons: Array[WeaponDef] = []
var projectiles: Array[ProjectileDef] = []
var doctrines: Array[DoctrineDef] = []
var economy: EconomyDef = null
var match_rules: MatchRulesDef = null
var modes: Array[ModeDef] = []
var slots_by_player_count: Dictionary = {}
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
var wing: WingDef = null  ## FEAT-01 (08 SL-2); null when wing.json is absent (N8)
var callsigns: CallsignDef = null  ## FEAT-01 (08 SL-3)
var barks: Array[BarkDef] = []  ## FEAT-01 (08 SL-3)
var supply_canister: SupplyCanisterDef = null  ## FEAT-01 (08 SL-5, commander_verbs.json, candidate)

var entity_index: Dictionary = {}  ## StringName -> def_id (ships, ground units, structures, towers)
var weapon_index: Dictionary = {}
var projectile_index: Dictionary = {}
var content_hash: PackedByteArray = PackedByteArray()

var errors: Array[String] = []
var warnings: Array[String] = []


func ok() -> bool:
	return errors.is_empty()
