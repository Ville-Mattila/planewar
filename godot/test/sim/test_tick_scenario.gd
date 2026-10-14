extends GdUnitTestSuite
## Scenario layer (TA-18 acceptance): a scripted 100-tick match through SimWorld.step() in the R0 B.5 order yields
## exactly the expected event sequence: spawns, possession hand-offs (05 C6 / C9), a refused cross-team possess,
## a deferred death, a pending order on a possessed ship (C7), Core Exposure, a disconnect release (C12) and the
## hard end releasing every possession (C16) before MATCH_END; commands after the end get REJECTED_PHASE.
## Commands are queued before the step that applies them, so "at t" means step t's events.

const EXPOSURE_S: float = 2.0
const HARD_END_S: float = 3.0


func test_scripted_100_ticks_event_sequence() -> void:
	var hz: int = WorldTestKit.content().rules.tick_hz
	assert_int(hz).is_equal(30)                               # the tick numbers below assume rules.json's 30 Hz
	var w: SimWorld = WorldTestKit.world(11, WorldTestKit.rules(EXPOSURE_S, HARD_END_S))
	var hook: WorldTestKit.RecordingHook = WorldTestKit.RecordingHook.new()
	w.set_ai_hook(hook)
	var got: Array = []
	var ids: Dictionary = {}
	for t: int in range(1, 101):
		_script(w, t, ids, hook)
		w.step()
		for e: SimEvent in w.drain_events():
			var reason: int = e.extra[0] if e.extra.size() > 0 else -1
			if e.kind == SimEvent.Kind.SPAWN:
				ids[["A", "B", "C"][ids.size()]] = e.a
			got.append([e.tick, e.kind, e.a, reason])
	var a: int = ids["A"]
	var b: int = ids["B"]
	var c: int = ids["C"]
	var K := SimEvent.Kind
	var expected: Array = [
		[1, K.SPAWN, a, -1], [1, K.SPAWN, b, -1], [1, K.SPAWN, c, -1],
		[5, K.POSSESSED, a, -1],
		[20, K.RELEASED, a, CommandApplier.RR_PLAYER], [20, K.POSSESSED, b, -1],
		[40, K.RELEASED, b, CommandApplier.RR_PLAYER],
		[45, K.POSSESSED, c, -1],
		[50, K.DEATH, a, CommandApplier.DEATH_CAUSE_DEBUG],
		[55, K.ALERT, AlertKind.Kind.PENDING_ORDER, -1],
		[60, K.CORE_EXPOSURE, 0, -1],
		[71, K.RELEASED, c, CommandApplier.RR_DISCONNECT],
		[80, K.POSSESSED, b, -1],
		[90, K.RELEASED, b, CommandApplier.RR_MATCH], [90, K.MATCH_END, -1, -1],
	]
	assert_array(got).is_equal(expected)
	# the AI hook ran every tick; drive() was refused exactly while C was possessed (ticks 45..70)
	assert_int(hook.ticks.size()).is_equal(100)
	for k: int in hook.drive_results.size():
		var tick_k: int = hook.ticks[hook.ticks.size() - hook.drive_results.size() + k]
		assert_bool(hook.drive_results[k]).override_failure_message("tick %d" % tick_k).is_equal(tick_k < 45 or tick_k > 70)
	assert_int(w.view().order_head(c).kind).is_equal(OrderSpec.Kind.HOLD)   # pending committed on release
	assert_object(w.view().order_head(b)).is_null()


func _script(w: SimWorld, t: int, ids: Dictionary, hook: WorldTestKit.RecordingHook) -> void:
	var A: int = ids.get("A", 0)
	var B: int = ids.get("B", 0)
	var C: int = ids.get("C", 0)
	match t:
		1:
			WorldTestKit.queue_spawn(w, &"dart", 0, 0, WorldTestKit.at(600.0))
			WorldTestKit.queue_spawn(w, &"dart", 0, 0, WorldTestKit.at(700.0, 200.0))
			WorldTestKit.queue_spawn(w, &"dart", 1, 1, WorldTestKit.at(800.0, 500.0))
		2:
			hook.drive_id = C
			hook.input.thrust = 0.5
		5:
			_ok(w, Command.possess(0, A))
		10:
			var inp: PilotInput = PilotInput.new()
			inp.thrust = 1.0
			_ok(w, Command.pilot(0, t, inp))
		20:
			_ok(w, Command.possess(0, B))
		30:
			assert_int(w.apply_command(Command.possess(1, A)).code).is_equal(CommandResult.Code.REJECTED_NOT_OWNER)
		31:
			_ok(w, Command.order(0, PackedInt32Array([A]), OrderSpec.make(OrderSpec.Kind.MOVE, 0, WorldTestKit.at(900.0, 900.0))))
		40:
			_ok(w, Command.release(0))
		45:
			_ok(w, Command.possess(1, C))
		50:
			_ok(w, CommandPayload.debug_set(0, A, CommandPayload.SET_KILL, 0.0))
		55:
			_ok(w, Command.order(1, PackedInt32Array([C]), OrderSpec.make(OrderSpec.Kind.HOLD)))
		71:
			w.remove_player(1)
		80:
			_ok(w, Command.possess(0, B))
		95:
			assert_int(w.apply_command(Command.release(0)).code).is_equal(CommandResult.Code.REJECTED_PHASE)


func _ok(w: SimWorld, cmd: Command) -> void:
	assert_int(w.apply_command(cmd).code).is_equal(CommandResult.Code.ACCEPTED)
