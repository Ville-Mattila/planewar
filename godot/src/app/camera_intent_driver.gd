class_name CameraIntentDriver extends Node
## Glue between InputRouter `intent` and the OrbitController (UX-44; 06 s2.5, s5.3). Drives the Tactical/Commander
## orbit camera in RTS mode only: in any other router mode every CAM_* intent is ignored and held motion stops, so
## flight modes never move the orbit camera. Not an autoload; `app` owns one per match.
##
## Payload conventions (what the input mappers must send): CAM_PAN_GRAB {from, to, on} in screen du; CAM_PAN_VEL
## {vel} = stick deflection (|vel| <= 1, held until a zero vector arrives; a larger vector is a touch fling that
## `grab_end` already carries, so it is ignored); CAM_ZOOM {log_delta, anchor?}; CAM_ROTATE {rad}; CAM_TILT {vec}
## in du, vertical component only, drag up = more top-down; CAM_TIER_TOGGLE {pos}; CAM_HOME. BUILD_ARM in
## Commander dives to the build altitude. Compass, north-up and follow come from the HUD via the methods below.

const TILT_DEG_PER_DU: float = 0.15       ## client-only feel constant: two-finger vertical travel to tilt degrees
const COMMANDER_SNAP_ALTITUDE: float = 5000.0   ## Tactical -> Commander snap target (above TACTICAL_A_MAX)
const MIN_GRAB_DT: float = 0.001

var controller: OrbitController = OrbitController.new()
var router: InputRouter
## Optional Camera3D that receives `controller.pose()` every step and supplies screen rays.
var camera: Camera3D
## Callable(screen_pos: Vector2) -> PackedVector3Array [origin, direction]; overrides `camera` rays (tests).
var ray_source: Callable
## Own Core direction (unit, from the moon centre) for Home and the compass inside the polar cap.
var core_dir: Vector3 = Vector3.RIGHT

var _pan_vec: Vector2 = Vector2.ZERO
var _grabbing: bool = false
var _since_grab: float = 0.0


func _process(delta: float) -> void:
	step(delta)


## Binds to `r.intent`; safe to call once per router.
func bind(r: InputRouter) -> void:
	router = r
	var _e: int = r.intent.connect(on_intent)


## Advances the controller by `dt`: held velocity pan, then smoothing, then the camera transform.
func step(dt: float) -> void:
	if not _rts_active():
		_pan_vec = Vector2.ZERO
		_release_grab()
	elif _pan_vec != Vector2.ZERO:
		controller.pan_velocity(_pan_vec, dt)
	_since_grab += dt
	controller.update(dt)
	if camera != null:
		camera.global_transform = controller.pose()


func on_intent(kind: StringName, payload: Dictionary) -> void:
	if not _rts_active():
		return
	match kind:
		Intents.CAM_PAN_GRAB:
			_pan_grab(payload)
		Intents.CAM_PAN_VEL:
			_pan_vel(_vec(payload, Intents.K_VEL))
		Intents.CAM_ZOOM:
			_zoom(_num(payload, Intents.K_LOG_DELTA), payload.get(Intents.K_ANCHOR, null))
		Intents.CAM_ROTATE:
			controller.rotate_heading(_num(payload, Intents.K_RAD))
		Intents.CAM_TILT:
			var v: Vector2 = _vec(payload, Intents.K_VEC)
			controller.tilt(-v.y * TILT_DEG_PER_DU)
		Intents.CAM_TIER_TOGGLE:
			_tier_toggle(payload.get(Intents.K_POS, null))
		Intents.CAM_HOME:
			controller.home(core_dir)
		Intents.BUILD_ARM:
			if not controller.is_tactical():
				controller.dive_to_build()


## HUD compass tap: heading to north in 0.4 s (toward the own Core inside the polar cap).
func compass_tap() -> void:
	controller.compass_tap(core_dir)


## HUD north-up toggle.
func toggle_north_up() -> void:
	var north: bool = controller.mode == OrbitController.HeadingMode.NORTH_UP
	controller.set_heading_mode(OrbitController.HeadingMode.FREE if north else OrbitController.HeadingMode.NORTH_UP)


## Follow toggle (app passes the followed entity's ground direction each frame while on).
func follow(dir: Vector3, on: bool = true) -> void:
	controller.follow(dir, on)


func _vec(payload: Dictionary, key: StringName) -> Vector2:
	var v: Variant = payload.get(key, Vector2.ZERO)
	return v if v is Vector2 else Vector2.ZERO


func _num(payload: Dictionary, key: StringName) -> float:
	var v: Variant = payload.get(key, 0.0)
	return v if v is float else 0.0


func _rts_active() -> bool:
	return router != null and router.current_mode() == InputRouter.Mode.RTS


func _ray(pos: Variant) -> PackedVector3Array:
	if not pos is Vector2:
		return PackedVector3Array()
	var p: Vector2 = pos
	if ray_source.is_valid():
		var r: Variant = ray_source.call(p)
		if r is PackedVector3Array:
			return r
		return PackedVector3Array()
	if camera != null and camera.is_inside_tree():
		return PackedVector3Array([camera.project_ray_origin(p), camera.project_ray_normal(p)])
	return PackedVector3Array()


func _pan_grab(payload: Dictionary) -> void:
	var on: bool = true
	var raw_on: Variant = payload.get(Intents.K_ON, true)
	if raw_on is bool:
		on = raw_on
	if not on:
		_release_grab()
		return
	if not _grabbing:
		var r0: PackedVector3Array = _ray(payload.get(Intents.K_FROM, null))
		if r0.size() < 2:
			return
		_pan_vec = Vector2.ZERO
		controller.grab_begin(r0[0], r0[1])
		_grabbing = true
		_since_grab = 0.0
	var r1: PackedVector3Array = _ray(payload.get(Intents.K_TO, null))
	if r1.size() < 2:
		return
	controller.grab_move(r1[0], r1[1], maxf(_since_grab, MIN_GRAB_DT))
	_since_grab = 0.0


func _release_grab() -> void:
	if _grabbing:
		controller.grab_end()
		_grabbing = false


func _pan_vel(vel: Vector2) -> void:
	_pan_vec = vel if vel.length() <= 1.0 else Vector2.ZERO


func _zoom(log_delta: float, anchor: Variant) -> void:
	var r: PackedVector3Array = _ray(anchor)
	if r.size() >= 2:
		controller.zoom(log_delta, r[0], r[1])
	else:
		controller.zoom(log_delta)


## Snap toward the tap: Tactical -> Commander altitude, Commander -> Home altitude, anchored on the tap.
func _tier_toggle(pos: Variant) -> void:
	var target: float = OrbitController.HOME_ALTITUDE if not controller.is_tactical() else COMMANDER_SNAP_ALTITUDE
	var d: float = log(controller.altitude() / target)
	var r: PackedVector3Array = _ray(pos)
	if r.size() >= 2:
		controller.zoom(d, r[0], r[1])
	else:
		controller.zoom(d)
