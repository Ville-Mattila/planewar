class_name Ballistics extends RefCounted
## Bomb and siege-shell impact prediction (05 s6.3.1, R0 C1-03). Static and pure: it only reads its arguments (S8).
## `predict_impact` integrates with the sim's own `Kinematics.step_projectile` (CF transport, gravity) so the autopilot,
## the HUD bomb sight and the "Bomb release" assist see the same fall; `flat_impact` is the closed-form local-flat
## refinement used between thinks. Only ballistic kinds need this; every gun, flak and rail solver is `AimSolver`.

const NO_IMPACT: Vector4 = Vector4(NAN, NAN, NAN, NAN)


static func has_impact(r: Vector4) -> bool:
	return not is_nan(r.w)


## Impact of a projectile released at `p` by a carrier moving at `v`: the release velocity is `v - n * def.eject_down_mps`
## (bombs; siege shells carry `eject_down_mps` 0 and pass their muzzle velocity as `v`). Stops where the sim's ground test
## fires (altitude < height + radius, `Collision._ground`) and interpolates inside the crossing step. Steps are `dt_far`
## while the clearance is above `near_m` and `dt` below it; a coarse step that would cross the ground is discarded and
## retried fine. The integrator's truncation error grows with the step (about 2 m at the sim's 2-tick step, 11 m at 0.25 s
## for an 800 m fall at 250 m/s; a velocity offset that cancels it for flat gravity fails once transport matters), so a
## caller that needs the 3 m figure passes `dt_far` = `dt`; a far-planning caller trades error for cost. At most `max_steps` steps in total. `st` is the caller's
## scratch (steer pattern: nothing allocated here). Result: xyz impact point, w time of flight; `NO_IMPACT` past the horizon.
static func predict_impact(p: Vector3, v: Vector3, def: ProjectileDef, rules: RulesDef, terrain: Terrain,
		dt: float, dt_far: float, near_m: float, max_steps: int, st: ProjectileState) -> Vector4:
	var q: Vector3 = p
	var w: Vector3 = v - p.normalized() * def.eject_down_mps
	var a: float = _clearance(terrain, q, def.radius_m)
	if a <= 0.0:
		return Vector4(q.x, q.y, q.z, 0.0)
	var t: float = 0.0
	var fine: bool = a <= near_m
	for _i: int in max_steps:
		var h: float = dt if fine else dt_far
		var _s: ProjectileState = Kinematics.step_projectile(q, w, def, rules, h, st)
		var b: float = _clearance(terrain, st.p, def.radius_m)
		if b <= 0.0:
			if not fine:
				fine = true                          # retry this stretch with the fine step
				continue
			var f: float = clampf(a / (a - b), 0.0, 1.0)
			var pt: Vector3 = q.lerp(st.p, f)
			return Vector4(pt.x, pt.y, pt.z, t + f * h)
		q = st.p
		w = st.v
		a = b
		t += h
		fine = fine or a <= near_m
	return NO_IMPACT


## Closed-form local-flat impact: constant gravity along the local vertical at `p`, ground at `ground_alt_m` above the
## datum (+ the projectile radius), horizontal velocity constant. No terrain sampling, no loop. Same release rule as above.
## Over a whole fall it ignores the curvature of a 6 km moon (hundreds of metres), so use it only through `shift_impact`.
static func flat_impact(p: Vector3, v: Vector3, def: ProjectileDef, rules: RulesDef, ground_alt_m: float) -> Vector4:
	var n: Vector3 = p.normalized()
	var w: Vector3 = v - n * def.eject_down_mps
	var h: float = p.length() - Sphere.PLANET_RADIUS - ground_alt_m - def.radius_m
	if h <= 0.0:
		return Vector4(p.x, p.y, p.z, 0.0)
	var vz: float = w.dot(n)
	var g: float = rules.gravity
	var t: float = 0.0
	if not is_zero_approx(g):
		t = (vz + sqrt(vz * vz + 2.0 * g * h)) / g
	elif vz < 0.0:
		t = h / -vz
	else:
		return NO_IMPACT
	var pt: Vector3 = p + (w - n * vz) * t
	pt = pt.normalized() * (Sphere.PLANET_RADIUS + ground_alt_m + def.radius_m)
	return Vector4(pt.x, pt.y, pt.z, t)


## The between-thinks refinement: the cached stepped impact `cached` (computed at the think from `p0`, `v0`) moved by the
## change of the closed form between that state and the current `p`, `v`. The curvature error cancels in the difference.
static func shift_impact(cached: Vector4, p0: Vector3, v0: Vector3, p: Vector3, v: Vector3, def: ProjectileDef,
		rules: RulesDef, ground_alt_m: float) -> Vector4:
	if not has_impact(cached):
		return cached
	var then: Vector4 = flat_impact(p0, v0, def, rules, ground_alt_m)
	var now: Vector4 = flat_impact(p, v, def, rules, ground_alt_m)
	if not has_impact(then) or not has_impact(now):
		return cached
	var d: Vector4 = now - then
	return Vector4(cached.x + d.x, cached.y + d.y, cached.z + d.z, maxf(cached.w + d.w, 0.0))


# Height of `q` above the sim's ground-contact surface (collision 8b): altitude - (terrain height + radius).
# One height sample per call: a bomb is nearly always inside the relief band, so the sim's relief prefilter would not pay.
static func _clearance(terrain: Terrain, q: Vector3, radius: float) -> float:
	return q.length() - Sphere.PLANET_RADIUS - terrain.height_at(q) - radius
