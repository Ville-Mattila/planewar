class_name ScreenFlow extends Node
## Screen state machine + back stack + focus rules (06 s8 Navigation, UX-24).
## B (Intents.BACK), Esc (ui_cancel) and Android back (NOTIFICATION_WM_GO_BACK_REQUEST) call back().

signal screen_changed(id: StringName, args: Dictionary)
signal quit_requested

var current_id: StringName = &""
var current: FlowScreen = null

var _host: Control = null
var _factories: Dictionary[StringName, Callable] = {}  # id -> Callable() -> FlowScreen
var _stack: Array[Entry] = []
var _current_args: Dictionary = {}


class Entry extends RefCounted:
	var id: StringName
	var args: Dictionary

	func _init(p_id: StringName, p_args: Dictionary) -> void:
		id = p_id
		args = p_args


func _ready() -> void:
	get_tree().set_quit_on_go_back(false)


## `host` is the Control that parents the active screen.
func setup(host: Control) -> void:
	_host = host


func register(id: StringName, factory: Callable) -> void:
	_factories[id] = factory


func register_scene(id: StringName, scene: PackedScene) -> void:
	_factories[id] = func() -> FlowScreen: return scene.instantiate() as FlowScreen


func stack_depth() -> int:
	return _stack.size()


func stack_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for e: Entry in _stack:
		out.append(e.id)
	return out


## Show the first screen (no transition check, empty stack).
func start(id: StringName, args: Dictionary = {}) -> bool:
	_stack.clear()
	return _show(id, args)


## Navigate along an allowed edge. Going to the stack top pops instead (Pause -> Match).
## The stack changes only after the new screen showed.
func go(id: StringName, args: Dictionary = {}) -> bool:
	if current == null or not ScreenId.targets(current_id).has(id):
		return false
	var prev_id: StringName = current_id
	var prev_args: Dictionary = _current_args
	var popping: bool = not _stack.is_empty() and _stack.back().id == id
	if not _show(id, args):
		return false
	if popping:
		_stack.pop_back()
	elif ScreenId.clears_stack(id):
		_stack.clear()
	elif not ScreenId.is_transient(prev_id):
		_stack.append(Entry.new(prev_id, prev_args))
	return true


## Back action. Returns true when something handled it. Pops only along a reverse edge of the table.
func back() -> bool:
	if current == null:
		return false
	if current.handle_back():
		return true
	if not _stack.is_empty():
		var e: Entry = _stack.back()
		if not ScreenId.targets(e.id).has(current_id) or not _show(e.id, e.args):
			return false
		_stack.pop_back()
		return true
	if current_id == ScreenId.MAIN_MENU and not OS.has_feature("web"):
		quit_requested.emit()  # main menu asks to quit (native only)
		return true
	return false


## Hook for the input lane's `intent` signal.
func on_intent(kind: StringName, _payload: Dictionary) -> void:
	if kind == Intents.BACK:
		var _handled: bool = back()


func _unhandled_input(event: InputEvent) -> void:
	# Gamepad B arrives as Intents.BACK; ui_cancel also maps joypad B, so ignore joypad events here.
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return
	if event.is_action_pressed(&"ui_cancel") and back():
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		var _handled: bool = back()


func _show(id: StringName, args: Dictionary) -> bool:
	if not _factories.has(id) or _host == null:
		return false
	var factory: Callable = _factories[id]
	var screen: FlowScreen = factory.call()
	if screen == null:
		return false
	if current != null:
		current.exit()
		_host.remove_child(current)
		current.queue_free()
	current = screen
	current_id = id
	_current_args = args
	_host.add_child(screen)
	screen.enter(args)
	_focus(screen)
	screen_changed.emit(id, args)
	return true


## Focus rule: initial_focus() if focusable, else the first focusable descendant.
func _focus(screen: FlowScreen) -> void:
	var target: Control = screen.initial_focus()
	if target == null or target.focus_mode == Control.FOCUS_NONE or not target.is_visible_in_tree():
		target = _first_focusable(screen)
	if target != null and target.is_inside_tree():
		target.grab_focus()


func _first_focusable(node: Node) -> Control:
	for child: Node in node.get_children():
		var c: Control = child as Control
		if c != null and c.focus_mode != Control.FOCUS_NONE and c.is_visible_in_tree():
			return c
		var deeper: Control = _first_focusable(child)
		if deeper != null:
			return deeper
	return null
