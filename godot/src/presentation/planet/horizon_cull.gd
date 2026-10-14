class_name HorizonCull extends RefCounted
## Conservative horizon test for a chunk bounding sphere (03 s7.5). The occluding sphere is R + RELIEF_MIN;
## a node is culled when theta_c - theta_r > theta_h + theta_up. 03 s7.5 takes theta_up for a RELIEF_MAX
## peak; the renderer passes the node's own maximum height instead (the built mesh's vertex maximum, or the
## inherited bound of an unbuilt node), which is still conservative for what is drawn and keeps the
## visible-chunk cap for chunks that can actually be seen. Per camera `horizon_angle(cam)` once; per node
## `is_culled_angle(...)` (asin, acos, cos).


## Radius of the occluding sphere, R + RELIEF_MIN.
static func r_low() -> float:
	return Sphere.PLANET_RADIUS + Sphere.RELIEF_MIN


## theta_up for a peak of height `h_max`: acos(R_low / (R + h_max)), 0 when the peak is below R_low.
static func theta_up_for(h_max: float) -> float:
	return acos(minf(1.0, r_low() / (Sphere.PLANET_RADIUS + h_max)))


## The 03 s7.5 global bound, theta_up_for(RELIEF_MAX).
static func theta_up() -> float:
	return theta_up_for(Sphere.RELIEF_MAX)


## theta_h = acos(R_low / |cam|); PI (never cull) when the camera is inside the occluding sphere.
static func horizon_angle(cam: Vector3) -> float:
	var dist: float = cam.length()
	if dist <= r_low():
		return PI
	return acos(r_low() / dist)


## True when the sphere (center, radius) whose points are at most `h_max` above the datum lies entirely
## beyond the horizon seen from `cam_dir` (unit): theta_c - theta_r > theta_h + theta_up(h_max).
static func is_culled_angle(cam_dir: Vector3, horizon: float, center: Vector3, radius: float, h_max: float) -> bool:
	var c_len: float = center.length()
	if c_len <= radius or horizon >= PI:
		return false
	var limit: float = horizon + theta_up_for(h_max) + asin(radius / c_len)
	if limit >= PI:
		return false
	return cam_dir.dot(center / c_len) < cos(limit)


## Convenience form with the global RELIEF_MAX bound of 03 s7.5 (tests and tools).
static func is_culled(cam: Vector3, center: Vector3, radius: float) -> bool:
	return is_culled_angle(cam.normalized(), horizon_angle(cam), center, radius, Sphere.RELIEF_MAX)
