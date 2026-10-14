extends GdUnitTestSuite
## TA-49 (R0 B.11 A-51): every sim rule constant is read from the injected ContentSet. Each test edits one def field
## on the shared shipped ContentSet, builds a world (or reads a system) and sees the behaviour change; before_test /
## after_test snapshot and restore the fields so no other suite sees an edit.

const C := CommandResult.Code
const _RULE_FIELDS: PackedStringArray = ["command_rate_per_s", "command_burst", "uplink_margin_m", "request_ttl_s",
	"override_echo_s", "shooter_grace_ticks", "path_heuristic_pct", "path_expansions_per_tick",
	"rung_3_projectile_cap", "rung_8_path_expansions_per_tick"]
const _MATCH_FIELDS: PackedStringArray = ["arc_open_divisor", "arc_expand_divisor"]

var _saved: Dictionary = {}


func before_test() -> void:
	var c: ContentSet = WorldTestKit.content()
	for f: String in _RULE_FIELDS:
		_saved[f] = c.rules.get(f)
	for f: String in _MATCH_FIELDS:
		_saved[f] = c.match_rules.get(f)


func after_test() -> void:
	var c: ContentSet = WorldTestKit.content()
	for f: String in _RULE_FIELDS:
		c.rules.set(f, _saved[f])
	for f: String in _MATCH_FIELDS:
		c.match_rules.set(f, _saved[f])


func _rules() -> RulesDef:
	return WorldTestKit.content().rules


func _code(w: SimWorld, cmd: Command) -> int:
	return w.apply_command(cmd).code


func test_shipped_defs_hold_the_documented_values() -> void:
	var r: RulesDef = _rules()
	assert_int(r.command_rate_per_s).is_equal(CommandValidator.RATE_PER_S)
	assert_int(r.command_burst).is_equal(CommandValidator.BURST)
	assert_int(r.uplink_margin_m).is_equal(ControlMachine.UPLINK_MARGIN_M)
	assert_int(r.request_ttl_s).is_equal(ControlMachine.REQUEST_TTL_S)
	assert_int(r.override_echo_s).is_equal(ControlMachine.ECHO_WINDOW_S)
	assert_int(r.shooter_grace_ticks).is_equal(10)
	assert_int(r.path_heuristic_pct).is_equal(25)
	assert_int(r.rung_1_think_period_ticks).is_equal(15)
	assert_int(r.rung_2_vision_hz).is_equal(5)
	assert_int(r.rung_3_projectile_cap).is_equal(1400)
	assert_bool(r.rung_4_ship_pairs_tier_a_only).is_true()
	assert_int(r.rung_5_tier_b_hz).is_equal(10)
	assert_int(r.rung_6_unit_cap).is_equal(60)
	assert_int(r.rung_8_path_expansions_per_tick).is_equal(60)
	assert_int(WorldTestKit.content().match_rules.arc_open_divisor).is_equal(6)
	assert_int(WorldTestKit.content().match_rules.arc_expand_divisor).is_equal(2)


func test_rulesdef_parses_every_a51_field() -> void:
	var d: Dictionary = {"gravity": 6.0, "ceiling_soft_m": 1.0, "ceiling_hard_m": 2.0, "tick_hz": 30, "lift_model": "speed_scaled",
		"path_expansions_per_tick": 120, "sim_budget_profile": [1], "friendly_fire": false, "debug_commands": false,
		"profile_enabled": false, "command_rate_per_s": 1, "command_burst": 2, "uplink_margin_m": 3, "request_ttl_s": 4,
		"override_echo_s": 5, "shooter_grace_ticks": 6, "path_heuristic_pct": 7, "cut_ladder": {
			"rung_1_think_period_ticks": 11, "rung_2_vision_hz": 12, "rung_3_projectile_cap": 13,
			"rung_4_ship_pairs_tier_a_only": false, "rung_5_tier_b_hz": 15, "rung_6_unit_cap": 16,
			"rung_8_path_expansions_per_tick": 18}}
	var r: RulesDef = RulesDef.from_dict(d)
	assert_array(r.errors).is_empty()
	assert_array(r.unknown).is_empty()
	assert_array([r.command_rate_per_s, r.command_burst, r.uplink_margin_m, r.request_ttl_s, r.override_echo_s,
		r.shooter_grace_ticks, r.path_heuristic_pct]).is_equal([1, 2, 3, 4, 5, 6, 7])
	assert_array([r.rung_1_think_period_ticks, r.rung_2_vision_hz, r.rung_3_projectile_cap, r.rung_5_tier_b_hz,
		r.rung_6_unit_cap, r.rung_8_path_expansions_per_tick]).is_equal([11, 12, 13, 15, 16, 18])
	assert_bool(r.rung_4_ship_pairs_tier_a_only).is_false()
	var m: MatchRulesDef = MatchRulesDef.from_dict({"arc_open_divisor": 3, "arc_expand_divisor": 4})
	assert_int(m.arc_open_divisor).is_equal(3)
	assert_int(m.arc_expand_divisor).is_equal(4)
	assert_array(m.unknown).is_empty()


func test_command_burst_and_rate_come_from_rules() -> void:
	_rules().command_burst = 3
	_rules().command_rate_per_s = 5
	var w: SimWorld = WorldTestKit.world()
	for k: int in 3:
		assert_int(_code(w, Command.release(0))).is_not_equal(C.REJECTED_RATE)
	assert_int(_code(w, Command.release(0))).is_equal(C.REJECTED_RATE)
	var per_token: int = _rules().tick_hz / 5
	for _i: int in per_token - 1:
		w.step()
	assert_int(_code(w, Command.release(0))).is_equal(C.REJECTED_RATE)
	w.step()
	assert_int(_code(w, Command.release(0))).is_not_equal(C.REJECTED_RATE)


func test_uplink_margin_comes_from_rules() -> void:
	var hard: float = _rules().ceiling_hard_m
	var w: SimWorld = ControlTestKit.world()
	var id: int = ControlTestKit.dart(w, 0, 0, hard - 200.0, 0.0)
	assert_int(ControlTestKit.code(w, Command.possess(0, id))).is_equal(C.ACCEPTED)       # margin 50: 1,800 m is fine
	_rules().uplink_margin_m = 300
	var w2: SimWorld = ControlTestKit.world()
	var id2: int = ControlTestKit.dart(w2, 0, 0, hard - 200.0, 0.0)
	assert_int(ControlTestKit.code(w2, Command.possess(0, id2))).is_equal(C.REJECTED_UPLINK)


func test_request_ttl_comes_from_rules() -> void:
	_rules().request_ttl_s = 2
	var w: SimWorld = ControlTestKit.world()
	var id: int = ControlTestKit.dart(w)
	var hz: int = _rules().tick_hz
	var _p: Array[SimEvent] = ControlTestKit.run(w, Command.possess(0, id))
	var _r: Array[SimEvent] = ControlTestKit.run(w, ControlTestKit.request(ControlTestKit.MATE, id))
	var _a: Array[SimEvent] = ControlTestKit.step(w, 2 * hz)
	assert_int(ControlTestKit.control(w).request_from(id)).is_equal(ControlTestKit.MATE)
	var _b: Array[SimEvent] = ControlTestKit.step(w)
	assert_int(ControlTestKit.control(w).request_from(id)).is_equal(-1)


func test_override_echo_window_comes_from_rules() -> void:
	_rules().override_echo_s = 1
	var w: SimWorld = ControlTestKit.world()
	var id: int = ControlTestKit.dart(w)
	var _a: Array[SimEvent] = ControlTestKit.run(w, ControlTestKit.order(0, id, OrderSpec.Kind.MOVE))
	var _s: Array[SimEvent] = ControlTestKit.step(w, _rules().tick_hz)       # 1 s: older than the window
	var ev: Array[SimEvent] = ControlTestKit.run(w, ControlTestKit.order(ControlTestKit.MATE, id, OrderSpec.Kind.HOLD))
	assert_int(ev.size()).is_equal(0)


func test_shooter_grace_comes_from_rules() -> void:
	_rules().shooter_grace_ticks = 3
	assert_int(WorldTestKit.world().collision.shooter_grace_ticks).is_equal(3)
	_rules().shooter_grace_ticks = 17
	assert_int(WorldTestKit.world().collision.shooter_grace_ticks).is_equal(17)


func test_pathing_from_rules_takes_budget_and_heuristic() -> void:
	_rules().path_expansions_per_tick = 777
	_rules().path_heuristic_pct = 40
	var p: Pathing = Pathing.from_rules(_rules())
	assert_int(p.expansions_per_tick).is_equal(777)
	assert_int(p.grid.heuristic_pct).is_equal(40)
	assert_int(p.clusters.heuristic_pct).is_equal(40)


func test_arc_divisors_come_from_match_rules() -> void:
	var c: ContentSet = WorldTestKit.content()
	c.match_rules.arc_open_divisor = 4
	c.match_rules.arc_expand_divisor = 3
	var r: MatchRules = MatchRules.from_defs(null, c.match_rules, c.rules, &"standard")
	r.core_exposure_s = 1200.0
	assert_int(r.arc(299 * 30)).is_equal(MatchArc.Arc.OPEN)           # 1200 / 4 = 300 s
	assert_int(r.arc(300 * 30)).is_equal(MatchArc.Arc.EXPAND)
	assert_int(r.arc(399 * 30)).is_equal(MatchArc.Arc.EXPAND)         # 1200 / 3 = 400 s
	assert_int(r.arc(400 * 30)).is_equal(MatchArc.Arc.SIEGE)
	assert_int(r.arc(1200 * 30)).is_equal(MatchArc.Arc.OVERTIME)
	c.match_rules.arc_open_divisor = 6
	c.match_rules.arc_expand_divisor = 2
	r = MatchRules.from_defs(null, c.match_rules, c.rules, &"standard")
	r.core_exposure_s = 1200.0
	assert_int(r.arc(399 * 30)).is_equal(MatchArc.Arc.EXPAND)         # 1200 / 6 = 200 s
	assert_int(r.arc(599 * 30)).is_equal(MatchArc.Arc.EXPAND)
	assert_int(r.arc(600 * 30)).is_equal(MatchArc.Arc.SIEGE)


func test_arc_divisors_survive_serialize() -> void:
	var c: ContentSet = WorldTestKit.content()
	c.match_rules.arc_open_divisor = 3
	var w: SimWorld = WorldTestKit.world(7, WorldTestKit.rules(1200.0))
	var copy: SimWorld = SimWorld.deserialize(w.serialize(), c, null)
	assert_object(copy).is_not_null()
	assert_int(copy._rules.arc_open_divisor).is_equal(3)
	assert_int(copy._rules.arc_expand_divisor).is_equal(c.match_rules.arc_expand_divisor)


func test_budget_rung_3_caps_live_projectiles() -> void:
	_rules().rung_3_projectile_cap = 5
	var r: MatchRules = WorldTestKit.rules()
	var w: SimWorld = WorldTestKit.world(7, r)
	var full: int = w.projectiles().live_cap
	assert_int(full).is_greater(5)
	w.set_budget_profile(2)
	assert_int(w.projectiles().live_cap).is_equal(full)
	w.set_budget_profile(3)
	assert_int(w.projectiles().live_cap).is_equal(5)
	for k: int in 5:
		assert_int(WorldTestKit.projectile(w, &"rocket", WorldTestKit.at(300.0, float(k)), Vector3.ZERO, 1, 5.0)).is_not_equal(EntityId.NULL_ID)
	assert_int(w.projectiles().alloc(ProjectileStore.SLUG, w.tick())).is_equal(EntityId.NULL_ID)
	w.set_budget_profile(0)
	assert_int(w.projectiles().live_cap).is_equal(full)


func test_budget_rung_8_sets_path_expansions() -> void:
	_rules().path_expansions_per_tick = 120
	_rules().rung_8_path_expansions_per_tick = 45
	var w: SimWorld = WorldTestKit.world()
	assert_int(w.path_expansions_per_tick()).is_equal(120)
	w.set_budget_profile(7)
	assert_int(w.path_expansions_per_tick()).is_equal(120)
	w.set_budget_profile(8)
	assert_int(w.path_expansions_per_tick()).is_equal(45)
	w.set_budget_profile(99)                                         # clamped to the ladder's top rung
	assert_array(Array(w._rules.sim_budget_profile)).is_equal([1, 2, 3, 4, 5, 6, 7, 8])
	w.set_budget_profile(1)
	assert_int(w.path_expansions_per_tick()).is_equal(120)
