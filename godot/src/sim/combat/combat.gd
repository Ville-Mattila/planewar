class_name Combat extends RefCounted
## Tick-order step 9 damage (02 s4.3, GD-08). `step(tick)` reads the Contact records of step 8 and applies, in
## contact order: gun and rail slugs and rockets (the rolled damage to the entity hit, times the structure / ground
## multiplier), bombs, flak and siege shells (`Blast`), and ramming (rule 7). A consumed projectile is freed. Zero-HP
## entities are marked for the deferred free; the caller resolves deaths afterwards. Weapons are the owner's
## doctrine-resolved defs, so doctrine factors are already inside `damage_min` / `damage_max` and never applied twice.
## The only random draw is `roll_gun_damage` on the `dice` passed in (= SimWorld.rng, S7; Combat owns no Rng), one draw per hit with a damage range,
## in contact order. Weapon fire, fuse timing, shield domes (GD-10) and terrain / landing damage are not here.

var _store: EntityStore
var _proj: ProjectileStore
var _collision: Collision
var _defs: WorldDefs
var _sink: DamageSink
var _blast: Blast


func _init(store: EntityStore, projectiles: ProjectileStore, collision: Collision, spatial: Spatial, defs: WorldDefs,
		rules: MatchRules, events: SimEvents, applier: CommandApplier) -> void:
	_store = store
	_proj = projectiles
	_collision = collision
	_defs = defs
	_sink = DamageSink.new(store, events, applier, defs)
	_blast = Blast.new(store, spatial, defs, _sink, rules, events)
	_blast.friendly_fire = rules.friendly_fire


## Applies every HIT, GROUND and RAM contact of the last Collision.step to the world.
func step(tick: int, dice: Rng) -> void:
	for k: int in _collision.contact_count:
		var kind: int = _collision.c_kind[k]
		if kind <= Collision.C_GROUND:
			_projectile(k, tick, dice)
		elif kind == Collision.C_RAM:
			_ram(_collision.c_a[k], _collision.c_b[k], tick)


## 02 s4.3 rule 1: `rng.range_i(damage_min, damage_max)` (no draw when the range is a point), times
## `structure_mult` vs structures or `ground_mult` vs ground units (`target_kind` is an EntityStore.K_*), times
## `extra_mult`, rounded, minimum 1. `dice` is `SimWorld.rng` (S7). `w` is the owner's doctrine-resolved def.
static func roll_gun_damage(w: WeaponDef, target_kind: int, dice: Rng, extra_mult: float = 1.0) -> int:
	var m: float = extra_mult
	if target_kind == EntityStore.K_STRUCTURE:
		m *= w.structure_mult
	elif target_kind == EntityStore.K_GROUND:
		m *= w.ground_mult
	return maxi(roundi(float(dice.range_i(w.damage_min, w.damage_max)) * m), 1)


## Bomb detonation at `pos` for `owner_team` (rules 2-3), as the fuse would fire it; `w` is the bomb weapon, `p`
## its projectile def (the blast radii), `dice` the world's Rng.
func detonate_bomb(pos: Vector3, owner_team: int, w: WeaponDef, p: ProjectileDef, attacker: int, tick: int,
		dice: Rng) -> void:
	_blast.bomb(pos, owner_team, attacker, w, p, dice, tick)


func _projectile(k: int, tick: int, dice: Rng) -> void:
	var pid: int = _collision.c_a[k]
	if not _proj.alive(pid):
		return
	var i: int = _proj.index_of(pid)
	var pd: ProjectileDef = _defs.content.projectiles[_proj.projectile_def[i]]
	var hit: bool = _collision.c_kind[k] == Collision.C_HIT
	if hit and not _armed(i, pd):
		return                                           # a fuse not yet armed: the projectile flies on
	var res: ResolvedDefs = _defs.resolved(_proj.owner[i])
	var wi: int = _proj.weapon_def[i]
	if wi < res.weapons.size():
		var w: WeaponDef = res.weapons[wi]
		var at: Vector3 = _collision.c_point[k]
		var team: int = _proj.team[i]
		var by: int = _proj.shooter[i]
		match _proj.kind[i]:
			ProjectileStore.BOMB:
				_blast.bomb(at, team, by, w, pd, dice, tick)
			ProjectileStore.FLAK:
				_blast.flak(at, team, by, w, pd, dice, tick)
			ProjectileStore.SIEGE_SHELL:
				_blast.shell(at, team, by, w, pd, dice, tick)
			_:
				if hit:
					_direct(_collision.c_b[k], w, by, _proj.kind[i] == ProjectileStore.ROCKET, tick, dice)
	var _f: bool = _proj.free_slot(i, tick)


# Slugs, rail slugs and rockets: the rolled damage to the one entity hit. A rocket cannot hurt a ship docked in a
# Hangar of an owner whose doctrine sets `hangar_blocks_rockets` (02 s4.3 rule 2, Bulwark).
func _direct(target: int, w: WeaponDef, attacker: int, rocket: bool, tick: int, dice: Rng) -> void:
	if not _store.alive(target):
		return
	var s: int = EntityId.slot(target)
	if rocket and _blast.hangar_docked(s) and _defs.resolved(_store.owner[s]).hangar_blocks_rockets:
		return
	var _h: bool = _sink.damage(s, float(roll_gun_damage(w, _store.kind[s], dice)), attacker, tick)


# Rule 7: ship-ship contact destroys both; ship-structure destroys the ship and deals its remaining HP to the
# structure. Teams are ignored (rule 8).
func _ram(ship: int, other: int, tick: int) -> void:
	if not _store.alive(ship) or not _store.alive(other):
		return
	var a: int = EntityId.slot(ship)
	var b: int = EntityId.slot(other)
	if not _sink.standing(a) or not _sink.standing(b):
		return
	if _store.kind[b] == EntityStore.K_SHIP:
		var _x: bool = _sink.destroy(a, other, tick)
		var _y: bool = _sink.destroy(b, ship, tick)
	else:
		var remaining: float = _store.hp[a]
		var _z: bool = _sink.destroy(a, other, tick)
		var _w: bool = _sink.damage(b, remaining, ship, tick)


# Armed once `arm_s` of life has passed (age = lifetime - ttl) or F_ARMED is set (02 s4.2).
func _armed(i: int, pd: ProjectileDef) -> bool:
	return pd.arm_s <= 0.0 or (_proj.flags[i] & ProjectileStore.F_ARMED) != 0 \
		or pd.lifetime_s - _proj.ttl[i] >= pd.arm_s

