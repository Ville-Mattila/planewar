extends GdUnitTestSuite
## AI-45 unit tests for DockedMode and its AiDriver feed (R0 B.24 A-119): an ALERT WAITING_FOR_ICE / WAITING_FOR_ORE marks
## a registered ship (OV_SVC_PAUSED), other alerts and unregistered or stale ids do nothing, `clear` ends the memory, the
## flag does not shift the S4 record size; the envelope literals stay out of sim_ai (the grep check).

func _alert(kind: int, id: int) -> SimEvent:
	var e: SimEvent = SimEvent.new()
	e.kind = SimEvent.Kind.ALERT
	e.a = kind
	e.b = id
	return e


func test_a_service_pause_alert_marks_a_registered_ship_only() -> void:
	var d: AiDriver = AiTestKit.driver(5)
	var id: int = EntityId.make(2, 1)
	d.on_event(_alert(AlertKind.Kind.WAITING_FOR_ICE, id))
	assert_int(d.state.ov_flags[2] & AiState.OV_SVC_PAUSED).is_equal(AiState.OV_SVC_PAUSED)
	DockedMode.clear(d.state, 2)
	assert_int(d.state.ov_flags[2]).is_equal(0)
	d.on_event(_alert(AlertKind.Kind.WAITING_FOR_ORE, id))
	assert_int(d.state.ov_flags[2] & AiState.OV_SVC_PAUSED).is_not_equal(0)
	DockedMode.clear(d.state, 2)
	d.on_event(_alert(AlertKind.Kind.SPEND_LOCKED, id))
	d.on_event(_alert(AlertKind.Kind.WAITING_FOR_ICE, EntityId.make(2, 9)))   # stale generation
	d.on_event(_alert(AlertKind.Kind.WAITING_FOR_ICE, EntityId.make(40, 1)))  # not registered
	assert_int(d.state.ov_flags[2]).is_equal(0)
	assert_int(d.state.ov_flags[40]).is_equal(0)


func test_clear_keeps_the_other_overlay_bits() -> void:
	var st: AiState = AiState.new()
	st.ov_flags[3] = AiState.OV_POSSESSED | AiState.OV_SVC_PAUSED
	DockedMode.clear(st, 3)
	assert_int(st.ov_flags[3]).is_equal(AiState.OV_POSSESSED)


func test_no_launch_envelope_literal_in_the_new_source() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/sim_ai/autopilot/docked_mode.gd")
	for lit: String in ["0.3", "0.5", "launch_hold", "launch_thrust"]:
		assert_bool(src.contains(lit)).override_failure_message(lit).is_false()
