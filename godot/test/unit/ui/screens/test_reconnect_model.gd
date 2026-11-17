extends GdUnitTestSuite
## UX-27 Reconnecting: auto-retries until the 120 s window, then offers Rejoin (06 s8, s9.1).


func test_window_matches_the_server_grace_and_loading_timeout() -> void:
	var r: Result = ContentDB.load_all()
	assert_bool(r.ok).is_true()
	assert_float(ScreenParams.param("reconnect_window_s")).is_equal(ContentDB.match_rules.reconnect_grace_s)
	assert_float(ScreenParams.param("loading_timeout_s")).is_equal(ContentDB.match_rules.load_timeout_s)


func test_transport_loss_retries_every_interval_then_offers_rejoin_at_120_s() -> void:
	var m: ReconnectModel = ReconnectModel.new()
	m.begin(false)
	assert_int(m.state).is_equal(ReconnectModel.State.RETRYING)
	var due: int = 0
	for i: int in 119:
		if m.tick(1.0):
			due += 1
	assert_int(m.state).is_equal(ReconnectModel.State.RETRYING)
	assert_int(due).is_greater_equal(30)
	assert_float(m.remaining_s()).is_equal_approx(1.0, 0.001)
	var _t: bool = m.tick(1.0)
	assert_int(m.state).is_equal(ReconnectModel.State.REJOIN_OFFERED)
	assert_bool(m.tick(5.0)).is_false()   # no auto-retry after the window
	assert_int(m.attempts).is_equal(due)


func test_stall_resyncs_for_60_s_then_retries() -> void:
	var m: ReconnectModel = ReconnectModel.new()
	m.begin(true)
	assert_int(m.state).is_equal(ReconnectModel.State.RESYNCING)
	for i: int in 60:
		assert_bool(m.tick(1.0)).is_false()
	assert_int(m.state).is_equal(ReconnectModel.State.RESYNCING)
	var fired: bool = false
	for i: int in 5:
		fired = m.tick(1.0) or fired
	assert_int(m.state).is_equal(ReconnectModel.State.RETRYING)
	assert_bool(fired).is_true()


func test_rejoin_only_when_offered_and_restarts_the_window() -> void:
	var m: ReconnectModel = ReconnectModel.new()
	m.begin(false)
	assert_bool(m.rejoin()).is_false()
	var _t: bool = m.tick(130.0)
	assert_int(m.state).is_equal(ReconnectModel.State.REJOIN_OFFERED)
	assert_bool(m.rejoin()).is_true()
	assert_int(m.state).is_equal(ReconnectModel.State.RETRYING)
	assert_float(m.remaining_s()).is_equal_approx(120.0, 0.001)
	assert_bool(m.tick(0.1)).is_true()   # an attempt right away


func test_recovery_closes_the_overlay() -> void:
	var m: ReconnectModel = ReconnectModel.new()
	m.begin(true)
	m.on_recovered()
	assert_int(m.state).is_equal(ReconnectModel.State.RECOVERED)
	assert_bool(m.is_open()).is_false()
	assert_bool(m.tick(1.0)).is_false()
