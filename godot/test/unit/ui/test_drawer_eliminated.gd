extends GdUnitTestSuite
## UX-22 round 2 (06 s7.5, U11): an eliminated commander's drawer emits nothing. Every input path is driven with an
## eliminated context: tile press, RMB, pad X, secondary, open_detail, every detail slot, replenish, a detail page that was
## open when the player was eliminated. Zero Commands and zero build_armed; the reason stays "Eliminated".

const SCENE: String = "res://scenes/ui/production_drawer.tscn"

var _v: DrawerMockView
var _got: Array[Command] = []
var _armed: Array[StringName] = []


func before_test() -> void:
	var r: Result = ContentDB.load_all()
	assert_bool(r.ok).is_true()
	_got = []
	_armed = []
	_v = DrawerMockView.new()
	var _p: PlayerStateView = _v.add_player(0, 0)
	_v.team_view.ore = 800
	_v.team_view.ice = 300
	_v.team_view.unit_cap = 20
	_v.team_view.structure_cap = 40
	_v.add_structure(1, &"core", 0, 0)
	_v.add_structure(2, &"refinery", 0, 0)
	_v.add_structure(3, &"shipyard", 0, 0)
	_v.add_structure(4, &"vehicle_bay", 0, 0)
	_v.queues[3] = PackedInt32Array([ContentDB.def_index(&"dart"), ContentDB.def_index(&"dart")])
	_v.add_structure(20, &"solar_array", 0, 0, Vector3.ZERO, DrawerMockView.BUILDING)


func _ctx(eliminated: bool) -> DrawerContext:
	_v.players[0].eliminated = eliminated
	_v.players[0].commander_rights = not eliminated
	return DrawerContextKit.from_view(_v, 0)


func _drawer(units: bool, eliminated: bool) -> ProductionDrawer:
	var d: ProductionDrawer = (load(SCENE) as PackedScene).instantiate() as ProductionDrawer
	add_child(d)
	auto_free(d)
	d.units_tab = units
	d.set_profile(UiScale.Profile.COMPACT)
	var _a: int = d.command_ready.connect(func(c: Command) -> void: _got.append(c))
	var _b: int = d.build_armed.connect(func(id: StringName) -> void: _armed.append(id))
	d.refresh(_v, _ctx(eliminated), Vector3.ZERO)
	return d


func _visible(d: ProductionDrawer) -> Array[DrawerTile]:
	var out: Array[DrawerTile] = []
	for t: DrawerTile in d.tile_nodes():
		if t.visible:
			out.append(t)
	return out


func _rmb() -> InputEventMouseButton:
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_RIGHT
	e.pressed = true
	return e


func _pad_x() -> InputEventJoypadButton:
	var e: InputEventJoypadButton = InputEventJoypadButton.new()
	e.button_index = JOY_BUTTON_X
	e.pressed = true
	return e


func _silent() -> void:
	assert_int(_got.size()).is_equal(0)
	assert_int(_armed.size()).is_equal(0)


func test_tile_presses_emit_nothing_on_both_tabs() -> void:
	for units: bool in [false, true]:
		var d: ProductionDrawer = _drawer(units, true)
		for t: DrawerTile in _visible(d):
			t.pressed.emit()
	_silent()


func test_rmb_and_pad_x_do_not_open_the_detail_page() -> void:
	var d: ProductionDrawer = _drawer(true, true)
	for t: DrawerTile in _visible(d):
		t._gui_input(_rmb())
		t.has_focus()
		t._gui_input(_pad_x())
		t.secondary.emit(t)
	for t: DrawerTile in _visible(d):
		assert_bool(t.plain_on).is_false()                                         # still the tile page
		t.pressed.emit()
	_silent()


func test_open_detail_is_refused_and_no_slot_can_emit() -> void:
	var d: ProductionDrawer = _drawer(true, true)
	d.open_detail(&"dart")
	for t: DrawerTile in d.tile_nodes():
		t.pressed.emit()
	d.open_detail(&"solar_array")
	for t: DrawerTile in d.tile_nodes():
		t.pressed.emit()
	_silent()
	for t: DrawerTile in d.tile_nodes():
		assert_bool(t.disabled).is_true()
		assert_bool(t.plain_on).is_false()


func test_elimination_while_the_detail_page_is_open_closes_it() -> void:
	var d: ProductionDrawer = _drawer(true, false)
	var first: DrawerTile = _visible(d)[0]
	first.secondary.emit(first)
	assert_bool(_visible(d)[0].plain_on).is_true()                                 # open for a live commander
	d.refresh(_v, _ctx(true), Vector3.ZERO)                                        # eliminated before the next press
	for t: DrawerTile in d.tile_nodes():
		assert_bool(t.disabled).is_true()
		t.pressed.emit()                                                           # batch, cancel, replenish, queue items
	_silent()
	assert_str(d._reason.text).is_equal(TranslationServer.translate(&"ui.prod.disabled.eliminated"))


func test_the_reason_stays_eliminated_after_every_path() -> void:
	var d: ProductionDrawer = _drawer(true, true)
	d.open_detail(&"dart")
	_visible(d)[0]._gui_input(_rmb())
	assert_str(d._reason.text).is_equal(TranslationServer.translate(&"ui.prod.disabled.eliminated"))


func test_a_live_commander_still_emits() -> void:
	var d: ProductionDrawer = _drawer(true, false)
	_visible(d)[0].pressed.emit()
	assert_int(_got.size()).is_equal(1)
	_visible(d)[0].secondary.emit(_visible(d)[0])
	_visible(d)[1].pressed.emit()
	assert_int(_got.size()).is_equal(2)
