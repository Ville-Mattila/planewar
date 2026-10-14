class_name AimSolver extends RefCounted
## Straight-line intercept for slugs, flak shells and rail slugs (05 s6.2 ENGAGE, s6.8; R0 C1-03, C2-11). Static and pure.
## The projectile flies a straight world-frame line with no gravity and no transport, launched at the shooter's velocity
## plus `speed` along the aim direction, so with `r = p_t - p_s` and `u = v_t - v_s` the flight time solves
## `|r + u t| = speed t`, an exact quadratic (05 asks for two fixed-point iterations; the closed form is their limit).
## `ui/hud/lead_solver.gd` iterates the same equation for the pip; `test_aim_solver` checks the two agree.

const NONE: float = INF


## Smallest positive flight time to the lead point, or `NONE` when the target outruns the projectile.
static func intercept_time(r: Vector3, u: Vector3, speed: float) -> float:
	if speed <= 0.0:
		return NONE
	var a: float = u.length_squared() - speed * speed
	var b: float = r.dot(u)
	var c: float = r.length_squared()
	if c <= 0.0:
		return 0.0
	if is_zero_approx(a):
		return -c / (2.0 * b) if b < 0.0 else NONE
	var disc: float = b * b - a * c
	if disc < 0.0:
		return NONE
	var sq: float = sqrt(disc)
	var t1: float = (-b - sq) / a
	var t2: float = (-b + sq) / a
	var lo: float = minf(t1, t2)
	var hi: float = maxf(t1, t2)
	if lo > 0.0:
		return lo
	return hi if hi > 0.0 else NONE


## World lead point `p_t + (v_t - v_s) t`; the target's own position when no solution exists.
static func lead_point(p_s: Vector3, v_s: Vector3, p_t: Vector3, v_t: Vector3, speed: float) -> Vector3:
	var t: float = intercept_time(p_t - p_s, v_t - v_s, speed)
	return p_t if is_inf(t) else p_t + (v_t - v_s) * t


## Unit aim direction from the muzzle (the shell inherits `v_s`); ZERO when there is no solution or no range.
static func aim_dir(p_s: Vector3, v_s: Vector3, p_t: Vector3, v_t: Vector3, speed: float) -> Vector3:
	var t: float = intercept_time(p_t - p_s, v_t - v_s, speed)
	if is_inf(t):
		return Vector3.ZERO
	var d: Vector3 = p_t - p_s + (v_t - v_s) * t
	return d.normalized() if d.length_squared() > 0.0 else Vector3.ZERO


## Flak: seconds after firing at which the timed fuse bursts, the intercept time plus `delay_s` (02 s4.2), clamped to
## [`arm_s`, `lifetime_s`]; `lifetime_s` when there is no solution (burst at the end of life, as `FireTables.fuse_ticks`).
static func fuse_time(r: Vector3, u: Vector3, speed: float, delay_s: float, arm_s: float, lifetime_s: float) -> float:
	var t: float = intercept_time(r, u, speed)
	return lifetime_s if is_inf(t) else clampf(t + delay_s, arm_s, lifetime_s)


## True when `nose` (unit) is within `atan(cone_k * radius / dist)` of the aim direction `aim` (unit): the 05 s6.2 fire cone.
static func in_fire_cone(nose: Vector3, aim: Vector3, cone_k: float, target_radius: float, dist: float) -> bool:
	if dist <= 0.0 or aim == Vector3.ZERO:
		return false
	return nose.angle_to(aim) < atan(cone_k * target_radius / dist)
