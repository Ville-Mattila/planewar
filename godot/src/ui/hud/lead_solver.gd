class_name LeadSolver extends RefCounted
## Straight-line intercept for slugs (docs/06 s6.3, R0 C2-11): no gravity term, no transport.
## The slug carries the shooter's velocity, so the target moves by (v_t - v_s) relative to the muzzle.
## Iteration count comes from res://content/ui/hud.json.


## Time of flight in seconds to the lead point, or INF when no positive-speed solution exists.
static func lead_time(p_s: Vector3, v_s: Vector3, p_t: Vector3, v_t: Vector3, speed: float) -> float:
	if speed <= 0.0:
		return INF
	var rel: Vector3 = v_t - v_s
	var t: float = p_t.distance_to(p_s) / speed
	var n: int = int(HudMath.param("lead_iterations"))
	for _i: int in n:
		t = (p_t + rel * t).distance_to(p_s) / speed
	return t


## World-frame lead point (where the target is when the slug arrives).
static func lead_point(p_s: Vector3, v_s: Vector3, p_t: Vector3, v_t: Vector3, speed: float) -> Vector3:
	var t: float = lead_time(p_s, v_s, p_t, v_t, speed)
	if is_inf(t):
		return p_t
	return p_t + (v_t - v_s) * t


## True when the pip may be shown: a solution exists and the flight time fits the slug range (range_m / speed).
static func pip_visible(p_s: Vector3, v_s: Vector3, p_t: Vector3, v_t: Vector3, speed: float, range_m: float) -> bool:
	if speed <= 0.0:
		return false
	var t: float = lead_time(p_s, v_s, p_t, v_t, speed)
	return not is_inf(t) and t <= range_m / speed


## Unit aim direction (muzzle frame, add nothing: the slug inherits v_s) toward the lead point.
static func aim_dir(p_s: Vector3, v_s: Vector3, p_t: Vector3, v_t: Vector3, speed: float) -> Vector3:
	var d: Vector3 = lead_point(p_s, v_s, p_t, v_t, speed) - p_s
	return d.normalized() if d.length_squared() > 0.0 else Vector3.ZERO
