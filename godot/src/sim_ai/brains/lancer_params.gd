class_name LancerParams extends RefCounted
## The Lancer brain's own numbers (05 s6.4, AI-14), read-only, beside its DartParams: the rocket rules of 05 s6.4 /
## s6.3 R3 and the AUTO GUARD cluster. From `ap_lancer`: `guard_cluster_m` (800: the friendly structures within it of
## the home pad give the GUARD centre) and the `rocket` block (`lock_range_m` 1,200: fire at or inside it;
## `bomber_reserve` 2 rockets kept while an enemy bomber is known within `bomber_known_m` 5,000; `breakaway_m`: an R3
## rocket pass ends this close to the target). The lock itself comes from the ship's secondary WeaponDef
## (`lock_cone_deg` full cone, `lock_time_s`, R0 B.1; the sim's seeker holds it, 02 s4.4). **Needs content (AI-19):** the
## fixture `test/sim/ai/ai14_autopilots.json` carries the keys until `autopilots.json` does.

const KEYS: PackedStringArray = ["guard_cluster_m"]
const ROCKET_KEYS: PackedStringArray = ["lock_range_m", "bomber_reserve", "bomber_known_m", "breakaway_m"]

var guard_cluster: float = 0.0
var lock_range: float = 0.0
var bomber_reserve: int = 0
var bomber_known: float = 0.0
var breakaway: float = 0.0
var cone_cos: float = 1.0        ## cos(lock_cone_deg / 2): the seeker's boresight test (FireTables.cone_cos)
var lock_ticks: int = 0          ## lock_time_s in ticks (the first rocket leaves this long after the lock starts)
var rocket_damage: float = 0.0   ## one rocket's damage (the salvo size of an R3 pass)
var bomber_def: int = -1         ## def id of `bomber` (the reserve rule)


## Null on a missing key, or when the ship's secondary is not a locking rocket (ADR-09: no defaults).
static func from_content(ap: Dictionary, def: ShipDef, c: ContentSet) -> LancerParams:
	var r: Dictionary = DartParams.block(ap, "rocket")
	for k: String in KEYS:
		if not (ap.get(k) is float or ap.get(k) is int):
			return null
	for k: String in ROCKET_KEYS:
		if not (r.get(k) is float or r.get(k) is int):
			return null
	var wi: int = c.weapon_index.get(def.secondary_weapon, -1)
	wi -= DefRanges.WEAPON_BASE
	var w: WeaponDef = c.weapons[wi] if wi >= 0 and wi < c.weapons.size() else null
	if w == null or w.kind != &"rocket" or w.lock_time_s <= 0.0 or c.rules == null:
		return null
	var p: LancerParams = LancerParams.new()
	p.guard_cluster = TargetParams.num(ap, "guard_cluster_m", 0.0)
	p.lock_range = minf(TargetParams.num(r, "lock_range_m", 0.0), w.range_m)
	p.bomber_reserve = roundi(TargetParams.num(r, "bomber_reserve", 0.0))
	p.bomber_known = TargetParams.num(r, "bomber_known_m", 0.0)
	p.breakaway = TargetParams.num(r, "breakaway_m", 0.0)
	var half: float = deg_to_rad(w.lock_cone_deg) * 0.5   # lock_cone_deg is the full cone (the seeker's half angle)
	p.cone_cos = cos(half) if half > 0.0 and half < PI else -1.0
	p.lock_ticks = maxi(1, roundi(w.lock_time_s * float(c.rules.tick_hz)))
	p.rocket_damage = float(w.damage_max)
	var bd: int = c.entity_index.get(&"bomber", -1)
	p.bomber_def = bd
	return p
