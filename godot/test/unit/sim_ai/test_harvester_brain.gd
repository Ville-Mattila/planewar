extends GdUnitTestSuite
## AI-16 contract tests of `HarvesterBrain` (sim_ai/brains/MODULE.md; 05 s6.6, s5.7) on a real SimWorld: orders (HOLD, MOVE,
## HARVEST_HERE and its fallback), re-targeting (a drained field, a full field), the threat rules (only armed enemy ships the
## team sees; fog fairness), the stuck ladder (repath, another destination, give up), the ticket timeout, NO_PATH, hand-back after
## a possession, sticky field choice, and S4 (a restored world continues byte for byte). The acceptance scenarios are in
## `test/sim/ai/test_sc_harvester.gd` / `test_sc_ground_follow.gd`.

const HZ: int = 30

var _w: SimWorld
var _d: AiDriver
var _b: HarvesterBrain


func _world(fields: Array[float] = [450.0]) -> int:
	_w = Ai16Kit.world(11)
	var _r: int = Ai16Kit.put(_w, &"refinery", 0, 0.0)
	for e: float in fields:
		var _f: int = Ai16Kit.field(_w, e, 0.0, 6000, 2.0, 150.0, 2)
	var h: int = Ai16Kit.put(_w, &"harvester", 0, 60.0)
	_b = Ai16Kit.brain()
	_d = Ai16Kit.driver(_w, _b)
	return h


func _tag(h: int) -> int:
	return _w.view().ai_tag(h)


func _run(n: int) -> void:
	Ai16Kit.step(_w, n)


func _until(h: int, tag: int, max_ticks: int) -> bool:
	for _k: int in max_ticks:
		Ai16Kit.step(_w)
		if _tag(h) == tag:
			return true
	return false


func _order(h: int, spec: OrderSpec) -> void:
	DartKit.order(_w, h, spec)


func _speed(h: int) -> float:
	return _w.view().vel(h).length()


func _field_of(h: int) -> int:
	return _d.state.aux_id[EntityId.slot(h)] - 1


func test_hold_stops_the_unit_and_ends_with_the_order() -> void:
	var h: int = _world()
	_run(8 * HZ)
	assert_int(_tag(h)).is_equal(AiTag.Tag.TO_FIELD)
	_order(h, OrderSpec.make(OrderSpec.Kind.HOLD))
	_run(2 * _d.think_period())
	assert_int(_tag(h)).is_equal(AiTag.Tag.HOLD)
	assert_float(_speed(h)).is_equal(0.0)
	var at: Vector3 = _w.view().pos(h)
	_run(5 * HZ)
	assert_float(_w.view().pos(h).distance_to(at)).is_less(0.01)             # holds, and never reverses
	var _x: bool = _w.apply_command(Command.order(0, PackedInt32Array([h]), OrderSpec.make(OrderSpec.Kind.MOVE, 0, Ai16Kit.dir_at(60.0) * Ai16Kit.R))).code == CommandResult.Code.ACCEPTED
	_run(2 * _d.think_period())
	assert_int(_tag(h)).is_equal(AiTag.Tag.MOVE)                              # a new order replaces it


func test_move_drives_to_the_point_and_stands_there() -> void:
	var h: int = _world()
	var dest: Vector3 = Ai16Kit.dir_at(300.0, 150.0) * Ai16Kit.R
	_order(h, OrderSpec.make(OrderSpec.Kind.MOVE, 0, dest))
	_run(45 * HZ)
	assert_int(_tag(h)).is_equal(AiTag.Tag.MOVE)
	assert_float(GroundFollower.flat(_w.view().pos(h), dest)).is_less(_b.prm.ground.arrive_m + 0.5)
	assert_float(_speed(h)).is_equal(0.0)
	assert_int(_b.stats_gave_up).is_equal(0)


func test_harvest_here_mines_the_ordered_field_and_falls_back_to_auto_when_it_runs_dry() -> void:
	var h: int = _world([450.0, 1100.0])
	var spec: OrderSpec = OrderSpec.make(OrderSpec.Kind.HARVEST_HERE, 0, Ai16Kit.dir_at(1100.0) * Ai16Kit.R)
	_order(h, spec)
	assert_bool(_until(h, AiTag.Tag.MINE, 160 * HZ)).is_true()
	assert_int(_field_of(h)).is_equal(1)                                      # the far one, although the near one scores higher
	assert_float(GroundFollower.flat(_w.view().pos(h), Ai16Kit.dir_at(1100.0) * Ai16Kit.R)).is_less(150.0)
	_w.economy().harvest.fields.amount[1] = 0.0                               # dry: back to AUTO
	assert_bool(_until(h, AiTag.Tag.TO_REFINERY, 30 * HZ) or _until(h, AiTag.Tag.TO_FIELD, 30 * HZ)).is_true()
	_run(40 * HZ)
	assert_bool(_until(h, AiTag.Tag.MINE, 200 * HZ)).is_true()
	assert_int(_field_of(h)).is_equal(0)


func test_a_field_drained_on_the_way_is_dropped_for_another() -> void:
	var h: int = _world([450.0, 1100.0])
	_run(5 * HZ)
	assert_int(_tag(h)).is_equal(AiTag.Tag.TO_FIELD)
	assert_int(_field_of(h)).is_equal(0)
	_w.economy().harvest.fields.amount[0] = 0.0
	_run(2 * _d.think_period())
	assert_int(_field_of(h)).is_equal(1)
	assert_bool(_until(h, AiTag.Tag.MINE, 160 * HZ)).is_true()


func test_four_harvesters_two_miners_per_field_re_target_when_a_field_is_full() -> void:
	var h0: int = _world([450.0, 800.0])
	var ids: PackedInt32Array = PackedInt32Array([h0])
	for i: int in 3:
		var _a: bool = ids.push_back(Ai16Kit.put(_w, &"harvester", 0, 30.0 + 15.0 * float(i)))
	for id: int in ids:
		var _r: bool = _d.register(id, Ai16Kit.cls()) if _d.state.cls[EntityId.slot(id)] == AiState.NO_CLASS else true
	var f: OreFields = _w.economy().harvest.fields
	var best_a: int = 0
	var best_b: int = 0
	for _k: int in 90 * HZ:
		Ai16Kit.step(_w)
		assert_int(maxi(f.miners_of(0), f.miners_of(1))).is_less_equal(2)         # max_miners 2: the sim never allows more
		best_a = maxi(best_a, f.miners_of(0))
		best_b = maxi(best_b, f.miners_of(1))
	assert_int(best_a).is_equal(2)
	assert_int(best_b).is_equal(2)                                            # the two that found field A full went to B


func test_the_same_field_is_kept_after_a_delivery_when_it_is_still_good() -> void:
	var h: int = _world([450.0, 480.0])
	assert_bool(_until(h, AiTag.Tag.MINE, 90 * HZ)).is_true()
	var first: int = _field_of(h)
	assert_bool(_until(h, AiTag.Tag.UNLOAD, 150 * HZ)).is_true()
	assert_bool(_until(h, AiTag.Tag.TO_FIELD, 40 * HZ)).is_true()
	assert_int(_field_of(h)).is_equal(first)                                  # sticky (05 s6.6)


# --- threats ------------------------------------------------------------------------------------------------------------

func _foe(def: StringName, east: float, north: float, agl: float = 200.0) -> int:
	var p: Vector3 = DartKit.above(_w, Ai16Kit.dir_at(east, north), agl)
	var id: int = Ai17Kit.spawn_many(_w, def, DartKit.FOE, p, Vector3.ZERO, Vector3(0, 1, 0))
	_w.store().hp[EntityId.slot(id)] = 10000000.0
	return id


func _pin(id: int, p: Vector3) -> void:
	_w.store().pos[EntityId.slot(id)] = p
	_w.store().vel[EntityId.slot(id)] = Vector3.ZERO


func test_only_armed_enemy_ships_the_team_sees_within_flee_radius_make_it_flee() -> void:
	var h: int = _world()
	assert_bool(_until(h, AiTag.Tag.MINE, 90 * HZ)).is_true()
	var at: Vector3 = _w.view().pos(h)
	var hauler: int = _foe(&"hauler", 450.0, 200.0)                           # unarmed, close
	var far: int = _foe(&"lancer", 450.0, 900.0)                              # armed, beyond the sensor and the flee radius
	var hp: Vector3 = _w.view().pos(hauler)
	var fp: Vector3 = _w.view().pos(far)
	for _k: int in 5 * HZ:
		_pin(hauler, hp)
		_pin(far, fp)
		Ai16Kit.step(_w)
	assert_int(_tag(h)).is_equal(AiTag.Tag.MINE)
	assert_bool(_w.view().visible_to(0, far)).is_false()                      # the Lancer is out of the team's sight ...
	assert_int(_b.stats_flees).is_equal(0)                                     # ... and the brain never knew it was there
	assert_float(_w.view().pos(h).distance_to(at)).is_less(0.5)
	_foe_move(far, 450.0, 300.0)                                              # now it comes within sight and radius
	var lp: Vector3 = _w.view().pos(far)
	for _k: int in 3 * HZ:
		_pin(far, lp)
		_pin(hauler, hp)
		Ai16Kit.step(_w)
	assert_int(_tag(h)).is_equal(AiTag.Tag.FLEE)


func _foe_move(id: int, east: float, north: float) -> void:
	_pin(id, DartKit.above(_w, Ai16Kit.dir_at(east, north), 200.0))


func test_a_friendly_armed_ship_is_no_threat() -> void:
	var h: int = _world()
	assert_bool(_until(h, AiTag.Tag.MINE, 90 * HZ)).is_true()
	var p: Vector3 = DartKit.above(_w, Ai16Kit.dir_at(450.0, 100.0), 200.0)
	var mate: int = Ai17Kit.spawn_many(_w, &"lancer", 0, p, Vector3.ZERO, Vector3(0, 1, 0))
	_w.store().hp[EntityId.slot(mate)] = 10000000.0
	for _k: int in 4 * HZ:
		_pin(mate, p)
		Ai16Kit.step(_w)
	assert_int(_tag(h)).is_equal(AiTag.Tag.MINE)
	assert_int(_b.stats_flees).is_equal(0)


func test_a_flee_order_never_overrides_hold() -> void:
	var h: int = _world()
	_order(h, OrderSpec.make(OrderSpec.Kind.HOLD))
	_run(HZ)
	var foe: int = _foe(&"lancer", 60.0, 300.0)
	var p: Vector3 = _w.view().pos(foe)
	for _k: int in 3 * HZ:
		_pin(foe, p)
		Ai16Kit.step(_w)
	assert_int(_tag(h)).is_equal(AiTag.Tag.HOLD)                              # an ordered unit stays where it is told


func test_a_hit_in_the_think_that_rebases_the_window_still_flees() -> void:
	var h: int = _world()
	var sink: CommandSink = CommandSink.new()
	var inner: GroundFollowerPathSink = GroundFollowerPathSink.new()
	inner.pa = Pathing.new(120)
	sink.bind(inner)
	var st: AiState = AiState.new()
	var s: int = EntityId.slot(h)
	_b.think_one(h, _w.view(), st, sink, 5)                                    # the window starts: hp_mark = 1.0 at tick 5
	_w.store().hp[s] *= 0.8
	var window: int = _b.prm.hit_ticks
	_b.think_one(h, _w.view(), st, sink, 5 + window + 3)                       # the first think after the window ended sees the loss
	assert_int(st.mode[s]).is_equal(AiTag.Tag.FLEE)
	assert_int(_b.stats_flees).is_equal(1)


# --- route health -------------------------------------------------------------------------------------------------------

func test_the_stuck_ladder_repaths_then_picks_another_field_then_gives_up() -> void:
	var h: int = _world([450.0, 900.0])
	var start: Vector3 = _w.view().pos(h)
	var window: int = _b.prm.ground.stuck_window_ticks
	var first: int = -1
	var at_strike: Array[int] = []
	var fields_seen: Array[int] = []
	for k: int in 4 * window:                                                 # the unit is held in place: no progress at all
		_pin(h, start)
		Ai16Kit.step(_w)
		if at_strike.size() < _b.stats_strikes:
			at_strike.append(k)
			fields_seen.append(_field_of(h))
		if first < 0:
			first = _field_of(h)
	assert_int(first).is_equal(0)
	assert_int(at_strike.size()).is_greater_equal(3)
	assert_int(at_strike[0]).is_between(window, window + 2 * _d.think_period())      # one window of no progress = strike 1
	assert_int(at_strike[1] - at_strike[0]).is_between(window - 3, window + 2 * _d.think_period())
	assert_int(fields_seen[0]).is_equal(0)                                     # strike 1: the same destination, repathed
	assert_int(fields_seen[1]).is_equal(1)                                     # strike 2: another field
	assert_int(_b.stats_gave_up).is_greater_equal(1)                           # strike 3: the destination is given up


func test_an_unanswered_ticket_is_one_strike_after_30_ticks() -> void:
	var h: int = _world()
	var sink: CommandSink = CommandSink.new()
	var inner: GroundFollowerPathSink = GroundFollowerPathSink.new()
	inner.pa = Pathing.new(120)                                                # never advanced: every ticket stays pending
	sink.bind(inner)
	var st: AiState = AiState.new()
	var t0: int = 1000
	_b.think_one(h, _w.view(), st, sink, t0)
	var s: int = EntityId.slot(h)
	assert_int(st.mode[s]).is_equal(AiTag.Tag.TO_FIELD)
	assert_bool(st.path_ticket[s] >= 0).is_true()
	var first_ticket: int = st.path_ticket[s]
	_b.think_one(h, _w.view(), st, sink, t0 + 29)
	assert_int(_b.stats_strikes).is_equal(0)                                    # 29 ticks: still waiting
	assert_int(st.path_ticket[s]).is_equal(first_ticket)
	_b.think_one(h, _w.view(), st, sink, t0 + 30)
	assert_int(_b.stats_strikes).is_equal(1)                                    # 30 ticks: one strike, asked again
	assert_int(st.ground.req[s]).is_equal(t0 + 30)
	assert_int(st.ground.strikes[s]).is_equal(1)


class GroundFollowerPathSink extends CommandSinkBase:
	var pa: Pathing
	func pathing() -> Pathing:
		return pa


func test_a_field_with_no_path_is_left_for_another_without_waiting_for_a_stuck_window() -> void:
	var h: int = _world([450.0, 800.0])
	var pa: Pathing = _w._pathing
	for dx: int in range(-4, 5):                                               # a 9 x 9 cell block over the near field's centre
		for dy: int in range(-4, 5):
			pa.set_weight(PathGrid.cell_of(Ai16Kit.dir_at(450.0 + float(dx) * 36.8, float(dy) * 36.8)), PathGrid.W_BLOCKED)
	var _x: int = 0
	_run(8 * HZ)
	assert_int(_field_of(h)).is_equal(1)                                       # the near field's spot can not be reached
	assert_int(_b.stats_gave_up).is_equal(0)
	assert_bool(_until(h, AiTag.Tag.MINE, 120 * HZ)).is_true()
	assert_float(GroundFollower.flat(_w.view().pos(h), Ai16Kit.dir_at(800.0) * Ai16Kit.R)).is_less(150.0)


func test_after_a_possession_the_unit_repaths_from_where_it_was_left() -> void:
	var h: int = _world([900.0])
	_run(8 * HZ)
	OverlayKit.ok(_w, Command.possess(0, h))
	_run(2)
	for _k: int in 4 * HZ:                                                     # the pilot drives it in a circle
		var inp: PilotInput = PilotInput.new()
		inp.thrust = 1.0
		inp.yaw = 1.0
		OverlayKit.ok(_w, Command.pilot(0, _w.tick() + 1, inp))
		Ai16Kit.step(_w)
	OverlayKit.ok(_w, Command.release(0))
	assert_bool(_until(h, AiTag.Tag.MINE, 200 * HZ)).is_true()                 # back on the job
	assert_int(_b.stats_gave_up).is_equal(0)


# --- S4 -----------------------------------------------------------------------------------------------------------------

func test_a_restored_world_continues_byte_for_byte() -> void:
	var h: int = _world([450.0])
	var _h2: int = Ai16Kit.put(_w, &"harvester", 0, 90.0)
	_run(40 * HZ)
	assert_int(_tag(h)).is_not_equal(AiTag.Tag.NONE)
	var bytes: PackedByteArray = _w.serialize()
	var d2: AiDriver = AiDriver.new(Rng.new(3))
	var b2: HarvesterBrain = Ai16Kit.brain()
	var c: ContentSet = Ai16Kit.content()
	d2.set_class_table(AiClassTable.from_content(c))
	d2.set_brain(Ai16Kit.cls(), b2)
	d2.set_overlay_params(Ai16Kit.cls(), OverlayParams.for_ground(Ai16Kit.ap(), c.rules, c.rules.tick_hz))
	var w2: SimWorld = SimWorld.deserialize(bytes, c, d2)
	assert_object(w2).is_not_null()
	d2.set_terrain(w2.terrain())
	b2.bind_fields(w2.economy().harvest.fields)
	assert_bool(w2.serialize() == bytes).is_true()
	for _k: int in 60 * HZ:
		_w.step()
		w2.step()
		var _a: Array[SimEvent] = _w.drain_events()
		var _b2: Array[SimEvent] = w2.drain_events()
	assert_bool(w2.serialize() == _w.serialize()).is_true()
	assert_int(d2.state.mode[EntityId.slot(h)]).is_equal(_d.state.mode[EntityId.slot(h)])
