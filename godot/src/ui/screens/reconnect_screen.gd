class_name ReconnectScreen extends ScreenBase
## Reconnecting overlay (06 s8, s9.1): "Resyncing..." or "Reconnecting...", auto-retries until the 120 s window ends,
## then offers Rejoin (the Adjutant holds the slot). Thin: ReconnectModel holds the state.
## scenes/ui/screens/reconnecting.tscn.

signal retry_due                 ## the host makes one reconnect attempt
signal rejoin_requested
signal leave_requested

var model: ReconnectModel = ReconnectModel.new()
var _title: Label
var _detail: Label
var _rejoin: Button
var _leave: Button


func _ready() -> void:
	var box: VBoxContainer = ScreenKit.shell(self, 420.0)
	_title = ScreenKit.label("", int(ScreenParams.param("title_font_du")))
	_detail = ScreenKit.label("")
	box.add_child(_title)
	box.add_child(_detail)
	_rejoin = ScreenKit.button(tr(&"ui.reconnect.rejoin"))
	ScreenKit.on(_rejoin.pressed, _on_rejoin)
	box.add_child(_rejoin)
	_leave = ScreenKit.button(tr(&"ui.common.leave"))
	ScreenKit.on(_leave.pressed, func() -> void: leave_requested.emit())
	box.add_child(_leave)
	refresh()


func enter(args: Dictionary) -> void:
	model.begin(ResultsRow._flag(args, "resync"))
	refresh()


func _process(delta: float) -> void:
	if model.tick(delta):
		retry_due.emit()
	refresh()


func initial_focus() -> Control:
	return _rejoin if model.state == ReconnectModel.State.REJOIN_OFFERED else _leave


func handle_back() -> bool:
	return true   # nothing to go back to: Leave is explicit


func _on_rejoin() -> void:
	if model.rejoin():
		rejoin_requested.emit()
		refresh()


func title_key() -> StringName:
	return &"ui.reconnect.resyncing" if model.state == ReconnectModel.State.RESYNCING else &"ui.reconnect.title"


func refresh() -> void:
	if _title == null:
		return
	var offered: bool = model.state == ReconnectModel.State.REJOIN_OFFERED
	_title.text = tr(title_key())
	if offered:
		_detail.text = tr(&"ui.reconnect.offer")
	else:
		_detail.text = tr(&"ui.reconnect.retrying").format({"s": int(ceilf(model.remaining_s())), "n": model.attempts})
	_rejoin.visible = offered
	if offered and not _rejoin.has_focus():
		_rejoin.grab_focus()
