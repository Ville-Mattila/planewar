extends GdUnitTestSuite
## TEST-04 (R0 B.17 A-98): the `ai` scenario of test/perf/perf_tick_world.gd drives 48 registered Darts with the real
## AiDriver (no OrbitHook), one in four starts inside gun fire_range of an enemy, and the population holds while stepping.


func test_ai_world_shape_and_mix() -> void:
	var pw: PerfTickWorld = PerfTickWorld.new(24, 8, 16, 4, 60, &"", true)
	assert_object(pw.driver).is_not_null()
	assert_int(pw.ai_darts.size()).is_equal(PerfTickWorld.AI_DARTS)
	var st: EntityStore = pw.world.store()
	var fire_range: float = DartKit.params().fire_range
	var engaged: int = 0
	for s: int in pw.ai_darts:
		assert_int(pw.driver.state.cls[s]).is_equal(DartKit.CLS_DART)
		for o: int in pw.ai_darts:
			if st.team[o] != st.team[s] and st.pos[s].distance_to(st.pos[o]) < fire_range:
				engaged += 1
				break
	assert_int(engaged).is_equal(MathX.floori_div(PerfTickWorld.AI_DARTS, PerfTickWorld.AI_ENGAGED_EVERY))


func test_ai_world_steps_and_keeps_population() -> void:
	var pw: PerfTickWorld = PerfTickWorld.new(24, 8, 16, 4, 60, &"", true)
	for _i: int in 90:
		pw.world.step()
		var _ev: Array[SimEvent] = pw.world.drain_events()
		pw.top_up()
	assert_int(pw.world.store().ships.size()).is_equal(PerfTickWorld.AI_DARTS)
	assert_int(pw.driver.stats()["thinks"]).is_greater(0)


func test_ai_mix_holds_after_respawns() -> void:
	var pw: PerfTickWorld = PerfTickWorld.new(24, 8, 16, 4, 60, &"", true)
	var st: EntityStore = pw.world.store()
	var fire_range: float = DartKit.params().fire_range
	for k: int in [0, 5, 7]:   # a team-0 pair member, a team-1 pair member, another team-1 pair member
		assert_bool(st.free_slot(pw.ai_darts[k], pw.world.tick())).is_true()
	pw.top_up()
	assert_int(pw.respawns).is_equal(3)
	for pair: int in [0, 2, 3]:
		var a: int = pw.ai_darts[pair * 2]
		var b: int = pw.ai_darts[pair * 2 + 1]
		assert_float(st.pos[a].distance_to(st.pos[b])).is_less(fire_range)
