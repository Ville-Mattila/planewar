extends GdUnitTestSuite
## UX-27 pause items, loading states and the Match overlay state (06 s8).


func _item(list: Array[PauseItem], id: StringName) -> PauseItem:
	for i: PauseItem in list:
		if i.id == id:
			return i
	return null


func test_pause_lists_every_item_of_the_spec_in_order() -> void:
	var l: Array[PauseItem] = PauseModel.items(true, false, "", true)
	var ids: Array[StringName] = []
	for i: PauseItem in l:
		ids.append(i.id)
	assert_array(ids).is_equal(PauseModel.IDS)


func test_skirmish_has_save_load_but_no_surrender() -> void:
	var l: Array[PauseItem] = PauseModel.items(false, true, PauseModel.SCOPE_IN_PROCESS, false)
	assert_bool(_item(l, &"save").enabled).is_true()
	assert_bool(_item(l, &"load").enabled).is_true()
	assert_bool(_item(l, &"surrender").enabled).is_false()
	assert_bool(_item(l, &"resume").enabled).is_true()


func test_coop_listen_host_has_no_save_load() -> void:
	var l: Array[PauseItem] = PauseModel.items(true, true, PauseModel.SCOPE_LISTEN_HOST, true)
	assert_bool(_item(l, &"save").enabled).is_false()
	assert_str(String(_item(l, &"save").reason_key)).is_equal("ui.pause.reason.no_save")
	assert_bool(_item(l, &"surrender").enabled).is_true()
	assert_bool(_item(l, &"players").enabled).is_true()


func test_online_surrender_needs_the_sim_to_accept_it() -> void:
	var l: Array[PauseItem] = PauseModel.items(true, false, "", false)
	assert_bool(_item(l, &"surrender").enabled).is_false()
	assert_str(String(_item(l, &"surrender").reason_key)).is_equal("ui.pause.reason.too_early")
	assert_str(String(_item(l, &"resume").reason_key)).is_equal("")


func test_pause_scope_of_the_sim() -> void:
	assert_bool(PauseModel.pauses_sim(false, "in_process", true)).is_true()
	assert_bool(PauseModel.pauses_sim(true, "listen_host", true)).is_true()
	assert_bool(PauseModel.pauses_sim(true, "listen_host", false)).is_false()
	assert_bool(PauseModel.pauses_sim(true, "", false)).is_false()


func test_loading_walks_its_four_states() -> void:
	var m: LoadingModel = LoadingModel.new()
	assert_int(m.state()).is_equal(LoadingModel.State.DOWNLOADING_MAP)
	m.set_progress(1.0, 0.2)
	assert_int(m.state()).is_equal(LoadingModel.State.PREWARMING)
	m.set_progress(1.0, 1.0)
	m.set_roster(PackedStringArray(["a", "b"]), PackedStringArray(["x", ""]), PackedByteArray([1, 0]))
	assert_int(m.state()).is_equal(LoadingModel.State.WAITING_PLAYERS)
	assert_float(m.progress01()).is_equal_approx(0.85, 0.001)
	m.tick(59.0)
	assert_int(m.state()).is_equal(LoadingModel.State.WAITING_PLAYERS)
	m.tick(2.0)
	assert_int(m.state()).is_equal(LoadingModel.State.TIMEOUT)


func test_loading_clock_only_runs_while_waiting() -> void:
	var m: LoadingModel = LoadingModel.new()
	m.tick(500.0)
	assert_int(m.state()).is_equal(LoadingModel.State.DOWNLOADING_MAP)
	assert_float(m.progress01()).is_equal(0.0)


func test_overlay_state_priority() -> void:
	var S: Script = OverlayState
	assert_object(S).is_not_null()
	assert_int(OverlayState.resolve(false, false, false, false, false, false)).is_equal(OverlayState.State.PLAYING)
	assert_int(OverlayState.resolve(false, false, false, false, false, true)).is_equal(OverlayState.State.PEEK)
	assert_int(OverlayState.resolve(false, false, false, true, true, true)).is_equal(OverlayState.State.ELIMINATED_COMMANDER)
	assert_int(OverlayState.resolve(false, false, true, true, false, false)).is_equal(OverlayState.State.PAUSED)
	assert_int(OverlayState.resolve(false, true, true, true, false, false)).is_equal(OverlayState.State.RECONNECTING)
	assert_int(OverlayState.resolve(true, true, true, true, true, true)).is_equal(OverlayState.State.ENDING)
	assert_int(OverlayState.resolve(false, false, false, false, true, false)).is_equal(OverlayState.State.SPECTATING)


func test_elimination_event_for_the_local_slot_only() -> void:
	var e: SimEvent = SimEvent.new()
	e.kind = SimEvent.Kind.PLAYER_ELIMINATED
	e.a = 2
	assert_bool(OverlayState.is_local_elimination(e, 2)).is_true()
	assert_bool(OverlayState.is_local_elimination(e, 0)).is_false()
	e.kind = SimEvent.Kind.DEATH
	assert_bool(OverlayState.is_local_elimination(e, 2)).is_false()
	var p: PlayerStateView = PlayerStateView.new()
	assert_bool(OverlayState.is_eliminated(p)).is_false()
	p.eliminated = true
	assert_bool(OverlayState.is_eliminated(p)).is_true()
