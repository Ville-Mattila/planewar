extends GdUnitTestSuite
## NET-17 ClientClock (04 s5.1): drift estimator (alpha 0.05), time dilation (0.95x .. 1.05x, never a jump while
## synced), 500 ms resync, render / input ticks.

const MS: float = 1000.0 / 30.0


func _run(c: ClientClock, from_tick: int, to_tick: int, latency_ticks: float, jitter: float, rng: RandomNumberGenerator) -> void:
	for t: int in range(from_tick, to_tick):
		c.observe(t, (float(t) + latency_ticks + rng.randf_range(-jitter, jitter)) * MS)
		c.advance((float(t) + latency_ticks) * MS)    # the physics tick: regular


func test_first_sample_syncs_and_render_tick_is_three_behind() -> void:
	var c: ClientClock = ClientClock.new(30)
	assert_bool(c.synced).is_false()
	c.advance(100.0)
	assert_float(c.clock).is_equal(0.0)
	c.observe(500, 1000.0)
	assert_bool(c.synced).is_true()
	assert_float(c.clock).is_equal_approx(500.0, 1e-6)
	assert_float(c.render_tick()).is_equal_approx(497.0, 1e-6)
	c.advance(1000.0 + MS)
	assert_float(c.clock).is_equal_approx(501.0, 1e-6)
	assert_int(c.resyncs).is_equal(1)


func test_estimator_filters_jitter() -> void:
	var c: ClientClock = ClientClock.new(30)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	_run(c, 1, 300, 3.0, 0.45, rng)          # TARGET: 100 ms +- 15 ms one way
	var est: float = c.estimate(299.0 * MS + 3.0 * MS)
	assert_float(absf(est - 299.0)).is_less(0.2)
	assert_float(absf(c.clock - est)).is_less(0.2)
	assert_int(c.resyncs).is_equal(1)


func test_latency_step_converges_within_2_s_without_a_jump() -> void:
	# TARGET one way 100 ms +- 15 ms; at tick 120 the one-way latency drops by 66 ms (2 ticks). The physics tick
	# calls advance at a regular 30 Hz; arrivals are jittered.
	var c: ClientClock = ClientClock.new(30)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 9
	var prev: float = 0.0
	var converged_at: int = -1
	for t: int in range(1, 300):
		var shift: float = 2.0 if t >= 120 else 0.0
		c.observe(t, (float(t) + 3.0 - shift + rng.randf_range(-0.45, 0.45)) * MS)
		var before: float = c.clock
		c.advance((float(t) + 3.0) * MS)
		if t > 3:
			assert_float(c.clock - before).is_between(0.95 - 1e-6, 1.05 + 1e-6)   # dilation only, never a jump
		prev = c.clock
		# converged: the clock reads the tick that arrives with the new latency (t + shift at this local time)
		if t >= 120 and converged_at < 0 and absf(c.clock - (float(t) + shift)) < 0.5:
			converged_at = t
	assert_float(prev).is_greater(0.0)
	assert_int(c.resyncs).is_equal(1)
	assert_int(converged_at).is_greater(0)
	assert_int(converged_at - 120).is_less_equal(60)


func test_rate_is_clamped_and_a_500_ms_discontinuity_resyncs() -> void:
	var c: ClientClock = ClientClock.new(30)
	c.observe(100, 0.0)
	c.offset += 5.0                          # estimate 5 ticks (167 ms) ahead: dilation, no jump
	c.advance(MS)
	assert_float(c.rate).is_equal_approx(1.0 + ClientClock.DILATION_MAX, 1e-9)
	assert_float(c.clock).is_equal_approx(101.05, 1e-6)
	c.offset -= 10.0
	c.advance(2.0 * MS)
	assert_float(c.rate).is_equal_approx(1.0 - ClientClock.DILATION_MAX, 1e-9)
	c.observe(200, 3.0 * MS)                 # 97 ticks = 3.2 s off: resync
	assert_int(c.resyncs).is_equal(2)
	assert_float(c.clock).is_equal_approx(200.0, 1e-6)


func test_input_tick_and_lead_dilation() -> void:
	var c: ClientClock = ClientClock.new(30)
	c.observe(1000, 0.0)
	c.observe_rtt(150.0)
	assert_float(c.rtt_ms).is_equal(150.0)
	assert_int(c.input_tick()).is_equal(1000 + 3 + 1)      # ceil(75 / 33.3) = 3, + INPUT_LEAD_TICKS
	for _i: int in 20:
		c.note_input_timing(1, 0)
	assert_float(c.lead).is_equal_approx(1.0, 1e-9)        # 1.05x for 20 ticks = one tick of lead
	assert_int(c.input_tick()).is_equal(1005)
	for _i: int in 40:
		c.note_input_timing(0, ClientClock.EARLY_TICKS + 1)
	assert_float(c.lead).is_equal_approx(-1.0, 1e-9)
	c.note_input_timing(0, ClientClock.EARLY_TICKS)        # exactly 6 early: hold
	assert_float(c.lead).is_equal_approx(-1.0, 1e-9)
	for _i: int in 400:
		c.note_input_timing(3, 0)
	assert_float(c.lead).is_equal(ClientClock.LEAD_MAX)


func test_reset_unsyncs_and_time_never_runs_backwards() -> void:
	var c: ClientClock = ClientClock.new(30)
	c.observe(50, 1000.0)
	c.advance(900.0)                         # an earlier timestamp: no step
	assert_float(c.clock).is_equal_approx(50.0, 1e-6)
	c.reset()
	assert_bool(c.synced).is_false()
	c.observe(70, 2000.0)
	assert_float(c.clock).is_equal_approx(70.0, 1e-6)
