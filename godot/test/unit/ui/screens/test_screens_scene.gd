extends GdUnitTestSuite
## UX-27 scenes instantiate headless, take initial focus without a pointer, and keep text >= the 9 du floor.

const DIR: String = "res://scenes/ui/screens/"


func before() -> void:
	assert_bool(ContentDB.load_all().ok).is_true()


func _make(file: String) -> Control:
	var s: Control = (load(DIR + file) as PackedScene).instantiate() as Control
	add_child(s)
	return s


func test_every_screen_scene_instantiates() -> void:
	for f: String in ["loading.tscn", "reconnecting.tscn", "pause.tscn", "results.tscn", "eliminated.tscn"]:
		var s: Control = _make(f)
		assert_object(s).is_not_null()
		s.free()


func test_font_floor() -> void:
	assert_int(ScreenKit.font_px()).is_greater_equal(int(HudMath.param("font_du_min")))
	assert_int(int(ScreenParams.param("button_h_du"))).is_greater_equal(44)


func test_reconnect_screen_offers_rejoin_after_the_window() -> void:
	var s: ReconnectScreen = _make("reconnecting.tscn") as ReconnectScreen
	s.enter({"resync": false})
	var due: Array[int] = [0]
	s.retry_due.connect(func() -> void: due[0] += 1)
	s._process(3.5)
	assert_int(due[0]).is_equal(1)
	assert_str(String(s.title_key())).is_equal("ui.reconnect.title")
	assert_bool(s._rejoin.visible).is_false()
	s._process(130.0)
	assert_bool(s._rejoin.visible).is_true()
	assert_object(s.initial_focus()).is_same(s._rejoin)
	var asked: Array[int] = [0]
	s.rejoin_requested.connect(func() -> void: asked[0] += 1)
	s._rejoin.pressed.emit()
	assert_int(asked[0]).is_equal(1)
	assert_bool(s._rejoin.visible).is_false()
	assert_bool(s.handle_back()).is_true()
	s.free()


func test_resyncing_title() -> void:
	var s: ReconnectScreen = _make("reconnecting.tscn") as ReconnectScreen
	s.enter({"resync": true})
	assert_str(String(s.title_key())).is_equal("ui.reconnect.resyncing")
	s.free()


func test_pause_screen_focus_order_and_disabled_reasons() -> void:
	var s: PauseScreen = _make("pause.tscn") as PauseScreen
	s.configure(PauseModel.items(false, false, "", false))
	assert_object(s.initial_focus()).is_same(s.button_of(&"resume"))
	assert_bool(s.button_of(&"save").disabled).is_true()
	assert_bool(s.button_of(&"leave").disabled).is_false()
	var got: Array[StringName] = []
	s.item_chosen.connect(func(id: StringName) -> void: got.append(id))
	assert_bool(s.handle_back()).is_true()
	assert_array(got).is_equal([&"resume"])
	s.free()


func test_results_screen_binds_outcome_and_vote() -> void:
	var s: ResultsScreen = _make("results.tscn") as ResultsScreen
	var order: Array = ["feather_touch"]
	s.enter({
		"result": {"winner_team": 0, "end_reason": 1, "tick": 10, "structure_value": [5, 3],
				"players": [{"slot": 0, "team": 0, "name": "Ville", "medals": [1], "pilot_time_s": [5, 0, 0, 0, 0]},
				{"slot": 2, "team": 1, "name": "Aino"}]},
		"local_team": 0, "local_slot": 0, "medal_order": order, "rematch_allowed": true,
		"eligible": [0, 2],
	})
	assert_int(s.outcome()).is_equal(ResultsMath.Outcome.TIME_LIMIT)
	assert_str(String(s.outcome_key())).is_equal("ui.results.time_limit_win")
	assert_object(s.initial_focus()).is_same(s._yes)
	var cast: Array[bool] = []
	s.rematch_cast.connect(func(y: bool) -> void: cast.append(y))
	s._yes.pressed.emit()
	assert_array(cast).is_equal([true])
	assert_bool(s._yes.disabled).is_true()
	s._process(25.0)
	assert_int(s.vote.status).is_equal(RematchVote.Status.FAILED)
	assert_bool(s.handle_back()).is_true()
	s.free()


func test_loading_and_eliminated_overlay_text() -> void:
	var l: LoadingScreen = _make("loading.tscn") as LoadingScreen
	assert_str(String(l.state_key())).is_equal("ui.loading.downloading")
	l.model.set_progress(1.0, 1.0)
	l.model.tick(61.0)
	l.model.tick(61.0)
	assert_str(String(l.state_key())).is_equal("ui.loading.timeout")
	assert_object(l.initial_focus()).is_not_null()
	l.free()
	var _n: int = LocaleSelect.register_translations("res://content/locale")
	var _l: String = LocaleSelect.apply("en")
	var e: EliminatedOverlay = _make("eliminated.tscn") as EliminatedOverlay
	assert_bool(e.visible).is_false()
	e.show_for(45.0)
	assert_bool(e.visible).is_true()
	assert_str(e.hint_text()).contains("0:45")
	e.hide_overlay()
	assert_bool(e.visible).is_false()
	e.free()
