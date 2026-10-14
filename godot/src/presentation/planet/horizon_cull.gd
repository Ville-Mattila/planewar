class_name HorizonCull extends RefCounted
## Conservative horizon test for a chunk bounding sphere (03 s7.5). The horizon sphere is R + RELIEF_MIN and
## the angle a +RELIEF_MAX peak can poke over it (theta_up) is added, so nothing that could be visible is
## culled. Per camera: `horizon_angle(cam)` once; per node: `is_culled_angle(...)` (one asin, one cos).


## Radius of the horizon sphere, R + RELIEF_MIN.
static func r_low() -> float:
	return Sphere.PLANET_RADIUS + Sphere.RELIEF_MIN


## theta_up = acos(R_low / (R + RELIEF_MAX)): 0.2 rad at R = 6,000.
static func theta_up() -> float:
	return acos(r_low() / (Sphere.PLANET_RADIUS + Sphere.RELIEF_MAX))


## theta_h + theta_up for a camera at `cam`; PI (never cull) when the camera is inside the horizon sphere.
static func horizon_angle(cam: Vector3) -> float:
	var dist: float = cam.length()
	if dist <= r_low():
		return PI
	return acos(r_low() / dist) + theta_up()


## True when the sphere (center, radius) lies entirely beyond the horizon seen from `cam_dir` (unit):
## theta_c - theta_r > theta_h + theta_up.
static func is_culled_angle(cam_dir: Vector3, horizon: float, center: Vector3, radius: float) -> bool:
	var c_len: float = center.length()
	if c_len <= radius:
		return false
	var limit: float = horizon + asin(radius / c_len)
	if limit >= PI:
		return false
	return cam_dir.dot(center / c_len) < cos(limit)


## Convenience form of the test for one node (tests and tools).
static func is_culled(cam: Vector3, center: Vector3, radius: float) -> bool:
	return is_culled_angle(cam.normalized(), horizon_angle(cam), center, radius)
