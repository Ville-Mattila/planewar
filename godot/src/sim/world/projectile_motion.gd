class_name ProjectileMotion extends RefCounted
## Tick-order step 6 (03 s3.4, s5.4; R0 B.5): moves every live projectile once. Straight kinds (slugs, flak, rail:
## no gravity, no transport) take `p += v * dt` inline, the same expression as `Kinematics.step_projectile`'s
## straight branch; ballistic and guided kinds go through `Kinematics.step_projectile` with this object's one reused
## `ProjectileState` scratch (R0 B.9 A-12, TA-43). Guided projectiles (F_GUIDED) re-aim toward a live `target` within
## the firing weapon's `turn_rate_dps` before the step (lock-cone loss is Combat's). `prev_pos` keeps the
## pre-step position for the sweeps of step 8; `ttl` counts down and an expired projectile is freed here (its fuse
## effect is Combat's). Lane-internal (not a cross-lane type).

var _store: EntityStore
var _proj: ProjectileStore
var _defs: WorldDefs
var _scratch: ProjectileState = ProjectileState.new()
var _expired: PackedInt32Array = PackedInt32Array()
var terrain: Terrain = null   ## GD-09: the AGL of a locked target (SimWorld wires it; null = no AGL rule)


func _init(store: EntityStore, projectiles: ProjectileStore, defs: WorldDefs) -> void:
	_store = store
	_proj = projectiles
	_defs = defs


## Steps every live projectile by `dt` at `tick`; frees the ones whose ttl ran out.
func step(tick: int, dt: float) -> void:
	var pos: PackedVector3Array = _proj.pos
	var vel: PackedVector3Array = _proj.vel
	var prev: PackedVector3Array = _proj.prev_pos
	var ttl: PackedFloat32Array = _proj.ttl
	var pdef: PackedByteArray = _proj.projectile_def
	var straight: PackedByteArray = _defs.straight
	var defs: Array[ProjectileDef] = _defs.content.projectiles
	var rules: RulesDef = _defs.rules
	var _r: int = _expired.resize(0)
	for i: int in _proj.live:
		var p: Vector3 = pos[i]
		prev[i] = p
		var d: int = pdef[i]
		if straight[d] != 0:
			pos[i] = p + vel[i] * dt
		else:
			var v: Vector3 = vel[i]
			if (_proj.flags[i] & ProjectileStore.F_GUIDED) != 0:
				_lock_check(i, p, d, dt)
			if (_proj.flags[i] & ProjectileStore.F_GUIDED) != 0:
				v = _reaim(i, p, v, dt)
			var st: ProjectileState = Kinematics.step_projectile(p, v, defs[d], rules, dt, _scratch)
			pos[i] = st.p
			vel[i] = st.v
		var t: float = ttl[i] - dt
		ttl[i] = t
		if t <= 0.0:
			var _a: bool = _expired.push_back(i)
	_proj.pos = pos
	_proj.vel = vel
	_proj.prev_pos = prev
	_proj.ttl = ttl
	for i: int in _expired:
		var _f: bool = _proj.free_slot(i, tick)


# In-flight lock loss (02 s4.4, GD-09): a guided shot loses its target for good, flying straight to the end of its life,
# when a flying ship target is under the shot's `lock_break_agl_m` AGL, or when the target starts a flip this tick while the shot is
# between `lock_break_flip_min_m` and `lock_break_flip_max_m` away. Deterministic, no dice; the windows are projectile defs.
func _lock_check(i: int, p: Vector3, d: int, dt: float) -> void:
	var t: int = _proj.target[i]
	if t == 0 or not _store.alive(t):
		return
	var ts: int = EntityId.slot(t)
	var tp: Vector3 = _store.pos[ts]
	var hit: bool = false
	var agl_min: float = _defs.lock_break_agl[d]
	if agl_min > 0.0 and terrain != null and _flying_ship(ts):
		var r: float = tp.length()
		hit = r - Sphere.PLANET_RADIUS - terrain.height_at(tp / r) < agl_min
	var far: float = _defs.lock_break_flip_max[d]
	if not hit and far > 0.0 and _flip_started(ts, dt):
		var dist: float = p.distance_to(tp)
		hit = dist >= _defs.lock_break_flip_min[d] and dist <= far
	if hit:
		_proj.target[i] = 0
		_proj.flags[i] = _proj.flags[i] & ~ProjectileStore.F_GUIDED


# Ships in the air only: ground units and structures sit on the datum (AGL 0) and a landed ship is a target at rest.
func _flying_ship(ts: int) -> bool:
	return _store.kind[ts] == EntityStore.K_SHIP and (_store.flags[ts] & EntityStore.F_LANDED) == 0


# Whether ship slot `ts` began a flip in step 5 of this tick: its timer is within one tick of the full duration.
func _flip_started(ts: int, dt: float) -> bool:
	var ft: float = _store.flip_time[ts]
	if ft <= 0.0 or _store.kind[ts] != EntityStore.K_SHIP:
		return false
	var def: ShipDef = _defs.ship(_store.owner[ts], _store.def_id[ts])
	return def != null and ft > def.flip_duration_s - (dt + 0.5 * dt)


# Turns v toward the live target by at most the weapon's turn rate this tick; speed unchanged.
func _reaim(i: int, p: Vector3, v: Vector3, dt: float) -> Vector3:
	var t: int = _proj.target[i]
	if not _store.alive(t):
		return v
	var to: Vector3 = _store.pos[EntityId.slot(t)] - p
	var speed: float = v.length()
	if speed <= 0.0 or to.length_squared() <= 0.0:
		return v
	var cur: Vector3 = v / speed
	var want: Vector3 = to.normalized()
	var ang: float = cur.angle_to(want)
	var w: int = _proj.weapon_def[i]
	var lim: float = _defs.turn_rad_per_s[w] * dt if w < _defs.turn_rad_per_s.size() else 0.0
	if ang <= lim:
		return want * speed
	var axis: Vector3 = cur.cross(want)
	if axis.length_squared() <= 0.0:
		return v
	return cur.rotated(axis.normalized(), lim) * speed
