extends GdUnitTestSuite
## Unit tests for sim/steer/turret_aim.gd (AI-17, AI-44; 05 s6.8, R0 C2-09, B.23 A-118): the azimuth / elevation slew law
## of a tower's `pitch` / `yaw` rates (fractions of `turret_turn_dps`): +pitch raises the muzzle (elevation about the
## turret's right), +yaw turns it left (azimuth about the site normal n), the (pitch, yaw) pair is clamped on the unit
## norm, the rate applies in full in the commanded tick (no lag), the turret never rolls and truncates at the pole. The
## helper `_apply` is the A-118 step the sim (GD-09) implements; the tests run the law through it.

const TURN: float = deg_to_rad(120.0)
const DT: float = 1.0 / 30.0
const N: Vector3 = Vector3.UP

var _out: PilotInput


func before_test() -> void:
	_out = PilotInput.new()


# A level turret at the site whose normal is +y: muzzle toward -z, up +y, right +x.
func _basis() -> Basis:
	return Basis.IDENTITY


# A turret basis at elevation `el` (rad) above the horizon, facing -z in azimuth.
func _at_elevation(el: float) -> Basis:
	return Basis(Vector3.RIGHT, el)


# The A-118 step: azimuth about n, then elevation about the (tangent) right truncated at the pole, up
# re-orthonormalised against fwd with right kept tangent.
func _apply(b: Basis, n: Vector3, inp: PilotInput, step: float) -> Basis:
	var f: Vector3 = -b.z
	var r: Vector3 = f.cross(b.y).normalized()
	var qa: Quaternion = Quaternion(n, inp.yaw * step)
	f = qa * f
	r = qa * r
	var el: float = asin(clampf(f.dot(n), -1.0, 1.0))
	var de: float = clampf(inp.pitch * step, -PI * 0.5 - el, PI * 0.5 - el)
	f = (Quaternion(r, de) * f).normalized()
	var u: Vector3 = r.cross(f).normalized()
	return Basis(r, u, -f)


func test_target_left_turns_yaw_positive_and_above_pitches_positive() -> void:
	var left: Vector3 = Vector3(-1.0, 0.0, -1.0).normalized()
	var ang: float = TurretAim.slew(_basis(), N, left, TURN, DT, _out)
	assert_float(ang).is_equal_approx(deg_to_rad(45.0), 0.0001)
	assert_float(_out.yaw).is_greater(0.0)
	assert_float(_out.pitch).is_equal_approx(0.0, 0.0001)
	var up: Vector3 = Vector3(0.0, 1.0, -1.0).normalized()
	var _a: float = TurretAim.slew(_basis(), N, up, TURN, DT, _out)
	assert_float(_out.pitch).is_greater(0.0)
	assert_float(_out.yaw).is_equal_approx(0.0, 0.0001)
	var right: Vector3 = Vector3(1.0, 0.0, -1.0).normalized()
	var _b: float = TurretAim.slew(_basis(), N, right, TURN, DT, _out)
	assert_float(_out.yaw).is_less(0.0)


func test_far_error_saturates_at_the_cap_and_near_error_is_the_dead_beat_step() -> void:
	var _a: float = TurretAim.slew(_basis(), N, Vector3(-1.0, 0.0, -0.2).normalized(), TURN, DT, _out)
	assert_float(_out.yaw).is_equal(1.0)
	var step: float = TURN * DT
	var near: Vector3 = Vector3(-sin(0.25 * step), 0.0, -cos(0.25 * step))
	var _b: float = TurretAim.slew(_basis(), N, near, TURN, DT, _out)
	assert_float(_out.yaw).is_equal_approx(0.25, 0.0001)   # a quarter of one tick's turn: a quarter of the cap


func test_a_diagonal_error_is_clamped_on_the_norm_not_per_axis() -> void:
	var dir: Vector3 = Vector3(-1.0, 1.0, -1.0).normalized()   # far in both axes
	var _a: float = TurretAim.slew(_basis(), N, dir, TURN, DT, _out)
	assert_float(Vector2(_out.pitch, _out.yaw).length()).is_equal_approx(1.0, 0.0001)
	assert_float(_out.pitch).is_between(0.0, 1.0)
	assert_float(_out.yaw).is_between(0.0, 1.0)
	assert_float(_out.pitch).is_not_equal(1.0)
	assert_float(_out.yaw).is_not_equal(1.0)


func test_aligned_commands_nothing_and_a_zero_rate_commands_no_slew() -> void:
	var ang: float = TurretAim.slew(_basis(), N, Vector3(0.0, 0.0, -1.0), TURN, DT, _out)
	assert_float(ang).is_equal_approx(0.0, 0.0001)
	assert_float(_out.pitch).is_equal(0.0)
	assert_float(_out.yaw).is_equal(0.0)
	var _a: float = TurretAim.slew(_basis(), N, Vector3(-1.0, 0.0, 0.0), 0.0, DT, _out)
	assert_float(_out.yaw).is_equal(0.0)
	var _b: float = TurretAim.slew(_basis(), N, Vector3(-1.0, 0.0, 0.0), TURN, 0.0, _out)
	assert_float(_out.yaw).is_equal(0.0)


func test_target_straight_behind_turns_about_the_site_normal_at_the_cap() -> void:
	var ang: float = TurretAim.slew(_basis(), N, Vector3(0.0, 0.0, 1.0), TURN, DT, _out)
	assert_float(ang).is_equal_approx(PI, 0.0001)
	assert_float(_out.yaw).is_equal(1.0)   # exactly 180 deg: the tie-break turns left (+yaw)
	assert_float(_out.pitch).is_equal_approx(0.0, 0.0001)


func test_slew_is_a_pure_function_of_its_arguments() -> void:
	var b: Basis = _at_elevation(0.2)
	var dir: Vector3 = Vector3(0.3, 0.4, -0.8).normalized()
	var a: PilotInput = PilotInput.new()
	var c: PilotInput = PilotInput.new()
	var ang_a: float = TurretAim.slew(b, N, dir, TURN, DT, a)
	var _noise: float = TurretAim.slew(Basis.IDENTITY, N, Vector3(1, 0, 0), TURN, DT, _out)
	var ang_c: float = TurretAim.slew(b, N, dir, TURN, DT, c)
	assert_float(ang_a).is_equal(ang_c)
	assert_float(a.pitch).is_equal(c.pitch)
	assert_float(a.yaw).is_equal(c.yaw)


# A target a fraction of one tick's turn away in azimuth (and elevation): at 0, 45 and 75 degrees of elevation a
# single applied command arrives exactly (the azimuth is an angle about n, not a great-circle step).
func test_dead_beat_arrival_in_one_tick_at_elevations_0_45_75() -> void:
	var step: float = TURN * DT
	for el_deg: float in [0.0, 45.0, 75.0]:
		var el: float = deg_to_rad(el_deg)
		var b: Basis = _at_elevation(el)
		var target: Vector3 = Quaternion(N, 0.8 * step) * (-b.z)   # an azimuth step left at the same elevation
		var _a: float = TurretAim.slew(b, N, target, TURN, DT, _out)
		var after: Basis = _apply(b, N, _out, step)
		assert_float((-after.z).dot(target)).is_greater(1.0 - 0.000001)
		var t2: Vector3 = Quaternion(N, 0.5 * step) * Vector3(0.0, sin(el + 0.3 * step), -cos(el + 0.3 * step))
		var _c: float = TurretAim.slew(b, N, t2, TURN, DT, _out)
		var after2: Basis = _apply(b, N, _out, step)
		assert_float((-after2.z).dot(t2)).is_greater(1.0 - 0.000001)


func test_closed_loop_arrives_without_overshoot() -> void:
	var b: Basis = _basis()
	var dir: Vector3 = Vector3(-0.6, 0.5, -0.62).normalized()
	var step: float = TURN * DT
	var ticks: int = 0
	var prev: float = INF
	for _k: int in 200:
		var ang: float = TurretAim.slew(b, N, dir, TURN, DT, _out)
		assert_float(ang).is_less_equal(prev + 0.000001)   # monotone
		prev = ang
		if ang < 0.0001:
			break
		b = _apply(b, N, _out, step)
		ticks += 1
	var d_az: float = atan2(-dir.x, -dir.z)   # azimuth and elevation distance: the A-118 law arrives in ceil(hypot / step) ticks
	var d_el: float = asin(dir.y)
	assert_int(ticks).is_less_equal(int(ceil(Vector2(d_az, d_el).length() / step)))
	assert_float(prev).is_less(0.0001)


func test_a_yaw_command_at_60_degrees_turns_the_azimuth_by_the_step_and_a_diagonal_stays_on_the_cap() -> void:
	var step: float = TURN * DT
	var b: Basis = _at_elevation(deg_to_rad(60.0))
	var f0: Vector3 = -b.z
	var yawed: PilotInput = PilotInput.new()
	yawed.yaw = 1.0
	var b2: Basis = _apply(b, N, yawed, step)
	var h0: Vector3 = (f0 - N * f0.dot(N)).normalized()
	var h1: Vector3 = (-b2.z - N * (-b2.z).dot(N)).normalized()
	assert_float(h0.angle_to(h1)).is_equal_approx(step, 0.00001)
	var _a: float = TurretAim.slew(b, N, Vector3(-1.0, -0.3, 0.2).normalized(), TURN, DT, _out)
	assert_float(Vector2(_out.pitch, _out.yaw).length()).is_equal_approx(1.0, 0.0001)


func test_basis_stays_orthonormal_and_never_rolls_over_1000_random_ticks() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 44
	var n: Vector3 = Vector3(0.3, 0.8, -0.5).normalized()
	var f: Vector3 = n.cross(Vector3.RIGHT).normalized()
	var b: Basis = Basis(f.cross(n).normalized(), n, -f)
	var step: float = TURN * DT
	for _k: int in 1000:
		var dir: Vector3 = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
		var _a: float = TurretAim.slew(b, n, dir, TURN, DT, _out)
		b = _apply(b, n, _out, step)
		assert_float(b.x.length()).is_equal_approx(1.0, 0.00001)
		assert_float(b.y.length()).is_equal_approx(1.0, 0.00001)
		assert_float(b.x.dot(b.y)).is_equal_approx(0.0, 0.00001)
		assert_float(b.x.dot(b.z)).is_equal_approx(0.0, 0.00001)
		assert_float(b.x.dot(n)).is_equal_approx(0.0, 0.00001)


func test_a_target_at_the_zenith_stops_at_the_pole_and_commands_no_azimuth() -> void:
	var b: Basis = _at_elevation(deg_to_rad(80.0))
	var step: float = TURN * DT
	for _k: int in 40:
		var _a: float = TurretAim.slew(b, N, N, TURN, DT, _out)
		b = _apply(b, N, _out, step)
	assert_float((-b.z).dot(N)).is_greater(0.99999)
	var _c: float = TurretAim.slew(b, N, N, TURN, DT, _out)   # at the pole: no azimuth is defined, none is commanded
	assert_float(_out.yaw).is_equal(0.0)
	var past: PilotInput = PilotInput.new()
	past.pitch = 1.0
	b = _apply(b, N, past, step)   # a command past the zenith stays at the pole
	assert_float((-b.z).dot(N)).is_greater(0.99999)
	past.pitch = -1.0
	b = _apply(b, N, past, step)
	assert_float((-b.z).dot(N)).is_less(1.0)
