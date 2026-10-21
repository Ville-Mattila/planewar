class_name Combat extends RefCounted
## Tick-order step 9 (02 s4.3-4.4; GD-08 damage, GD-36 fire). `step(tick, dice)` runs, in order: weapon fire
## (`WeaponFire`: rate, bursts, ammo / supply draw, lock, projectile spawn), then the Contact records of step 8 in
## contact order: gun and rail slugs and rockets (the rolled damage to the entity hit, times the structure / ground
## multiplier), bombs, flak and siege shells (`Blast`), and ramming (rule 7); then the fuses of the projectiles still
## live: a rocket's proximity burst on its lock target (rule 4) and flak's timed or early burst (rule 5). A consumed
## projectile is freed. Zero-HP entities are marked for the deferred free; the caller resolves deaths afterwards.
## Weapons are the owner's doctrine-resolved defs, so doctrine factors are already inside `damage_min` / `damage_max`
## and never applied twice. Every random draw is on the `dice` passed in (= SimWorld.rng, S7; Combat owns no Rng):
## spread in fire order, then one damage roll per hit with a damage range in contact / fuse order. Shield domes
## (`shields`, GD-10) run before `step` (SimWorld calls `shields.absorb`); terrain / landing damage is not here.

var _store: EntityStore
var _proj: ProjectileStore
var _collision: Collision
var _defs: WorldDefs
var _sink: DamageSink
var _spatial: Spatial
var _friendly_fire: bool = false
var _blast: Blast
var _due: PackedInt32Array = PackedInt32Array()   ## fuse pass scratch: projectile indices bursting this tick
var fire: WeaponFire                              ## step 9 fire; GD-18 writes `fire.unsupplied`
var shields: ShieldDomes                          ## GD-10: rule 6 absorb (step 9, before `step`) and recharge (step 10)
var _fuse_r: PackedFloat32Array = PackedFloat32Array()     ## by projectile local index: fuse_radius_m
var _armed_ttl: PackedFloat64Array = PackedFloat64Array()  ## by projectile local index: ttl at or below which it is armed


func _init(store: EntityStore, projectiles: ProjectileStore, collision: Collision, spatial: Spatial, defs: WorldDefs,
		rules: MatchRules, events: SimEvents, applier: CommandApplier, inputs: InputSlots) -> void:
	_store = store
	_proj = projectiles
	_collision = collision
	_defs = defs
	_sink = DamageSink.new(store, events, applier, defs)
	_blast = Blast.new(store, spatial, defs, _sink, rules, events)
	_blast.friendly_fire = rules.friendly_fire
	_spatial = spatial
	_friendly_fire = rules.friendly_fire
	fire = WeaponFire.new(store, projectiles, inputs, defs, events, rules.tick_hz)
	shields = ShieldDomes.new(store, projectiles, defs, rules, events)
	var np: int = defs.content.projectiles.size()
	var e: int = _fuse_r.resize(np) | _armed_ttl.resize(np)
	assert(e == OK)
	for d: int in np:
		var pd: ProjectileDef = defs.content.projectiles[d]
		_fuse_r[d] = pd.fuse_radius_m
		_armed_ttl[d] = pd.lifetime_s - pd.arm_s if pd.arm_s > 0.0 else pd.lifetime_s + 1.0


## Weapon fire, then every HIT, GROUND and RAM contact of the last Collision.step, then the fuses.
func step(tick: int, dice: Rng) -> void:
	fire.step(tick, dice)
	for k: int in _collision.contact_count:
		var kind: int = _collision.c_kind[k]
		if kind <= Collision.C_GROUND:
			_projectile(k, tick, dice)
		elif kind == Collision.C_RAM:
			_ram(_collision.c_a[k], _collision.c_b[k], tick)
	_fuses(tick, dice)


## Drops the fire state (lock, supply) of a slot freed this tick; SimWorld calls it for every death.
func forget(s: int) -> void:
	fire.forget(s)


## Combat's S4 bytes: the fire state (locks, supply flags), then the shield domes; cooldowns and ammo live in EntityStore.
func write_state(buf: StreamPeerBuffer) -> void:
	fire.write_state(buf)
	shields.write_state(buf)


func read_state(buf: StreamPeerBuffer) -> bool:
	return fire.read_state(buf) and shields.read_state(buf)


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
	var hit: bool = _collision.c_kind[k] == Collision.C_HIT
	if hit and not _armed(i, _defs.content.projectiles[_proj.projectile_def[i]]):
		return                                           # a fuse not yet armed: the projectile flies on
	_detonate(i, _collision.c_point[k], _collision.c_b[k] if hit else 0, tick, dice)


# Applies projectile `i`'s effect at `at` (area kinds) or on `target` (slugs, rail, rockets; 0 = none), then frees it.
func _detonate(i: int, at: Vector3, target: int, tick: int, dice: Rng) -> void:
	var pd: ProjectileDef = _defs.content.projectiles[_proj.projectile_def[i]]
	var res: ResolvedDefs = _defs.resolved(_proj.owner[i])
	var wi: int = _proj.weapon_def[i]
	if wi < res.weapons.size():
		var w: WeaponDef = res.weapons[wi]
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
				if target != 0:
					_direct(target, w, by, _proj.kind[i] == ProjectileStore.ROCKET, tick, dice)
	var _f: bool = _proj.free_slot(i, tick)


# Fuses of the live projectiles, ascending index (a function of state, S4): an armed rocket whose sweep this tick
# passed within `fuse_radius_m` of its live lock target's bounding sphere bursts on it (rule 4); flak bursts at its
# burst tick or, armed, within `fuse_radius_m` of a hostile ship's bounding sphere (rule 5). Collected first, then
# applied, because a burst frees slots of the live list. Arming is read inline: `ttl <= armed_ttl[def]` or F_ARMED.
func _fuses(tick: int, dice: Rng) -> void:
	var _r: int = _due.resize(0)
	var kinds: PackedByteArray = _proj.kind
	var tg: PackedInt32Array = _proj.target
	var pdef: PackedByteArray = _proj.projectile_def
	var ttl: PackedFloat32Array = _proj.ttl
	var fl: PackedByteArray = _proj.flags
	for i: int in _proj.live:
		var kd: int = kinds[i]
		if kd != ProjectileStore.ROCKET and kd != ProjectileStore.FLAK:
			continue
		var t: int = tg[i]
		var d: int = pdef[i]
		var armed: bool = ttl[i] <= _armed_ttl[d] or (fl[i] & ProjectileStore.F_ARMED) != 0
		if kd == ProjectileStore.ROCKET:
			if t != 0 and armed and _fuse_r[d] > 0.0 and _rocket_near(i, t, _fuse_r[d]):
				var _a: bool = _due.push_back(i)
		elif (t != 0 and tick >= t) or (armed and _fuse_r[d] > 0.0 and _flak_near(i, _fuse_r[d])):
			var _b: bool = _due.push_back(i)
	for i: int in _due:
		var kd: int = _proj.kind[i]
		_detonate(i, _proj.pos[i], _proj.target[i] if kd == ProjectileStore.ROCKET else 0, tick, dice)


func _rocket_near(i: int, t: int, fuse_r: float) -> bool:
	if not _store.alive(t):
		return false
	var s: int = EntityId.slot(t)
	return Collision.sweep_sphere(_proj.prev_pos[i], _proj.pos[i], _store.pos[s], fuse_r + _store.radius[s]) >= 0.0


# Flak within `fuse_r` of a hostile ship (ring 1 of its hash cell, entity items only: no allocation).
func _flak_near(i: int, fuse_r: float) -> bool:
	var p: Vector3 = _proj.pos[i]
	var team: int = _proj.team[i]
	var sp: Spatial = _spatial
	var kind: PackedByteArray = _store.kind
	var tm: PackedByteArray = _store.team
	var pos: PackedVector3Array = _store.pos
	var rad: PackedFloat32Array = _store.radius
	var n: int = sp.ring_cells(Spatial.cell_of(p), 1)
	for k: int in n:
		var c: int = sp.ring[k]
		var s0: int = sp.cell_start[c]
		for m: int in sp.cell_entities[c]:
			var s: int = sp.cell_items[s0 + m]
			if kind[s] != EntityStore.K_SHIP or (tm[s] == team and not _friendly_fire):
				continue
			var r: float = fuse_r + rad[s]
			if pos[s].distance_squared_to(p) <= r * r:
				return true
	return false


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

