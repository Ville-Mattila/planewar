extends GdUnitTestSuite
## Unit tests for sim/steer/turret_aim.gd (AI-17; 05 s6.8, R0 C2-09): the slew law of a tower's `pitch` / `yaw` rates as
## a fraction of `turret_turn_dps`, in the ship stick convention (+pitch raises the muzzle, +yaw turns it left, the
## muzzle is -b.z): sign, saturation at the cap, the dead-beat step near the target, the opposite-direction fallback,
## purity, and a closed loop that arrives without overshoot.

const TURN: float = deg_to_rad(120.0)
const DT: float = 1.0 / 30.0

var _out: PilotInput


func before_test() -> void:
	_out = PilotInput.new()


# A level turret: muzzle toward -z, up +y, right +x.
func _basis() -> Basis:
	return Basis.IDENTITY


func test_target_left_turns_yaw_positive_and_above_pitches_positive() -> void:
	var left: Vector3 = Vector3(-1.0, 0.0, -1.0).normalized()
	var ang: float = TurretAim.slew(_basis(), left, TURN, DT, _out)
	assert_float(ang).is_equal_approx(deg_to_rad(45.0), 0.0001)
	assert_float(_out.yaw).is_greater(0.0)
	assert_float(_out.pitch).is_equal_approx(0.0, 0.0001)
	var up: Vector3 = Vector3(0.0, 1.0, -1.0).normalized()
	var _a: float = TurretAim.slew(_basis(), up, TURN, DT, _out)
	assert_float(_out.pitch).is_greater(0.0)
	assert_float(_out.yaw).is_equal_approx(0.0, 0.0001)
	var right: Vector3 = Vector3(1.0, 0.0, -1.0).normalized()
	var _b: float = TurretAim.slew(_basis(), right, TURN, DT, _out)
	assert_float(_out.yaw).is_less(0.0)


func test_far_error_saturates_at_the_cap_and_near_error_is_the_dead_beat_step() -> void:
	var _a: float = TurretAim.slew(_basis(), Vector3(-1.0, 0.0, -0.2).normalized(), TURN, DT, _out)
	assert_float(_out.yaw).is_equal(1.0)
	var step: float = TURN * DT
	var near: Vector3 = Vector3(-sin(0.25 * step), 0.0, -cos(0.25 * step))
	var _b: float = TurretAim.slew(_basis(), near, TURN, DT, _out)
	assert_float(_out.yaw).is_equal_approx(0.25, 0.0001)   # a quarter of one tick's turn: a quarter of the cap


func test_aligned_commands_nothing_and_a_zero_rate_commands_no_slew() -> void:
	var ang: float = TurretAim.slew(_basis(), Vector3(0.0, 0.0, -1.0), TURN, DT, _out)
	assert_float(ang).is_equal_approx(0.0, 0.0001)
	assert_float(_out.pitch).is_equal(0.0)
	assert_float(_out.yaw).is_equal(0.0)
	var _a: float = TurretAim.slew(_basis(), Vector3(-1.0, 0.0, 0.0), 0.0, DT, _out)
	assert_float(_out.yaw).is_equal(0.0)
	var _b: float = TurretAim.slew(_basis(), Vector3(-1.0, 0.0, 0.0), TURN, 0.0, _out)
	assert_float(_out.yaw).is_equal(0.0)


func test_target_straight_behind_turns_about_the_up_axis_at_the_cap() -> void:
	var ang: float = TurretAim.slew(_basis(), Vector3(0.0, 0.0, 1.0), TURN, DT, _out)
	assert_float(ang).is_equal_approx(PI, 0.0001)
	assert_float(_out.yaw).is_equal(1.0)
	assert_float(_out.pitch).is_equal_approx(0.0, 0.0001)


func test_slew_is_a_pure_function_of_its_arguments() -> void:
	var b: Basis = Basis(Vector3(0, 1, 0), 0.7) * Basis(Vector3(1, 0, 0), 0.2)
	var dir: Vector3 = Vector3(0.3, 0.4, -0.8).normalized()
	var a: PilotInput = PilotInput.new()
	var c: PilotInput = PilotInput.new()
	var ang_a: float = TurretAim.slew(b, dir, TURN, DT, a)
	var _noise: float = TurretAim.slew(Basis.IDENTITY, Vector3(1, 0, 0), TURN, DT, _out)
	var ang_c: float = TurretAim.slew(b, dir, TURN, DT, c)
	assert_float(ang_a).is_equal(ang_c)
	assert_float(a.pitch).is_equal(c.pitch)
	assert_float(a.yaw).is_equal(c.yaw)


# The stand-in turret of the scenarios applies rate = stick x cap for one tick about the body axes: the law arrives in
# ceil(angle / step) ticks and never overshoots.
func test_closed_loop_arrives_without_overshoot() -> void:
	var b: Basis = _basis()
	var dir: Vector3 = Vector3(-0.6, 0.5, -0.62).normalized()
	var step: float = TURN * DT
	var ticks: int = 0
	var prev: float = INF
	for _k: int in 200:
		var ang: float = TurretAim.slew(b, dir, TURN, DT, _out)
		assert_float(ang).is_less_equal(prev + 0.000001)   # monotone
		prev = ang
		if ang < 0.0001:
			break
		var rot: Quaternion = Quaternion(b.x, _out.pitch * step) * Quaternion(b.y, _out.yaw * step)
		b = Basis(rot) * b
		ticks += 1
	var first: float = acos((-Basis.IDENTITY.z).dot(dir))
	assert_int(ticks).is_less_equal(int(ceil(first / step)) + 2)
	assert_float(prev).is_less(0.0001)
