extends GdUnitTestSuite
## GD-43 launch from a service pad (R0 B.24 A-119; 05 s2.5, 02 s2.3, 03 s6.4): a DOCKED ship whose input-slot thrust
## stays >= flight_common.launch_thrust_min for ceil(launch_hold_s x hz) ticks leaves its service pad (hold in timer_b),
## with the service stay closed at its fill; an ascending PAD contact never lands; a launch_pad ship never enters the rule.

var _w: SimWorld
var _pad: int
var _hz: int


## Drives thrust `schedule(tick)` into one ship every tick from step 3, like a brain (CommandSink.drive). It holds no world
## state: a reloaded world gets a new hook with the same schedule.
class ThrustHook extends SimAiHook:
	var target: int = 0
	var schedule: Callable
	var input: PilotInput = PilotInput.new()

	func on_tick(t: int, _v: SimView, sink: CommandSinkBase) -> void:
		input.thrust = float(schedule.call(t))
		if target != 0:
			var _ok: bool = sink.drive(target, input)

	func serialize() -> PackedByteArray:
		return PackedByteArray()

	func deserialize(_bytes: PackedByteArray) -> void:
		pass


func before_test() -> void:
	_w = WorldTestKit.world()
	_hz = WorldTestKit.content().rules.tick_hz
	_pad = DockingTestKit.pad(_w)
	var _e: Array[SimEvent] = _w.drain_events()


static func _hook(id: int, schedule: Callable) -> ThrustHook:
	var hook: ThrustHook = ThrustHook.new()
	hook.target = id
	hook.schedule = schedule
	return hook


# A Dart docked on `pad` at half fuel, with a thrust schedule driven from the next tick.
func _docked(w: SimWorld, pad: int, schedule: Callable) -> int:
	var id: int = DockingTestKit.ship_over(w, &"dart", 0, 0, pad, DockingTestKit.HIGH)
	DockingTestKit.dock(w, id, pad)
	w.store().fuel[EntityId.slot(id)] = DockingTestKit.ship_def(&"dart").fuel_s * 0.5 - 0.001   # missing a hair over 10 Ice
	w.set_ai_hook(_hook(id, schedule))
	var _d: Array[SimEvent] = w.drain_events()
	return id


func _hold_ticks() -> int:
	return ceili(Def.num(DockingTestKit.common().raw.get("launch_hold_s", 0.0)) * float(_hz))


func _docked_flag(w: SimWorld, id: int) -> bool:
	return (w.store().flags[EntityId.slot(id)] & EntityStore.F_DOCKED) != 0


# Steps `n` ticks; returns the 1-based step of the first LAUNCHED event for `id`, 0 when none; `all` collects the events.
func _run(w: SimWorld, id: int, n: int, all: Array[SimEvent] = []) -> int:
	var at: int = 0
	for k: int in n:
		w.step()
		for e: SimEvent in w.drain_events():
			all.append(e)
			if e.kind == SimEvent.Kind.LAUNCHED and e.a == id and at == 0:
				at = k + 1
	return at


# One step of a possessed ship with PILOT_INPUT thrust `thrust`; returns the tick's events.
func _pilot_step(w: SimWorld, thrust: float) -> Array[SimEvent]:
	var inp: PilotInput = PilotInput.new()
	inp.thrust = thrust
	var _r: CommandResult = w.apply_command(Command.pilot(0, w.tick() + 1, inp))
	w.step()
	return w.drain_events()


func test_the_def_fields_are_the_a_119_values() -> void:
	var fc: FlightCommonDef = DockingTestKit.common()
	assert_float(Def.num(fc.raw.get("launch_thrust_min", -1.0))).is_equal(0.5)
	assert_float(Def.num(fc.raw.get("launch_hold_s", -1.0))).is_equal(0.3)
	assert_int(_hold_ticks()).is_equal(9)


func test_a_dart_at_half_service_launches_on_the_ninth_tick_keeping_its_partial_fuel() -> void:
	var id: int = _docked(_w, _pad, func(_t: int) -> float: return 1.0)
	var s: int = EntityId.slot(id)
	var st: EntityStore = _w.store()
	var ice0: int = DockingTestKit.pool(_w, 0).y
	var events: Array[SimEvent] = []
	assert_int(_run(_w, id, 8, events)).is_equal(0)
	assert_bool(_docked_flag(_w, id)).is_true()
	assert_float(st.timer_b[s]).is_greater(0.0)                                  # the hold accumulates in timer_b
	assert_int(_run(_w, id, 1, events)).is_equal(1)                              # the 9th tick
	var fuel_full: float = DockingTestKit.ship_def(&"dart").fuel_s
	assert_float(st.fuel[s]).is_greater(fuel_full * 0.5)                         # the service ran for 9 ticks
	assert_float(st.fuel[s]).is_less(fuel_full)                                  # partial fuel kept
	assert_int(st.flags[s] & (EntityStore.F_DOCKED | EntityStore.F_LANDED)).is_equal(0)
	assert_int(st.link[s]).is_equal(0)
	assert_float(st.timer_b[s]).is_equal(0.0)
	assert_vector(st.rates[s]).is_equal(Vector3.ZERO)
	assert_float(st.vel[s].dot(st.up[EntityId.slot(_pad)])).is_equal_approx(DockingTestKit.common().launch_speed_mps, 0.001)
	var ice_at: int = DockingTestKit.pool(_w, 0).y
	assert_int(ice_at).is_less(ice0)                                             # the Ice drawn so far is spent, not refunded
	var after: Array[SimEvent] = []
	var _x: int = _run(_w, id, 3, after)                                         # no re-landing, no SERVICED, no more Ice
	assert_int(DockingTestKit.of_kind(after, SimEvent.Kind.LANDING).size()).is_equal(0)
	assert_int(DockingTestKit.of_kind(after, SimEvent.Kind.DOCKED).size()).is_equal(0)
	assert_int(DockingTestKit.pool(_w, 0).y).is_equal(ice_at)
	assert_bool(_docked_flag(_w, id)).is_false()
	var launched: Array[SimEvent] = DockingTestKit.of_kind(events, SimEvent.Kind.LAUNCHED)
	assert_int(launched.size()).is_equal(1)
	assert_int(launched[0].b).is_equal(_pad)
	assert_int(DockingTestKit.of_kind(events, SimEvent.Kind.SERVICED).size()).is_equal(0)


func test_thrust_below_the_minimum_never_launches() -> void:
	var below: float = Def.num(DockingTestKit.common().raw.get("launch_thrust_min", 0.5)) - 0.01
	var id: int = _docked(_w, _pad, func(_t: int) -> float: return below)
	assert_int(_run(_w, id, 10 * _hz)).is_equal(0)
	assert_bool(_docked_flag(_w, id)).is_true()


func test_a_hold_broken_at_eight_ticks_restarts() -> void:
	var gap: int = _hold_ticks() - 1                                             # thrust on for 8 ticks, one off, then on
	var brk: Array[int] = [0]                                                   # the tick of the gap, set once the scene is posed
	var id: int = _docked(_w, _pad, func(t: int) -> float: return 0.0 if t == brk[0] else 1.0)
	brk[0] = _w.tick() + gap + 1
	assert_int(_run(_w, id, gap + 1 + _hold_ticks() - 1)).is_equal(0)
	assert_float(_w.store().timer_b[EntityId.slot(id)]).is_greater(0.0)
	assert_int(_run(_w, id, 1)).is_equal(1)                                      # 9 ticks after the break
	assert_bool(_docked_flag(_w, id)).is_false()


func test_thrust_cut_after_launch_falls_back_and_relands_as_a_graded_manual_landing() -> void:
	var id: int = DockingTestKit.ship_over(_w, &"dart", 0, 0, _pad, DockingTestKit.HIGH)
	DockingTestKit.dock(_w, id, _pad)
	assert_bool(DockingTestKit.possess(_w, id)).is_true()
	var all: Array[SimEvent] = []
	var launched_at: int = 0
	for k: int in 40 * _hz:
		for e: SimEvent in _pilot_step(_w, 1.0 if launched_at == 0 else 0.0):
			all.append(e)
			if e.kind == SimEvent.Kind.LAUNCHED and launched_at == 0:
				launched_at = k + 1
	assert_int(launched_at).is_equal(_hold_ticks())
	var landings: Array[SimEvent] = DockingTestKit.of_kind(all, SimEvent.Kind.LANDING)
	assert_int(landings.size()).is_equal(1)
	assert_int(landings[0].extra[0]).is_not_equal(LandingGrade.Grade.CRASH)
	assert_int(landings[0].extra[2] & 1).is_equal(1)                              # manual
	assert_int(DockingTestKit.of_kind(all, SimEvent.Kind.DOCKED).size()).is_equal(1)
	assert_bool(_docked_flag(_w, id)).is_true()


func test_a_pilot_and_a_brain_driving_the_same_thrust_launch_on_the_same_tick() -> void:
	var by_drive: int = _run(_w, _docked(_w, _pad, func(_t: int) -> float: return 1.0), 20)
	var w2: SimWorld = WorldTestKit.world()
	var pad2: int = DockingTestKit.pad(w2)
	var id2: int = DockingTestKit.ship_over(w2, &"dart", 0, 0, pad2, DockingTestKit.HIGH)
	DockingTestKit.dock(w2, id2, pad2)
	assert_bool(DockingTestKit.possess(w2, id2)).is_true()
	var by_pilot: int = 0
	for k: int in 20:
		for e: SimEvent in _pilot_step(w2, 1.0):
			if e.kind == SimEvent.Kind.LAUNCHED and by_pilot == 0:
				by_pilot = k + 1
	assert_int(by_drive).is_equal(_hold_ticks())
	assert_int(by_pilot).is_equal(by_drive)


func test_a_ship_on_a_launch_pad_never_enters_the_rule() -> void:
	var yard: int = DockingTestKit.pad(_w, &"shipyard", 0, 0, 200.0)
	var id: int = _docked(_w, yard, func(_t: int) -> float: return 1.0)
	assert_int(_run(_w, id, 3 * _hold_ticks())).is_equal(0)
	assert_float(_w.store().timer_b[EntityId.slot(id)]).is_equal(0.0)
	assert_bool(_docked_flag(_w, id)).is_true()


func test_an_ascending_pad_contact_is_never_judged_and_a_contact_at_zero_lands() -> void:
	var id: int = DockingTestKit.ship_over(_w, &"dart", 0, 0, _pad, 5.0)
	var s: int = EntityId.slot(id)
	var up: Vector3 = _w.store().up[EntityId.slot(_pad)]
	_w.store().vel[s] = up * 0.5                                                  # ascending, even by a little
	var _b: int = DockingTestKit.contact(_w, id, _pad, 20.0, 40.0, 90.0, 0.0)     # a DESTROY-band contact is skipped too
	assert_int(DockingTestKit.of_kind(_w.drain_events(), SimEvent.Kind.LANDING).size()).is_equal(0)
	assert_bool(_docked_flag(_w, id)).is_false()
	assert_bool(_w.store().alive(id)).is_true()
	_w.store().vel[s] = Vector3.ZERO
	var _c: int = DockingTestKit.contact(_w, id, _pad, 1.0, 1.0, 0.0, 0.0)
	assert_int(DockingTestKit.of_kind(_w.drain_events(), SimEvent.Kind.LANDING).size()).is_equal(1)
	assert_bool(_docked_flag(_w, id)).is_true()


# S4: a save in the middle of the hold reloads byte-exact and launches on the same tick as the original continues.
func test_save_mid_hold_reloads_exact_and_launches_on_the_same_tick() -> void:
	var sched: Callable = func(_t: int) -> float: return 1.0
	var id: int = _docked(_w, _pad, sched)
	var _x: int = _run(_w, id, 4)
	assert_float(_w.store().timer_b[EntityId.slot(id)]).is_greater(0.0)
	var bytes: PackedByteArray = _w.serialize()
	var r: SimWorld = SimWorld.deserialize(bytes, WorldTestKit.content(), _hook(id, sched))
	assert_object(r).is_not_null()
	assert_bool(r.serialize() == bytes).is_true()
	assert_int(SimSerialize.FORMAT).is_equal(13)                                   # the hold is timer_b: no new saved array
	var launched_at: int = 0
	for k: int in _hold_ticks():
		_w.step()
		r.step()
		var a: Array[SimEvent] = _w.drain_events()
		var b: Array[SimEvent] = r.drain_events()
		assert_int(a.size()).is_equal(b.size())
		assert_bool(r.serialize() == _w.serialize()).override_failure_message("differs %d ticks after the save" % (k + 1)).is_true()
		if not DockingTestKit.of_kind(b, SimEvent.Kind.LAUNCHED).is_empty() and launched_at == 0:
			launched_at = k + 1
	assert_int(launched_at).is_equal(_hold_ticks() - 4)
