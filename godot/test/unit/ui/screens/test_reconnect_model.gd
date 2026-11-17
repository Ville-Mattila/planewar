extends GdUnitTestSuite
## UX-27 Reconnecting: auto-retries until the 120 s window, then offers Rejoin (06 s8, s9.1).


func before() -> void:
	assert_bool(ContentDB.load_all().ok).is_true()


func test_window_and_timeout_follow_the_match_rules_def() -> void:
	var rules: MatchRulesDef = ContentDB.match_rules
	var grace: float = rules.reconnect_grace_s
	var load_s: float = rules.load_timeout_s
	var m: ReconnectModel = ReconnectModel.new()
	assert_float(m.window_s()).is_equal(grace)
	rules.reconnect_grace_s = 30.0
	rules.load_timeout_s = 10.0
	m.begin(false)
	var _t: bool = m.tick(31.0)
	assert_int(m.state).is_equal(ReconnectModel.State.REJOIN_OFFERED)
	var l: LoadingModel = LoadingModel.new()
	l.set_progress(1.0, 1.0)
	l.tick(11.0)
	assert_int(l.state()).is_equal(LoadingModel.State.TIMEOUT)
	rules.reconnect_grace_s = grace
	rules.load_timeout_s = load_s


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
