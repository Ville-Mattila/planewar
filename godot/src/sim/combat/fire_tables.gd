class_name FireTables extends RefCounted
## Per-def weapon tables of `WeaponFire` (GD-36), built once per world from the base defs: which weapon each ship,
## ground unit and tower carries, what a tower may target, and each weapon's projectile kind / def. Doctrine never
## changes a weapon's identity, only its numbers: `bind` copies each owner's doctrine-resolved numbers into flat rows
## `[owner * weapon_count + weapon]` so the fire pass reads packed arrays, never a def object (03 s12.2). Lane-internal.

const ALL_KINDS: int = Spatial.MASK_SHIP | Spatial.MASK_GROUND | Spatial.MASK_STRUCTURE

var prim: PackedInt32Array = PackedInt32Array()     ## by def_id: primary weapon local index, -1 none
var sec: PackedInt32Array = PackedInt32Array()      ## by def_id: ship secondary weapon local index, -1 none
var mask: PackedByteArray = PackedByteArray()       ## by def_id: Spatial.MASK_* bits a lock / flak aim may pick
var tower: PackedByteArray = PackedByteArray()      ## by def_id: 1 = tower (supply applies)
var w_kind: PackedByteArray = PackedByteArray()     ## by weapon local index: ProjectileStore kind
var w_proj: PackedInt32Array = PackedInt32Array()   ## by weapon local index: projectile local index, -1 none
var weapon_count: int = 0
# Rows by owner * weapon_count + weapon (owner slot, or WorldDefs.NEUTRAL), from the owner's resolved defs:
var interval: PackedFloat64Array = PackedFloat64Array()   ## s between shots (1 / rof) or salvos (reload_s); 0 = never
var lock_s: PackedFloat64Array = PackedFloat64Array()     ## lock_time_s; 0 = no lock needed
var burst_n: PackedInt32Array = PackedInt32Array()        ## rounds per burst window; 0 = no bursts
var burst_s: PackedFloat64Array = PackedFloat64Array()    ## burst_interval_s
var shot_s: PackedFloat64Array = PackedFloat64Array()     ## 1 / rof inside a burst
var salvo: PackedInt32Array = PackedInt32Array()          ## projectiles per salvo, >= 1
var cost: PackedInt32Array = PackedInt32Array()           ## ammo_per_shot, >= 1
var spread: PackedFloat64Array = PackedFloat64Array()     ## spread_deg
var range2: PackedFloat64Array = PackedFloat64Array()     ## range_m squared
var cone: PackedFloat64Array = PackedFloat64Array()       ## lock cone half-angle cosine (cone_cos)
var bound: Array[ResolvedDefs] = []                       ## per owner: the ResolvedDefs the rows were copied from
# By projectile local index:
var p_speed: PackedFloat64Array = PackedFloat64Array()
var p_life: PackedFloat64Array = PackedFloat64Array()
var p_eject: PackedFloat64Array = PackedFloat64Array()


## Ship primary / secondary, ground unit weapon, tower weapon and target kinds of every def in `c`.
func _init(c: ContentSet) -> void:
	var nw: int = c.weapons.size()
	var e: int = w_kind.resize(nw) | w_proj.resize(nw)
	e |= prim.resize(DefRanges.WEAPON_BASE) | sec.resize(DefRanges.WEAPON_BASE) | mask.resize(DefRanges.WEAPON_BASE)
	e |= tower.resize(DefRanges.WEAPON_BASE)
	assert(e == OK)
	prim.fill(-1)
	sec.fill(-1)
	mask.fill(ALL_KINDS)
	tower.fill(0)
	for i: int in nw:
		var w: WeaponDef = c.weapons[i]
		w_kind[i] = _kind_of(w.kind)
		var pd: int = c.projectile_index.get(w.projectile, -1)
		w_proj[i] = pd - DefRanges.PROJECTILE_BASE if pd >= 0 else -1
	weapon_count = nw
	var rows: int = (WorldDefs.NEUTRAL + 1) * nw
	e = interval.resize(rows) | lock_s.resize(rows) | burst_n.resize(rows) | burst_s.resize(rows) | shot_s.resize(rows)
	e |= salvo.resize(rows) | cost.resize(rows) | spread.resize(rows) | range2.resize(rows) | cone.resize(rows)
	var np: int = c.projectiles.size()
	e |= p_speed.resize(np) | p_life.resize(np) | p_eject.resize(np)
	assert(e == OK)
	var _b: int = bound.resize(WorldDefs.NEUTRAL + 1)
	for i: int in np:
		p_speed[i] = c.projectiles[i].speed_mps
		p_life[i] = c.projectiles[i].lifetime_s
		p_eject[i] = c.projectiles[i].eject_down_mps
	for i: int in c.ships.size():
		prim[DefRanges.SHIP_BASE + i] = _wl(c, c.ships[i].primary_weapon)
		sec[DefRanges.SHIP_BASE + i] = _wl(c, c.ships[i].secondary_weapon)
	for i: int in c.ground_units.size():
		prim[DefRanges.GROUND_BASE + i] = _wl(c, c.ground_units[i].weapon)
	for i: int in c.structures.size():
		var sd: StructureDef = c.structures[i]
		if sd.is_tower():
			var d: int = DefRanges.STRUCTURE_BASE + i
			prim[d] = _wl(c, StringName(str(sd.tower.get("weapon", ""))))
			tower[d] = 1
			mask[d] = _kinds_mask(sd.tower.get("target_kinds", []))


## Copies owner `o`'s resolved weapon numbers into the rows; false (nothing done) when `r` is already bound.
func bind(o: int, r: ResolvedDefs) -> bool:
	if bound[o] == r:
		return false
	bound[o] = r
	for wi: int in weapon_count:
		var w: WeaponDef = r.weapons[wi]
		var k: int = o * weapon_count + wi
		interval[k] = w.reload_s if w.reload_s > 0.0 else (1.0 / w.rof if w.rof > 0.0 else 0.0)
		lock_s[k] = w.lock_time_s
		burst_n[k] = w.burst if w.burst_interval_s > 0.0 and w.rof > 0.0 else 0
		burst_s[k] = w.burst_interval_s
		shot_s[k] = 1.0 / w.rof if w.rof > 0.0 else 0.0
		salvo[k] = maxi(w.salvo, 1)
		cost[k] = maxi(w.ammo_per_shot, 1)
		spread[k] = w.spread_deg
		range2[k] = w.range_m * w.range_m
		cone[k] = cone_cos(w.lock_cone_deg)
	return true


## Muzzle direction: `fwd` turned by two uniform `dice.range_f` draws in [-spread, spread] degrees about `up` and
## `right` (no draw when `spread_deg` is 0).
static func aim(fwd: Vector3, up: Vector3, spread_deg: float, dice: Rng) -> Vector3:
	if spread_deg <= 0.0:
		return fwd
	var a: float = deg_to_rad(spread_deg)
	var yaw: float = dice.range_f(-a, a)
	var pitch: float = dice.range_f(-a, a)
	var right: Vector3 = fwd.cross(up)
	var d: Vector3 = fwd.rotated(up, yaw)
	return d.rotated(right, pitch).normalized() if right.length_squared() > 0.0 else d


## Flak timed fuse in ticks after the fire tick: closest approach of a straight shell to a constant-velocity target
## (`rel_p`, `rel_v` = target minus shell) plus `delay_s`, clamped to [arm_s, lifetime_s - 1 tick]; the end of life
## when the approach is behind or the relative velocity is zero.
static func fuse_ticks(rel_p: Vector3, rel_v: Vector3, pd: ProjectileDef, hz: int, delay_s: float) -> int:
	var k_max: int = maxi(floori(pd.lifetime_s * float(hz)) - 1, 1)
	var k_min: int = clampi(ceili(pd.arm_s * float(hz)), 1, k_max)
	var vv: float = rel_v.length_squared()
	var tc: float = -rel_p.dot(rel_v) / vv if vv > 0.0 else 0.0
	return clampi(roundi((tc + delay_s) * float(hz)), k_min, k_max) if tc > 0.0 else k_max


## Half-angle cosine of a lock cone given as its full apex angle; 0 or a full turn (360) means no cone limit (-1).
static func cone_cos(cone_deg: float) -> float:
	var half: float = deg_to_rad(cone_deg) * 0.5
	if half <= 0.0 or half >= PI:
		return -1.0
	return cos(half)


static func _wl(c: ContentSet, id: StringName) -> int:
	var d: int = c.weapon_index.get(id, -1) if id != &"" else -1
	return d - DefRanges.WEAPON_BASE if d >= 0 else -1


static func _kinds_mask(kinds: Variant) -> int:
	var m: int = 0
	if typeof(kinds) == TYPE_ARRAY:
		var a: Array = kinds
		for k: Variant in a:
			match str(k):
				"ship":
					m |= Spatial.MASK_SHIP
				"ground":
					m |= Spatial.MASK_GROUND
				"structure":
					m |= Spatial.MASK_STRUCTURE
	return m if m != 0 else ALL_KINDS


static func _kind_of(weapon_kind: StringName) -> int:
	match weapon_kind:
		&"bomb":
			return ProjectileStore.BOMB
		&"rocket":
			return ProjectileStore.ROCKET
		&"flak":
			return ProjectileStore.FLAK
		&"rail":
			return ProjectileStore.RAIL
		&"artillery":
			return ProjectileStore.SIEGE_SHELL
	return ProjectileStore.SLUG
