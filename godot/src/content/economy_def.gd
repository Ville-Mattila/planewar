class_name EconomyDef extends Def
## economy.json (R0 B.1, 02 s8.1). Singleton file.

var start_ore: int = 0
var start_ice: int = 0
var start_kit: PackedStringArray = PackedStringArray()
var core_trickle_ore_per_s: float = 0.0
var repair_ore_per_hp: float = 0.0
var wreck_fraction: float = 0.0
var wreck_lifetime_s: float = 0.0
var salvage_pod_max_ore: int = 0
var solar_band_deg: float = 0.0
var solar_plateau_mult: float = 0.0
var solar_plateau_radius_m: float = 0.0
var tower_offline_ratio: float = 0.0
var production_min_speed: float = 0.0
var pipe_radius_m: float = 0.0
var refinery_docks: int = 0
var hauler_transfer_per_s: float = 0.0
var queue_max: int = 0
var construction_slots_base: int = 0
var construction_slots_max: int = 0
var cancel_refund_queued: float = 0.0
var cancel_refund_assembly: float = 0.0
var self_repair_delay_s: float = 0.0
var self_repair_min_hp_s: float = 0.0          ## 02 s6.3 floor of the self-repair rate (A-80)
var self_repair_frac_per_s: float = 0.0        ## 02 s6.3 share of max HP per second (A-80)
var early_share_lock_s: float = 0.0
var early_share_ore: int = 0
var unused_slot_yield: float = 0.0
var build_max_slope_deg: float = 0.0           ## 02 s6.2 rule 2
var outpost_presence_radius_m: float = 0.0     ## 02 s6.2 rule 5(a)
var outpost_spacing_friendly_m: float = 0.0    ## 02 s6.2 rule 5(b)
var outpost_spacing_enemy_m: float = 0.0       ## 02 s6.2 rule 5(c)
var site_hp_fraction: float = 0.0              ## 02 s6.3: site hp = hp * max(site_hp_fraction, progress)
var start_refinery_dist_m: float = 0.0         ## 02 s8.1 start kit geometry
var start_adjacent_dist_m: float = 0.0

const SPEC: Dictionary = {
	"i": "start_ore start_ice salvage_pod_max_ore refinery_docks queue_max construction_slots_base construction_slots_max early_share_ore",
	"f": "core_trickle_ore_per_s repair_ore_per_hp wreck_fraction wreck_lifetime_s solar_band_deg solar_plateau_mult solar_plateau_radius_m tower_offline_ratio production_min_speed pipe_radius_m hauler_transfer_per_s cancel_refund_queued cancel_refund_assembly self_repair_delay_s self_repair_min_hp_s self_repair_frac_per_s early_share_lock_s unused_slot_yield build_max_slope_deg outpost_presence_radius_m outpost_spacing_friendly_m outpost_spacing_enemy_m site_hp_fraction start_refinery_dist_m start_adjacent_dist_m",
	"a": "start_kit",
	"req": "start_ore start_ice start_kit core_trickle_ore_per_s repair_ore_per_hp self_repair_min_hp_s self_repair_frac_per_s wreck_fraction wreck_lifetime_s salvage_pod_max_ore queue_max early_share_lock_s early_share_ore build_max_slope_deg outpost_presence_radius_m outpost_spacing_friendly_m outpost_spacing_enemy_m site_hp_fraction start_refinery_dist_m start_adjacent_dist_m",
}


static func from_dict(d: Dictionary) -> EconomyDef:
	var e: EconomyDef = EconomyDef.new()
	e._read_singleton(d, &"economy")
	e._fill(d, SPEC)
	return e
