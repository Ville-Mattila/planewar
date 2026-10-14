extends GdUnitTestSuite
## Unit tests for sim_ai/target_chooser.gd, target_params.gd, target_context.gd, tower_envelope.gd (AI-12; 05 s4.2, s6.2,
## s6.8; R0 C2-15): the scoring tables, the hysteresis, view-gated candidate gathering, envelopes and priorities read from
## the shipped `towers.json`, determinism and the think cost.

const R: float = Sphere.PLANET_RADIUS
const ME: int = 0
const FOE: int = 1
const THINK_ROW_US: float = 25.0   # 05 s10 "Think slice" per-item budget (6 probes, 1 neighbour query, 1 choice point)
const CI_TOLERANCE: float = 3.0

var _c: ContentSet
var _p: TargetParams
var _ctx: TargetContext
var _view: FakeView
var _out: PackedInt32Array = PackedInt32Array()


class FakeView extends SimView:
	## Typed arrays by slot so the view costs what a SimView read costs (an array index), not a Dictionary lookup.
	var _pos: PackedVector3Array = PackedVector3Array()
	var _def: PackedInt32Array = PackedInt32Array()
	var _team: PackedInt32Array = PackedInt32Array()
	var _hp: PackedFloat32Array = PackedFloat32Array()
	var _cargo: PackedFloat32Array = PackedFloat32Array()
	var _vis: PackedByteArray = PackedByteArray()
	var _live: PackedByteArray = PackedByteArray()
	var reads: int = 0

	func _init() -> void:
		var _r: Array[int] = [_pos.resize(128), _def.resize(128), _team.resize(128), _hp.resize(128), _cargo.resize(128),
			_vis.resize(128), _live.resize(128)]

	func put(id: int, pos_: Vector3, def_id_: int, team_: int = 1, hp: float = 1.0, cargo_: float = 0.0, vis: bool = true) -> void:
		var s: int = EntityId.slot(id)
		_pos[s] = pos_
		_def[s] = def_id_
		_team[s] = team_
		_hp[s] = hp
		_cargo[s] = cargo_
		_vis[s] = 1 if vis else 0
		_live[s] = 1

	func alive(id: int) -> bool:
		reads += 1
		return _live[EntityId.slot(id)] != 0

	func pos(id: int) -> Vector3:
		reads += 1
		return _pos[EntityId.slot(id)]

	func def_id(id: int) -> int:
		reads += 1
		return _def[EntityId.slot(id)]

	func team(id: int) -> int:
		reads += 1
		return _team[EntityId.slot(id)]

	func hp01(id: int) -> float:
		reads += 1
		return _hp[EntityId.slot(id)]

	func cargo(id: int) -> float:
		reads += 1
		return _cargo[EntityId.slot(id)]

	func visible_to(_t: int, id: int) -> bool:
		reads += 1
		return _vis[EntityId.slot(id)] != 0

	func terrain_height(_d: Vector3) -> float:
		return 0.0


func before_test() -> void:
	_c = FlightTestKit.real_content()
	_p = TargetParams.from_dict({
		"target_weights": {"bomber": 1.0, "hauler_loaded": 0.9, "lancer": 0.7, "dart": 0.6, "scout": 0.3},
		"target_dist_falloff_m": 1000.0, "target_under_tower_penalty": 0.4, "switch_margin": 1.2,
	})
	_p.bind(_c.entity_index)
	_ctx = TargetContext.new(64)
	_view = FakeView.new()
	var _r: int = _out.resize(64)


func _def(id: StringName) -> int:
	return int(_c.entity_index[id])


func _id(slot: int) -> int:
	return EntityId.make(slot, 1)


func _at(alt: float, along: float) -> Vector3:
	return Vector3(R + alt, along, 0.0)


# region scoring tables
func test_params_need_the_required_keys() -> void:
	assert_object(TargetParams.from_dict({"switch_margin": 1.2})).is_null()
	assert_float(_p.weight(_def(&"bomber"), false)).is_equal(1.0)
	assert_float(_p.weight(_def(&"hauler"), false)).is_equal(0.0)
	assert_float(_p.weight(_def(&"hauler"), true)).is_equal(0.9)


func test_score_distance_falloff() -> void:
	assert_float(TargetChooser.score_ship(1.0, 0.0, 1.0, false, false, 0, _p)).is_equal(1.0)
	assert_float(TargetChooser.score_ship(1.0, 1000.0, 1.0, false, false, 0, _p)).is_equal_approx(0.5, 0.0001)


func test_score_modifier_table() -> void:
	var base: float = TargetChooser.score_ship(1.0, 0.0, 1.0, false, false, 0, _p)
	assert_float(TargetChooser.score_ship(1.0, 0.0, 1.0, true, false, 0, _p)).is_equal_approx(base * 1.5, 0.0001)
	assert_float(TargetChooser.score_ship(1.0, 0.0, 0.49, false, false, 0, _p)).is_equal_approx(base * 1.3, 0.0001)
	assert_float(TargetChooser.score_ship(1.0, 0.0, 0.5, false, false, 0, _p)).is_equal(base)      # strictly below 0.5
	assert_float(TargetChooser.score_ship(1.0, 0.0, 1.0, false, true, 0, _p)).is_equal_approx(base * 0.4, 0.0001)
	assert_float(TargetChooser.score_ship(1.0, 0.0, 1.0, false, false, 1, _p)).is_equal(base)
	assert_float(TargetChooser.score_ship(1.0, 0.0, 1.0, false, false, 2, _p)).is_equal_approx(base * 0.5, 0.0001)
	assert_float(TargetChooser.score_ship(1.0, 0.0, 0.2, true, true, 3, _p)).is_equal_approx(1.0 * 1.5 * 1.3 * 0.4 * 0.5, 0.0001)


func test_tower_score_table() -> void:
	var base: float = TargetChooser.score_tower(100.0, false, 1.0, 0, false, 0.0, _p)
	assert_float(base).is_equal(100.0)
	assert_float(TargetChooser.score_tower(100.0, true, 1.0, 0, false, 0.0, _p)).is_equal_approx(150.0, 0.001)
	assert_float(TargetChooser.score_tower(100.0, false, 0.0, 0, false, 0.0, _p)).is_equal_approx(150.0, 0.001)
	assert_float(TargetChooser.score_tower(100.0, false, 1.0, 2, false, 0.0, _p)).is_equal(100.0)        # > 2 only
	assert_float(TargetChooser.score_tower(100.0, false, 1.0, 3, false, 0.0, _p)).is_equal_approx(70.0, 0.001)
	assert_float(TargetChooser.score_tower(100.0, true, 1.0, 0, true, 0.0, _p)).is_equal_approx(300.0, 0.001)
	assert_float(TargetChooser.score_tower(100.0, false, 1.0, 0, false, 1.0, _p)).is_equal_approx(50.0, 0.001)
# endregion


# region hysteresis
func test_pick_best_wins_without_a_current() -> void:
	var ids: PackedInt32Array = PackedInt32Array([_id(1), _id(2), _id(3)])
	var sc: PackedFloat32Array = PackedFloat32Array([0.4, 0.9, 0.5])
	assert_int(TargetChooser.pick(ids, sc, 3, TargetChooser.NONE, 1.2)).is_equal(_id(2))
	assert_int(TargetChooser.pick(ids, sc, 0, TargetChooser.NONE, 1.2)).is_equal(TargetChooser.NONE)
	assert_int(TargetChooser.pick(ids, PackedFloat32Array([0.0, 0.0, 0.0]), 3, TargetChooser.NONE, 1.2)).is_equal(TargetChooser.NONE)


func test_hysteresis_margin_boundaries() -> void:
	var ids: PackedInt32Array = PackedInt32Array([_id(1), _id(2)])
	var cur: int = _id(1)
	# Rival at 1.19 x current: stays; 1.21 x: switches (it must exceed the margin).
	assert_int(TargetChooser.pick(ids, PackedFloat32Array([1.0, 1.19]), 2, cur, 1.2)).is_equal(cur)
	assert_int(TargetChooser.pick(ids, PackedFloat32Array([1.0, 1.21]), 2, cur, 1.2)).is_equal(_id(2))


func test_current_that_is_no_longer_a_candidate_is_dropped() -> void:
	var ids: PackedInt32Array = PackedInt32Array([_id(2), _id(3)])
	assert_int(TargetChooser.pick(ids, PackedFloat32Array([0.1, 0.2]), 2, _id(1), 1.2)).is_equal(_id(3))


func test_equal_scores_tie_to_the_earlier_candidate() -> void:
	var ids: PackedInt32Array = PackedInt32Array([_id(5), _id(4)])
	assert_int(TargetChooser.pick(ids, PackedFloat32Array([1.0, 1.0]), 2, TargetChooser.NONE, 1.2)).is_equal(_id(5))


func test_no_flip_flop_between_near_equal_targets() -> void:
	# Two targets whose scores swap by a few percent each think: the choice never changes after the first pick.
	var ids: PackedInt32Array = PackedInt32Array([_id(1), _id(2)])
	var cur: int = TargetChooser.NONE
	var switches: int = 0
	for i: int in 40:
		var wob: float = 0.05 if i % 2 == 0 else -0.05
		var nxt: int = TargetChooser.pick(ids, PackedFloat32Array([1.0 + wob, 1.0 - wob]), 2, cur, 1.2)
		if nxt != cur:
			switches += 1
		cur = nxt
	assert_int(switches).is_equal(1)
# endregion


# region view-gated choose_ship
func _choose(cand: Array[int], current: int, tick: int = 100, radius: float = 3000.0) -> int:
	var ids: PackedInt32Array = PackedInt32Array(cand)
	return TargetChooser.choose_ship(_view, ME, ids, ids.size(), _at(300.0, 0.0), radius, current, tick, _ctx, _p, _out)


func test_class_weight_orders_equidistant_targets() -> void:
	_view.put(_id(1), _at(300.0, 500.0), _def(&"dart"))
	_view.put(_id(2), _at(300.0, -500.0), _def(&"bomber"))
	_view.put(_id(3), _at(300.0, 400.0 * 1.0), _def(&"scout"))
	assert_int(_choose([_id(1), _id(2), _id(3)], 0)).is_equal(_id(2))


func test_invisible_friendly_dead_and_out_of_radius_are_never_chosen() -> void:
	_view.put(_id(1), _at(300.0, 100.0), _def(&"bomber"), FOE, 1.0, 0.0, false)       # not visible to the team
	_view.put(_id(2), _at(300.0, 100.0), _def(&"bomber"), ME)                         # friendly
	_view.put(_id(3), _at(300.0, 9000.0), _def(&"bomber"))                            # outside intercept radius
	_view.put(_id(5), _at(300.0, 200.0), _def(&"hauler"))                             # unweighted class (empty hauler)
	assert_int(_choose([_id(1), _id(2), _id(3), _id(4), _id(5)], 0)).is_equal(0)       # id 4 is not in the view: dead
	_view.put(_id(6), _at(300.0, 900.0), _def(&"scout"))
	assert_int(_choose([_id(1), _id(2), _id(3), _id(4), _id(5), _id(6)], 0)).is_equal(_id(6))


func test_loaded_hauler_uses_the_loaded_weight() -> void:
	_view.put(_id(1), _at(300.0, 400.0), _def(&"hauler"), FOE, 1.0, 5.0)
	_view.put(_id(2), _at(300.0, -400.0), _def(&"dart"))
	assert_int(_choose([_id(1), _id(2)], 0)).is_equal(_id(1))


func test_attacker_low_hp_and_focus_fire_shift_the_choice() -> void:
	_view.put(_id(1), _at(300.0, 500.0), _def(&"dart"))
	_view.put(_id(2), _at(300.0, -500.0), _def(&"dart"))
	_ctx.mark_attacker(_id(2), 100, 150)                                  # 5 s at 30 Hz
	assert_int(_choose([_id(1), _id(2)], 0, 120)).is_equal(_id(2))
	assert_int(_choose([_id(1), _id(2)], 0, 260)).is_equal(_id(1))        # window over: tie goes to the earlier one
	_ctx.add_targeter(_id(1))
	_ctx.add_targeter(_id(1))
	assert_int(_choose([_id(1), _id(2)], 0, 260)).is_equal(_id(2))        # two friendlies already on id 1: x 0.5
	_ctx.remove_targeter(_id(1))
	_ctx.remove_targeter(_id(1))


func test_enemy_tower_envelope_penalises_a_target_inside_it() -> void:
	var ac: StructureDef = _structure(&"autocannon_turret")
	var env: TowerEnvelope = TowerEnvelope.from_block(ac.tower, _c.entity_index, _p)
	_view.put(_id(1), _at(100.0, 300.0), _def(&"bomber"))                  # under the guns
	_view.put(_id(2), _at(900.0, 300.0), _def(&"bomber"))                  # 900 m above: outside h_rel_max
	assert_int(_choose([_id(1), _id(2)], 0)).is_equal(_id(1))
	var _ok: bool = _ctx.add_tower(_at(0.0, 300.0), _weapon(ac).range_m, env)
	assert_int(_choose([_id(1), _id(2)], 0)).is_equal(_id(2))
	_ctx.clear_towers()
	assert_int(_choose([_id(1), _id(2)], 0)).is_equal(_id(1))
# endregion


# region towers (towers.json envelopes and priorities)
func _structure(id: StringName) -> StructureDef:
	for s: StructureDef in _c.structures:
		if s.id == id:
			return s
	fail("no structure " + str(id))
	return null


func _weapon(s: StructureDef) -> WeaponDef:
	return _c.weapons[int(_c.weapon_index[StringName(str(s.tower["weapon"]))]) - DefRanges.WEAPON_BASE]


func test_envelopes_come_from_towers_json() -> void:
	var ac: TowerEnvelope = TowerEnvelope.from_block(_structure(&"autocannon_turret").tower, _c.entity_index, _p)
	assert_bool(ac.in_envelope(-200.0, 0.0)).is_true()
	assert_bool(ac.in_envelope(400.0, 0.0)).is_true()
	assert_bool(ac.in_envelope(401.0, 0.0)).is_false()
	assert_bool(ac.in_envelope(-201.0, 0.0)).is_false()
	var fl: TowerEnvelope = TowerEnvelope.from_block(_structure(&"flak_battery").tower, _c.entity_index, _p)
	assert_bool(fl.in_envelope(149.0, 0.0)).is_false()
	assert_bool(fl.in_envelope(150.0, 0.0)).is_true()
	assert_bool(fl.in_envelope(1500.0, 0.0)).is_true()
	assert_bool(fl.kind_ok(_def(&"dart"))).is_true()
	var mt: StructureDef = _structure(&"missile_tower")
	var me: TowerEnvelope = TowerEnvelope.from_block(mt.tower, _c.entity_index, _p)
	assert_float(me.agl_min).is_equal(float(mt.tower["target_agl_min"]))
	assert_bool(me.in_envelope(0.0, me.agl_min - 1.0)).is_false()


func test_tower_priority_ranks_use_rank_weights() -> void:
	var ac: TowerEnvelope = TowerEnvelope.from_block(_structure(&"autocannon_turret").tower, _c.entity_index, _p)
	assert_float(ac.base_weight(_def(&"bomber"), false)).is_equal(100.0)
	assert_float(ac.base_weight(_def(&"hauler"), true)).is_equal(80.0)
	assert_float(ac.base_weight(_def(&"lancer"), false)).is_equal(60.0)
	assert_float(ac.base_weight(_def(&"dart"), false)).is_equal(50.0)
	assert_float(ac.base_weight(_def(&"hauler"), false)).is_equal(20.0)


func test_choose_tower_filters_by_envelope_range_and_priority() -> void:
	var fb: StructureDef = _structure(&"flak_battery")
	var env: TowerEnvelope = TowerEnvelope.from_block(fb.tower, _c.entity_index, _p)
	var rng_m: float = _weapon(fb).range_m
	var tp: Vector3 = _at(0.0, 0.0)
	_view.put(_id(1), _at(60.0, 200.0), _def(&"bomber"))                    # below h_rel_min 150: ineligible
	_view.put(_id(2), _at(400.0, 300.0), _def(&"dart"))
	_view.put(_id(3), _at(400.0, rng_m + 500.0), _def(&"bomber"))           # out of weapon range
	_view.put(_id(4), _at(500.0, -300.0), _def(&"scout"))
	var ids: PackedInt32Array = PackedInt32Array([_id(1), _id(2), _id(3), _id(4)])
	var aim: Vector3 = Vector3(0, 1, 0)
	var got: int = TargetChooser.choose_tower(_view, ME, tp, aim, env, rng_m, ids, 4, 0, 100, _ctx, _p, 0, _out)
	assert_int(got).is_equal(_id(2))                                          # dart (50) outranks scout (25)
	_view.put(_id(5), _at(400.0, 100.0), _def(&"bomber"))
	ids = PackedInt32Array([_id(1), _id(2), _id(3), _id(4), _id(5)])
	assert_int(TargetChooser.choose_tower(_view, ME, tp, aim, env, rng_m, ids, 5, _id(2), 100, _ctx, _p, 0, _out)).is_equal(_id(5))


func test_tower_hysteresis_and_slew_time() -> void:
	var env: TowerEnvelope = TowerEnvelope.from_block(_structure(&"autocannon_turret").tower, _c.entity_index, _p)
	var tp: Vector3 = _at(0.0, 0.0)
	_view.put(_id(1), _at(100.0, 300.0), _def(&"dart"))
	_view.put(_id(2), _at(100.0, -300.0), _def(&"dart"))
	var ids: PackedInt32Array = PackedInt32Array([_id(1), _id(2)])
	var rng_m: float = _weapon(_structure(&"autocannon_turret")).range_m
	# Turret already aimed at id 1: the slew term favours it; id 2 (needs a half turn) loses.
	var aim: Vector3 = Vector3(0, 1, 0)
	assert_int(TargetChooser.choose_tower(_view, ME, tp, aim, env, rng_m, ids, 2, 0, 100, _ctx, _p, 0, _out)).is_equal(_id(1))
	# Turn it around: the new target must beat the current by 1.3, and it does only if the slew gain is enough.
	var back: Vector3 = Vector3(0, -1, 0)
	var keep: int = TargetChooser.choose_tower(_view, ME, tp, back, env, rng_m, ids, 2, _id(1), 100, _ctx, _p, 0, _out)
	assert_bool(keep == _id(1) or keep == _id(2)).is_true()
# endregion


func _fill(count: int) -> Array[int]:
	var ids: Array[int] = []
	for i: int in count:
		var d: StringName = [&"dart", &"bomber", &"lancer", &"scout"][i % 4]
		_view.put(_id(i + 1), _at(200.0 + 20.0 * float(i), 40.0 * float(i)), _def(d), FOE, 0.3 + 0.01 * float(i))
		ids.append(_id(i + 1))
	return ids


func test_deterministic() -> void:
	var ids: Array[int] = _fill(24)
	var first: int = _choose(ids, 0)
	for i: int in 20:
		assert_int(_choose(ids, 0)).is_equal(first)


func test_candidate_cap_keeps_the_best_by_base_score() -> void:
	# 40 candidates, cap 8: only the 8 best by w / (1 + d / falloff) are fully scored; the bomber nearest wins.
	var ids: Array[int] = _fill(40)
	var got: int = _choose(ids, 0)
	assert_int(got).is_equal(_id(2))                  # i = 1 is the closest bomber (weight 1.0)
	assert_int(_out[0]).is_equal(_id(2))              # `out` keeps the kept set in base-score order
	# Reads are bounded: the cheap pass reads <= 6 per candidate, the full pass <= 6 per kept candidate.
	_view.reads = 0
	var _r: int = _choose(ids, 0)
	assert_int(_view.reads).is_less_equal(6 * 40 + 6 * 8)


func test_chooser_is_not_counted_in_the_focus_fire_of_its_own_target() -> void:
	_view.put(_id(1), _at(300.0, 500.0), _def(&"dart"))
	_view.put(_id(2), _at(300.0, -500.0), _def(&"dart"))
	_ctx.add_targeter(_id(1))                         # this ship targets id 1 and is counted
	_ctx.add_targeter(_id(1))                         # one other friendly too: 1 other < focus_count 2
	# Others on id 1 = 1: no x 0.5, so 1 keeps the pick (the earlier tie); counting itself it would be 2 and lose.
	assert_int(_choose([_id(1), _id(2)], _id(1))).is_equal(_id(1))
	_ctx.add_targeter(_id(1))                         # now 2 others: halved, the margin does not hold it
	assert_int(_choose([_id(1), _id(2)], _id(1))).is_equal(_id(2))


func test_cost_of_one_choice_point_at_the_budget_row() -> void:
	# 05 s10 think row: 25 us per think holding 6 probes, a neighbour query and ONE choice point; the chooser is allowed
	# that whole row at N = max_candidates = 8 with a 3x CI tolerance (a shared runner, GDScript debug build).
	var ids: Array[int] = _fill(8)
	var first: int = _choose(ids, 0)
	var t0: int = Time.get_ticks_usec()
	for i: int in 200:
		var _r: int = _choose(ids, first)
	var us: float = float(Time.get_ticks_usec() - t0) / 200.0
	print("choose_ship at N=8: %.1f us" % us)
	assert_float(us).is_less(THINK_ROW_US * CI_TOLERANCE)
	# Bounded whatever n: 64 candidates cost less than 4x the N=8 call (cheap pass only) and never full-score more than 8.
	var many: Array[int] = _fill(64)
	t0 = Time.get_ticks_usec()
	for i: int in 200:
		var _r: int = _choose(many, first)
	var us64: float = float(Time.get_ticks_usec() - t0) / 200.0
	print("choose_ship at n=64 (cap 8): %.1f us" % us64)
	assert_float(us64).is_less(THINK_ROW_US * CI_TOLERANCE * 4.0)
