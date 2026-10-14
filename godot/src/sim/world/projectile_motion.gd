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
