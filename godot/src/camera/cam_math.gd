class_name CamMath
## Pure camera math shared by Chase, orbit and transitions (06 s5.2, s5.4, s5.5). All static, no state.
## Basis convention (03): forward f = -basis.z, up u = basis.y, right r = basis.x.

## Near plane, default policy (03 s7.6, R0 C2-28): near = clamp(0.3 + 0.004 h_cam, 0.3, 20).
const NEAR_BASE: float = 0.3
const NEAR_PER_M: float = 0.004
const NEAR_MAX: float = 20.0
## Named alternative `orbit_alt` (06 s5.5): clamp(4 + (A_g - 300) * 16 / 2200, 4, 20).
const NEAR_ALT_MIN: float = 4.0
const NEAR_ALT_A0: float = 300.0
const NEAR_ALT_SPAN: float = 2200.0
const NEAR_ALT_RISE: float = 16.0
## Far plane, always (ADR-02).
const FAR_PLANE: float = 40000.0

const _PERP_EPS2: float = 1e-6
const _VIEW_EPS2: float = 1e-10
const _ROLL_FREE_DEG: float = 90.0
const _ROLL_NONE_DEG: float = 150.0
const _ROLL_CLAMP_DEG: float = 30.0
const _VERTICAL_COS_LO: float = 0.8191520442889918   # cos 35 deg
const _VERTICAL_COS_HI: float = 0.9659258262890683   # cos 15 deg


## Critically damped spring step. Returns [position, velocity]; exact for any dt, never overshoots a
## target reached from rest (06 s5.2).
static func crit_damp(x: Vector3, v: Vector3, target: Vector3, omega: float, dt: float) -> PackedVector3Array:
	var delta: Vector3 = x - target
	var temp: Vector3 = (v + delta * omega) * dt
	var decay: float = exp(-omega * dt)
	return PackedVector3Array([target + (delta + temp) * decay, (v - temp * omega) * decay])


## Scalar twin of crit_damp for angles and ln-altitude. Returns Vector2(position, velocity).
static func crit_damp_f(x: float, v: float, target: float, omega: float, dt: float) -> Vector2:
	var delta: float = x - target
	var temp: float = (v + delta * omega) * dt
	var decay: float = exp(-omega * dt)
	return Vector2(target + (delta + temp) * decay, (v - temp * omega) * decay)


## Radians; > 0 = right wing down. 0 when the ship forward is (anti)parallel to n (06 s5.2).
static func bank_angle(b: Basis, n: Vector3) -> float:
	var f: Vector3 = -b.z
	var n_perp: Vector3 = n - f * f.dot(n)
	if n_perp.length_squared() < _PERP_EPS2:
		return 0.0
	n_perp = n_perp.normalized()
	return atan2(-b.x.dot(n_perp), b.y.dot(n_perp))


## x with its component along unit d removed.
static func perp(x: Vector3, d: Vector3) -> Vector3:
	return x - d * x.dot(d)


## e(t) = 6t^5 - 15t^4 + 10t^3 on [0, 1] (06 s5.4).
static func smootherstep(t: float) -> float:
	var c: float = clampf(t, 0.0, 1.0)
	return c * c * c * (c * (c * 6.0 - 15.0) + 10.0)


## Weight toward the ship up when the view is near-vertical (06 s5.2): smoothstep(cos 35, cos 15, |d.n|).
static func vertical_weight(d: Vector3, n: Vector3) -> float:
	return smoothstep(_VERTICAL_COS_LO, _VERTICAL_COS_HI, absf(d.dot(n)))


## Head-up reference: normalize(lerp(perp(n, d), perp(u, d), w)). Falls back to perp(u, d), then to any
## perpendicular, if the blend degenerates. Unit length and perpendicular to d.
static func up_reference(d: Vector3, n: Vector3, u: Vector3) -> Vector3:
	var w: float = vertical_weight(d, n)
	var r: Vector3 = perp(n, d).lerp(perp(u, d), w)
	if r.length_squared() < _PERP_EPS2:
		r = perp(u, d)
	if r.length_squared() < _PERP_EPS2:
		r = perp(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT, d)
	return r.normalized()


## Target camera roll: clamp(k_roll * phi, +-30 deg), faded out between |phi| 90 and 150 deg so an
## inverted ship keeps a head-up camera (06 s5.2).
static func roll_target(phi: float, k_roll: float) -> float:
	var lim: float = deg_to_rad(_ROLL_CLAMP_DEG)
	var fade: float = 1.0 - smoothstep(deg_to_rad(_ROLL_FREE_DEG), deg_to_rad(_ROLL_NONE_DEG), absf(phi))
	return clampf(k_roll * phi, -lim, lim) * fade


## Camera basis looking along unit d with up hint u_cam: z = -d, y = normalize(perp(u_cam, d)), x = y x z.
static func view_basis(d: Vector3, u_cam: Vector3) -> Basis:
	var z: Vector3 = -d
	var yv: Vector3 = perp(u_cam, d)
	if yv.length_squared() < _VIEW_EPS2:
		yv = perp(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT, d)
	var y: Vector3 = yv.normalized()
	return Basis(y.cross(z), y, z)


## Near plane from camera height above ground, default policy (R0 C2-28).
static func near_plane(h_cam: float) -> float:
	return clampf(NEAR_BASE + NEAR_PER_M * h_cam, NEAR_BASE, NEAR_MAX)


## Named alternative `orbit_alt` (06 s5.5); a_g = camera altitude above ground.
static func near_plane_orbit_alt(a_g: float) -> float:
	return clampf(NEAR_ALT_MIN + (a_g - NEAR_ALT_A0) * NEAR_ALT_RISE / NEAR_ALT_SPAN, NEAR_ALT_MIN, NEAR_MAX)


## Interpolates ln(near) between two planes (06 s5.5).
static func near_lerp(n0: float, n1: float, s: float) -> float:
	return exp(lerpf(log(n0), log(n1), s))
