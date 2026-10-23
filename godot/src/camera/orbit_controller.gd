class_name OrbitController extends RefCounted
## Tactical / Commander orbit controller (06 s5.3; UX-13). Pure, time-stepped state machine: callers feed
## gestures as plain arguments (grab rays, zoom deltas, pan vectors) and call update(dt) once per frame;
## pose() returns the camera Transform3D. No Nodes, no signals, no sim reads. Tuning consts cite 06 s5.3.

enum HeadingMode { FREE, NORTH_UP }

const TAU_ZOOM: float = 0.12              # ln A and theta smoothing (06 s5.3)
const TAU_FLING: float = 0.35             # fling decay
const FLING_STOP: float = 0.002           # rad/s
const FLING_MAX_AGE: float = 0.1          # s: a grab that paused longer than this releases without fling
const FLING_BLEND: float = 0.5            # low-pass weight of the newest grab-velocity sample
const TAU_NORTH: float = 0.5              # NORTH_UP slew
const POLAR_CAP_DEG: float = 8.0          # |dF.Z| > cos 8 deg suspends NORTH_UP
const RESUME_ERR_DEG: float = 100.0       # after the cap: resume only below this heading error
const COMPASS_TIME: float = 0.4
const TAU_FOLLOW: float = 0.2
const ZOOM_SETTLE_LN: float = 1e-4        # anchor lock ends when |ln A - target| is below this
const HOME_ALTITUDE: float = 1800.0       # match start (06 s5.3 focus table)
const DIVE_ALTITUDE: float = 1200.0       # build armed in Commander
const DIVE_TIME: float = 0.5
const MIN_LEN2: float = 1e-6

var d_f: Vector3 = Vector3.RIGHT          ## focus direction (unit)
var h: Vector3 = Vector3.BACK             ## heading, unit tangent at d_f
var ground_h: float = 0.0                 ## gF, ground height at the focus (caller sets each frame)
var mode: HeadingMode = HeadingMode.FREE
var delta_deg: float = 0.0                ## user tilt offset

var _ln_a: float = 0.0
var _ln_a_v: float = 0.0
var _ln_a_target: float = 0.0
var _theta: float = 0.0
var _theta_v: float = 0.0
var _fling: Vector3 = Vector3.ZERO        ## angular velocity (rad/s, world axis)
var _grabbing: bool = false
var _g0: Vector3 = Vector3.ZERO
var _grab_vel: Vector3 = Vector3.ZERO
var _since_move: float = 0.0
var _anchor_on: bool = false
var _anchor_local: Vector3 = Vector3.ZERO
var _anchor_g: Vector3 = Vector3.ZERO
var _north_suspended: bool = false
var _compass_left: float = 0.0
var _compass_target: Vector3 = Vector3.ZERO
var _follow_on: bool = false
var _follow_dir: Vector3 = Vector3.ZERO
var _dive_left: float = 0.0
var _dive_rate: float = 0.0


func _init(start_dir: Vector3 = Vector3.RIGHT, altitude_m: float = HOME_ALTITUDE) -> void:
	set_focus(start_dir, OrbitMath.north_heading(start_dir.normalized()), altitude_m)


## Hard-set the focus (match start, jump, release): snaps altitude and tilt, clears motion.
func set_focus(dir: Vector3, heading: Vector3, altitude_m: float) -> void:
	d_f = dir.normalized()
	h = (heading - d_f * heading.dot(d_f)).normalized()
	_ln_a = log(maxf(altitude_m, OrbitMath.A_FLOOR))
	_ln_a_target = _ln_a
	_ln_a_v = 0.0
	_theta = _theta_goal()
	_theta_v = 0.0
	_fling = Vector3.ZERO
	_grabbing = false
	_anchor_on = false
	_compass_left = 0.0
	_dive_left = 0.0


func altitude() -> float:
	return exp(_ln_a)


func zoom_level() -> float:
	return OrbitMath.zoom_z(exp(_ln_a))


func is_tactical() -> bool:
	return OrbitMath.is_tactical(exp(_ln_a))


func is_following() -> bool:
	return _follow_on


func is_flinging() -> bool:
	return _fling != Vector3.ZERO


func is_north_suspended() -> bool:
	return _north_suspended


func focus_length() -> float:
	return Sphere.PLANET_RADIUS + ground_h


func pose() -> Transform3D:
	return OrbitMath.pose(d_f, h, focus_length(), exp(_ln_a), _theta)


# region grab pan and fling
## Touch-down / mouse-down: remember the ground point under the screen ray (06 s5.3). Cancels fling and follow.
func grab_begin(ray_origin: Vector3, ray_dir: Vector3) -> void:
	_grabbing = true
	_fling = Vector3.ZERO
	_grab_vel = Vector3.ZERO
	_since_move = 0.0
	_follow_on = false
	_compass_left = 0.0
	_g0 = OrbitMath.ray_sphere_point(ray_origin, ray_dir, focus_length())


## Finger moved: the ray is cast from the CURRENT pose(). Rotates the focus so the grab point returns under it.
func grab_move(ray_origin: Vector3, ray_dir: Vector3, dt: float) -> void:
	if not _grabbing:
		return
	var g1: Vector3 = OrbitMath.ray_sphere_point(ray_origin, ray_dir, focus_length())
	var old_d: Vector3 = d_f
	var res: PackedVector3Array = OrbitMath.grab_pan(d_f, h, _g0, g1)
	d_f = res[0]
	h = res[1]
	_since_move = 0.0
	if dt > 0.0:
		var sample: Vector3 = _angular_velocity(old_d, d_f, dt)
		_grab_vel = _grab_vel.lerp(sample, FLING_BLEND) if _grab_vel != Vector3.ZERO else sample


## Release: starts a fling from the smoothed grab velocity when the finger was still moving.
func grab_end() -> void:
	if not _grabbing:
		return
	_grabbing = false
	var moving: bool = _since_move <= FLING_MAX_AGE and _grab_vel.length() >= FLING_STOP
	_fling = _grab_vel if moving else Vector3.ZERO


func _angular_velocity(a: Vector3, b: Vector3, dt: float) -> Vector3:
	var axis: Vector3 = a.cross(b)
	var s: float = axis.length()
	if s < 1e-9:
		return Vector3.ZERO
	return axis / s * (atan2(s, a.dot(b)) / dt)


func _rotate_focus(axis: Vector3, angle: float) -> void:
	var nd: Vector3 = d_f.rotated(axis, angle).normalized()
	h = OrbitMath.transport_heading(h, d_f, nd)
	d_f = nd
# endregion


# region velocity pan, zoom, tilt, rotate
## Velocity pan (LS, WASD, edge): vec.x right, vec.y up the screen, full deflection = OrbitMath.pan_speed.
func pan_velocity(vec: Vector2, dt: float) -> void:
	if vec.length_squared() < MIN_LEN2:
		return
	_follow_on = false
	_fling = Vector3.ZERO
	var v: Vector2 = vec.limit_length(1.0)
	var move: Vector3 = h * v.y + h.cross(d_f) * v.x
	var m_len: float = move.length()
	var ang: float = OrbitMath.pan_speed(altitude(), ground_h) * m_len * dt / focus_length()
	_rotate_focus(d_f.cross(move / m_len).normalized(), ang)


## Zoom (wheel, pinch, triggers): log_delta > 0 zooms in (A shrinks by e^-log_delta). The ground point under
## the anchor ray (cast from the CURRENT pose()) stays fixed while the smoothed altitude settles.
func zoom(log_delta: float, anchor_origin: Vector3 = Vector3.ZERO, anchor_dir: Vector3 = Vector3.ZERO) -> void:
	_dive_left = 0.0
	var lo: float = log(OrbitMath.altitude_min(ground_h))
	_ln_a_target = clampf(_ln_a_target - log_delta, lo, log(OrbitMath.A_MAX))
	if anchor_dir.length_squared() > 0.5:
		var p: Transform3D = pose()
		var dir: Vector3 = anchor_dir.normalized()
		_anchor_g = OrbitMath.ray_sphere_point(anchor_origin, dir, focus_length())
		_anchor_local = p.basis.inverse() * dir
		_anchor_on = true


## Two-finger vertical drag / RS Y / MMB drag Y: tilt offset in degrees (Tactical only; fades above).
func tilt(d_deg: float) -> void:
	delta_deg = clampf(delta_deg + d_deg, OrbitMath.DELTA_MIN_DEG, OrbitMath.DELTA_MAX_DEG)


## Rotate heading (twist, RS X, Q/E) by rad about the focus normal; a manual turn leaves NORTH_UP.
func rotate_heading(rad: float) -> void:
	h = h.rotated(d_f, rad)
	h = (h - d_f * h.dot(d_f)).normalized()
	mode = HeadingMode.FREE
	_compass_left = 0.0


func _theta_goal() -> float:
	return OrbitMath.theta_of(OrbitMath.zoom_z(exp(_ln_a_target)), delta_deg)
# endregion


# region heading modes, follow, dive
func set_heading_mode(m: HeadingMode) -> void:
	mode = m
	_north_suspended = false


## Compass tap: slew to north in 0.4 s; inside the polar cap toward `core_dir` (own Core). Clears the suspension.
func compass_tap(core_dir: Vector3) -> void:
	var to: Vector3 = OrbitMath.north_heading(d_f)
	if _in_polar_cap():
		var t: Vector3 = core_dir.normalized()
		var tang: Vector3 = t - d_f * t.dot(d_f)
		if tang.length_squared() > MIN_LEN2:
			to = tang.normalized()
	_compass_target = to
	_compass_left = COMPASS_TIME
	_north_suspended = false


func _in_polar_cap() -> bool:
	return absf(d_f.z) > cos(deg_to_rad(POLAR_CAP_DEG))


## Follow a ground point (tau 0.2 s); any pan or grab cancels. Call again each frame with the new position.
func follow(dir: Vector3, on: bool = true) -> void:
	_follow_on = on
	_follow_dir = dir.normalized()


## Build armed in Commander: dive to 1,200 m over 0.5 s (06 s5.3 focus table).
func dive_to_build() -> void:
	_ln_a_target = log(DIVE_ALTITUDE)
	_dive_left = DIVE_TIME
	_dive_rate = (_ln_a_target - _ln_a) / DIVE_TIME


## Home (H, L3): refocus on `core_dir`, north up, 1,800 m.
func home(core_dir: Vector3) -> void:
	set_focus(core_dir, OrbitMath.north_heading(core_dir.normalized()), HOME_ALTITUDE)
# endregion


## Advance by dt seconds: fling decay, follow, heading slew, zoom/tilt smoothing, anchor lock.
func update(dt: float) -> void:
	_since_move += dt
	_update_fling(dt)
	_update_follow(dt)
	_update_heading(dt)
	_update_zoom(dt)


func _update_fling(dt: float) -> void:
	if _fling == Vector3.ZERO:
		return
	var rate: float = _fling.length()
	_rotate_focus(_fling / rate, rate * dt)
	_fling *= exp(-dt / TAU_FLING)
	if _fling.length() < FLING_STOP:
		_fling = Vector3.ZERO


func _update_follow(dt: float) -> void:
	if not _follow_on:
		return
	var k: float = 1.0 - exp(-dt / TAU_FOLLOW)
	var nd: Vector3 = Sphere.slerp_dir(d_f, _follow_dir, k)
	h = OrbitMath.transport_heading(h, d_f, nd)
	d_f = nd


func _update_heading(dt: float) -> void:
	if _compass_left > 0.0:
		var step: float = minf(dt, _compass_left)
		var err: float = OrbitMath.heading_error(h, _compass_target, d_f)
		h = h.rotated(d_f, err * step / _compass_left)
		_compass_left -= step
		return
	if mode != HeadingMode.NORTH_UP:
		return
	var e: float = OrbitMath.heading_error(h, OrbitMath.north_heading(d_f), d_f)
	if _in_polar_cap():
		_north_suspended = true
	elif _north_suspended and absf(e) < deg_to_rad(RESUME_ERR_DEG):
		_north_suspended = false
	if _north_suspended:
		return
	h = h.rotated(d_f, e * (1.0 - exp(-dt / TAU_NORTH)))


func _update_zoom(dt: float) -> void:
	if _dive_left > 0.0:
		var step: float = minf(dt, _dive_left)
		_ln_a += _dive_rate * step
		_dive_left -= step
		_ln_a_v = 0.0
	else:
		var r: Vector2 = CamMath.crit_damp_f(_ln_a, _ln_a_v, _ln_a_target, 1.0 / TAU_ZOOM, dt)
		_ln_a = r.x
		_ln_a_v = r.y
	var t: Vector2 = CamMath.crit_damp_f(_theta, _theta_v, _theta_goal(), 1.0 / TAU_ZOOM, dt)
	_theta = t.x
	_theta_v = t.y
	if _anchor_on:
		_lock_anchor()
		if absf(_ln_a - _ln_a_target) < ZOOM_SETTLE_LN:
			_anchor_on = false


## Re-aim so the anchor ray (fixed in camera space) meets the remembered ground point again.
func _lock_anchor() -> void:
	var p: Transform3D = pose()
	var g1: Vector3 = OrbitMath.ray_sphere_point(p.origin, p.basis * _anchor_local, focus_length())
	var res: PackedVector3Array = OrbitMath.grab_pan(d_f, h, _anchor_g, g1)
	d_f = res[0]
	h = res[1]
