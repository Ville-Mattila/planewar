extends GdUnitTestSuite
## Overlays (AI-08, 05 s2.4) against a hand-filled SimView (no SimWorld): entry kind, SAFETY hold / pull-up
## hysteresis / settle rules, the low-fuel RETURN request, RECOVER_CEILING guidance and exit, ground SAFETY, the
## OverlayParams parse, and AiDriver's scan (release edge, no thinks while an overlay runs, wake at its end).
## Flat datum terrain (Terrain.new()); numbers from the AI-08 autopilot fixture.

const R: float = Sphere.PLANET_RADIUS


class FakeView extends SimView:
	var p: Vector3 = Vector3(R + 500.0, 0.0, 0.0)
	var v: Vector3 = Vector3(0.0, 110.0, 0.0)
	var cs: int = 0
	var fuel: float = 1.0
	var head: OrderSpec = null
	var dead: bool = false
	var fl: int = 0

	func flags(_id: int) -> int:
		return fl

	func alive(_id: int) -> bool:
		return not dead

	func pos(_id: int) -> Vector3:
		return p

	func vel(_id: int) -> Vector3:
		return v

	func basis(_id: int) -> Basis:   # nose along the velocity, up radial-ish
		var f: Vector3 = v.normalized() if v.length() > 0.0 else Vector3(0, 1, 0)
		var n: Vector3 = p.normalized()
		var u: Vector3 = (n - f * n.dot(f)).normalized()
		return Basis(f.cross(u), u, -f)

	func control_state(_id: int) -> int:
		return cs

	func fuel01(_id: int) -> float:
		return fuel

	func owner(_id: int) -> int:
		return 2

	func order_head(_id: int) -> OrderSpec:
		return head


class Rec extends CommandSinkBase:
	var cmds: Array[Command] = []
	var drives: int = 0
	var last: PilotInput = PilotInput.new()

	func submit(cmd: Command) -> CommandResult:
		cmds.append(cmd)
		var r: CommandResult = CommandResult.new()
		r.code = CommandResult.Code.ACCEPTED
		return r

	func drive(_id: int, input: PilotInput) -> bool:
		drives += 1
		last.thrust = input.thrust
		last.pitch = input.pitch
		last.yaw = input.yaw
		last.roll = input.roll
		last.buttons = input.buttons
		return true


class ThinkCount extends AiBrain:
	var thinks: int = 0

	func think_batch(_ids: PackedInt32Array, n: int, _v: SimView, _st: AiState, _sink: CommandSink, _tick: int) -> void:
		thinks += n


const ID: int = (1 << 16) | 5   # slot 5, generation 1


var _st: AiState
var _rec: Rec
var _sink: CommandSink
var _p: OverlayParams
var _probe: ProbeResult
var _out: PilotInput
var _flat: Terrain


func before_test() -> void:
	_st = AiState.new()
	_rec = Rec.new()
	_sink = CommandSink.new()
	_sink.bind(_rec)
	_p = OverlayKit.overlay_params(&"dart")
	_probe = ProbeResult.new()
	_out = PilotInput.new()
	_flat = Terrain.new()


func _run(v: FakeView, tick: int) -> bool:
	return Overlays.run(_id(), v, _st, _p, _flat, _sink, tick, _probe, _out)


func _id() -> int:
	return EntityId.make(5, 1)


func test_params_parse_and_refuse_gaps() -> void:
	assert_object(_p).is_not_null()
	assert_int(_p.min_hold_ticks).is_equal(15)
	assert_int(_p.max_hold_ticks).is_equal(90)
	assert_float(_p.clear_tti_s).is_equal(4.0)
	assert_float(_p.force_rtb_fuel01).is_equal_approx(0.2, 1e-9)
	assert_float(rad_to_deg(_p.rc_gamma_rad)).is_equal_approx(-20.0, 1e-9)
	assert_float(_p.rc_exit_alt_m).is_equal(1400.0)
	assert_float(_p.ceiling_hard_m).is_equal(OverlayKit.content().rules.ceiling_hard_m)
	for k: String in OverlayParams.KEYS:
		var ap: Dictionary = OverlayKit.ap(&"dart").duplicate(true)
		var _e: bool = ap.erase(k)
		assert_object(OverlayParams.for_ship(ap, OverlayKit.ship(&"dart"), OverlayKit.content().rules, 30, OverlayKit.content().flight_common)).override_failure_message(k).is_null()
	var g: OverlayParams = OverlayParams.for_ground({"safety_min_hold_s": 0.5}, OverlayKit.content().rules, 30)
	assert_bool(g.ground).is_true()
	assert_int(g.min_hold_ticks).is_equal(15)
	assert_object(OverlayParams.for_ground({}, OverlayKit.content().rules, 30)).is_null()


func test_enter_picks_recover_ceiling_at_the_hard_ceiling_else_safety() -> void:
	var v: FakeView = FakeView.new()
	Overlays.enter(_id(), v, _st, _p, 7)
	assert_int(_st.overlay[5]).is_equal(Overlays.SAFETY)
	assert_int(_st.overlay_since[5]).is_equal(7)
	assert_vector(_st.guidance_vel[5]).is_equal(v.v)
	v.p = Vector3(R + _p.ceiling_hard_m, 0.0, 0.0)
	Overlays.enter(_id(), v, _st, _p, 9)
	assert_int(_st.overlay[5]).is_equal(Overlays.RECOVER_CEILING)


func test_safety_holds_min_then_clears_when_clear() -> void:
	var v: FakeView = FakeView.new()
	Overlays.enter(_id(), v, _st, _p, 0)
	for t: int in _p.min_hold_ticks:
		assert_bool(_run(v, t)).override_failure_message("tick %d" % t).is_false()
	assert_bool(_run(v, _p.min_hold_ticks)).is_true()
	assert_int(_st.overlay[5]).is_equal(Overlays.NONE)
	assert_int(_rec.drives).is_equal(_p.min_hold_ticks + 1)
	assert_int(_rec.cmds.size()).is_equal(0)


func test_safety_ends_at_max_hold_when_the_tti_stays_short_of_clear() -> void:
	var v: FakeView = FakeView.new()
	v.p = Vector3(R + 30.0, 0.0, 0.0)        # level at 30 m: the gravity drop meets the ground at 3.2 s
	Overlays.enter(_id(), v, _st, _p, 0)
	var ended: int = -1
	for t: int in 200:
		if _run(v, t):
			ended = t
			break
	assert_float(_st.tti[5]).is_between(_p.bridge.pull_up_tti_s, _p.clear_tti_s)
	assert_int(ended).is_equal(_p.max_hold_ticks)


func test_pull_up_below_two_seconds_held_until_clear_then_hold_recaptured() -> void:
	var v: FakeView = FakeView.new()
	v.p = Vector3(R + 120.0, 0.0, 0.0)
	v.v = Vector3(-90.0, 110.0, 0.0)        # diving: impact in about 1.3 s
	Overlays.enter(_id(), v, _st, _p, 0)
	assert_bool(_run(v, 0)).is_false()
	assert_int(_st.ov_flags[5] & AiState.OV_PULL_UP).is_equal(AiState.OV_PULL_UP)
	assert_float(_rec.last.thrust).is_equal(0.0)   # AI-38 PULL_UP: nose along the dive, below the horizon: no thrust
	assert_float(_rec.last.pitch).is_greater(0.0)
	v.v = Vector3(-30.0, 110.0, 0.0)        # better, TTI between 2 and 4 s: still pulling (hysteresis)
	assert_bool(_run(v, 1)).is_false()
	assert_int(_st.ov_flags[5] & AiState.OV_PULL_UP).is_equal(AiState.OV_PULL_UP)
	v.v = Vector3(20.0, 110.0, 0.0)         # climbing: clear
	for t: int in range(2, 200):
		if _run(v, t):
			break
	assert_int(_st.ov_flags[5] & AiState.OV_PULL_UP).is_equal(0)
	assert_vector(_st.guidance_vel[5]).is_equal(Vector3(20.0, 110.0, 0.0))
	assert_int(_st.overlay[5]).is_equal(Overlays.NONE)


func test_pull_up_outlasts_max_hold() -> void:
	var v: FakeView = FakeView.new()
	v.p = Vector3(R + 60.0, 0.0, 0.0)
	v.v = Vector3(-60.0, 50.0, 0.0)
	Overlays.enter(_id(), v, _st, _p, 0)
	for t: int in _p.max_hold_ticks + 30:
		assert_bool(_run(v, t)).override_failure_message("tick %d" % t).is_false()
	assert_int(_st.overlay[5]).is_equal(Overlays.SAFETY)


func test_low_fuel_requests_one_prepended_return_for_the_owner() -> void:
	var v: FakeView = FakeView.new()
	v.fuel = 0.15
	v.head = OrderSpec.make(OrderSpec.Kind.PATROL)
	Overlays.enter(_id(), v, _st, _p, 0)
	for t: int in 20:
		var _e: bool = _run(v, t)
	assert_int(_rec.cmds.size()).is_equal(1)
	var spec: OrderSpec = OrderSpec.new()
	var ids: PackedInt32Array = PackedInt32Array()
	assert_bool(CommandPayload.read_order(_rec.cmds[0], spec, ids)).is_true()
	assert_int(spec.kind).is_equal(OrderSpec.Kind.RETURN)
	assert_int(spec.flags).is_equal(OrderSpec.FLAG_PREPEND)
	assert_int(_rec.cmds[0].player).is_equal(2)
	assert_array(Array(ids)).is_equal([_id()])


func test_no_return_when_fuel_ok_or_head_is_return() -> void:
	var v: FakeView = FakeView.new()
	Overlays.enter(_id(), v, _st, _p, 0)
	var _a: bool = _run(v, 0)
	v.fuel = 0.1
	v.head = OrderSpec.make(OrderSpec.Kind.RETURN)
	Overlays.enter(_id(), v, _st, _p, 1)
	var _b: bool = _run(v, 1)
	assert_int(_rec.cmds.size()).is_equal(0)


func test_recover_ceiling_descends_at_minus_20_and_ends_at_1400() -> void:
	var v: FakeView = FakeView.new()
	v.p = Vector3(R + 2000.0, 0.0, 0.0)
	v.v = Vector3(30.0, 80.0, 0.0)
	Overlays.enter(_id(), v, _st, _p, 0)
	assert_bool(_run(v, 0)).is_false()
	assert_float(_rec.last.pitch).is_less(0.0)          # nose down toward the -20 degree path
	v.p = Vector3(R + 1401.0, 0.0, 0.0)
	assert_bool(_run(v, 1)).is_false()
	v.p = Vector3(R + 1400.0, 0.0, 0.0)
	assert_bool(_run(v, 2)).is_true()
	assert_int(_st.overlay[5]).is_equal(Overlays.NONE)


func test_release_on_the_pad_is_satisfied_at_once() -> void:
	var v: FakeView = FakeView.new()
	v.p = Vector3(R + 8.0, 0.0, 0.0)
	v.v = Vector3.ZERO
	v.fl = EntityStore.F_DOCKED
	Overlays.enter(_id(), v, _st, _p, 0)
	assert_bool(_run(v, 0)).is_true()
	assert_int(_st.overlay[5]).is_equal(Overlays.NONE)
	assert_int(_rec.drives).is_equal(0)


func test_ground_safety_brakes_for_min_hold() -> void:
	var g: OverlayParams = OverlayParams.for_ground({"safety_min_hold_s": 0.5}, OverlayKit.content().rules, 30)
	var v: FakeView = FakeView.new()
	Overlays.enter(_id(), v, _st, g, 0)
	var ended: int = -1
	for t: int in 40:
		if Overlays.run(_id(), v, _st, g, _flat, _sink, t, _probe, _out):
			ended = t
			break
		assert_int(_rec.last.buttons).is_equal(PilotInput.BRAKE)
		assert_float(_rec.last.thrust).is_equal(0.0)
	assert_int(ended).is_equal(g.min_hold_ticks - 1)


func test_driver_runs_the_overlay_on_the_release_edge_and_skips_thinks() -> void:
	var d: AiDriver = AiDriver.new(Rng.new(1), 1)
	var brain: ThinkCount = ThinkCount.new()
	d.set_brain(0, brain)
	d.set_overlay_params(0, _p)
	assert_bool(d.register(_id(), 0)).is_true()
	var v: FakeView = FakeView.new()
	v.cs = ControlMachine.State.POSSESSED
	d.on_tick(1, v, _rec)
	assert_int(d.state.overlay[5]).is_equal(Overlays.NONE)
	assert_int(brain.thinks).is_equal(0)
	v.cs = ControlMachine.State.AUTO                  # released
	d.on_tick(2, v, _rec)
	assert_int(d.state.overlay[5]).is_equal(Overlays.SAFETY)
	assert_int(brain.thinks).is_equal(0)
	assert_int(_rec.drives).is_equal(1)
	var t: int = 3
	while d.state.overlay[5] != Overlays.NONE and t < 200:
		d.on_tick(t, v, _rec)
		t += 1
	assert_int(brain.thinks).is_equal(0)             # think period 1: every tick would think without the overlay
	assert_int(d.state.wake_pending[5]).is_equal(1)
	d.on_tick(t, v, _rec)
	assert_int(brain.thinks).is_equal(1)
	assert_int(d.stats()["overlay_ticks"]).is_equal(t - 2)


func test_driver_sees_a_possession_on_the_think_phase_or_at_once_by_event() -> void:
	var d: AiDriver = AiDriver.new(Rng.new(1), 10)
	d.set_overlay_params(0, _p)
	var _r: bool = d.register(_id(), 0)            # stagger 0: phase ticks 0, 10, 20 ...
	var v: FakeView = FakeView.new()
	v.cs = ControlMachine.State.POSSESSED
	d.on_tick(1, v, _rec)
	assert_int(d.state.ov_flags[5] & AiState.OV_POSSESSED).is_equal(0)
	d.on_tick(10, v, _rec)
	assert_int(d.state.ov_flags[5] & AiState.OV_POSSESSED).is_equal(AiState.OV_POSSESSED)
	var e: AiDriver = AiDriver.new(Rng.new(1), 10)
	e.set_overlay_params(0, _p)
	var _q: bool = e.register(_id(), 0)
	var ev: SimEvent = SimEvent.new()
	ev.kind = SimEvent.Kind.POSSESSED
	ev.a = _id()
	e.on_event(ev)
	v.cs = ControlMachine.State.AUTO                  # released on tick 3, off phase: the overlay starts that tick
	e.on_tick(3, v, _rec)
	assert_int(e.state.overlay[5]).is_equal(Overlays.SAFETY)


func test_driver_drops_the_overlay_when_possessed_again_and_ignores_death() -> void:
	var d: AiDriver = AiDriver.new(Rng.new(1), 1)
	d.set_overlay_params(0, _p)
	var _r: bool = d.register(_id(), 0)
	var v: FakeView = FakeView.new()
	v.cs = ControlMachine.State.POSSESSED
	d.on_tick(1, v, _rec)
	v.cs = ControlMachine.State.ORDERED
	d.on_tick(2, v, _rec)
	assert_int(d.state.overlay[5]).is_equal(Overlays.SAFETY)
	v.cs = ControlMachine.State.POSSESSED
	d.on_tick(3, v, _rec)
	assert_int(d.state.overlay[5]).is_equal(Overlays.NONE)
	v.dead = true                                      # a dead entity reads AUTO: no overlay starts
	v.cs = ControlMachine.State.AUTO
	d.on_tick(4, v, _rec)
	assert_int(d.state.overlay[5]).is_equal(Overlays.NONE)


func test_ai_state_round_trips_the_overlay_fields() -> void:
	var a: AiState = AiState.new(64)
	a.cls[5] = 0
	a.eid[5] = _id()
	a.overlay[5] = Overlays.RECOVER_CEILING
	a.ov_flags[5] = AiState.OV_PULL_UP | AiState.OV_RTB_SENT
	a.integ[5] = Vector2(0.25, -0.5)
	var b: AiState = AiState.new(64)
	assert_bool(b.deserialize(a.serialize())).is_true()
	assert_int(b.overlay[5]).is_equal(Overlays.RECOVER_CEILING)
	assert_int(b.ov_flags[5]).is_equal(AiState.OV_PULL_UP | AiState.OV_RTB_SENT)
	assert_vector(b.integ[5]).is_equal(Vector2(0.25, -0.5))
	assert_bool(b.serialize() == a.serialize()).is_true()
