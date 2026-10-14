class_name PlanetView extends RefCounted
## What the planet renderer needs from the camera each frame (03 s7.5): world position, forward axis and the
## six frustum planes (normals pointing out of the frustum, as `Camera3D.get_frustum()` returns them). The
## presentation `ViewState` (06 s5) will hand this over; until then `from_camera` fills it from a Camera3D.

var position: Vector3 = Vector3.ZERO
var forward: Vector3 = Vector3.FORWARD
var frustum: Array[Plane] = []               ## empty = no frustum test (everything passes)


static func make(p_position: Vector3, p_forward: Vector3, p_frustum: Array[Plane]) -> PlanetView:
	var v: PlanetView = PlanetView.new()
	v.position = p_position
	v.forward = p_forward.normalized()
	v.frustum = p_frustum
	return v


static func from_camera(cam: Camera3D) -> PlanetView:
	return make(cam.global_position, -cam.global_basis.z, cam.get_frustum())


## The six planes of a symmetric perspective frustum (camera looks along -basis.z of `xf`), outward normals.
static func perspective_planes(xf: Transform3D, fov_y_deg: float, aspect: float, near: float, far: float) -> Array[Plane]:
	var fwd: Vector3 = -xf.basis.z.normalized()
	var right: Vector3 = xf.basis.x.normalized()
	var up: Vector3 = xf.basis.y.normalized()
	var tan_v: float = tan(deg_to_rad(fov_y_deg) * 0.5)
	var tan_h: float = tan_v * aspect
	var p: Vector3 = xf.origin
	return [
		Plane(-fwd, p + fwd * near), Plane(fwd, p + fwd * far),
		Plane((-right - fwd * tan_h).normalized(), p), Plane((up - fwd * tan_v).normalized(), p),
		Plane((right - fwd * tan_h).normalized(), p), Plane((-up - fwd * tan_v).normalized(), p),
	]


## Sphere-versus-frustum with radius-expanded planes (03 s7.5): false only when the sphere is wholly outside
## one plane.
func sphere_in_frustum(center: Vector3, radius: float) -> bool:
	for p: Plane in frustum:
		if p.distance_to(center) > radius:
			return false
	return true


## True when `center` lies in the half-space ahead of the camera (priority bonus, 03 s7.4).
func is_ahead(center: Vector3) -> bool:
	return forward.dot(center - position) > 0.0
