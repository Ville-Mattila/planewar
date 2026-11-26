extends GdUnitTestSuite
## TA-69 LoadingJob: map output hashes verified through ChunkedHasher, one step per call.

const MAP: String = "res://content/maps/tiny_test"


func test_verifies_a_real_map_one_step_at_a_time() -> void:
	var job: LoadingJob = LoadingJob.new()
	assert_int(job.begin(MAP)).is_equal(OK)
	assert_bool(job.is_done()).is_false()
	var steps: int = 0
	var t0: int = Time.get_ticks_usec()
	while not job.step(0):   # budget 0: one chunk per step
		steps += 1
		assert_int(steps).is_less(100000)
	var us: float = float(Time.get_ticks_usec() - t0)
	assert_bool(PerfGate.check("loading_job_tiny_test", us, 2000000.0, "R0 B.17 A-97")).is_true()
	assert_int(job.error()).is_equal(OK)
	assert_float(job.progress()).is_equal(1.0)
	assert_int(steps).is_greater(0)


func test_missing_map_fails_without_crash() -> void:
	var job: LoadingJob = LoadingJob.new()
	assert_int(job.begin("res://content/maps/__nope__")).is_not_equal(OK)
	assert_bool(job.is_done()).is_true()


func test_corrupt_hash_is_reported() -> void:
	var job: LoadingJob = LoadingJob.new()
	assert_int(job.begin(MAP)).is_equal(OK)
	job.corrupt_expected_for_test()
	while not job.step(0):
		pass
	assert_int(job.error()).is_equal(ERR_FILE_CORRUPT)


func test_unavailable_user_storage_does_not_affect_res_maps() -> void:
	Saves.simulate_unavailable = true
	var job: LoadingJob = LoadingJob.new()
	var err: Error = job.begin(MAP)
	Saves.simulate_unavailable = false
	assert_int(err).is_equal(OK)
