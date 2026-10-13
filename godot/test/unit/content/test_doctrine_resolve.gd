extends GdUnitTestSuite
## N4, N7 and the 02 s7 resolved examples (scenario C-10), against the real doctrines.json (GD-07).


func before_test() -> void:
	var r: Result = ContentDB.load_all()
	assert_bool(r.ok).is_true()


func test_doctrines_file_loaded() -> void:
	assert_int(ContentDB.doctrines.size()).is_equal(3)
	for id: StringName in [&"vanguard", &"bulwark", &"foundry"]:
		assert_object(ContentDB.doctrine(id)).is_not_null()
		assert_array(ContentDB.doctrine(id).errors).is_empty()


func test_every_modifier_matches_a_def_with_the_field() -> void:
	# 02 s7: a modifier on a field that exists on no selected def is a content error.
	var base: String = ContentDB.resolve_for_doctrine(&"").serialise()
	for d: DoctrineDef in ContentDB.doctrines.duplicate():
		for m: Variant in d.modifiers:
			var md: Dictionary = m
			var one: DoctrineDef = DoctrineDef.from_dict({"id": "probe", "status": "core", "tags": [],
				"modifiers": [{"select": md["select"], "field": md["field"], "op": "add", "value": 100}], "rules": {}})
			ContentDB.doctrines.append(one)
			var probed: String = ContentDB.resolve_for_doctrine(&"probe").serialise()
			ContentDB.doctrines.erase(one)
			assert_bool(probed != base).override_failure_message(
				"%s: %s matches nothing" % [d.id, md["field"]]).is_true()


func test_foundry_ship_mount_only_in_file() -> void:
	for m: Variant in ContentDB.doctrine(&"foundry").modifiers:
		var md: Dictionary = m
		var sel: Dictionary = md["select"]
		if sel.has("weapon_mount"):
			assert_str(str(sel["weapon_mount"])).is_equal("ship")


func test_selector_and_op_semantics() -> void:
	var row: Dictionary = {"id": "probe", "status": "core", "tags": [], "rules": {}, "modifiers": [
		{"select": {"ids": ["dart"]}, "field": "hp", "op": "add", "value": -10},
		{"select": {"ids": ["dart"]}, "field": "hp", "op": "mul", "value": 0.5},
		{"select": {"weapon_mount": "ground"}, "field": "range_m", "op": "set", "value": 123.0},
		{"select": {"ids": ["dart"]}, "field": "no_such_field", "op": "mul", "value": 2.0}]}
	var probe: DoctrineDef = DoctrineDef.from_dict(row)
	ContentDB.doctrines.append(probe)
	var r: ResolvedDefs = ContentDB.resolve_for_doctrine(&"probe")
	ContentDB.doctrines.erase(probe)
	assert_int(r.ship(ContentDB.def_index(&"dart")).hp).is_equal(45)  # file order: (100-10)*0.5
	assert_float(r.weapon(ContentDB.weapon_index(&"siege_gun")).range_m).is_equal(123.0)
	assert_float(r.weapon(ContentDB.weapon_index(&"gun_dart")).range_m).is_equal(800.0)


func test_vanguard_examples() -> void:
	var r: ResolvedDefs = ContentDB.resolve_for_doctrine(&"vanguard")
	var dart: ShipDef = r.ship(ContentDB.def_index(&"dart"))
	assert_int(dart.hp).is_equal(80)
	assert_float(dart.v_cruise).is_equal(126.5)
	assert_int(dart.secondary_count).is_equal(1)
	assert_float(r.flip_cooldown_s_override).is_equal(1.0)
	for s: ShipDef in r.ships:
		assert_float(s.flip_cooldown_s).is_equal(1.0)
	assert_object(r.doctrine_id).is_equal(&"vanguard")
	# untouched fields stay
	assert_float(dart.k_side).is_equal(0.5)


func test_bulwark_examples() -> void:
	var r: ResolvedDefs = ContentDB.resolve_for_doctrine(&"bulwark")
	assert_int(r.structure(ContentDB.def_index(&"core")).hp).is_equal(3750)
	assert_float(r.weapon(ContentDB.weapon_index(&"gun_turret")).range_m).is_equal(770.0)
	assert_int(r.structure(ContentDB.def_index(&"pad")).cost_ore).is_equal(175)  # 172.5 rounds up to 175
	assert_float(r.weapon(ContentDB.weapon_index(&"gun_dart")).range_m).is_equal(800.0)  # ship mount untouched
	assert_bool(r.hangar_blocks_rockets).is_true()


func test_foundry_examples() -> void:
	var r: ResolvedDefs = ContentDB.resolve_for_doctrine(&"foundry")
	assert_int(r.ship(ContentDB.def_index(&"dart")).cost_ore).is_equal(130)  # 127.5 rounds up
	var gun: WeaponDef = r.weapon(ContentDB.weapon_index(&"gun_dart"))
	assert_int(gun.damage_min).is_equal(5)
	assert_int(gun.damage_max).is_equal(12)
	var harvester: GroundUnitDef = r.ground_unit(ContentDB.def_index(&"harvester"))
	assert_int(harvester.cost_ore).is_equal(215)
	assert_int(harvester.cargo_ore).is_equal(375)
	assert_int(r.ship(ContentDB.def_index(&"hauler")).tow_slots).is_equal(2)
	assert_int(r.weapon(ContentDB.weapon_index(&"bomb")).damage_min).is_equal(340)
	# A-3: the Siege Crawler's ground-mounted gun is not discounted
	var base_siege: WeaponDef = ContentDB.weapon(ContentDB.weapon_index(&"siege_gun"))
	var siege: WeaponDef = r.weapon(ContentDB.weapon_index(&"siege_gun"))
	assert_int(siege.damage_min).is_equal(base_siege.damage_min)
	assert_float(r.reactor_unlock_s).is_equal(600.0)


func test_base_defs_unchanged_after_resolution() -> void:
	var dart: ShipDef = ContentDB.ship(0)
	var before_raw: String = ContentHash.canonical(dart.raw)
	var core: StructureDef = ContentDB.structure(ContentDB.def_index(&"core"))
	for id: StringName in [&"vanguard", &"bulwark", &"foundry"]:
		var r: ResolvedDefs = ContentDB.resolve_for_doctrine(id)
		assert_object(r.ship(0)).is_not_same(dart)
	assert_int(dart.hp).is_equal(100)
	assert_float(dart.v_cruise).is_equal(110.0)
	assert_int(dart.secondary_count).is_equal(2)
	assert_str(ContentHash.canonical(dart.raw)).is_equal(before_raw)
	assert_int(core.hp).is_equal(3000)
	assert_int(ContentDB.weapon(ContentDB.weapon_index(&"gun_dart")).damage_min).is_equal(6)


func test_resolution_is_pure_byte_identical() -> void:
	for id: StringName in [&"vanguard", &"bulwark", &"foundry"]:
		var a: String = ContentDB.resolve_for_doctrine(id).serialise()
		var b: String = ContentDB.resolve_for_doctrine(id).serialise()
		assert_str(a).is_equal(b)
		assert_bool(a.is_empty()).is_false()
	assert_str(ContentDB.resolve_for_doctrine(&"vanguard").serialise()) \
		.is_not_equal(ContentDB.resolve_for_doctrine(&"bulwark").serialise())


func test_no_doctrine_resolves_to_unmodified_copies() -> void:
	var r: ResolvedDefs = ContentDB.resolve_for_doctrine(&"")
	assert_int(r.ship(0).hp).is_equal(100)
	assert_object(r.ship(0)).is_not_same(ContentDB.ship(0))
	assert_int(r.ship(0).def_id).is_equal(0)
	assert_object(r.projectile(DefRanges.PROJECTILE_BASE)).is_same(ContentDB.projectile(DefRanges.PROJECTILE_BASE))


func test_unknown_doctrine_returns_null() -> void:
	assert_object(ContentDB.resolve_for_doctrine(&"nope")).is_null()


func test_round_field_rules() -> void:
	assert_float(DoctrineResolver.round_field("cost_ore", 172.49999999999997)).is_equal(175.0)
	assert_float(DoctrineResolver.round_field("cost_ore", 127.5)).is_equal(130.0)
	assert_float(DoctrineResolver.round_field("hp", 79.5)).is_equal(80.0)
	assert_float(DoctrineResolver.round_field("v_cruise", 126.49999999999999)).is_equal(126.5)
	assert_float(DoctrineResolver.round_field("v_cruise", 99.04)).is_equal(99.0)
