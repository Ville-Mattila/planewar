class_name BombSight extends RefCounted
## Bomb impact predictor (docs/06 s6.3). The HUD owns no physics: the caller injects
##   step:   Callable(p: Vector3, v: Vector3, dt: float) -> PackedVector3Array  # [p', v'], wraps Kinematics.step_projectile
##   ground: Callable(dir: Vector3) -> float                                   # ground radius along a unit direction
## Result is a plain Vector4 (xyz impact point, w time to impact) or NO_IMPACT when the sight is hidden.

const NO_IMPACT: Vector4 = Vector4(NAN, NAN, NAN, NAN)


static func has_impact(r: Vector4) -> bool:
	return not is_nan(r.w)


## Predicts impact from release at p with carrier velocity v; n is the local up; eject_down_mps from projectiles.json.
## dt <= 0 uses 1 / bomb_rate_hz. The crossing step is linearly interpolated to the ground radius.
static func predict(p: Vector3, v: Vector3, n: Vector3, eject_down_mps: float, step: Callable, ground: Callable,
		dt: float = 0.0) -> Vector4:
	var h: float = dt if dt > 0.0 else 1.0 / HudMath.param("bomb_rate_hz")
	var steps: int = int(roundf(HudMath.param("bomb_horizon_s") / h))
	var q: Vector3 = p
	var w: Vector3 = v - n * eject_down_mps
	var gr0: float = _g(ground, q)
	if q.length() <= gr0:
		return Vector4(q.x, q.y, q.z, 0.0)
	for i: int in range(1, steps + 1):
		var r: PackedVector3Array = step.call(q, w, h)
		var q1: Vector3 = r[0]
		var g1: float = _g(ground, q1)
		if q1.length() <= g1:
			return _cross(q, q1, g1, _g(ground, q), i, h)
		q = q1
		w = r[1]
	return NO_IMPACT


static func _g(ground: Callable, q: Vector3) -> float:
	var r: float = ground.call(q.normalized())
	return r


static func _cross(q0: Vector3, q1: Vector3, g1: float, g0: float, i: int, h: float) -> Vector4:
	var a: float = q0.length() - g0
	var b: float = q1.length() - g1
	var f: float = 1.0 if a <= b else clampf(a / (a - b), 0.0, 1.0)
	var pt: Vector3 = q0.lerp(q1, f)
	return Vector4(pt.x, pt.y, pt.z, (float(i - 1) + f) * h)


## True when the impact is within bomb_hit_radius_m of any target position (ring turns green; feeds bomb release).
static func hit_predicted(r: Vector4, targets: PackedVector3Array) -> bool:
	if not has_impact(r):
		return false
	var pt: Vector3 = Vector3(r.x, r.y, r.z)
	var lim: float = HudMath.param("bomb_hit_radius_m")
	for t: Vector3 in targets:
		if pt.distance_squared_to(t) <= lim * lim:
			return true
	return false
