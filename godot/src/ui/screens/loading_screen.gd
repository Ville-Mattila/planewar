class_name LoadingScreen extends ScreenBase
## Loading screen (06 s8): DOWNLOADING_MAP, PREWARMING, WAITING_PLAYERS, TIMEOUT; roster with revealed doctrines.
## Thin: LoadingModel holds the state. scenes/ui/screens/loading.tscn.

signal leave_requested

var model: LoadingModel = LoadingModel.new()
var _status: Label
var _bar: ProgressBar
var _roster: VBoxContainer
var _leave: Button


func _ready() -> void:
	var box: VBoxContainer = ScreenKit.shell(self, 480.0)
	box.add_child(ScreenKit.label(tr(&"ui.loading.title"), int(ScreenParams.param("title_font_du"))))
	_status = ScreenKit.label("")
	box.add_child(_status)
	_bar = ProgressBar.new()
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0.0, 12.0)
	box.add_child(_bar)
	_roster = VBoxContainer.new()
	box.add_child(_roster)
	_leave = ScreenKit.button(tr(&"ui.common.leave"))
	ScreenKit.on(_leave.pressed, func() -> void: leave_requested.emit())
	box.add_child(_leave)
	refresh()


func _process(delta: float) -> void:
	model.tick(delta)
	refresh()


func initial_focus() -> Control:
	return _leave


func handle_back() -> bool:
	leave_requested.emit()
	return true


func state_key() -> StringName:
	match model.state():
		LoadingModel.State.DOWNLOADING_MAP:
			return &"ui.loading.downloading"
		LoadingModel.State.PREWARMING:
			return &"ui.loading.prewarming"
		LoadingModel.State.TIMEOUT:
			return &"ui.loading.timeout"
	return &"ui.loading.waiting"


func refresh() -> void:
	if _status == null:
		return
	_status.text = tr(state_key())
	_bar.value = model.progress01()
	for c: Node in _roster.get_children():
		c.queue_free()
	for i: int in model.names.size():
		var doc: String = model.doctrines[i] if i < model.doctrines.size() else ""
		var ready: bool = i < model.ready_flags.size() and model.ready_flags[i] != 0
		var row: Label = ScreenKit.label("%s   %s   %s" % [model.names[i], doc, tr(&"ui.loading.ready") if ready else "..."])
		_roster.add_child(row)
