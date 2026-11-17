class_name SiegeAim extends RefCounted
## The Siege Crawler's geometry (AI-18, 05 s6.7), static and pure (no state outside the arguments; `st` is caller
## scratch). `loft` is the lofted solve R0 B.25 A-74 gives the Crawler brain: the low-arc barrel elevation that lands a
## siege shell on a point, flown by `Ballistics.predict_impact` (terrain on the way, CF transport, gravity). `ring_point`
## and `heading_error` are the firing-spot ring and the in-place traverse of the brain.


## The low-arc elevation in radians above the local horizontal at the muzzle `p` that lands a shell fired at `speed` m/s
## toward `aim` within `tol_m` of it along the great circle. Start: the flat vacuum angle 0.5 asin(g d / v^2); then
## secant steps on the along-track miss, at most `iters` more `predict_impact` calls of at most `max_steps` steps of `dt`.
## NAN when `aim` is beyond reach (g d >= v^2), the shell finds no impact (a ridge, the horizon) or the miss stays above
## `tol_m`.
static func loft(p: Vector3, aim: Vector3, speed: float, def: ProjectileDef, rules: RulesDef, terrain: Terrain,
		dt: float, max_steps: int, iters: int, tol_m: float, st: ProjectileState) -> float:
	var n: Vector3 = p.normalized()
	var h: Vector3 = tangent_to(p, aim)
	if h == Vector3.ZERO or speed <= 0.0:
		return NAN
	var want: float = arc(n, aim)
	var s: float = rules.gravity * want / (speed * speed)
	if s >= 1.0:
		return NAN
	var e0: float = 0.5 * asin(maxf(s, 0.0))
	var m0: float = _miss(p, n, h, e0, speed, want, def, rules, terrain, dt, max_steps, st)
	if absf(m0) <= tol_m:
		return e0
	var e1: float = e0 + (0.02 if m0 < 0.0 else -0.02)
	for _i: int in iters:
		var m1: float = _miss(p, n, h, e1, speed, want, def, rules, terrain, dt, max_steps, st)
		if absf(m1) <= tol_m:
			return e1
		if is_inf(m1) or is_inf(m0) or is_equal_approx(m1, m0):
			return NAN
		var e2: float = clampf(e1 - m1 * (e1 - e0) / (m1 - m0), -0.25 * PI, 0.25 * PI)
		e0 = e1
		m0 = m1
		e1 = e2
	return NAN


## Unit tangent at `p` toward `q` (the great-circle heading), ZERO when `q` is straight above or below `p`.
static func tangent_to(p: Vector3, q: Vector3) -> Vector3:
	var n: Vector3 = p.normalized()
	var d: Vector3 = q - p
	var t: Vector3 = d - n * d.dot(n)
	return t.normalized() if not t.is_zero_approx() else Vector3.ZERO


## Great-circle distance on the datum sphere from radial `n` to the direction of `q`.
static func arc(n: Vector3, q: Vector3) -> float:
	return n.angle_to(q) * Sphere.PLANET_RADIUS


## The point of the ring of arc radius `radius_m` round the surface direction `centre_n` at bearing `bearing` (a unit
## tangent at the centre) turned by `turn` radians about the centre (+ = counter-clockwise seen from above); a unit
## direction (the caller snaps it to the terrain).
static func ring_point(centre_n: Vector3, bearing: Vector3, turn: float, radius_m: float) -> Vector3:
	var b: Vector3 = Quaternion(centre_n, turn) * bearing
	var a: float = radius_m / Sphere.PLANET_RADIUS
	return (centre_n * cos(a) + b * sin(a)).normalized()


## Signed angle (radians, + = the target is to the left, the ground `yaw` sign) from heading `fwd` to the great-circle
## heading from `p` to `q`, about the local vertical.
static func heading_error(p: Vector3, fwd: Vector3, q: Vector3) -> float:
	var n: Vector3 = p.normalized()
	var t: Vector3 = q - p
	t -= n * t.dot(n)
	if t.is_zero_approx():
		return 0.0
	return atan2(fwd.cross(t).dot(n), fwd.dot(t))


# Signed along-track miss (impact arc - `want`) of a shell fired at elevation `e` along heading `h`; -INF without impact.
static func _miss(p: Vector3, n: Vector3, h: Vector3, e: float, speed: float, want: float, def: ProjectileDef,
		rules: RulesDef, terrain: Terrain, dt: float, max_steps: int, st: ProjectileState) -> float:
	var v: Vector3 = (h * cos(e) + n * sin(e)) * speed
	var r: Vector4 = Ballistics.predict_impact(p, v, def, rules, terrain, dt, dt, 0.0, max_steps, st)
	if not Ballistics.has_impact(r):
		return -INF
	return arc(n, Vector3(r.x, r.y, r.z)) - want
