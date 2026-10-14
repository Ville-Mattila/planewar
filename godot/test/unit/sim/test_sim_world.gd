extends GdUnitTestSuite
## SimWorld tick driver (TA-18; 03 s4.1, R0 B.5): S1 command queueing, S3 view validity, S5 event ticks, S11 drive
## refusal, the AI hook at step 3, the per-row profiler, set_budget_profile, step 5 (A-41 docked skip, terrain
## report to Collision), step 6 ProjectileMotion, step 9 deferred deaths, step 10 match timers.


func test_tick_counts_from_zero() -> void:
	var w: SimWorld = WorldTestKit.world()
	assert_int(w.tick()).is_equal(0)
	w.step()
	w.step()
	assert_int(w.tick()).is_equal(2)
	assert_int(w.view().tick()).is_equal(2)


func test_s1_apply_command_queues_and_step1_applies() -> void:
	var w: SimWorld = WorldTestKit.world()
	var id: int = WorldTestKit.spawn(w, &"dart", 0, 0, WorldTestKit.at(500.0))
	var before: PackedByteArray = WorldTestKit.store_bytes(w)
	var r: CommandResult = w.apply_command(Command.possess(0, id))
	assert_int(r.code).is_equal(CommandResult.Code.ACCEPTED)
	assert_bool(WorldTestKit.store_bytes(w) == before).is_true()        # queued only: no state change
	assert_int(w.view().possessor(id)).is_equal(-1)
	w.step()
	assert_int(w.view().possessor(id)).is_equal(0)
	assert_int(w.view().control_state(id)).is_equal(ControlMachine.State.POSSESSED)


func test_s1_pilot_input_is_stored_at_once_and_flown() -> void:
	var a: SimWorld = WorldTestKit.world()
	var b: SimWorld = WorldTestKit.world()
	var ida: int = WorldTestKit.spawn(a, &"dart", 0, 0, WorldTestKit.at(500.0), Vector3(0, 60, 0))
	var _idb: int = WorldTestKit.spawn(b, &"dart", 0, 0, WorldTestKit.at(500.0), Vector3(0, 60, 0))
	a.apply_command(Command.possess(0, ida))
	b.apply_command(Command.possess(0, ida))
	a.step()
	b.step()
	var inp: PilotInput = PilotInput.new()
	inp.thrust = 1.0
	assert_int(a.apply_command(Command.pilot(0, a.tick() + 1, inp)).code).is_equal(CommandResult.Code.ACCEPTED)
	a.step()
	b.step()
	assert_float(a.view().vel(ida).y).is_greater(b.view().vel(ida).y)


func test_s3_view_reads_are_stable_until_step_and_reuse_objects() -> void:
	var w: SimWorld = WorldTestKit.world()
	var id: int = WorldTestKit.spawn(w, &"dart", 0, 0, WorldTestKit.at(500.0), Vector3(0, 60, 0))
	var v: SimView = w.view()
	var p0: Vector3 = v.pos(id)
	assert_vector(v.pos(id)).is_equal(p0)
	assert_object(v.team_state(0)).is_same(v.team_state(0))
	assert_object(v.player_state(1)).is_same(v.player_state(1))
	w.apply_command(Command.order(0, PackedInt32Array([id]), OrderSpec.make(OrderSpec.Kind.MOVE, 0, WorldTestKit.at(800.0, 300.0))))
	assert_vector(v.pos(id)).is_equal(p0)                    # a queued command does not move anything
	w.step()
	assert_vector(v.pos(id)).is_not_equal(p0)
	var h: OrderSpec = v.order_head(id)
	assert_object(h).is_not_null()
	assert_object(v.order_head(id)).is_same(h)
	assert_int(h.kind).is_equal(OrderSpec.Kind.MOVE)
	assert_int(v.order_issuer(id)).is_equal(0)
	assert_int(v.control_state(id)).is_equal(ControlMachine.State.ORDERED)


func test_s5_every_event_has_the_tick_of_its_step() -> void:
	var w: SimWorld = WorldTestKit.world(7, WorldTestKit.rules(0.2, 0.4))
	WorldTestKit.queue_spawn(w, &"dart", 0, 0, WorldTestKit.at(500.0))
	var seen: int = 0
	for _i: int in 20:
		w.step()
		for e: SimEvent in w.drain_events():
			assert_int(e.tick).is_equal(w.tick())
			seen += 1
	assert_int(seen).is_greater_equal(3)                     # SPAWN, CORE_EXPOSURE, MATCH_END


func test_s11_drive_on_possessed_id_returns_false_and_leaves_the_slot() -> void:
	var w: SimWorld = WorldTestKit.world()
	var twin: SimWorld = WorldTestKit.world()
	var id: int = WorldTestKit.spawn(w, &"dart", 0, 0, WorldTestKit.at(500.0), Vector3(0, 60, 0))
	var _t: int = WorldTestKit.spawn(twin, &"dart", 0, 0, WorldTestKit.at(500.0), Vector3(0, 60, 0))
	var hook: WorldTestKit.RecordingHook = WorldTestKit.RecordingHook.new()
	hook.drive_id = id
	hook.input.thrust = 1.0
	hook.input.pitch = 1.0
	w.set_ai_hook(hook)
	var twin_hook: WorldTestKit.RecordingHook = WorldTestKit.RecordingHook.new()
	twin_hook.drive_id = id
	twin_hook.input = hook.input
	twin.set_ai_hook(twin_hook)
	w.step()                                                 # AUTO: drive accepted in both
	twin.step()
	twin_hook.drive_id = 0                                   # the twin stops driving; w keeps trying
	assert_bool(hook.drive_results[0]).is_true()
	w.apply_command(Command.possess(0, id))
	twin.apply_command(Command.possess(0, id))
	for _i: int in 5:
		w.step()
		twin.step()
	for k: int in range(1, 6):
		assert_bool(hook.drive_results[k]).is_false()
		assert_int(hook.possessor_seen[k]).is_equal(0)      # step 1 applied before the hook ran
	# the refused drives left the slot alone: w flew exactly like the twin that stopped driving
	assert_vector(w.view().pos(id)).is_equal(twin.view().pos(id))


func test_drive_refuses_dead_and_wreck_ids() -> void:
	var w: SimWorld = WorldTestKit.world()
	var hook: WorldTestKit.RecordingHook = WorldTestKit.RecordingHook.new()
	hook.drive_id = EntityId.make(5, 1)
	w.set_ai_hook(hook)
	w.step()
	assert_bool(hook.drive_results[0]).is_false()


func test_hook_runs_once_per_tick_after_commands_before_kinematics() -> void:
	var w: SimWorld = WorldTestKit.world()
	var hook: WorldTestKit.RecordingHook = WorldTestKit.RecordingHook.new()
	w.set_ai_hook(hook)
	for _i: int in 4:
		w.step()
	assert_array(Array(hook.ticks)).is_equal([1, 2, 3, 4])


func test_profile_has_14_rows_and_is_populated_when_enabled() -> void:
	var w: SimWorld = WorldTestKit.world(7, WorldTestKit.rules(-1.0, -1.0, true))
	for k: int in 20:
		WorldTestKit.queue_spawn(w, &"dart", k % 2, k % 2, WorldTestKit.at(300.0 + 10.0 * k, 25.0 * k), Vector3(0, 50, 0))
	for _i: int in 3:
		w.step()
	var p: PackedFloat32Array = w.profile()
	assert_int(p.size()).is_equal(TickProfiler.ROWS)
	assert_float(p[TickProfiler.ROW_TOTAL]).is_greater(0.0)
	assert_float(p[TickProfiler.ROW_KINEMATICS]).is_greater(0.0)
	var parts: float = 0.0
	for r: int in range(TickProfiler.ROW_COMMANDS, TickProfiler.ROW_TOTAL):
		assert_float(p[r]).is_greater_equal(0.0)
		parts += p[r]
	assert_float(parts).is_less_equal(p[TickProfiler.ROW_TOTAL] + 0.01)
	var off: SimWorld = WorldTestKit.world()
	off.step()
	assert_float(off.profile()[TickProfiler.ROW_TOTAL]).is_equal(0.0)


func test_set_budget_profile_rewrites_the_rung_list() -> void:
	var r: MatchRules = WorldTestKit.rules()
	var w: SimWorld = WorldTestKit.world(7, r)
	assert_array(Array(r.sim_budget_profile)).is_equal([1, 2])     # rules.json default
	w.set_budget_profile(4)
	assert_array(Array(r.sim_budget_profile)).is_equal([1, 2, 3, 4])
	w.set_budget_profile(0)
	assert_int(r.sim_budget_profile.size()).is_equal(0)


func test_step5_skips_docked_ships() -> void:
	var w: SimWorld = WorldTestKit.world()
	var id: int = WorldTestKit.spawn(w, &"dart", 0, 0, WorldTestKit.at(500.0), Vector3(0, 60, 0))
	var s: int = EntityId.slot(id)
	w.store().flags[s] |= EntityStore.F_DOCKED
	var p: Vector3 = w.store().pos[s]
	var f: float = w.store().fuel[s]
	for _i: int in 10:
		w.step()
	assert_vector(w.store().pos[s]).is_equal(p)
	assert_float(w.store().fuel[s]).is_equal(f)


func test_step5_reports_terrain_contact_to_collision() -> void:
	var w: SimWorld = WorldTestKit.world()
	var c: FlightCommonDef = WorldTestKit.content().flight_common
	var id: int = WorldTestKit.spawn(w, &"dart", 0, 0, WorldTestKit.at(30.0), Vector3(-(c.terrain_kill_speed + 10.0), 0, 0))
	var found: bool = false
	for _i: int in 30:
		w.step()
		for k: int in w.collision.contact_count:
			if w.collision.c_kind[k] == Collision.C_TERRAIN and w.collision.c_a[k] == id:
				found = true
				assert_int(w.collision.c_class[k]).is_equal(Collision.T_DESTROY)
		if found:
			break
	assert_bool(found).is_true()
	assert_int(w.collision.ep_gen[EntityId.slot(id)]).is_equal(EntityId.gen(id))


func test_step6_moves_straight_and_ballistic_projectiles() -> void:
	var w: SimWorld = WorldTestKit.world()
	var dt: float = 1.0 / float(WorldTestKit.content().rules.tick_hz)
	var p0: Vector3 = WorldTestKit.at(900.0)
	var slug: int = WorldTestKit.projectile(w, &"slug_light", p0, Vector3(0, 400, 0), 0, 5.0)
	var bomb: int = WorldTestKit.projectile(w, &"bomb", p0, Vector3(0, 50, 0), 0, 5.0)
	w.step()
	var ps: ProjectileStore = w.projectiles()
	var i: int = ps.index_of(slug)
	assert_vector(ps.prev_pos[i]).is_equal(p0)
	assert_vector(ps.pos[i]).is_equal(p0 + Vector3(0, 400, 0) * dt)
	assert_float(ps.ttl[i]).is_equal_approx(5.0 - dt, 1e-6)
	var j: int = ps.index_of(bomb)
	var bdef: ProjectileDef = WorldTestKit.content().projectiles[ps.projectile_def[j]]
	var want: ProjectileState = Kinematics.step_projectile(p0, Vector3(0, 50, 0), bdef, WorldTestKit.content().rules, dt)
	assert_vector(ps.pos[j]).is_equal(want.p)
	assert_vector(ps.vel[j]).is_equal(want.v)


func test_step6_frees_expired_projectiles() -> void:
	var w: SimWorld = WorldTestKit.world()
	var id: int = WorldTestKit.projectile(w, &"slug_light", WorldTestKit.at(900.0), Vector3(0, 400, 0), 0, 0.05)
	w.step()
	assert_bool(w.projectiles().alive(id)).is_true()
	w.step()
	assert_bool(w.projectiles().alive(id)).is_false()


func test_step6_guided_reaim_is_rate_limited() -> void:
	var w: SimWorld = WorldTestKit.world()
	var dt: float = 1.0 / float(WorldTestKit.content().rules.tick_hz)
	var tgt: int = WorldTestKit.spawn(w, &"dart", 1, 1, WorldTestKit.at(900.0, 0.0) + Vector3(0, 0, 500))
	var id: int = WorldTestKit.projectile(w, &"rocket", WorldTestKit.at(900.0), Vector3(0, 200, 0), 0, 5.0)
	var ps: ProjectileStore = w.projectiles()
	var i: int = ps.index_of(id)
	ps.flags[i] |= ProjectileStore.F_GUIDED
	ps.target[i] = tgt
	var wi: int = int(WorldTestKit.content().weapon_index.get(&"rocket_lancer", -1)) - DefRanges.WEAPON_BASE
	ps.weapon_def[i] = maxi(wi, 0)
	var v0: Vector3 = ps.vel[i]
	w.step()
	var turned: float = rad_to_deg(v0.angle_to(ps.vel[i]))
	var lim: float = WorldTestKit.content().weapons[ps.weapon_def[i]].turn_rate_dps * dt
	assert_float(turned).is_greater(0.0)
	assert_float(turned).is_less_equal(lim + 0.5)           # + parallel transport of one tick


func test_step9_projectile_contact_ends_the_projectile() -> void:
	var w: SimWorld = WorldTestKit.world()
	var tgt: int = WorldTestKit.spawn(w, &"dart", 1, 1, WorldTestKit.at(900.0, 10.0))
	var id: int = WorldTestKit.projectile(w, &"slug_light", WorldTestKit.at(900.0), Vector3(0, 400, 0), 0, 5.0)
	w.step()
	assert_bool(w.projectiles().alive(id)).is_false()
	assert_bool(w.store().alive(tgt)).is_true()             # damage is Combat's (GD-08)


func test_debug_kill_is_deferred_to_step9_with_release_first() -> void:
	var w: SimWorld = WorldTestKit.world()
	var id: int = WorldTestKit.spawn(w, &"dart", 0, 0, WorldTestKit.at(500.0))
	w.apply_command(Command.possess(0, id))
	w.step()
	var _d: Array[SimEvent] = w.drain_events()
	w.apply_command(CommandPayload.debug_set(0, id, CommandPayload.SET_KILL, 0.0))
	w.step()
	var ev: Array[SimEvent] = w.drain_events()
	assert_array(Array(WorldTestKit.kinds(ev))).is_equal([SimEvent.Kind.RELEASED, SimEvent.Kind.DEATH])
	assert_int(ev[0].extra[0]).is_equal(ControlMachine.ReleaseReason.DEATH)
	assert_bool(w.store().alive(id)).is_false()
	assert_int(w.view().player_state(0).possessed).is_equal(0)


func test_disconnect_releases_in_the_next_step1() -> void:
	var w: SimWorld = WorldTestKit.world()
	var id: int = WorldTestKit.spawn(w, &"dart", 1, 1, WorldTestKit.at(500.0))
	w.apply_command(Command.possess(1, id))
	w.step()
	var _d: Array[SimEvent] = w.drain_events()
	w.remove_player(1)
	assert_int(w.view().possessor(id)).is_equal(1)
	assert_bool(w.view().player_state(1).connected).is_false()
	w.step()
	var ev: Array[SimEvent] = w.drain_events()
	assert_int(ev[0].kind).is_equal(SimEvent.Kind.RELEASED)
	assert_int(ev[0].extra[0]).is_equal(ControlMachine.ReleaseReason.DISCONNECT)
	assert_int(w.view().possessor(id)).is_equal(-1)


func test_ceiling_releases_a_possessed_ship() -> void:
	var w: SimWorld = WorldTestKit.world()
	var hard: float = WorldTestKit.content().rules.ceiling_hard_m
	var id: int = WorldTestKit.spawn(w, &"dart", 0, 0, WorldTestKit.at(hard - 60.0))
	w.apply_command(Command.possess(0, id))
	w.step()
	var _d: Array[SimEvent] = w.drain_events()
	w.store().pos[EntityId.slot(id)] = WorldTestKit.at(hard + 1.0)
	w.step()
	var ev: Array[SimEvent] = w.drain_events()
	assert_array(Array(WorldTestKit.kinds(ev))).is_equal([SimEvent.Kind.RELEASED, SimEvent.Kind.CEILING_RELEASE])
	assert_int(w.store().overlay[EntityId.slot(id)]).is_equal(ControlMachine.Overlay.RECOVER_CEILING)


func test_match_timers_fire_once_and_end_rejects_commands() -> void:
	var w: SimWorld = WorldTestKit.world(7, WorldTestKit.rules(0.1, 0.2))
	var hz: int = WorldTestKit.content().rules.tick_hz
	var got: PackedInt32Array = PackedInt32Array()
	for _i: int in hz:
		w.step()
		for e: SimEvent in w.drain_events():
			got.push_back(e.kind)
			got.push_back(e.tick)
	var exp_t: int = ceili(0.1 * hz)
	var end_t: int = ceili(0.2 * hz)
	assert_array(Array(got)).is_equal([SimEvent.Kind.CORE_EXPOSURE, exp_t, SimEvent.Kind.MATCH_END, end_t])
	assert_int(w.view().match_phase()).is_equal(MatchRules.Phase.ENDED)
	assert_int(w.apply_command(Command.release(0)).code).is_equal(CommandResult.Code.REJECTED_PHASE)
