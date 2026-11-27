class_name SiegeAim extends RefCounted
## The Siege Crawler's geometry (AI-18, 05 s6.7), static and pure (no state outside the arguments; `st` is caller
## scratch). `loft` is the lofted solve R0 B.25 A-74 gives the Crawler brain: the low-arc barrel elevation that lands a
## siege shell on a point, flown by `Ballistics.predict_impact` (terrain on the way, CF transport, gravity). `ring_point`
## and `heading_error` are the firing-spot ring and the in-place traverse of the brain.


## The low-arc barrel elevation in radians above the local horizontal that lands a siege shell fired by a Crawler standing
## at `p` and facing the great-circle bearing of `aim` within `k.solve_tol_m` of `aim` along the great circle. Each trial
## flies the shell the sim spawns (sim/ground B4, sim/combat CB15; AI-18b): direction `BarrelSlew.muzzle_dir(p, h, e)`, from
## the muzzle `p + dir x k.radius`, at `k.speed`, with `Ballistics.predict_impact` (terrain on the way, CF transport,
## gravity) at the `solve_step_ticks` step for `k.max_steps` steps (the shell's lifetime). Start: the flat vacuum angle
## 0.5 asin(g d / v^2); the second point is a Newton step on the flat vacuum range slope dR/de = 2 v^2 cos(2e) / g; then
## at most `CrawlerParams.loft_iters` secant steps on the along-track miss, inside the barrel's [`barrel_lo`, `barrel_hi`]. NAN when `aim` is beyond reach (g d >= v^2), the shell finds no impact inside its lifetime
## (a ridge, the horizon, too high an arc), the solve leaves the barrel's limits or the miss stays above `solve_tol_m`.
static func loft(p: Vector3, aim: Vector3, k: CrawlerParams, terrain: Terrain, st: ProjectileState) -> float:
	var n: Vector3 = p.normalized()
	var h: Vector3 = tangent_to(p, aim)
	if h == Vector3.ZERO or k.speed <= 0.0:
		return NAN
	var want: float = arc(n, aim)
	var s: float = k.rules.gravity * want / (k.speed * k.speed)
	if s >= 1.0:
		return NAN
	var e0: float = clampf(0.5 * asin(maxf(s, 0.0)), k.barrel_lo, k.barrel_hi)
	var m0: float = _miss(p, n, h, e0, want, k, terrain, st)
	if absf(m0) <= k.solve_tol_m:
		return e0
	var slope: float = 2.0 * k.speed * k.speed * cos(2.0 * e0) / k.rules.gravity
	if is_inf(m0) or slope <= 0.0:
		return NAN                               # no impact at the vacuum angle, or past the maximum-range angle
	var e1: float = clampf(e0 - m0 / slope, k.barrel_lo, k.barrel_hi)
	for _i: int in k.loft_iters:
		var m1: float = _miss(p, n, h, e1, want, k, terrain, st)
		if absf(m1) <= k.solve_tol_m:
			return e1
		if is_inf(m1) or is_inf(m0) or is_equal_approx(m1, m0):
			return NAN
		var e2: float = clampf(e1 - m1 * (e1 - e0) / (m1 - m0), k.barrel_lo, k.barrel_hi)
		if e2 == e1:
			return NAN                           # pinned at a barrel limit and still missing
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


# Signed along-track miss (impact arc - `want`) of the shell the sim fires at elevation `e` on heading `h` (unit,
# tangent at `p`): BarrelSlew's muzzle direction and offset, no second copy of the formula. -INF without an impact.
static func _miss(p: Vector3, n: Vector3, h: Vector3, e: float, want: float, k: CrawlerParams, terrain: Terrain,
		st: ProjectileState) -> float:
	var dir: Vector3 = BarrelSlew.muzzle_dir(p, h, e)
	var step: float = float(k.solve_step_ticks) * k.dt
	var r: Vector4 = Ballistics.predict_impact(p + dir * k.radius, dir * k.speed, k.shell, k.rules, terrain, step, step,
		0.0, k.max_steps, st)
	if not Ballistics.has_impact(r):
		return -INF
	return arc(n, Vector3(r.x, r.y, r.z)) - want
