class_name SfChaseCamera extends Camera3D
## Chase camera stub (06 s5.2): look direction with velocity look-ahead (or the mouse-aim vector), head-up
## basis from the surface normal with damped bank roll (k_roll 0.35, tau 0.25 s), critically damped spring arm,
## ground clearance, FOV boost. Spike addition (reported to 06): a hover view that, as the nose rises past
## 30-60 degrees, swings the look direction to the belly-side horizontal tilted down, so a tail-down hover is
## seen from behind and above instead of from under the ship.

var _p: Dictionary
var _d: Vector3 = Vector3.ZERO
var _phi_cam: float
var _o: Vector3 = Vector3.ZERO
var _o_vel: Vector3 = Vector3.ZERO
var _fov: float
var _init_done: bool
var _v_cruise: float
var _v_dive: float
var hover_w: float                 # 0 = flight view, 1 = hover view (HUD shows it)


func setup(cam: Dictionary, def: ShipDef) -> void:
	_p = cam
	_v_cruise = def.v_cruise
	_v_dive = def.v_dive_max
	near = SfDefs.num(cam, "near_m")
	far = SfDefs.num(cam, "far_m")
	_fov = SfDefs.num(cam, "fov_deg")
	fov = _fov


static func bank_angle(fwd: Vector3, up: Vector3, n: Vector3) -> float:
	var right: Vector3 = fwd.cross(up)
	var n_perp: Vector3 = n - fwd * fwd.dot(n)
	if n_perp.length_squared() < 1e-6:
		return 0.0
	n_perp = n_perp.normalized()
	return atan2(-right.dot(n_perp), up.dot(n_perp))   # > 0 = right wing down (06 s5.2)


static func _perp(x: Vector3, d: Vector3) -> Vector3:
	return x - d * x.dot(d)


## `aim`: mouse-aim vector (unit) or ZERO. `boosting` widens the FOV.
func follow(p: Vector3, fwd: Vector3, up: Vector3, v: Vector3, aim: Vector3, boosting: bool, delta: float) -> void:
	var n: Vector3 = p.normalized()
	var d_star: Vector3 = _look_target(n, fwd, up, v, aim)
	if not _init_done:
		_d = d_star
		_init_done = true
	_d = Sphere.slerp_dir(_d, d_star, 1.0 - exp(-delta / SfDefs.num(_p, "tau_dir_s"))).normalized()
	var w: float = smoothstep(cos(deg_to_rad(35.0)), cos(deg_to_rad(15.0)), absf(_d.dot(n)))
	var u_ref: Vector3 = _perp(n, _d).lerp(_perp(up, _d), w)
	if u_ref.length_squared() < 1e-6:
		u_ref = _perp(up, _d)
	u_ref = u_ref.normalized()
	var phi: float = bank_angle(fwd, up, n) * (1.0 - hover_w)
	var clamp_r: float = deg_to_rad(SfDefs.num(_p, "roll_clamp_deg"))
	var phi_t: float = clampf(SfDefs.num(_p, "k_roll") * phi, -clamp_r, clamp_r) \
		* (1.0 - smoothstep(deg_to_rad(90.0), deg_to_rad(150.0), absf(phi)))
	_phi_cam += (phi_t - _phi_cam) * (1.0 - exp(-delta / SfDefs.num(_p, "tau_roll_s")))
	var u_cam: Vector3 = u_ref.rotated(_d, _phi_cam)
	var speed: float = v.length()
	var stretch: float = clampf((speed - _v_cruise) / (_v_dive - _v_cruise), 0.0, 1.0)
	var dist: float = SfDefs.num(_p, "chase_distance_m") * (1.0 + SfDefs.num(_p, "stretch") * stretch)
	var y_cam: Vector3 = _perp(u_cam, _d).normalized()
	var o_star: Vector3 = -_d * dist + y_cam * dist * SfDefs.num(_p, "height_ratio")
	if not _init_done or _o == Vector3.ZERO:
		_o = o_star
	var res: PackedVector3Array = _crit_damp(_o, _o_vel, o_star, SfDefs.num(_p, "omega"), delta)
	_o = res[0]
	_o_vel = res[1]
	var cam_p: Vector3 = p + _o
	var floor_r: float = Sphere.PLANET_RADIUS + SfDefs.num(_p, "clearance_m")
	if cam_p.length() < floor_r:
		cam_p = cam_p.normalized() * floor_r
	var z: Vector3 = -_d
	var y: Vector3 = _perp(u_cam, _d).normalized()
	global_transform = Transform3D(Basis(y.cross(z), y, z), cam_p)
	var fov_t: float = SfDefs.num(_p, "fov_deg") + (SfDefs.num(_p, "fov_boost_deg") if boosting else 0.0)
	_fov += (fov_t - _fov) * (1.0 - exp(-delta / SfDefs.num(_p, "fov_tau_s")))
	fov = _fov


func _look_target(n: Vector3, fwd: Vector3, up: Vector3, v: Vector3, aim: Vector3) -> Vector3:
	var d_flight: Vector3 = fwd
	if aim != Vector3.ZERO:
		d_flight = aim
	elif v.length() > SfDefs.num(_p, "look_vel_min_mps"):
		d_flight = (fwd + (v.normalized() - fwd) * SfDefs.num(_p, "look_vel_blend")).normalized()
	var pitch: float = asin(clampf(fwd.dot(n), -1.0, 1.0))
	hover_w = smoothstep(deg_to_rad(SfDefs.num(_p, "hover_pitch_lo_deg")),
		deg_to_rad(SfDefs.num(_p, "hover_pitch_hi_deg")), pitch)
	if hover_w <= 0.0:
		return d_flight
	var belly: Vector3 = _perp(-up, n)
	if belly.length_squared() < 1e-6:
		belly = _perp(fwd, n)
	var dep: float = deg_to_rad(SfDefs.num(_p, "hover_depression_deg"))
	var d_hover: Vector3 = (belly.normalized() * cos(dep) - n * sin(dep)).normalized()
	return Sphere.slerp_dir(d_flight, d_hover, hover_w).normalized()


static func _crit_damp(x: Vector3, v: Vector3, target: Vector3, omega: float, dt: float) -> PackedVector3Array:
	var delta: Vector3 = x - target
	var temp: Vector3 = (v + delta * omega) * dt
	var decay: float = exp(-omega * dt)
	return PackedVector3Array([target + (delta + temp) * decay, (v - temp * omega) * decay])
