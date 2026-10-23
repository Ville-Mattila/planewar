extends GdUnitTestSuite
## AI-17 contract tests (sim_ai/brains/MODULE.md, sim_ai/MODULE.md): `TowerParams` reads every envelope, priority, range,
## shell speed and lock time from the defs (towers.json, weapons, projectiles, economy), the missing-key refusal, the
## one shared tower class of `AiClassTable`, the `TargetParams.for_tower` defaults, and the grep check of the
## acceptance: no envelope literal in `src/sim_ai`.

var _c: ContentSet
var _p: TowerParams


func before_test() -> void:
	_c = Ai17Kit.content()
	_p = TowerParams.from_content(Ai17Kit.ap_tower(), _c)


func _tower_defs() -> Array[StructureDef]:
	var out: Array[StructureDef] = []
	for sd: StructureDef in _c.structures:
		if sd.is_tower():
			out.append(sd)
	return out


func test_every_tower_def_has_its_envelope_from_towers_json() -> void:
	assert_object(_p).is_not_null()
	var seen: int = 0
	for sd: StructureDef in _tower_defs():
		var env: TowerEnvelope = _p.envelope(int(_c.entity_index[sd.id]))
		assert_object(env).is_not_null()
		assert_float(env.h_rel_min).is_equal(TargetParams.num(sd.tower, "h_rel_min", 0.0))
		assert_float(env.h_rel_max).is_equal(TargetParams.num(sd.tower, "h_rel_max", 0.0))
		assert_float(env.agl_min).is_equal(TargetParams.num(sd.tower, "target_agl_min", 0.0))
		assert_float(env.turn_rad_s).is_equal_approx(deg_to_rad(TargetParams.num(sd.tower, "turret_turn_dps", 0.0)), 0.00001)
		seen += 1
	assert_int(seen).is_greater_equal(4)
	var shield: int = int(_c.entity_index[&"shield_projector"])
	assert_object(_p.envelope(shield)).is_null()   # no tower block
	assert_object(_p.envelope(int(_c.entity_index[&"core"]))).is_null()
	assert_object(_p.envelope(-1)).is_null()


func test_priority_weights_follow_target_priority_rank() -> void:
	var sd: StructureDef = Ai17Kit.content().structures[0]
	for s: StructureDef in _tower_defs():
		if s.id == &"flak_battery":
			sd = s
	var env: TowerEnvelope = _p.envelope(int(_c.entity_index[sd.id]))
	var prio: Array = sd.tower["target_priority"]
	assert_float(env.base_weight(int(_c.entity_index[&"bomber"]), false)).is_equal(100.0)
	assert_float(env.base_weight(int(_c.entity_index[&"hauler"]), true)).is_equal(80.0)
	assert_float(env.base_weight(int(_c.entity_index[&"hauler"]), false)).is_equal(20.0)
	assert_int(prio.size()).is_equal(8)


func test_weapon_range_shell_speed_and_lock_ticks_come_from_the_weapon_and_projectile_defs() -> void:
	for sd: StructureDef in _tower_defs():
		var i: int = int(_c.entity_index[sd.id]) - DefRanges.STRUCTURE_BASE
		var w: WeaponDef = _c.weapons[int(_c.weapon_index[sd.tower["weapon"]]) - DefRanges.WEAPON_BASE]
		var pj: ProjectileDef = _c.projectiles[int(_c.projectile_index[w.projectile]) - DefRanges.PROJECTILE_BASE]
		assert_float(_p.range_m[i]).is_equal(w.range_m)
		if pj.behaviour == &"straight":
			assert_float(_p.speed[i]).is_equal(pj.speed_mps)   # slug 700, flak 300, rail 1500: straight lines (R0 B.5)
		else:
			assert_float(_p.speed[i]).is_equal(0.0)            # the guided rocket is aimed at the target
		var want: int = maxi(1, roundi(w.lock_time_s * float(_c.rules.tick_hz))) if w.lock_time_s > 0.0 else 0
		assert_int(_p.lock_ticks[i]).is_equal(want)
	var mt: int = int(_c.entity_index[&"missile_tower"]) - DefRanges.STRUCTURE_BASE
	assert_int(_p.lock_ticks[mt]).is_greater(0)
	var ac: int = int(_c.entity_index[&"autocannon_turret"]) - DefRanges.STRUCTURE_BASE
	assert_int(_p.lock_ticks[ac]).is_equal(0)


func test_offline_ratio_and_choice_numbers() -> void:
	assert_float(_p.off_ratio).is_equal(_c.economy.tower_offline_ratio)
	assert_int(_p.window_ticks).is_equal(roundi(_p.targets.attacked_window_s * float(_c.rules.tick_hz)))
	assert_float(_p.attack_r2).is_equal(_p.targets.tower_attack_radius_m * _p.targets.tower_attack_radius_m)
	assert_float(_p.targets.tower_switch_margin).is_equal(1.3)
	assert_int(_p.targets.rank_weights.size()).is_equal(8)
	assert_int(_p.vision_period).is_greater_equal(1)


func test_for_tower_needs_no_ship_keys_and_a_missing_cone_refuses() -> void:
	var t: TargetParams = TargetParams.for_tower({})
	assert_float(t.tower_switch_margin).is_equal(1.3)
	assert_float(t.guard_mult).is_equal(2.0)
	assert_int(t.rank_weights.size()).is_equal(8)
	assert_object(TowerParams.from_content({}, _c)).is_null()
	assert_object(TowerBrain.create(_c, {})).is_null()
	assert_object(TowerBrain.create(_c, Ai17Kit.ap_tower())).is_not_null()


func test_class_table_gives_every_tower_one_shared_class() -> void:
	var t: PackedByteArray = AiClassTable.from_content(_c)
	var cls: int = AiClassTable.tower_class(_c)
	assert_int(cls).is_not_equal(AiClassTable.NONE)
	assert_int(cls).is_less(AiDriver.MAX_CLASSES)
	for sd: StructureDef in _tower_defs():
		assert_int(AiClassTable.class_of(t, int(_c.entity_index[sd.id]))).is_equal(cls)
	for id: StringName in [&"core", &"refinery", &"shield_projector", &"relay_pylon"]:
		assert_int(AiClassTable.class_of(t, int(_c.entity_index[id]))).is_equal(AiClassTable.NONE)
	assert_int(AiClassTable.class_of(t, int(_c.entity_index[&"dart"]))).is_not_equal(cls)   # ships keep their own classes
	var ships_and_ground: int = _c.ships.size() + _c.ground_units.size()
	assert_int(cls).is_equal(ships_and_ground)   # the class after the last ship / ground class (append-only growth)


# Acceptance grep check: no tower envelope number in sim_ai (05 s6.8 "No envelope number is hard-coded in sim_ai").
# An envelope field (`h_rel_*`, `agl_min`, `target_agl_min`, `turn_dps`) is never assigned or compared with a numeral
# other than the 0.0 default of TowerEnvelope's own field declarations; the towers.json numbers do not appear beside it.
func test_no_envelope_literal_in_sim_ai() -> void:
	var bad: PackedStringArray = PackedStringArray()
	var rx: RegEx = RegEx.create_from_string("(h_rel_m(in|ax)|agl_min|turn_dps|turret_turn)[^\\n#]*[^\\w.](-?\\d+(\\.\\d+)?)\\b")
	var dirs: PackedStringArray = ["res://src/sim_ai"]
	while not dirs.is_empty():
		var dir: String = dirs[dirs.size() - 1]
		dirs.remove_at(dirs.size() - 1)
		for sub: String in DirAccess.get_directories_at(dir):
			var _a: bool = dirs.append(dir + "/" + sub)
		for f: String in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd"):
				continue
			var n: int = 0
			for line: String in FileAccess.get_file_as_string(dir + "/" + f).split("\n"):
				n += 1
				var code: String = line.split("#")[0]
				var m: RegExMatch = rx.search(code)
				if m != null and m.get_string(3) != "0" and m.get_string(3) != "0.0":
					bad.append("%s/%s:%d: %s" % [dir, f, n, line.strip_edges()])
	assert_array(bad).override_failure_message("envelope literals: %s" % str(bad)).is_empty()
