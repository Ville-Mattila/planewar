extends GdUnitTestSuite
## ProductionDrawer scene (UX-22; docs/06 s7.5): tiles fit at 800x360 / 1280x720, tile states from a mocked SimView,
## the commands each press emits, the detail page, the disabled drawer, focus navigation and the locale keys.

const SCENE: String = "res://scenes/ui/production_drawer.tscn"
const S := DrawerMath.State
const C := UiScale.Profile.COMPACT
const R := UiScale.Profile.REGULAR

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


func _drawer(p: UiScale.Profile, units: bool) -> ProductionDrawer:
	var d: ProductionDrawer = (load(SCENE) as PackedScene).instantiate() as ProductionDrawer
	add_child(d)
	auto_free(d)
	d.units_tab = units
	d.set_profile(p)
	var _a: int = d.command_ready.connect(func(c: Command) -> void: _got.append(c))
	var _b: int = d.build_armed.connect(func(id: StringName) -> void: _armed.append(id))
	d.refresh(_v, DrawerContextKit.from_view(_v, 0), Vector3.ZERO)
	return d


func _visible(d: ProductionDrawer) -> Array[DrawerTile]:
	var out: Array[DrawerTile] = []
	for t: DrawerTile in d.tile_nodes():
		if t.visible:
			out.append(t)
	return out


func test_18_tiles_exist_and_each_tab_shows_its_defs() -> void:
	var d: ProductionDrawer = _drawer(C, false)
	assert_int(d.tile_nodes().size()).is_equal(18)
	assert_int(_visible(d).size()).is_equal(16)
	d.units_tab = true
	d.refresh(_v, DrawerContextKit.from_view(_v, 0), Vector3.ZERO)
	assert_int(_visible(d).size()).is_equal(7)
	assert_str(String(_visible(d)[0].info.id)).is_equal("dart")


func test_tiles_fit_without_scrolling_at_800x360_and_1280x720() -> void:
	for case: Array in [[C, Vector2(800.0, 360.0)], [R, Vector2(1280.0, 720.0)]]:
		var p: UiScale.Profile = case[0]
		var canvas: Vector2 = case[1]
		var d: ProductionDrawer = _drawer(p, false)
		assert_bool(DrawerLayout.fits(p, canvas)).is_true()
		var box: Rect2 = Rect2(Vector2.ZERO, d.size)
		for t: DrawerTile in _visible(d):
			assert_bool(box.encloses(Rect2(t.position, t.size))).is_true()
			assert_float(t.size.x).is_greater_equal(44.0)                          # 06 s4.3 touch target
		var placed: Rect2 = Rect2(Vector2(0.0, DrawerLayout.top_du(p)), d.size)
		assert_bool(Rect2(Vector2.ZERO, canvas).encloses(placed)).is_true()
		assert_int(DrawerLayout.font_du(p)).is_greater_equal(9)                    # ADR-13: text >= 9 px at 1280x800


func test_tile_states_come_from_the_mocked_sim_view() -> void:
	_v.missing_tech[ContentDB.def_index(&"bomber")] = true
	_v.team_view.ore = 200
	var d: ProductionDrawer = _drawer(C, true)
	var by: Dictionary = {}
	for t: DrawerTile in _visible(d):
		by[t.info.id] = t.info.state
	assert_int(by[&"dart"]).is_equal(S.AVAILABLE)
	assert_int(by[&"lancer"]).is_equal(S.UNAFFORDABLE)
	assert_int(by[&"bomber"]).is_equal(S.LOCKED)
	assert_int(by[&"scout"]).is_equal(S.AVAILABLE)


func test_the_lock_shows_the_greyed_amount_and_the_reason() -> void:
	var info: TileInfo = DrawerModel.tile(_v, DrawerContextKit.from_view(_v, 0, 100), &"dart")
	assert_int(info.state).is_equal(S.SPEND_LOCKED)
	assert_vector(info.cost).is_equal(Vector2i(150, 0))
	assert_str(String(DrawerText.reason_key(info))).is_equal("ui.prod.reason.lock")
	var args: Dictionary = DrawerText.reason_args(info)
	assert_str(str(args["time"])).is_equal("2:00")
	assert_int(int(args["left"])).is_equal(100)
	assert_str(String(DrawerText.caption_key(info))).is_equal("ui.prod.tile.lock")
	_v.players[0].early_spend_left_ore = 100
	var d: ProductionDrawer = _drawer(C, true)
	assert_int(_visible(d)[0].info.state).is_equal(S.SPEND_LOCKED)                 # refresh reads the player's left share
	assert_str(String(DrawerText.reason_key(DrawerModel.tile(_v, DrawerContextKit.from_view(_v, 0, -1), &"dart")))).is_equal("")


func test_tapping_a_unit_tile_queues_one_at_the_best_factory() -> void:
	var d: ProductionDrawer = _drawer(C, true)
	_visible(d)[0].pressed.emit()
	assert_int(_got.size()).is_equal(1)
	assert_int(_got[0].kind).is_equal(Command.Kind.PRODUCE)
	assert_int(_got[0].target).is_equal(3)
	assert_int(_got[0].payload.decode_u8(2)).is_equal(1)


func test_tapping_a_blocked_tile_issues_nothing() -> void:
	_v.team_view.ore = 10
	var d: ProductionDrawer = _drawer(C, true)
	_visible(d)[0].pressed.emit()
	assert_int(_got.size()).is_equal(0)


func test_tapping_a_structure_tile_arms_placement() -> void:
	var d: ProductionDrawer = _drawer(R, false)
	_visible(d)[0].pressed.emit()
	assert_array(_armed).contains_exactly([&"outpost"])
	assert_int(_got.size()).is_equal(0)


func test_secondary_opens_the_detail_page_and_its_slots_issue_commands() -> void:
	_v.queues[3] = PackedInt32Array([ContentDB.def_index(&"dart"), ContentDB.def_index(&"dart")])
	var d: ProductionDrawer = _drawer(C, true)
	_visible(d)[0].secondary.emit(_visible(d)[0])
	var tiles: Array[DrawerTile] = _visible(d)
	assert_int(tiles.size()).is_equal(1 + 5 + 2)                                   # back, x5, cancel, - / value / +, two queue items
	assert_bool(tiles[0].plain_on).is_true()
	tiles[1].pressed.emit()                                                        # x5, clipped to the free slots
	assert_int(_got[0].kind).is_equal(Command.Kind.PRODUCE)
	assert_int(_got[0].payload.decode_u8(2)).is_equal(3)
	tiles[2].pressed.emit()                                                        # cancel one: the last item
	assert_int(_got[1].kind).is_equal(Command.Kind.CANCEL_PRODUCE)
	assert_int(_got[1].payload.decode_u8(0)).is_equal(1)
	tiles[5].pressed.emit()                                                        # replenish +
	assert_int(_got[2].kind).is_equal(Command.Kind.TOGGLE_AUTO_REPLENISH)
	assert_int(_got[2].payload.decode_u16(1)).is_equal(ContentDB.def_index(&"dart"))
	assert_int(_got[2].payload.decode_u8(3)).is_equal(1)
	tiles[6].pressed.emit()                                                        # queue item 1
	assert_int(_got[3].payload.decode_u8(0)).is_equal(0)
	tiles[0].pressed.emit()                                                        # back
	assert_int(_visible(d).size()).is_equal(7)
	assert_bool(_visible(d)[0].plain_on).is_false()


func test_detail_page_of_a_structure_cancels_its_sites() -> void:
	_v.add_structure(20, &"solar_array", 0, 0, Vector3.ZERO, DrawerMockView.BUILDING)
	var d: ProductionDrawer = _drawer(R, false)
	d.open_detail(&"solar_array")
	var tiles: Array[DrawerTile] = _visible(d)
	assert_int(tiles.size()).is_equal(2)                                           # back + the one site
	tiles[1].pressed.emit()
	assert_int(_got[0].kind).is_equal(Command.Kind.CANCEL_BUILD)
	assert_int(_got[0].target).is_equal(20)


func test_cancel_of_a_foreign_site_is_disabled_with_a_reason() -> void:
	var _o: PlayerStateView = _v.add_player(1, 0)
	_v.add_structure(21, &"solar_array", 1, 0, Vector3.ZERO, DrawerMockView.BUILDING)
	var d: ProductionDrawer = _drawer(R, false)
	d.open_detail(&"solar_array")
	var tiles: Array[DrawerTile] = _visible(d)
	assert_bool(tiles[1].disabled).is_true()
	tiles[1].pressed.emit()
	assert_int(_got.size()).is_equal(0)


func test_an_eliminated_commander_sees_the_drawer_disabled() -> void:
	_v.players[0].eliminated = true
	_v.players[0].commander_rights = false
	var d: ProductionDrawer = _drawer(C, true)
	for t: DrawerTile in _visible(d):
		assert_bool(t.disabled).is_true()


func test_focus_navigation_without_a_pointer() -> void:
	var d: ProductionDrawer = _drawer(C, false)
	d.focus_first()
	var tiles: Array[DrawerTile] = _visible(d)
	for t: DrawerTile in tiles:
		assert_int(t.focus_mode).is_equal(Control.FOCUS_ALL)
	assert_bool(tiles[0].has_focus()).is_true()
	assert_object(tiles[0].find_valid_focus_neighbor(SIDE_RIGHT)).is_same(tiles[1])
	assert_object(tiles[0].find_valid_focus_neighbor(SIDE_BOTTOM)).is_same(tiles[DrawerLayout.cols()])


func test_every_locale_key_exists_in_en_json() -> void:
	var en: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/locale/en.json"))
	var keys: Array[String] = ["ui.prod.tab.build", "ui.prod.tab.units", "ui.prod.badge.auto", "ui.prod.disabled.eliminated"]
	for id: StringName in DrawerCatalog.structure_ids() + DrawerCatalog.unit_ids():
		keys.append(DrawerCatalog.name_key(id))
	for st: int in DrawerMath.State.size():
		var i: TileInfo = TileInfo.new()
		i.state = st as DrawerMath.State
		i.need = &"hangar"
		keys.append(String(DrawerText.reason_key(i)))
		keys.append(String(DrawerText.caption_key(i)))
	for k: int in DetailSlot.Kind.size():
		var s: DetailSlot = DetailSlot.new()
		s.kind = k as DetailSlot.Kind
		keys.append(String(DrawerText.slot_key(s)))
	for c: int in DrawerMath.Cancel.size():
		keys.append(String(DrawerMath.cancel_reason(c as DrawerMath.Cancel)))
	for k: String in ["ui.prod.reason.queue_full", "ui.prod.reason.queue_empty", "ui.prod.reason.unavailable"]:
		keys.append(k)
	for k: String in keys:
		if k != "":
			assert_bool(en.has(k)).is_true()


func test_flag_and_kind_constants_match_the_sim() -> void:
	assert_int(DrawerModel.FLAG_BUILDING).is_equal(EntityStore.F_BUILDING)
	assert_int(DrawerMockView.BUILDING).is_equal(EntityStore.F_BUILDING)
