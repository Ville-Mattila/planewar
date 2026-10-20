class_name InputRouter extends Node
## Routes device events to the DeviceMonitor and emits one PilotInput per physics tick in flight modes
## (06 s2.1-2.3). Runs before ClientSession.tick() (priority -10). Raw PilotInput comes from `sampler` when set
## (tests, replays), else from the mapper of the active class: GAMEPAD -> gamepad_mapper, POINTER -> kbm_mapper,
## TOUCH -> neutral until the touch mapper (UX-04). The assist stack (UX-07) runs after the mapper.

enum Mode { MENU, FLIGHT, TURRET, GROUND, RTS, PLACEMENT, TEXT, PEEK }

signal pilot_input(input: PilotInput)
signal intent(kind: StringName, payload: Dictionary)
signal input_class_changed(kind: int)
signal glyph_set_changed(glyphs: StringName)

## Callable() -> PilotInput supplying the raw sample each tick; an invalid Callable yields a neutral input.
var sampler: Callable
var gamepad_mapper: GamepadFlightMapper = GamepadFlightMapper.new()
var kbm_mapper: KbmFlightMapper = KbmFlightMapper.new()

var _monitor: DeviceMonitor
var _mode: Mode = Mode.MENU
var _match_class: int = -1


func _init() -> void:
	process_physics_priority = -10
	_monitor = DeviceMonitor.new(InputClass.boot_class())


func _input(event: InputEvent) -> void:
	route_event(event, Time.get_ticks_msec())


## Feeds an event to the monitor and emits class and glyph changes. Public for tests and replays.
func route_event(event: InputEvent, now_ms: int) -> void:
	if event is InputEventMouseMotion and is_flight_mode(_mode):
		kbm_mapper.add_mouse_motion((event as InputEventMouseMotion).relative)
	var before_class: int = _monitor.active_class
	var before_glyphs: StringName = _monitor.glyph_set
	if not _monitor.feed(event, now_ms):
		return
	if _monitor.active_class != before_class:
		input_class_changed.emit(_monitor.active_class)
	if _monitor.glyph_set != before_glyphs:
		glyph_set_changed.emit(_monitor.glyph_set)


func _physics_process(_delta: float) -> void:
	var _emitted: bool = emit_tick()


## Emits `pilot_input` once if the mode is a flight mode; returns whether it emitted.
## PEEK sends neutral axes with thrust held (assists then level the ship, 06 s2.3).
func emit_tick() -> bool:
	if not is_flight_mode(_mode):
		return false
	var sample: PilotInput = null
	if sampler.is_valid():
		var raw: Variant = sampler.call()
		if raw is PilotInput:
			sample = raw
	if sample == null:
		sample = _mapper_sample()
	if _mode == Mode.PEEK:
		sample.pitch = 0.0
		sample.yaw = 0.0
		sample.roll = 0.0
		sample.buttons = 0
	pilot_input.emit(sample)
	return true


func _mapper_sample() -> PilotInput:
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	match _monitor.active_class:
		InputClass.Kind.GAMEPAD:
			return gamepad_mapper.sample(dt)
		InputClass.Kind.POINTER:
			return kbm_mapper.sample(dt)
	return PilotInput.new()


## Flight modes emit pilot_input; MENU, RTS, PLACEMENT and TEXT never do (06 s2.3).
static func is_flight_mode(m: Mode) -> bool:
	return m == Mode.FLIGHT or m == Mode.TURRET or m == Mode.GROUND or m == Mode.PEEK


func input_class() -> int:
	return _monitor.active_class


func match_input_class() -> int:
	return _match_class


func set_match_input_class(kind: int) -> void:
	_match_class = kind


func set_mode(new_mode: Mode) -> void:
	_mode = new_mode


func current_mode() -> Mode:
	return _mode


func current_glyph_set() -> StringName:
	return _monitor.glyph_set
