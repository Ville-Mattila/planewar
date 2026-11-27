class_name CrawlerParams extends RefCounted
## The Siege Crawler brain's numbers (05 s6.7, s5.7; AI-18): the `ap_crawler` autopilot entry (`follow` = GroundParams,
## required by R0 B.29 A-145; the `siege` block, required with all 12 keys and no default in code, R0 B.33 A-161), the
## Crawler def (path mask, weapon) and its `siege_gun` / `siege_shell` defs. Read-only after `from_content`.
## A def without the block, or with a key missing or <= 0, makes `from_content` return null. The ring lies inside the
## weapon's [`range_min_m`, `range_m`] and `solve_tol_m <= loft_tol_m`, or `from_content` refuses the block. AI-18b: the
## barrel (typed `GroundUnitDef.barrel_*`, CONTENT-5; R0 B.31 A-151) and the ground turn rate (`ground_common`): the brain
## drives both dead-beat; a Crawler def without a barrel cannot loft and is refused.

const SIEGE_KEYS: PackedStringArray = ["spot_min_m", "spot_max_m", "spot_slope_deg", "relocate_bomb_m", "relocate_step_m",
	"aim_tol_deg", "spot_samples", "loft_tol_m", "solve_tol_m", "loft_iters", "solve_step_ticks", "relocate_tries"]
## DEPRECATED (R0 B.33 A-161): the 9 pre-A-161 defaults and the solve's iteration count, kept for the public API (10 s4.1)
## and read by nothing; the values now come from the required `siege` block.
const SIEGE_DEFAULTS: Array[float] = [1000.0, 1150.0, 10.0, 60.0, 150.0, 1.0, 24.0, 15.0, 2.0]
const LOFT_ITERS: int = 6

var ground: GroundParams = null
var tick_hz: int = 30
var dt: float = 0.0
var mask: int = 0                  ## Pathing.mask_for(max_slope_deg) of the Crawler def
var spot_min_m: float = 0.0        ## a firing spot is at least this far from the target (05: 1,000)
var spot_max_m: float = 0.0        ## ... and at most this far (05: 1,150)
var spot_mid_m: float = 0.0        ## the ring a new spot is placed on: the middle of the band
var slope_max_deg: float = 0.0     ## steepest ground a spot may stand on (05: 10)
var relocate_m: float = 0.0        ## an enemy bomb this close to a sieging Crawler moves it (05: 60)
var relocate_step_m: float = 0.0   ## a relocation moves this far along the ring, away from the bomb
var aim_tol_rad: float = 0.0       ## the trigger is held while the heading is within this of the target bearing
var samples: int = 1               ## ring candidates (every 360 / samples degrees) a spot search may try
var loft_tol_m: float = 0.0        ## the promised impact accuracy: a target that moved farther than this is re-solved
var solve_tol_m: float = 0.0       ## AI-18b: the lofted solve stops at this along-track miss (<= loft_tol_m, 2 m default)
var range_m: float = 0.0           ## siege_gun range_m
var range_min_m: float = 0.0       ## siege_gun range_min_m
var shell: ProjectileDef = null    ## siege_shell
var speed: float = 0.0             ## shell muzzle speed (speed_mps)
var max_steps: int = 0             ## predict_impact steps of one solve: the shell's lifetime at the solve step
var radius: float = 0.0            ## Crawler bounding radius (the muzzle offset of the sim's fire pipeline)
var barrel_rate: float = 0.0       ## AI-18b: barrel_slew_dps in rad/s (the elevation rate at pitch 1)
var barrel_lo: float = 0.0         ## AI-18b: barrel_min_deg in rad (the sim swaps reversed limits; so does this)
var barrel_hi: float = 0.0         ## AI-18b: barrel_max_deg in rad
var turn_rate: float = 0.0         ## AI-18b: ground_common ground_turn_rate_dps in rad/s (the heading rate at yaw 1)
var rules: RulesDef = null
var loft_iters: int = 1            ## A-161: secant steps of one solve after the first guess (SiegeAim.loft)
var solve_step_ticks: int = 1      ## A-161: predict_impact steps of the lofted solve, in ticks
var relocate_tries: int = 1        ## A-161: ring candidates CrawlerBrain._relocate tries


## `ap` = the `ap_crawler` dictionary; null on a bad `follow` block, a bad `siege` key, a band outside the weapon's
## range, `solve_tol_m` above `loft_tol_m`, a missing `siege` block or key, or a Crawler def without its weapon /
## projectile / barrel.
static func from_content(c: ContentSet, ap: Dictionary, def: GroundUnitDef) -> CrawlerParams:
	var g: GroundParams = GroundParams.from_dict(TargetParams.dict_of(ap, "follow"), c.ground_common, c.rules.tick_hz)
	var w: WeaponDef = _weapon(c, def.weapon)
	var pd: ProjectileDef = _projectile(c, w.projectile) if w != null else null
	if g == null or pd == null or pd.speed_mps <= 0.0:
		return null
	var sg: Dictionary = TargetParams.dict_of(ap, "siege")
	var v: PackedFloat32Array = PackedFloat32Array()
	for i: int in SIEGE_KEYS.size():
		var x: float = TargetParams.num(sg, SIEGE_KEYS[i], 0.0)           # no default: a missing key reads 0 and refuses
		if x <= 0.0:
			return null
		var _a: bool = v.append(x)
	if v[0] >= v[1] or v[0] < w.range_min_m or v[1] > w.range_m or v[8] > v[7]:
		return null
	var rate: float = deg_to_rad(def.barrel_slew_dps)
	var lo: float = deg_to_rad(def.barrel_min_deg)
	var hi: float = deg_to_rad(def.barrel_max_deg)
	if rate <= 0.0 or c.ground_common == null or c.ground_common.ground_turn_rate_dps <= 0.0:
		return null
	var p: CrawlerParams = CrawlerParams.new()
	p.ground = g
	p.tick_hz = c.rules.tick_hz
	p.dt = 1.0 / float(p.tick_hz)
	p.mask = Pathing.mask_for(def.max_slope_deg)
	p.spot_min_m = v[0]
	p.spot_max_m = v[1]
	p.spot_mid_m = 0.5 * (v[0] + v[1])
	p.slope_max_deg = v[2]
	p.relocate_m = v[3]
	p.relocate_step_m = v[4]
	p.aim_tol_rad = deg_to_rad(v[5])
	p.samples = maxi(roundi(v[6]), 1)
	p.loft_tol_m = v[7]
	p.solve_tol_m = v[8]
	p.range_m = w.range_m
	p.range_min_m = w.range_min_m
	p.shell = pd
	p.speed = pd.speed_mps
	p.loft_iters = roundi(v[9])
	p.solve_step_ticks = roundi(v[10])
	p.relocate_tries = roundi(v[11])
	p.max_steps = maxi(ceili(pd.lifetime_s / (float(p.solve_step_ticks) * p.dt)), 1)
	p.radius = def.bounding_radius
	p.rules = c.rules
	p.barrel_rate = rate
	p.barrel_lo = minf(lo, hi)
	p.barrel_hi = maxf(lo, hi)
	p.turn_rate = deg_to_rad(c.ground_common.ground_turn_rate_dps)
	return p


## True when a firing spot at distance `d` m from the target is inside the band.
func in_band(d: float) -> bool:
	return d >= spot_min_m and d <= spot_max_m


static func _weapon(c: ContentSet, id: StringName) -> WeaponDef:
	var k: int = c.weapon_index.get(id, -1)
	var i: int = k - DefRanges.WEAPON_BASE if k >= 0 else -1
	return c.weapons[i] if i >= 0 and i < c.weapons.size() else null


static func _projectile(c: ContentSet, id: StringName) -> ProjectileDef:
	var k: int = c.projectile_index.get(id, -1)
	var i: int = k - DefRanges.PROJECTILE_BASE if k >= 0 else -1
	return c.projectiles[i] if i >= 0 and i < c.projectiles.size() else null
