class_name DartParams extends RefCounted
## The Dart brain's numbers (05 s6.2, s6.3, s5.3, s4.4; AI-13), read-only: built once per class from its autopilot def
## (`ap_dart`), the ship def, the world rules, `order_rules.json` and the weapon / projectile / tower defs. No numeric
## defaults (ADR-09): `from_content` returns null when a key is missing. Top-level and `gun` / `bomb` / `evade` keys are
## 05 s4.4's; `guidance` (the AI-05 rig names, 05 s5.3 values), `intercept` and `attack_run` (05 s6.2 / s6.3 inline
## numbers) and `evade.heading_change_deg` are AI-13 additions. **Needs content (AI-19):** the fixture
## `test/sim/ai/ai13_autopilots.json` carries them until `autopilots.json` does.
## AI-14: the same numbers drive the Lancer, Bomber and Scout brains (they extend DartBrain). Which blocks a class
## needs follows its ship def's weapons: top-level KEYS, `guidance`, `intercept`, `landing` and order_rules always;
## `gun`, `evade` and `rtb.ammo` with a gun primary; `bomb` with a bomb secondary; `attack_run` with a bomb or rocket
## secondary (an absent, unneeded block leaves its fields 0).

const KEYS: PackedStringArray = ["think_period_ticks", "cruise_alt_agl_m", "deck_alt_agl_m", "max_alt_m", "patrol_radius_m",
	"intercept_radius_m", "safety_clear_tti_s", "safety_pull_up_tti_s"]
const GUN_KEYS: PackedStringArray = ["fire_range_m", "fire_cone_k", "burst_s", "pause_s", "aim_error_deg", "aoa_comp_max_deg"]
const BOMB_KEYS: PackedStringArray = ["dive_angle_deg", "release_tolerance_m", "pullout_g_margin_s"]
const EVADE_KEYS: PackedStringArray = ["hp_drop_trigger", "duration_s", "heading_change_deg"]
const GUIDE_KEYS: PackedStringArray = ["kp_alt", "vz_max_mps", "waypoint_radius_m", "pull_up_check_ticks",
	"pull_up_sample_s", "pull_up_min_hold_s", "launch_tilt_deg", "deck_speed_mps"]
const INTERCEPT_KEYS: PackedStringArray = ["boost_close_m", "lost_s", "engage_extra_m", "engage_speed_margin_mps",
	"overshoot_m", "extend_s", "choice_period_thinks", "patrol_points", "patrol_switch_m", "hp_window_s", "standoff_m", "break_ttc_s"]
const RUN_KEYS: PackedStringArray = ["ip_dist_m", "ip_arrive_m", "band_low_agl_m", "band_high_agl_m", "continue_deg",
	"egress_turn_deg", "egress_s", "abort_hp01", "max_passes", "predict_dt_ticks", "predict_max_steps", "dive_release_frac"]
const LAUNCH_KEYS: PackedStringArray = ["pitch_over_agl_m", "launch_climb_agl_m", "approach_min_speed_mps"]
const RTB_KEYS: PackedStringArray = ["ammo"]
const ORDER_KEYS: PackedStringArray = ["arrival_radius_ship_m", "default_move_agl_m", "patrol_engage_radius_m",
	"hold_orbit_radius_m", "guard_orbit_radius_m", "guard_engage_radius_m", "no_pad_loiter_altitude_m", "ghost_timeout_s"]
## Tower threat classes of 05 s6.3 R1 (by the tower weapon's kind): gun = Autocannon, flak, rocket = Missile.
const THREAT_NONE: int = 0
const THREAT_GUN: int = 1
const THREAT_FLAK: int = 2
const THREAT_MISSILE: int = 4

var tick_hz: int = 0
var think_ticks: int = 0                                   ## think_period_ticks (online; the R3 sight horizon)
var cruise_speed: float = 0.0                              ## ShipDef.v_cruise
var boost_speed: float = 0.0                               ## ShipDef.v_boost
var dt: float = 0.0
var gravity: float = 0.0
var cruise_agl: float = 0.0
var deck_agl: float = 0.0
var max_alt: float = 0.0
var patrol_radius: float = 0.0
var intercept_radius: float = 0.0
var clear_tti: float = 0.0
var pull_up_tti: float = 0.0
var fire_range: float = 0.0
var fire_cone_k: float = 0.0
var burst_ticks: int = 0
var cycle_ticks: int = 0
var aim_error_rad: float = 0.0
var slug_speed: float = 0.0
var aoa_comp_max: float = 0.0
var aoa_comp_cos: float = 0.0                              ## cos(aoa_comp_max): the act's dot test
var dive_rad: float = 0.0
var release_tol: float = 0.0
var pullout_margin_s: float = 0.0
var hp_drop: float = 0.0
var evade_ticks: int = 0
var evade_turn_rad: float = 0.0
var kp_alt: float = 0.0
var vz_max: float = 0.0
var wp_radius: float = 0.0
var check_ticks: int = 0
var sample_s: float = 0.0
var pull_up_hold_ticks: int = 0
var launch_tilt_rad: float = 0.0
var deck_speed: float = 0.0
var vision_period: int = 1                                 ## ticks between two Vision passes of a team (rules.vision_hz, rung 2)
var boost_close: float = 0.0
var lost_ticks: int = 0
var engage_extra: float = 0.0
var engage_margin: float = 0.0
var overshoot: float = 0.0
var extend_ticks: int = 0
var choice_period: int = 0
var patrol_points: int = 0
var patrol_switch: float = 0.0
var hp_window_ticks: int = 0
var standoff: float = 0.0
var break_ttc: float = 0.0
var ip_dist: float = 0.0
var ip_arrive: float = 0.0
var band_low: float = 0.0
var band_high: float = 0.0
var continue_rad: float = 0.0
var egress_turn_rad: float = 0.0
var egress_ticks: int = 0
var abort_hp01: float = 0.0
var max_passes: int = 0
var predict_dt: float = 0.0
var predict_steps: int = 0
var dive_release_frac: float = 0.0
var pitch_over_agl: float = 0.0
var launch_climb_agl: float = 0.0
var launch_max_speed: float = 0.0                          ## landing.approach_min_speed_mps: below it a fresh ship is launching
var arrival: float = 0.0
var move_agl: float = 0.0
var patrol_engage: float = 0.0
var hold_orbit: float = 0.0
var guard_orbit: float = 0.0
var guard_engage: float = 0.0
var loiter_alt: float = 0.0
var ghost_ticks: int = 0
var bomb_def: ProjectileDef = null
var bomb_damage: float = 0.0
var bomb_interval: float = 0.0                             ## 1 / the bomb weapon's rof: the stick spacing in time
var rules: RulesDef = null
var threat_kind: PackedByteArray = PackedByteArray()       ## by def id: THREAT_* of a tower def (0 for the rest)
var threat_range: PackedFloat32Array = PackedFloat32Array() ## by def id: that tower weapon's range_m
var threat_scan: float = 0.0                               ## largest tower range: the R1 scan radius around a target
var hp_by_def: PackedFloat32Array = PackedFloat32Array()    ## by def id: hit points (the 05 s6.3 R3 stick size)
var rtb_ammo: int = 0                                      ## rtb.ammo: the gun-empty term of the 05 s6 RTB rule
var has_gun: bool = false                                  ## AI-14: the primary is a gun (Dart, Lancer)
var has_bombs: bool = false                                ## AI-14: the secondary is a bomb (Dart, Bomber)
var has_rockets: bool = false                              ## AI-14: the secondary is a rocket (Lancer)
var secondary: WeaponDef = null                            ## AI-14: the secondary weapon def (bomb or rocket), null when none


## Builds the parameters of ship `def` from `ap` (its autopilot def's raw dictionary); null on a missing key or def.
static func from_content(ap: Dictionary, def: ShipDef, c: ContentSet) -> DartParams:
	var d: Dictionary = ap
	var orr: Dictionary = c.order_rules.raw if c.order_rules != null else {}
	var gun: WeaponDef = _weapon(c, def.primary_weapon)
	var sec: WeaponDef = _weapon(c, def.secondary_weapon)
	if c.rules == null or (def.primary_weapon != &"" and gun == null) or (def.secondary_weapon != &"" and sec == null):
		return null
	var p: DartParams = DartParams.new()
	p.has_gun = gun != null and gun.kind == &"gun"
	p.has_bombs = sec != null and sec.kind == &"bomb"
	p.has_rockets = sec != null and sec.kind == &"rocket"
	p.secondary = sec
	if not (_has(d, KEYS) and _has(block(d, "guidance"), GUIDE_KEYS) and _has(block(d, "intercept"), INTERCEPT_KEYS)
			and _has(block(d, "landing"), LAUNCH_KEYS) and _has(orr, ORDER_KEYS)
			and (not p.has_gun or (_has(block(d, "gun"), GUN_KEYS) and _has(block(d, "evade"), EVADE_KEYS)
				and _has(block(d, "rtb"), RTB_KEYS)))
			and (not p.has_bombs or _has(block(d, "bomb"), BOMB_KEYS))
			and (not (p.has_bombs or p.has_rockets) or _has(block(d, "attack_run"), RUN_KEYS))):
		return null
	p.rules = c.rules
	var vhz: float = TargetParams.as_num(c.rules.raw.get("vision_hz"), -1.0)
	if vhz <= 0.0:
		return null
	var rate: int = c.rules.rung_2_vision_hz if c.rules.sim_budget_profile.has(Vision.RUNG_VISION) else roundi(vhz)
	p.vision_period = maxi(1, MathX.floori_div(c.rules.tick_hz, maxi(1, rate)))
	p.tick_hz = c.rules.tick_hz
	p.dt = 1.0 / float(p.tick_hz)
	p.gravity = c.rules.gravity
	p._top(d)
	p.cruise_speed = def.v_cruise
	p.boost_speed = def.v_boost
	if p.has_gun:
		p.rtb_ammo = roundi(_f(block(d, "rtb"), "ammo"))
		p._gun(block(d, "gun"), gun, c)
		p._evade(block(d, "evade"))
	if p.has_bombs:
		p._bomb(block(d, "bomb"), sec, c)
	p._guide(block(d, "guidance"), block(d, "landing"))
	p._intercept(block(d, "intercept"))
	if p.has_bombs or p.has_rockets:
		p._run(block(d, "attack_run"))
	p._orders(orr)
	p._threats(c)
	return p


## Ticks of `s` seconds at this tick rate (at least 1).
func ticks(s: float) -> int:
	return maxi(1, roundi(s * float(tick_hz)))


func _top(d: Dictionary) -> void:
	think_ticks = maxi(1, roundi(_f(d, "think_period_ticks")))
	cruise_agl = _f(d, "cruise_alt_agl_m")
	deck_agl = _f(d, "deck_alt_agl_m")
	max_alt = _f(d, "max_alt_m")
	patrol_radius = _f(d, "patrol_radius_m")
	intercept_radius = _f(d, "intercept_radius_m")
	clear_tti = _f(d, "safety_clear_tti_s")
	pull_up_tti = _f(d, "safety_pull_up_tti_s")


func _gun(g: Dictionary, w: WeaponDef, c: ContentSet) -> void:
	fire_range = minf(_f(g, "fire_range_m"), w.range_m)
	fire_cone_k = _f(g, "fire_cone_k")
	burst_ticks = ticks(_f(g, "burst_s"))
	cycle_ticks = burst_ticks + ticks(_f(g, "pause_s"))
	aim_error_rad = deg_to_rad(_f(g, "aim_error_deg"))
	aoa_comp_max = deg_to_rad(_f(g, "aoa_comp_max_deg"))
	aoa_comp_cos = cos(aoa_comp_max)
	var pd: ProjectileDef = _projectile(c, w.projectile)
	slug_speed = pd.speed_mps if pd != null else 0.0


func _bomb(b: Dictionary, w: WeaponDef, c: ContentSet) -> void:
	dive_rad = deg_to_rad(_f(b, "dive_angle_deg"))
	release_tol = _f(b, "release_tolerance_m")
	pullout_margin_s = _f(b, "pullout_g_margin_s")
	bomb_def = _projectile(c, w.projectile)
	bomb_damage = float(w.damage_max) * w.structure_mult
	bomb_interval = 1.0 / w.rof if w.rof > 0.0 else 0.0


func _evade(e: Dictionary) -> void:
	hp_drop = _f(e, "hp_drop_trigger")
	evade_ticks = ticks(_f(e, "duration_s"))
	evade_turn_rad = deg_to_rad(_f(e, "heading_change_deg"))


func _guide(g: Dictionary, l: Dictionary) -> void:
	kp_alt = _f(g, "kp_alt")
	vz_max = _f(g, "vz_max_mps")
	wp_radius = _f(g, "waypoint_radius_m")
	check_ticks = maxi(1, roundi(_f(g, "pull_up_check_ticks")))
	sample_s = _f(g, "pull_up_sample_s")
	pull_up_hold_ticks = ticks(_f(g, "pull_up_min_hold_s"))
	launch_tilt_rad = deg_to_rad(_f(g, "launch_tilt_deg"))
	deck_speed = _f(g, "deck_speed_mps")
	pitch_over_agl = _f(l, "pitch_over_agl_m")
	launch_climb_agl = _f(l, "launch_climb_agl_m")
	launch_max_speed = _f(l, "approach_min_speed_mps")


func _intercept(i: Dictionary) -> void:
	boost_close = _f(i, "boost_close_m")
	lost_ticks = ticks(_f(i, "lost_s"))
	engage_extra = _f(i, "engage_extra_m")
	engage_margin = _f(i, "engage_speed_margin_mps")
	overshoot = _f(i, "overshoot_m")
	extend_ticks = ticks(_f(i, "extend_s"))
	choice_period = maxi(1, roundi(_f(i, "choice_period_thinks")))
	patrol_points = maxi(3, roundi(_f(i, "patrol_points")))
	patrol_switch = _f(i, "patrol_switch_m")
	hp_window_ticks = ticks(_f(i, "hp_window_s"))
	standoff = _f(i, "standoff_m")
	break_ttc = _f(i, "break_ttc_s")


func _run(r: Dictionary) -> void:
	ip_dist = _f(r, "ip_dist_m")
	ip_arrive = _f(r, "ip_arrive_m")
	band_low = _f(r, "band_low_agl_m")
	band_high = _f(r, "band_high_agl_m")
	continue_rad = deg_to_rad(_f(r, "continue_deg"))
	egress_turn_rad = deg_to_rad(_f(r, "egress_turn_deg"))
	egress_ticks = ticks(_f(r, "egress_s"))
	abort_hp01 = _f(r, "abort_hp01")
	max_passes = roundi(_f(r, "max_passes"))
	predict_dt = _f(r, "predict_dt_ticks") * dt
	predict_steps = roundi(_f(r, "predict_max_steps"))
	dive_release_frac = _f(r, "dive_release_frac")


func _orders(o: Dictionary) -> void:
	arrival = _f(o, "arrival_radius_ship_m")
	move_agl = _f(o, "default_move_agl_m")
	patrol_engage = _f(o, "patrol_engage_radius_m")
	hold_orbit = _f(o, "hold_orbit_radius_m")
	guard_orbit = _f(o, "guard_orbit_radius_m")
	guard_engage = _f(o, "guard_engage_radius_m")
	loiter_alt = _f(o, "no_pad_loiter_altitude_m")
	ghost_ticks = ticks(_f(o, "ghost_timeout_s"))


# Tower threat table by def id: the class of each tower's weapon (05 s6.3 R1) and its range; the scan radius is the
# largest range, so one structure query around a target finds every tower that covers it.
func _threats(c: ContentSet) -> void:
	var _r: int = threat_kind.resize(DefRanges.END) | threat_range.resize(DefRanges.END) | hp_by_def.resize(DefRanges.END)
	threat_kind.fill(THREAT_NONE)
	threat_range.fill(0.0)
	hp_by_def.fill(0.0)
	for sh: ShipDef in c.ships:
		_hp(c, sh.id, float(sh.hp))
	for gd: GroundUnitDef in c.ground_units:
		_hp(c, gd.id, float(gd.hp))
	for sd: StructureDef in c.structures:
		_hp(c, sd.id, float(sd.hp))
		if not sd.is_tower():
			continue
		var w: WeaponDef = _weapon(c, StringName(str(sd.tower.get("weapon", ""))))
		var id: int = c.entity_index.get(sd.id, -1)
		if w == null or id < 0 or id >= DefRanges.END:
			continue
		var k: int = THREAT_GUN if w.kind == &"gun" else (THREAT_FLAK if w.kind == &"flak" else (THREAT_MISSILE if w.kind == &"rocket" else THREAT_NONE))
		threat_kind[id] = k
		threat_range[id] = w.range_m
		if k != THREAT_NONE:
			threat_scan = maxf(threat_scan, w.range_m)


func _hp(c: ContentSet, id: StringName, hp: float) -> void:
	var d: int = c.entity_index.get(id, -1)
	if d >= 0 and d < DefRanges.END:
		hp_by_def[d] = hp


static func _weapon(c: ContentSet, id: StringName) -> WeaponDef:
	var i: int = c.weapon_index.get(id, -1)
	i -= DefRanges.WEAPON_BASE
	return c.weapons[i] if i >= 0 and i < c.weapons.size() else null


static func _projectile(c: ContentSet, id: StringName) -> ProjectileDef:
	var i: int = c.projectile_index.get(id, -1)
	i -= DefRanges.PROJECTILE_BASE
	return c.projectiles[i] if i >= 0 and i < c.projectiles.size() else null


## The sub-dictionary `k` of `d` ({} when absent or not a dictionary).
static func block(d: Dictionary, k: String) -> Dictionary:
	var x: Variant = d.get(k)
	if x is Dictionary:
		var r: Dictionary = x
		return r
	return {}


static func _has(d: Dictionary, keys: PackedStringArray) -> bool:
	for k: String in keys:
		if not (d.get(k) is float or d.get(k) is int):
			return false
	return true


static func _f(d: Dictionary, k: String) -> float:
	var x: Variant = d[k]
	if x is int:
		var i: int = x
		return float(i)
	var f: float = x
	return f
