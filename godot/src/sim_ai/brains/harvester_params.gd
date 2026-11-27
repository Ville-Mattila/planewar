class_name HarvesterParams extends RefCounted
## The Harvester brain's numbers (05 s6.6, s5.7; AI-16): the `ap_harvester` autopilot entry (`flee_radius_m`, `quiet_s`,
## the `follow` block = `GroundParams`, the `harvest` block), the Harvester def (path mask, top speed), `economy.json`
## `salvage_deliver_m` (the sim's delivery reach), the finished-structure tables the brain reads by def (Refinery docks,
## tower envelopes from `towers.json`, armed ships) and the Vision epoch. Read-only after `from_content`.

const KEYS: PackedStringArray = ["flee_radius_m", "quiet_s"]
const HARVEST_KEYS: PackedStringArray = ["hit_window_s", "assigned_weight", "sticky_drop", "queue_s", "claim_wait_s",
	"count_margin_m", "spot_frac", "dock_frac", "refinery_scan_s", "unload_wait_s"]

var ground: GroundParams = null
var tick_hz: int = 30
var mask: int = 0                  ## Pathing.mask_for(max_slope_deg) of the Harvester def
var flee_radius_m: float = 0.0     ## an armed visible enemy this close is a threat (600)
var quiet_ticks: int = 0           ## no threat for this long: resume (15 s)
var hit_ticks: int = 0             ## a HIT / hull loss counts as a threat for this long (3 s)
var assigned_weight: float = 0.0   ## HarvestPicker's 0.5
var sticky_drop: float = 0.0       ## the same field is kept unless its utility fell by more than this (0.3)
var queue_m: float = 0.0           ## one queued Harvester at a Refinery costs this much path: queue_s x ground_speed (20 s x 12 m/s)
var claim_wait_ticks: int = 0      ## stopped in a field without a mining slot this long: another field
var unload_wait_ticks: int = 0     ## stopped at a Refinery with cargo but no dock claim this long: another Refinery
var count_margin_m: float = 0.0    ## own Harvesters within field radius + this count as assigned
var spot_frac: float = 0.0         ## mining spots lie at this fraction of the field radius from its centre (approach side, BUG-4)
var dock_frac: float = 0.0         ## the dock stop lies at Refinery radius + this x salvage_deliver_m from its centre
var scan_ticks: int = 0            ## the per-team Refinery list is rebuilt at most this often
var deliver_m: float = 0.0         ## economy.salvage_deliver_m
var vision_period: int = 1         ## ticks between two Vision passes (TeamPicture epoch)
var cargo_ore: float = 0.0         ## the Harvester def's base capacity
var face_tol_rad: float = 0.0      ## BUG-4: a held unit has faced its next stop within one tick of full-rate turn (ground_turn_rate_dps / tick_hz)
var dock: PackedByteArray = PackedByteArray()          ## by structure index: 1 = a Refinery (docks > 0)
var tower_min: PackedFloat32Array = PackedFloat32Array()   ## by structure index: envelope h_rel_min (towers)
var tower_max: PackedFloat32Array = PackedFloat32Array()   ## ... h_rel_max; NAN = not a tower
var tower_agl: PackedFloat32Array = PackedFloat32Array()   ## ... target_agl_min (0 = none)
var armed: PackedByteArray = PackedByteArray()         ## by ship def id: 1 = carries a gun, bomb or rocket


## `ap` = the `ap_harvester` dictionary; null on a missing key or a bad `follow` / `harvest` block.
static func from_content(c: ContentSet, ap: Dictionary, def: GroundUnitDef) -> HarvesterParams:
	var hv: Dictionary = TargetParams.dict_of(ap, "harvest")
	for k: String in KEYS:
		if not ap.has(k):
			return null
	for k: String in HARVEST_KEYS:
		if not hv.has(k):
			return null
	var g: GroundParams = GroundParams.from_dict(TargetParams.dict_of(ap, "follow"), c.ground_common, c.rules.tick_hz)
	if g == null or c.economy == null:
		return null
	var p: HarvesterParams = HarvesterParams.new()
	p.ground = g
	p.tick_hz = c.rules.tick_hz
	p.mask = Pathing.mask_for(def.max_slope_deg)
	p.flee_radius_m = TargetParams.num(ap, "flee_radius_m", 0.0)
	p.quiet_ticks = roundi(TargetParams.num(ap, "quiet_s", 0.0) * float(p.tick_hz))
	p.hit_ticks = roundi(TargetParams.num(hv, "hit_window_s", 0.0) * float(p.tick_hz))
	p.assigned_weight = TargetParams.num(hv, "assigned_weight", 0.0)
	p.sticky_drop = TargetParams.num(hv, "sticky_drop", 0.0)
	p.queue_m = TargetParams.num(hv, "queue_s", 0.0) * def.ground_speed
	p.claim_wait_ticks = roundi(TargetParams.num(hv, "claim_wait_s", 0.0) * float(p.tick_hz))
	p.unload_wait_ticks = roundi(TargetParams.num(hv, "unload_wait_s", 0.0) * float(p.tick_hz))
	p.count_margin_m = TargetParams.num(hv, "count_margin_m", 0.0)
	p.spot_frac = TargetParams.num(hv, "spot_frac", 0.0)
	p.dock_frac = TargetParams.num(hv, "dock_frac", 0.0)
	p.scan_ticks = roundi(TargetParams.num(hv, "refinery_scan_s", 0.0) * float(p.tick_hz))
	p.deliver_m = c.economy.salvage_deliver_m
	p.cargo_ore = float(def.cargo_ore)
	p.face_tol_rad = deg_to_rad(c.ground_common.ground_turn_rate_dps) / float(p.tick_hz) if c.ground_common != null else 0.0
	var vhz: float = TargetParams.as_num(c.rules.raw.get("vision_hz"), -1.0)
	if vhz <= 0.0:
		return null
	var rate: int = c.rules.rung_2_vision_hz if c.rules.sim_budget_profile.has(Vision.RUNG_VISION) else roundi(vhz)
	p.vision_period = maxi(1, MathX.floori_div(p.tick_hz, maxi(1, rate)))
	p._tables(c)
	return p


func _tables(c: ContentSet) -> void:
	var n: int = c.structures.size()
	var _r: Array[int] = [dock.resize(n), tower_min.resize(n), tower_max.resize(n), tower_agl.resize(n), armed.resize(DefRanges.GROUND_BASE)]
	tower_max.fill(NAN)
	for sd: StructureDef in c.structures:
		var di: int = c.entity_index.get(sd.id, -1)
		var i: int = di - DefRanges.STRUCTURE_BASE
		if i < 0 or i >= n:
			continue
		dock[i] = 1 if sd.docks > 0 else 0
		if sd.is_tower():
			tower_min[i] = TargetParams.num(sd.tower, "h_rel_min", -INF)
			tower_max[i] = TargetParams.num(sd.tower, "h_rel_max", INF)
			tower_agl[i] = TargetParams.num(sd.tower, "target_agl_min", 0.0)
	for sh: ShipDef in c.ships:
		var d: int = c.entity_index.get(sh.id, -1)
		if d >= 0 and d < armed.size():
			armed[d] = 1 if sh.primary_weapon != &"" or sh.secondary_weapon != &"" else 0


## True when structure def `def_id` is a Refinery (it has docks).
func is_dock(def_id: int) -> bool:
	var i: int = def_id - DefRanges.STRUCTURE_BASE
	return i >= 0 and i < dock.size() and dock[i] != 0


## True when tower def `def_id`'s envelope covers a threat `h_rel` m above the tower and `agl` m above the ground.
func covers(def_id: int, h_rel: float, agl: float) -> bool:
	var i: int = def_id - DefRanges.STRUCTURE_BASE
	if i < 0 or i >= tower_max.size() or is_nan(tower_max[i]):
		return false
	return h_rel >= tower_min[i] and h_rel <= tower_max[i] and (tower_agl[i] <= 0.0 or agl >= tower_agl[i])


## True when ship def `def_id` is armed.
func is_armed(def_id: int) -> bool:
	return def_id >= 0 and def_id < armed.size() and armed[def_id] != 0
