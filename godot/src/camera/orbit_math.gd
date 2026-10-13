class_name OrbitMath
## Tactical / Commander orbit-camera math on the sphere (06 s5.3). All static, no state.
## State is (focus direction dF, heading h, altitude A above datum, tilt offset delta); there is no
## latitude parameter, so there is no pole singularity. R is Sphere.PLANET_RADIUS everywhere.

const A_FLOOR: float = 300.0          # A_min = max(A_FLOOR, gF + A_CLEARANCE)
const A_CLEARANCE: float = 200.0
const A_MAX: float = 14000.0          # |P| <= PLANET_RADIUS + 14,000 (ADR-03)
const TACTICAL_A_MAX: float = 2500.0  # Tactical when A < this
const THETA_BASE_DEG: float = 40.0
const THETA_RISE_DEG: float = 50.0
const THETA_MIN_DEG: float = 25.0
const THETA_MAX_DEG: float = 90.0
const Z_RISE_LO: float = 0.45
const Z_RISE_HI: float = 0.85
const Z_DELTA_FADE_HI: float = 0.60
const DELTA_MIN_DEG: float = -15.0
const DELTA_MAX_DEG: float = 30.0
const PAN_SPEED_PER_M: float = 0.6    # m/s per metre of height above ground, full deflection

const _TRANSPORT_EPS: float = 1e-7
const _RAY_EPS2: float = 1e-9


## A_min = max(300, gF + 200), gF = ground height at the focus.
static func altitude_min(g_f: float) -> float:
	return maxf(A_FLOOR, g_f + A_CLEARANCE)


## z = ln(A / 300) / ln(A_max / 300), clamped to [0, 1].
static func zoom_z(a: float) -> float:
	return clampf(log(maxf(a, A_FLOOR) / A_FLOOR) / log(A_MAX / A_FLOOR), 0.0, 1.0)


## Inverse of zoom_z.
static func altitude_of_z(z: float) -> float:
	return A_FLOOR * exp(clampf(z, 0.0, 1.0) * log(A_MAX / A_FLOOR))


static func is_tactical(a: float) -> bool:
	return a < TACTICAL_A_MAX


## Tilt angle theta (radians above the horizon at F); delta_deg is the user offset in degrees.
static func theta_of(z: float, delta_deg: float) -> float:
	var off: float = clampf(delta_deg, DELTA_MIN_DEG, DELTA_MAX_DEG) * (1.0 - smoothstep(Z_RISE_LO, Z_DELTA_FADE_HI, z))
	var deg: float = THETA_BASE_DEG + THETA_RISE_DEG * smoothstep(Z_RISE_LO, Z_RISE_HI, z) + off
	return deg_to_rad(clampf(deg, THETA_MIN_DEG, THETA_MAX_DEG))


## Closed-form D with |F + D w| = R + A, w = cos(theta)(-h) + sin(theta) dF (06 s5.3).
static func solve_distance(f_len: float, theta: float, a: float) -> float:
	var s: float = f_len * sin(theta)
	var rr: float = Sphere.PLANET_RADIUS + a
	return -s + sqrt(maxf(s * s - f_len * f_len + rr * rr, 0.0))


## Camera pose for focus direction d_f, unit tangent heading h, |F| = f_len, altitude a, tilt theta.
## origin = P; basis columns x_cam, y_cam, z_cam = w. Orthonormal when h is a unit tangent at d_f.
static func pose(d_f: Vector3, h: Vector3, f_len: float, a: float, theta: float) -> Transform3D:
	var st: float = sin(theta)
	var ct: float = cos(theta)
	var w: Vector3 = -h * ct + d_f * st
	var d: float = solve_distance(f_len, theta, a)
	var y: Vector3 = h * st + d_f * ct
	return Transform3D(Basis(y.cross(w), y, w), d_f * f_len + w * d)


## Heading transport along d_old -> d_new (06 s5.3): rotate by the minimal rotation, re-project, normalize.
static func transport_heading(h: Vector3, d_old: Vector3, d_new: Vector3) -> Vector3:
	var axis: Vector3 = d_old.cross(d_new)
	var s: float = axis.length()
	var out: Vector3 = h
	if s > _TRANSPORT_EPS:
		out = h.rotated(axis / s, atan2(s, d_old.dot(d_new)))
	out = out - d_new * out.dot(d_new)
	return out.normalized()


## Unit tangent at d pointing to ENU north (toward +Z); at a pole falls back to the prime axis.
static func north_heading(d: Vector3) -> Vector3:
	return Sphere.tangent_frame(d).y


## Signed angle (radians, about d) from heading a to heading b, both tangent at d.
static func heading_error(a: Vector3, b: Vector3, d: Vector3) -> float:
	return atan2(d.dot(a.cross(b)), a.dot(b))


## Where a ray meets the sphere of `radius` about the moon centre (near hit). A ray past the limb
## returns its closest point to the centre projected onto the sphere (06 s5.3). dir is a unit vector.
static func ray_sphere_point(origin: Vector3, dir: Vector3, radius: float) -> Vector3:
	var b: float = origin.dot(dir)
	var disc: float = b * b - (origin.length_squared() - radius * radius)
	if disc >= 0.0 and b < 0.0:
		return origin + dir * (-b - sqrt(disc))
	var closest: Vector3 = origin - dir * b
	if closest.length_squared() < _RAY_EPS2:
		return origin.normalized() * radius
	return closest.normalized() * radius


## Grab pan: given the grab point g0 and the point g1 now under the finger, rotate d_f by the minimal
## rotation g1_hat -> g0_hat and transport h. Returns [d_f', h'].
static func grab_pan(d_f: Vector3, h: Vector3, g0: Vector3, g1: Vector3) -> PackedVector3Array:
	var n0: Vector3 = g0.normalized()
	var n1: Vector3 = g1.normalized()
	var axis: Vector3 = n1.cross(n0)
	var s: float = axis.length()
	var nd: Vector3 = d_f
	if s > _TRANSPORT_EPS:
		nd = d_f.rotated(axis / s, atan2(s, n1.dot(n0))).normalized()
	return PackedVector3Array([nd, transport_heading(h, d_f, nd)])


## Velocity pan speed at full deflection: 0.6 (A - gF) m/s (06 s5.3).
static func pan_speed(a: float, g_f: float) -> float:
	return PAN_SPEED_PER_M * (a - g_f)
