class_name TowerParams extends RefCounted
## The tower brain's numbers (05 s6.8, AI-17): the envelope and priority of every tower def from its `towers.json`
## `tower` block (`TowerEnvelope`, no number of it lives in sim_ai), the weapon's range, projectile speed and lock time
## from the weapon / projectile defs, `economy.tower_offline_ratio`, and the `ap_tower` autopilot entry (`fire_cone_k`
## and the optional `tower_*` choice-point keys of `TargetParams.for_tower`). Tables are indexed by
## `def_id - DefRanges.STRUCTURE_BASE`; non-tower structures hold null / 0. Read-only after `from_content`.

const KEYS: PackedStringArray = ["fire_cone_k"]

var tick_hz: int = 30
var dt: float = 0.0
var cone_k: float = 0.0               ## ap_tower fire_cone_k: the fire cone is atan(cone_k * target radius / distance)
var targets: TargetParams = null
var window_ticks: int = 0             ## attacked_window_s in ticks
var attack_r2: float = 0.0            ## tower_attack_radius_m squared
var off_ratio: float = 0.0            ## economy tower_offline_ratio: below it the tower is offline (02 s8.4)
var vision_period: int = 1
var slack_m: float = 0.0              ## the farthest a ship moves in one Vision epoch (top speed x period): TeamPicture.near_built's margin
var env: Array[TowerEnvelope] = []    ## by structure index; null for a non-tower
var range_m: PackedFloat32Array = PackedFloat32Array()
var speed: PackedFloat32Array = PackedFloat32Array()      ## projectile speed_mps of a straight shell; 0 = aim at the target (guided)
var lock_ticks: PackedInt32Array = PackedInt32Array()     ## WeaponDef.lock_time_s in ticks (0: no lock)


## `ap` = the `ap_tower` dictionary (raw autopilot entry); null on a missing key or a tower with an unknown weapon.
static func from_content(ap: Dictionary, c: ContentSet) -> TowerParams:
	for k: String in KEYS:
		if not ap.has(k):
			return null
	var vhz: float = TargetParams.as_num(c.rules.raw.get("vision_hz"), -1.0)
	if vhz <= 0.0:
		return null
	var p: TowerParams = TowerParams.new()
	p.tick_hz = c.rules.tick_hz
	p.dt = 1.0 / float(p.tick_hz)
	p.cone_k = TargetParams.num(ap, "fire_cone_k", 0.0)
	p.targets = TargetParams.for_tower(ap)
	p.window_ticks = roundi(p.targets.attacked_window_s * float(p.tick_hz))
	p.attack_r2 = p.targets.tower_attack_radius_m * p.targets.tower_attack_radius_m
	p.off_ratio = c.economy.tower_offline_ratio
	var rate: int = c.rules.rung_2_vision_hz if c.rules.sim_budget_profile.has(Vision.RUNG_VISION) else roundi(vhz)
	p.vision_period = maxi(1, MathX.floori_div(p.tick_hz, maxi(1, rate)))
	var vmax: float = 0.0
	for sd: ShipDef in c.ships:
		vmax = maxf(vmax, maxf(sd.v_boost, sd.v_dive_max))
	p.slack_m = vmax * float(p.vision_period) * p.dt
	var n: int = c.structures.size()
	var _r: Array[int] = [p.range_m.resize(n), p.speed.resize(n), p.lock_ticks.resize(n), p.env.resize(n)]
	for sd: StructureDef in c.structures:
		if sd.is_tower() and not p._add(sd, c):
			return null
	return p


## The envelope of structure def `def_id` (null when it is not a tower).
func envelope(def_id: int) -> TowerEnvelope:
	var i: int = def_id - DefRanges.STRUCTURE_BASE
	return env[i] if i >= 0 and i < env.size() else null


func _add(sd: StructureDef, c: ContentSet) -> bool:
	var di: int = c.entity_index.get(sd.id, -1)
	var i: int = di - DefRanges.STRUCTURE_BASE
	var e: TowerEnvelope = TowerEnvelope.from_block(sd.tower, c.entity_index, targets)
	if i < 0 or i >= env.size() or not c.weapon_index.has(e.weapon):
		return false
	var wi: int = c.weapon_index[e.weapon]
	var w: WeaponDef = c.weapons[wi - DefRanges.WEAPON_BASE]
	if not c.projectile_index.has(w.projectile):
		return false
	var pi: int = c.projectile_index[w.projectile]
	var pj: ProjectileDef = c.projectiles[pi - DefRanges.PROJECTILE_BASE]
	env[i] = e
	range_m[i] = w.range_m
	speed[i] = pj.speed_mps if pj.behaviour == &"straight" else 0.0
	lock_ticks[i] = maxi(1, roundi(w.lock_time_s * float(tick_hz))) if w.lock_time_s > 0.0 else 0
	return true
