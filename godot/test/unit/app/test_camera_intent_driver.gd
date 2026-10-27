extends GdUnitTestSuite
## Scene-level test for CameraIntentDriver (UX-44): synthetic touch events go through a real InputRouter (gesture
## recognizer included); mouse and gamepad CAM_* intents are emitted on the router's `intent` signal exactly as their
## mappers will. Asserts the OrbitController pose changes in RTS mode and never in flight modes.

const DT: float = 1.0 / 60.0
const FOV_TAN: float = 0.57735            # tan(30 deg), 1080 p
const SIZE: Vector2 = Vector2(1920.0, 1080.0)

var _router: InputRouter
var _drv: CameraIntentDriver
var _t: int = 0


func before_test() -> void:
	_router = auto_free(InputRouter.new()) as InputRouter
	_drv = auto_free(CameraIntentDriver.new()) as CameraIntentDriver
	_drv.controller = OrbitController.new(Vector3(1.0, 0.0, 0.0), 1800.0)
	_drv.core_dir = Vector3(0.0, 1.0, 0.0)
	_drv.ray_source = _ray
	_drv.bind(_router)
	_router.set_mode(InputRouter.Mode.RTS)
	_t = 0


func _ray(p: Vector2) -> PackedVector3Array:
	var pose: Transform3D = _drv.controller.pose()
	var nx: float = (p.x / SIZE.x - 0.5) * 2.0 * FOV_TAN * SIZE.x / SIZE.y
	var ny: float = (0.5 - p.y / SIZE.y) * 2.0 * FOV_TAN
	return PackedVector3Array([pose.origin, (pose.basis * Vector3(nx, ny, -1.0)).normalized()])


func _run(secs: float) -> void:
	for i in int(secs / DT):
		_drv.step(DT)


func _touch(idx: int, pressed: bool, p: Vector2) -> void:
	var e: InputEventScreenTouch = InputEventScreenTouch.new()
	e.index = idx
	e.pressed = pressed
	e.position = p
	_router.route_event(e, _t)


func _drag(idx: int, p: Vector2, rel: Vector2) -> void:
	var e: InputEventScreenDrag = InputEventScreenDrag.new()
	e.index = idx
	e.position = p
	e.relative = rel
	_router.route_event(e, _t)


func _dir() -> Vector3:
	return _drv.controller.d_f


func test_touch_one_finger_drag_grabs_globe() -> void:
	var before: Vector3 = _dir()
	_touch(0, true, Vector2(960, 540))
	for i in 10:
		_t += 16
		var x: float = 960.0 - 20.0 * float(i + 1)
		_drag(0, Vector2(x, 540), Vector2(-20, 0))
		_drv.step(DT)
	_touch(0, false, Vector2(760, 540))
	assert_float(_dir().angle_to(before)).is_greater(0.01)


func test_touch_two_finger_pinch_zooms_in() -> void:
	var a0: float = _drv.controller.altitude()
	_touch(0, true, Vector2(900, 540))
	_touch(1, true, Vector2(1000, 540))
	for i in 8:
		_t += 16
		var s: float = 50.0 + 15.0 * float(i + 1)
		_drag(0, Vector2(960.0 - s, 540), Vector2(-15, 0))
		_drag(1, Vector2(960.0 + s, 540), Vector2(15, 0))
	_run(1.0)
	assert_float(_drv.controller.altitude()).is_less(a0)


func test_touch_two_finger_vertical_drag_tilts() -> void:
	var d0: float = _drv.controller.delta_deg
	_touch(0, true, Vector2(900, 600))
	_touch(1, true, Vector2(1000, 600))
	for i in 8:
		_t += 16
		var y: float = 600.0 - 20.0 * float(i + 1)
		_drag(0, Vector2(900, y), Vector2(0, -20))
		_drag(1, Vector2(1000, y), Vector2(0, -20))
	assert_float(_drv.controller.delta_deg).is_not_equal(d0)


func test_gamepad_stick_pan_moves_until_released() -> void:
	var before: Vector3 = _dir()
	_router.intent.emit(Intents.CAM_PAN_VEL, {Intents.K_VEL: Vector2(0.0, 1.0)})
	_run(0.5)
	var moved: float = _dir().angle_to(before)
	assert_float(moved).is_greater(0.001)
	_router.intent.emit(Intents.CAM_PAN_VEL, {Intents.K_VEL: Vector2.ZERO})
	var at: Vector3 = _dir()
	_run(0.5)
	assert_float(_dir().angle_to(at)).is_less(0.0001)


func test_touch_fling_magnitude_is_not_a_stick() -> void:
	_router.intent.emit(Intents.CAM_PAN_VEL, {Intents.K_VEL: Vector2(900.0, 0.0)})
	var before: Vector3 = _dir()
	_run(0.5)
	assert_float(_dir().angle_to(before)).is_less(0.0001)


func test_mouse_wheel_zoom_anchored_and_rotate_and_tilt() -> void:
	var a0: float = _drv.controller.altitude()
	_router.intent.emit(Intents.CAM_ZOOM, {Intents.K_LOG_DELTA: 0.3, Intents.K_ANCHOR: Vector2(1200, 400)})
	_run(1.0)
	assert_float(_drv.controller.altitude()).is_less(a0)
	var h0: Vector3 = _drv.controller.h
	_router.intent.emit(Intents.CAM_ROTATE, {Intents.K_RAD: 0.5})
	assert_float(_drv.controller.h.angle_to(h0)).is_equal_approx(0.5, 0.001)
	_router.intent.emit(Intents.CAM_TILT, {Intents.K_VEC: Vector2(0, -100)})
	assert_float(_drv.controller.delta_deg).is_equal_approx(15.0, 0.001)


func test_tier_toggle_goes_commander_then_back() -> void:
	assert_bool(_drv.controller.is_tactical()).is_true()
	_router.intent.emit(Intents.CAM_TIER_TOGGLE, {Intents.K_POS: Vector2(960, 540)})
	_run(2.0)
	assert_bool(_drv.controller.is_tactical()).is_false()
	_router.intent.emit(Intents.CAM_TIER_TOGGLE, {Intents.K_POS: Vector2(960, 540)})
	_run(2.0)
	assert_bool(_drv.controller.is_tactical()).is_true()


func test_home_compass_northup_and_build_dive() -> void:
	_drv.controller.set_focus(Vector3(0.0, 0.0, 1.0).slerp(Vector3(1.0, 0.0, 0.0), 0.5), Vector3(0.0, 1.0, 0.0), 3000.0)
	_router.intent.emit(Intents.CAM_HOME, {})
	assert_float(_dir().angle_to(Vector3(0.0, 1.0, 0.0))).is_less(0.001)
	assert_float(_drv.controller.altitude()).is_equal_approx(OrbitController.HOME_ALTITUDE, 1.0)
	_drv.toggle_north_up()
	assert_int(_drv.controller.mode).is_equal(OrbitController.HeadingMode.NORTH_UP)
	_drv.toggle_north_up()
	assert_int(_drv.controller.mode).is_equal(OrbitController.HeadingMode.FREE)
	_drv.controller.set_focus(Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), 5000.0)
	_router.intent.emit(Intents.BUILD_ARM, {})
	_run(1.0)
	assert_float(_drv.controller.altitude()).is_equal_approx(OrbitController.DIVE_ALTITUDE, 30.0)
	_drv.follow(Vector3(0.0, 1.0, 0.0))
	assert_bool(_drv.controller.is_following()).is_true()


func test_flight_modes_do_not_move_the_camera() -> void:
	var modes: Array[InputRouter.Mode] = [InputRouter.Mode.FLIGHT, InputRouter.Mode.TURRET, InputRouter.Mode.GROUND,
			InputRouter.Mode.PEEK, InputRouter.Mode.MENU]
	for m: InputRouter.Mode in modes:
		_router.set_mode(m)
		var pose: Transform3D = _drv.controller.pose()
		_router.intent.emit(Intents.CAM_PAN_VEL, {Intents.K_VEL: Vector2(1.0, 0.0)})
		_router.intent.emit(Intents.CAM_ZOOM, {Intents.K_LOG_DELTA: 1.0})
		_router.intent.emit(Intents.CAM_ROTATE, {Intents.K_RAD: 1.0})
		_router.intent.emit(Intents.CAM_HOME, {})
		_touch(0, true, Vector2(960, 540))
		for i in 6:
			_t += 16
			_drag(0, Vector2(960.0 - 30.0 * float(i + 1), 540), Vector2(-30, 0))
		_touch(0, false, Vector2(780, 540))
		_run(0.5)
		assert_bool(_drv.controller.pose().is_equal_approx(pose)).is_true()


func test_leaving_rts_stops_held_pan() -> void:
	_router.intent.emit(Intents.CAM_PAN_VEL, {Intents.K_VEL: Vector2(1.0, 0.0)})
	_run(0.2)
	_router.set_mode(InputRouter.Mode.FLIGHT)
	_run(0.01)
	var at: Vector3 = _dir()
	_run(0.5)
	assert_float(_dir().angle_to(at)).is_less(0.0001)
