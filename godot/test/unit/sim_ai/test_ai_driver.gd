extends GdUnitTestSuite
## AI-04: AiDriver scheduling. Each AI entity thinks exactly 30/P times per 30 ticks (P = 10 and 15), with an even
## stagger; event wake is next-tick and rate-limited to 1 per 5 ticks; bots follow 90/30/30/30 with a 4-tick stagger;
## AiState and driver S4 bytes round-trip; two identical runs are identical.


func _brain(d: AiDriver) -> AiTestKit.CountBrain:
	return d._brains[0] as AiTestKit.CountBrain


func _per_30(p: int) -> void:
	var d: AiDriver = AiTestKit.driver(47, p, p)
	AiTestKit.run(d, AiTestKit.StubView.new(), 1000, 30)
	var br: AiTestKit.CountBrain = _brain(d)
	for s: int in range(1, 48):
		assert_int(br.thinks[s]).is_equal(30 / p)


func test_thinks_30_over_p_times_per_30_ticks_p10() -> void:
	_per_30(10)


func test_thinks_30_over_p_times_per_30_ticks_p15() -> void:
	_per_30(15)


func test_stagger_fairness_p10_and_p15() -> void:
	for p: int in [10, 15]:
		var d: AiDriver = AiTestKit.driver(150, p, p)
		var v: AiTestKit.StubView = AiTestKit.StubView.new()
		var br: AiTestKit.CountBrain = _brain(d)
		var lo: int = 1 << 30
		var hi: int = 0
		for t: int in p:
			var before: int = d.stats()["thinks"]
			AiTestKit.run(d, v, 500 + t, 1)
			var k: int = int(d.stats()["thinks"]) - before
			lo = mini(lo, k)
			hi = maxi(hi, k)
		assert_int(lo).is_equal(150 / p)
		assert_int(hi).is_equal(150 / p)
		assert_int(br.per_tick_max).is_equal(150 / p)


func test_offline_profile_and_rung1_use_cut_period() -> void:
	var d: AiDriver = AiTestKit.driver(30, 10, 15)
	assert_int(d.think_period()).is_equal(10)
	d.set_offline_profile(true)
	assert_int(d.think_period()).is_equal(15)
	d.set_offline_profile(false)
	d.set_cut_rung1(true)
	assert_int(d.think_period()).is_equal(15)
	d.set_cut_rung1(false)
	d.set_offline_profile(true)
	AiTestKit.run(d, AiTestKit.StubView.new(), 0, 30)
	assert_int(_brain(d).thinks[7]).is_equal(2)


func test_act_runs_every_tick_for_whole_batch() -> void:
	var d: AiDriver = AiTestKit.driver(20)
	AiTestKit.run(d, AiTestKit.StubView.new(), 0, 30)
	assert_int(_brain(d).acts).is_equal(20 * 30)


func test_wake_thinks_next_tick_and_rate_limits() -> void:
	var d: AiDriver = AiTestKit.driver(10)
	var v: AiTestKit.StubView = AiTestKit.StubView.new()
	var id: int = EntityId.make(3, 1)
	var br: AiTestKit.CountBrain = _brain(d)
	AiTestKit.run(d, v, 0, 10)
	var base: int = br.thinks[3]
	assert_int(base).is_equal(1)
	assert_bool(d.wake(id, 10)).is_true()
	assert_bool(d.wake(id, 12)).is_false()
	assert_bool(d.wake(id, 14)).is_false()
	AiTestKit.run(d, v, 11, 1)
	assert_int(br.thinks[3]).is_equal(base + 1)
	assert_bool(d.wake(id, 15)).is_true()
	assert_bool(d.wake(EntityId.make(99, 1), 20)).is_false()


func test_wake_rate_one_per_five_ticks_over_a_run() -> void:
	var d: AiDriver = AiTestKit.driver(1, 90, 90)   # natural thinks are rare, so extras are wakes
	var v: AiTestKit.StubView = AiTestKit.StubView.new()
	var id: int = EntityId.make(1, 1)
	var sink: CommandSinkBase = CommandSinkBase.new()
	var accepted: int = 0
	for t: int in range(1, 101):
		if d.wake(id, t):
			accepted += 1
		d.on_tick(t, v, sink)
	assert_int(accepted).is_equal(20)
	assert_int(_brain(d).thinks[1]).is_between(20, 21)


func test_hit_event_wakes_and_death_unregisters_and_wakes_hunters() -> void:
	var d: AiDriver = AiTestKit.driver(5)
	var hit: SimEvent = SimEvent.new()
	hit.kind = SimEvent.Kind.HIT
	hit.a = EntityId.make(2, 1)
	hit.tick = 40
	d.on_event(hit)
	assert_int(d.state.wake_pending[2]).is_equal(1)
	d.state.target[4] = EntityId.make(5, 1)
	var dead: SimEvent = SimEvent.new()
	dead.kind = SimEvent.Kind.DEATH
	dead.a = EntityId.make(5, 1)
	dead.tick = 41
	d.on_event(dead)
	assert_int(d.state.cls[5]).is_equal(AiState.NO_CLASS)
	assert_int(d.state.wake_pending[4]).is_equal(1)
	assert_int(d.stats()["registered"]).is_equal(4)


func test_dead_and_possessed_do_not_think() -> void:
	var d: AiDriver = AiTestKit.driver(10)
	var v: AiTestKit.StubView = AiTestKit.StubView.new()
	v.possessed[EntityId.make(2, 1)] = true
	v.dead[EntityId.make(3, 1)] = true
	AiTestKit.run(d, v, 0, 10)
	var br: AiTestKit.CountBrain = _brain(d)
	assert_int(br.thinks[2]).is_equal(0)
	assert_int(br.thinks[3]).is_equal(0)
	assert_int(br.thinks[4]).is_equal(1)
	assert_int(d.state.cls[3]).is_equal(AiState.NO_CLASS)   # dead one dropped at its think


func test_bot_think_period_per_difficulty_tier() -> void:
	var expect: PackedInt32Array = PackedInt32Array([90, 30, 30, 30])
	for tier: int in 4:
		var d: AiDriver = AiTestKit.driver(0)
		d.schedule_bot(0, tier)
		AiTestKit.run(d, AiTestKit.StubView.new(), 0, 180)
		assert_int(_brain(d).bot_ticks.size()).is_equal(180 / expect[tier])


func test_bots_are_staggered_four_ticks_apart() -> void:
	var d: AiDriver = AiTestKit.driver(0)
	for k: int in 8:
		d.schedule_bot(k, 1)
	AiTestKit.run(d, AiTestKit.StubView.new(), 0, 30)
	var ticks: Dictionary = {}
	for rec: int in _brain(d).bot_ticks:
		ticks[rec / 100] = true
	assert_int(_brain(d).bot_ticks.size()).is_equal(8)
	assert_int(ticks.size()).is_equal(8)   # eight bots, eight distinct ticks
	d.unschedule_bot(7)
	assert_bool(d.bot_due(1, 1, 26)).is_true()   # (26 + 4) % 30 == 0


func test_register_rejects_duplicates_and_bad_class() -> void:
	var d: AiDriver = AiTestKit.driver(3)
	assert_bool(d.register(EntityId.make(2, 1), 0)).is_false()
	assert_bool(d.register(EntityId.make(9, 1), AiDriver.MAX_CLASSES)).is_false()
	assert_bool(d.unregister(EntityId.make(2, 2))).is_false()   # stale generation
	assert_bool(d.unregister(EntityId.make(2, 1))).is_true()
	assert_bool(d.register(EntityId.make(2, 2), 0)).is_true()


func test_ai_state_round_trip() -> void:
	var st: AiState = AiState.new(64)
	st.cls[5] = 2
	st.eid[5] = EntityId.make(5, 3)
	st.stagger[5] = 9
	st.set_mode(EntityId.make(5, 3), 4, 77)
	st.target[5] = 123
	st.guidance_vel[5] = Vector3(1.5, -2.0, 3.25)
	st.aim_lead[5] = Vector3(0.5, 0.25, -8.0)
	st.tti[5] = 2.5
	st.timer[5] = 0.75
	st.fire_mask[5] = 5
	st.path_ticket[5] = 12
	st.path[5] = PackedVector3Array([Vector3(1, 2, 3), Vector3(4, 5, 6)])
	st.cls[9] = 0
	st.wake_pending[9] = 1
	var bytes: PackedByteArray = st.serialize()
	var b: AiState = AiState.new(8)
	assert_bool(b.deserialize(bytes)).is_true()
	assert_bool(b.serialize() == bytes).is_true()
	assert_int(b.capacity).is_equal(64)
	assert_int(b.mode[5]).is_equal(4)
	assert_int(b.mode_since[5]).is_equal(77)
	assert_vector(b.guidance_vel[5]).is_equal(Vector3(1.5, -2.0, 3.25))
	assert_int((b.path[5] as PackedVector3Array).size()).is_equal(2)
	assert_int(b.cls[6]).is_equal(AiState.NO_CLASS)
	assert_bool(b.deserialize(bytes.slice(0, bytes.size() - 3))).is_false()
	assert_int(b.registered_count()).is_equal(0)


func test_driver_bytes_round_trip_continue_identically() -> void:
	var v: AiTestKit.StubView = AiTestKit.StubView.new()
	var a: AiDriver = AiTestKit.driver(40)
	a.set_offline_profile(true)
	a.schedule_bot(2, 3)
	AiTestKit.run(a, v, 0, 23)
	var _w: bool = a.wake(EntityId.make(7, 1), 23)
	a.state.target[3] = 99
	var bytes: PackedByteArray = a.serialize()
	var b: AiDriver = AiTestKit.driver(0)
	b.deserialize(bytes)
	assert_bool(b.serialize() == bytes).is_true()
	assert_int(b.think_period()).is_equal(15)
	var ba: AiTestKit.CountBrain = _brain(a)
	var bb: AiTestKit.CountBrain = _brain(b)
	ba.thinks.fill(0)
	AiTestKit.run(a, v, 23, 40)
	AiTestKit.run(b, v, 23, 40)
	assert_bool(ba.thinks == bb.thinks).is_true()
	assert_bool(a.serialize() == b.serialize()).is_true()
	b.deserialize(PackedByteArray())
	assert_int(b.stats()["registered"]).is_equal(0)


func test_determinism_two_runs_identical() -> void:
	var outs: Array[PackedByteArray] = []
	for _run: int in 2:
		var d: AiDriver = AiTestKit.driver(60)
		var v: AiTestKit.StubView = AiTestKit.StubView.new()
		AiTestKit.run(d, v, 0, 25)
		var _w: bool = d.wake(EntityId.make(11, 1), 25)
		AiTestKit.run(d, v, 25, 25)
		outs.append(d.serialize())
	assert_bool(outs[0] == outs[1]).is_true()


func test_world_hook_bytes_round_trip() -> void:
	var a: SimWorld = WorldTestKit.world(11)
	var da: AiDriver = AiDriver.new(Rng.new(11))
	a.set_ai_hook(da)
	var id: int = WorldTestKit.spawn(a, &"dart", 0, 0, WorldTestKit.at(300.0), Vector3(0.0, 50.0, 0.0))
	var _ok: bool = da.register(id, 1)
	var _e: Array[SimEvent] = ControlTestKit.step(a, 12)
	var db: AiDriver = AiDriver.new(Rng.new(11))
	var b: SimWorld = SimWorld.deserialize(a.serialize(), WorldTestKit.content(), db)
	assert_object(b).is_not_null()
	assert_int(db.stats()["registered"]).is_equal(1)
	assert_bool(db.serialize() == da.serialize()).is_true()
	a.step()
	b.step()
	assert_bool(a.serialize() == b.serialize()).is_true()


# AI-37 (R0 B.12 A-71): SPAWN registers a unit in its def's class, DEATH unregisters; driven through SimWorld.step.
const _MIX: Array[StringName] = [&"dart", &"lancer", &"bomber", &"scout", &"hauler", &"harvester", &"siege_crawler"]

var _world: SimWorld = null


func _mixed_world(d: AiDriver, n: int) -> PackedInt32Array:
	var w: SimWorld = WorldTestKit.world(37)
	w.set_ai_hook(d)
	d.set_class_table(AiClassTable.from_content(WorldTestKit.content()))
	for k: int in n:
		var def: StringName = _MIX[k % _MIX.size()]
		var p: int = k % 3
		var alt: float = 300.0 + 60.0 * float(k) if k % _MIX.size() < 5 else 0.0
		var pos: Vector3 = WorldTestKit.at(alt, 40.0 * float(k))
		var c: Command = CommandPayload.debug_spawn(p, WorldTestKit.def_id(def), p, 1 if p == 1 else 0, pos, Vector3.ZERO, Vector3(0, 1, 0))
		assert_int(w.apply_command(c).code).is_equal(CommandResult.Code.ACCEPTED)
	_world = w
	var ids: PackedInt32Array = PackedInt32Array()
	w.step()
	for e: SimEvent in w.drain_events():
		if e.kind == SimEvent.Kind.SPAWN:
			var _a: bool = ids.push_back(e.a)
	return ids


func test_class_table_maps_ships_then_ground_and_skips_structures() -> void:
	var t: PackedByteArray = AiClassTable.from_content(WorldTestKit.content())
	for k: int in _MIX.size():
		assert_int(AiClassTable.class_of(t, WorldTestKit.def_id(_MIX[k]))).is_equal(k)
	assert_int(AiClassTable.class_of(t, DefRanges.STRUCTURE_BASE)).is_equal(AiClassTable.NONE)
	assert_int(AiClassTable.class_of(t, -1)).is_equal(AiClassTable.NONE)
	assert_int(AiClassTable.class_of(PackedByteArray(), 3)).is_equal(AiClassTable.NONE)


func test_spawn_registers_50_mixed_units_in_their_class_and_death_unregisters() -> void:
	var d: AiDriver = AiDriver.new(Rng.new(37))
	var ids: PackedInt32Array = _mixed_world(d, 50)
	assert_int(ids.size()).is_equal(50)
	assert_int(d.state.registered_count()).is_equal(0)         # events reach the hook at step 3 of the next tick
	_world.step()
	var _ev: Array[SimEvent] = _world.drain_events()
	assert_int(d.state.registered_count()).is_equal(50)
	var per: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
	for k: int in ids.size():
		var s: int = EntityId.slot(ids[k])
		assert_int(d.state.eid[s]).is_equal(ids[k])
		assert_int(d.state.cls[s]).is_equal(k % _MIX.size())
		per[d.state.cls[s]] += 1
	assert_int(per[0]).is_equal(8)
	assert_int(per[6]).is_equal(7)
	var left: PackedInt32Array = ids.duplicate()      # the 04 s11.3 bucket spaces 50 + 50 commands out over a few ticks
	var guard: int = 0
	while not left.is_empty() and guard < 120:
		var rest: PackedInt32Array = PackedInt32Array()
		for k: int in left.size():
			var kill: Command = CommandPayload.debug_set(EntityId.slot(left[k]) % 3, left[k], CommandPayload.SET_KILL, 0.0)
			if _world.apply_command(kill).code != CommandResult.Code.ACCEPTED:
				var _p: bool = rest.push_back(left[k])
		left = rest
		_world.step()
		var _e2: Array[SimEvent] = _world.drain_events()
		guard += 1
	for _t: int in 3:
		_world.step()
		var _e3: Array[SimEvent] = _world.drain_events()
	assert_int(d.state.registered_count()).is_equal(0)


func test_possessed_unit_stays_registered_and_is_skipped() -> void:
	var d: AiDriver = AiDriver.new(Rng.new(38), 10, 10)
	var cb: AiTestKit.CountBrain = AiTestKit.CountBrain.new()
	for c: int in 7:
		d.set_brain(c, cb)
	var ids: PackedInt32Array = _mixed_world(d, 7)
	var dart: int = ids[0]
	var lancer: int = ids[1]
	assert_int(_world.apply_command(Command.possess(0, dart)).code).is_equal(CommandResult.Code.ACCEPTED)
	for _t: int in 60:
		_world.step()
		var _e: Array[SimEvent] = _world.drain_events()
	assert_int(d.state.registered_count()).is_equal(7)
	assert_int(cb.thinks[EntityId.slot(dart)]).is_equal(0)
	assert_int(cb.thinks[EntityId.slot(lancer)]).is_greater(0)


func test_spawn_registration_is_deterministic_and_empty_table_registers_nothing() -> void:
	var a: AiDriver = AiDriver.new(Rng.new(5))
	var _ia: PackedInt32Array = _mixed_world(a, 20)
	_world.step()
	var wa: SimWorld = _world
	var b: AiDriver = AiDriver.new(Rng.new(5))
	var _ib: PackedInt32Array = _mixed_world(b, 20)
	_world.step()
	assert_bool(a.serialize() == b.serialize()).is_true()
	assert_bool(wa.serialize() == _world.serialize()).is_true()
	var e: AiDriver = AiDriver.new(Rng.new(5))
	var spawn: SimEvent = SimEvent.new()
	spawn.kind = SimEvent.Kind.SPAWN
	spawn.a = EntityId.make(3, 1)
	spawn.b = WorldTestKit.def_id(&"dart")
	e.on_event(spawn)
	assert_int(e.state.registered_count()).is_equal(0)


# S4: a world saved between a SPAWN and its forwarding registers the unit after restore exactly as the original does.
func test_spawn_registration_survives_save_and_restore() -> void:
	var a: AiDriver = AiDriver.new(Rng.new(9))
	var ids: PackedInt32Array = _mixed_world(a, 12)
	var wa: SimWorld = _world
	var b: AiDriver = AiDriver.new(Rng.new(9))
	b.set_class_table(AiClassTable.from_content(WorldTestKit.content()))
	var wb: SimWorld = SimWorld.deserialize(wa.serialize(), WorldTestKit.content(), b)
	assert_object(wb).is_not_null()
	for _t: int in 5:
		wa.step()
		wb.step()
		assert_bool(wa.serialize() == wb.serialize()).is_true()
		var _ea: Array[SimEvent] = wa.drain_events()
		var _eb: Array[SimEvent] = wb.drain_events()
	assert_int(a.state.registered_count()).is_equal(ids.size())
	assert_int(b.state.registered_count()).is_equal(ids.size())
	assert_bool(a.serialize() == b.serialize()).is_true()
