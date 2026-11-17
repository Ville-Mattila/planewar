class_name ResultsScreen extends ScreenBase
## Results (06 s8): VICTORY, DEFEAT, TIME_LIMIT and the REMATCH_VOTE; binds every MATCH_END field via ResultsData.
## Thin: ResultsMath and RematchVote decide. scenes/ui/screens/results.tscn.

signal rematch_cast(yes: bool)
signal lobby_requested
signal menu_requested
signal report_requested

var data: ResultsData = ResultsData.new()
var vote: RematchVote = RematchVote.new()
var local_team: int = 0
var local_slot: int = 0
var medal_order: PackedStringArray = PackedStringArray()   ## medals.json ids, wire order
var _box: VBoxContainer
var _body: VBoxContainer
var _vote_label: Label
var _yes: Button
var _no: Button
var _menu: Button


func _ready() -> void:
	_box = ScreenKit.shell(self, 860.0)
	_body = VBoxContainer.new()
	_box.add_child(_body)
	_vote_label = ScreenKit.label("")
	_box.add_child(_vote_label)
	var row: HBoxContainer = HBoxContainer.new()
	_yes = ScreenKit.button(tr(&"ui.results.rematch_yes"))
	_no = ScreenKit.button(tr(&"ui.results.rematch_no"))
	ScreenKit.on(_yes.pressed, func() -> void: _cast(true))
	ScreenKit.on(_no.pressed, func() -> void: _cast(false))
	var lobby: Button = ScreenKit.button(tr(&"ui.results.lobby"))
	_menu = ScreenKit.button(tr(&"ui.results.menu"))
	var report: Button = ScreenKit.button(tr(&"ui.results.report"))
	ScreenKit.on(lobby.pressed, func() -> void: lobby_requested.emit())
	ScreenKit.on(_menu.pressed, func() -> void: menu_requested.emit())
	ScreenKit.on(report.pressed, func() -> void: report_requested.emit())
	for b: Button in [_yes, _no, lobby, _menu, report]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	_box.add_child(row)
	refresh()


## args: result (Dictionary, ResultsData.from_dict keys), local_team, local_slot, medal_order (Array of ids), rematch_allowed, eligible (Array of slots).
func enter(args: Dictionary) -> void:
	data = ResultsData.from_dict(ResultsRow._dict(args, "result"))
	local_team = ResultsRow._int(args, "local_team")
	local_slot = ResultsRow._int(args, "local_slot")
	medal_order = PackedStringArray(ResultsRow._arr(args, "medal_order"))
	var eligible: PackedInt32Array = PackedInt32Array(ResultsRow._arr(args, "eligible"))
	vote.open(eligible, ResultsRow._flag(args, "rematch_allowed"))
	refresh()


func _process(delta: float) -> void:
	vote.tick(delta)
	if _vote_label != null:
		_refresh_vote()


func initial_focus() -> Control:
	return _yes if vote.status == RematchVote.Status.PENDING else _menu


func handle_back() -> bool:
	menu_requested.emit()
	return true


func outcome() -> ResultsMath.Outcome:
	return ResultsMath.outcome(data.winner_team, data.end_reason, local_team)


func outcome_key() -> StringName:
	match outcome():
		ResultsMath.Outcome.VICTORY:
			return &"ui.results.victory"
		ResultsMath.Outcome.TIME_LIMIT:
			return &"ui.results.time_limit_win" if ResultsMath.local_won(data.winner_team, local_team) \
					else &"ui.results.time_limit_loss"
	return &"ui.results.defeat"


func _cast(yes: bool) -> void:
	if vote.cast(local_slot, yes):
		rematch_cast.emit(yes)
		_refresh_vote()


func _refresh_vote() -> void:
	var pending: bool = vote.status == RematchVote.Status.PENDING
	_yes.visible = vote.status != RematchVote.Status.DISABLED
	_no.visible = _yes.visible
	_yes.disabled = not pending or vote.vote_of(local_slot) != RematchVote.Vote.NONE
	_no.disabled = _yes.disabled
	match vote.status:
		RematchVote.Status.PENDING:
			_vote_label.text = tr(&"ui.results.vote").format({"s": int(ceilf(vote.left_s)), "y": vote.yes_count(),
					"n": vote.eligible_count()})
		RematchVote.Status.PASSED:
			_vote_label.text = tr(&"ui.results.vote_passed")
		RematchVote.Status.FAILED:
			_vote_label.text = tr(&"ui.results.vote_failed")
		_:
			_vote_label.text = ""


func refresh() -> void:
	if _body == null:
		return
	for c: Node in _body.get_children():
		c.queue_free()
	var colour: Color = UiTokens.UI_OK if ResultsMath.local_won(data.winner_team, local_team) else UiTokens.UI_DANGER
	_body.add_child(ScreenKit.label(tr(outcome_key()), int(ScreenParams.param("title_font_du")), colour))
	_body.add_child(ScreenKit.label(tr(ResultsMath.reason_key(data.end_reason))))
	_body.add_child(ScreenKit.label(_values_text()))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 220.0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_table())
	_body.add_child(scroll)
	_refresh_vote()


func _values_text() -> String:
	var parts: PackedStringArray = PackedStringArray()
	var loc: String = TranslationServer.get_locale()
	for t: int in data.team_ids():
		parts += PackedStringArray([tr(&"ui.results.structure_value").format({"t": t + 1, "v": Fmt.integer(data.value_of(t), loc)})])
	return "   ".join(parts)


func _table() -> VBoxContainer:
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head: PackedStringArray = PackedStringArray()
	for col: String in ResultsMath.COLUMNS:
		head += PackedStringArray([tr(StringName("ui.results.col." + col))])
	box.add_child(_line(head, UiTokens.UI_TEXT_DIM))
	var loc: String = TranslationServer.get_locale()
	for row: ResultsRow in ResultsMath.sorted_rows(data.rows):
		var c: Color = UiTokens.team_color(row.team)
		box.add_child(_line(ResultsMath.cells(row, loc), c))
		box.add_child(_detail(row))
	return box


func _line(cells: PackedStringArray, colour: Color) -> HBoxContainer:
	var h: HBoxContainer = HBoxContainer.new()
	for i: int in cells.size():
		var l: Label = ScreenKit.label(cells[i], 0, colour)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.custom_minimum_size = Vector2(ScreenParams.param("name_col_du") if i == 0 else ScreenParams.param("num_col_du"), 0.0)
		h.add_child(l)
	return h


## Medals and pilot time per class sit on their own line under the player.
func _detail(row: ResultsRow) -> Label:
	var parts: PackedStringArray = PackedStringArray()
	for id: String in ResultsMath.medal_ids(row, medal_order):
		parts += PackedStringArray([tr(StringName("ui.medal." + id))])
	for ct: PackedStringArray in ResultsMath.pilot_times(row):
		parts += PackedStringArray(["%s %s" % [tr(StringName("ui.results.class." + ct[0])), ct[1]]])
	var l: Label = ScreenKit.label("   ".join(parts), 0, UiTokens.UI_TEXT_DIM)
	l.custom_minimum_size = Vector2(ScreenParams.param("name_col_du") + 9.0 * ScreenParams.param("num_col_du"), 0.0)
	return l
