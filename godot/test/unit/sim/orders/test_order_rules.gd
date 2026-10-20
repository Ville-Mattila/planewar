extends GdUnitTestSuite
## OrderRules + OrderSpec (05 s3.1-3.3, R0 B.3/C2-06, 04 V-ORD): validity per class and kind from the real
## order_rules.json, towers accept ATTACK/HOLD/GUARD only, reserved kinds rejected, flag and field checks,
## ORDER payload size arithmetic.

const K := OrderSpec.Kind

var _rules: OrderRules


func before_test() -> void:
	var r: Result = ContentDB.load_all()
	assert_bool(r.ok).is_true()
	assert_object(ContentDB.order_rules).is_not_null()
	_rules = OrderRules.from_def(ContentDB.order_rules)
	_rules.bind(ContentDB.ships, ContentDB.ground_units, ContentDB.structures)


func _id(name: StringName) -> int:
	var i: int = ContentDB.def_index(name)
	assert_int(i).is_greater_equal(0)
	return i


func _spec(kind: int, flags: int = 0) -> OrderSpec:
	var s: OrderSpec = OrderSpec.make(kind as K, 5, Vector3(0.0, 6300.0, 0.0), flags)
	if kind == K.PATROL:
		s.points = PackedVector3Array([Vector3.ZERO, Vector3.ONE])
	return s


func _accepted(def_name: StringName) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for k: int in OrderSpec.KIND_COUNT:
		if _rules.validate(_spec(k), _id(def_name), true) == OrderRules.Verdict.OK:
			out.append(k)
	return out


func test_kind_ordinals_are_frozen() -> void:
	assert_int(K.MOVE).is_equal(0)
	assert_int(K.GUARD).is_equal(8)
	assert_int(K.SUPPLY_DROP).is_equal(9)
	assert_int(K.PATROL_ROUTE).is_equal(10)
	assert_int(K.ATTACK_VIA).is_equal(11)
	assert_int(OrderSpec.HaulMode.CAPTURE).is_equal(2)
	assert_int(OrderSpec.EscortMode.BREAK).is_equal(2)
	assert_int(OrderSpec.FLAG_QUEUE).is_equal(1)
	assert_int(OrderSpec.FLAG_PREPEND).is_equal(2)
	assert_int(OrderSpec.FLAG_LOW).is_equal(4)
	assert_int(OrderSpec.KIND_NAMES.size()).is_equal(OrderSpec.KIND_COUNT)


func test_towers_accept_attack_hold_guard_only() -> void:
	for t: StructureDef in ContentDB.structures:
		if t.tower.is_empty():
			continue
		assert_array(_accepted(t.id)).contains_exactly([K.ATTACK, K.HOLD, K.GUARD])


func test_other_structures_accept_nothing() -> void:
	var n: int = 0
	for s: StructureDef in ContentDB.structures:
		if not s.tower.is_empty():
			continue
		n += 1
		assert_array(_accepted(s.id)).is_empty()
	assert_int(n).is_equal(14)   # 13 structures + the shield_projector (no weapon, no tower block)


func test_class_matrix_matches_05_s3_2() -> void:
	assert_array(_accepted(&"dart")).contains_exactly([K.MOVE, K.PATROL, K.ATTACK, K.ESCORT, K.RETURN, K.HOLD, K.GUARD])
	assert_array(_accepted(&"lancer")).contains_exactly([K.MOVE, K.PATROL, K.ATTACK, K.ESCORT, K.RETURN, K.HOLD, K.GUARD])
	assert_array(_accepted(&"bomber")).contains_exactly([K.MOVE, K.PATROL, K.ATTACK, K.RETURN, K.HOLD, K.GUARD])
	assert_array(_accepted(&"scout")).contains_exactly([K.MOVE, K.PATROL, K.RETURN, K.HOLD, K.GUARD])
	assert_array(_accepted(&"hauler")).contains_exactly([K.MOVE, K.PATROL, K.HAUL, K.RETURN, K.HOLD, K.GUARD])
	assert_array(_accepted(&"harvester")).contains_exactly([K.MOVE, K.HARVEST_HERE, K.HOLD])
	assert_array(_accepted(&"siege_crawler")).contains_exactly([K.MOVE, K.PATROL, K.ATTACK, K.HOLD, K.GUARD])


func test_reserved_and_unknown_kinds_are_rejected_for_every_class() -> void:
	for d: ShipDef in ContentDB.ships:
		assert_int(_rules.validate(_spec(K.PATROL_ROUTE), _id(d.id), true)).is_equal(OrderRules.Verdict.RESERVED_KIND)
		assert_int(_rules.validate(_spec(K.ATTACK_VIA), _id(d.id), true)).is_equal(OrderRules.Verdict.RESERVED_KIND)
		assert_int(_rules.validate(_spec(K.SUPPLY_DROP), _id(d.id), true)).is_equal(OrderRules.Verdict.DISABLED_KIND)
	var bad: OrderSpec = OrderSpec.new()
	bad.kind = 12 as K
	assert_int(_rules.validate(bad, _id(&"dart"), true)).is_equal(OrderRules.Verdict.UNKNOWN_KIND)
	assert_bool(_rules.allows(10, _id(&"dart"))).is_false()
	assert_bool(_rules.allows(-1, _id(&"dart"))).is_false()
	assert_bool(_rules.allows(0, 99999)).is_false()


func test_supply_drop_stays_disabled_until_the_gate_opens() -> void:
	assert_bool(_rules.kind_enabled(K.SUPPLY_DROP)).is_false()
	assert_int(_rules.validate(_spec(K.SUPPLY_DROP), _id(&"core"), true)).is_equal(OrderRules.Verdict.DISABLED_KIND)
	# With the kind enabled the pad-bearing structures accept it and a Dart does not.
	var d: OrderRulesDef = OrderRulesDef.from_dict(ContentDB.order_rules.raw)
	d.raw["enabled_kinds"] = (d.raw["enabled_kinds"] as Array) + ["supply_drop"]
	var r: OrderRules = OrderRules.from_def(d)
	r.bind(ContentDB.ships, ContentDB.ground_units, ContentDB.structures)
	for n: StringName in [&"core", &"pad", &"hangar", &"relay_station"]:
		assert_int(r.validate(_spec(K.SUPPLY_DROP), _id(n), true)).is_equal(OrderRules.Verdict.OK)
	assert_int(r.validate(_spec(K.SUPPLY_DROP), _id(&"dart"), true)).is_equal(OrderRules.Verdict.NOT_ALLOWED)


func test_flags_client_may_not_prepend_or_combine() -> void:
	var dart: int = _id(&"dart")
	assert_int(_rules.validate(_spec(K.MOVE, OrderSpec.FLAG_QUEUE | OrderSpec.FLAG_LOW), dart, true)).is_equal(OrderRules.Verdict.OK)
	assert_int(_rules.validate(_spec(K.RETURN, OrderSpec.FLAG_PREPEND), dart, true)).is_equal(OrderRules.Verdict.BAD_FLAGS)
	assert_int(_rules.validate(_spec(K.RETURN, OrderSpec.FLAG_PREPEND), dart, false)).is_equal(OrderRules.Verdict.OK)
	assert_int(_rules.validate(_spec(K.RETURN, OrderSpec.FLAG_PREPEND | OrderSpec.FLAG_QUEUE), dart, false)).is_equal(OrderRules.Verdict.BAD_FLAGS)
	assert_int(_rules.validate(_spec(K.MOVE, 8), dart, false)).is_equal(OrderRules.Verdict.BAD_FLAGS)


func test_patrol_needs_two_to_eight_points_others_none() -> void:
	var dart: int = _id(&"dart")
	for n: int in [0, 1, 9, 16]:
		var s: OrderSpec = _spec(K.PATROL)
		s.points.resize(n)
		assert_int(_rules.validate(s, dart, true)).is_equal(OrderRules.Verdict.BAD_POINTS)
	for n: int in [2, 5, 8]:
		var s2: OrderSpec = _spec(K.PATROL)
		s2.points.resize(n)
		assert_int(_rules.validate(s2, dart, true)).is_equal(OrderRules.Verdict.OK)
	var m: OrderSpec = _spec(K.MOVE)
	m.points = PackedVector3Array([Vector3.ZERO])
	assert_int(_rules.validate(m, dart, true)).is_equal(OrderRules.Verdict.BAD_POINTS)
	assert_bool(OrderRules.malformed(OrderRules.Verdict.BAD_POINTS)).is_true()
	assert_bool(OrderRules.malformed(OrderRules.Verdict.NOT_ALLOWED)).is_false()


func test_haul_mode_only_with_haul() -> void:
	var h: OrderSpec = _spec(K.HAUL)
	h.haul_mode = OrderSpec.HaulMode.CAPTURE
	assert_int(_rules.validate(h, _id(&"hauler"), true)).is_equal(OrderRules.Verdict.OK)
	assert_int(_rules.validate(h, _id(&"dart"), true)).is_equal(OrderRules.Verdict.NOT_ALLOWED)
	var m: OrderSpec = _spec(K.MOVE)
	m.haul_mode = OrderSpec.HaulMode.TOW
	assert_int(_rules.validate(m, _id(&"hauler"), true)).is_equal(OrderRules.Verdict.BAD_HAUL_MODE)


func test_escort_fields_only_on_escort_and_in_range() -> void:
	var e: OrderSpec = _spec(K.ESCORT)
	e.escort_slot = 2
	e.focus = 9
	e.escort_mode = OrderSpec.EscortMode.FOCUS
	assert_int(_rules.validate(e, _id(&"lancer"), true)).is_equal(OrderRules.Verdict.OK)
	assert_int(_rules.validate(e, _id(&"hauler"), true)).is_equal(OrderRules.Verdict.NOT_ALLOWED)
	e.escort_slot = _rules.escort_slot_max + 1
	assert_int(_rules.validate(e, _id(&"lancer"), true)).is_equal(OrderRules.Verdict.BAD_ESCORT)
	e.escort_slot = -2
	assert_int(_rules.validate(e, _id(&"lancer"), true)).is_equal(OrderRules.Verdict.BAD_ESCORT)
	var m: OrderSpec = _spec(K.MOVE)
	m.escort_mode = OrderSpec.EscortMode.BREAK
	assert_int(_rules.validate(m, _id(&"lancer"), true)).is_equal(OrderRules.Verdict.BAD_ESCORT)


func test_numbers_come_from_the_json() -> void:
	assert_int(_rules.queue_max).is_equal(OrderQueue.QUEUE_MAX)
	assert_float(_rules.arrival_radius_ship_m).is_equal(150.0)
	assert_float(_rules.arrival_radius_ground_m).is_equal(40.0)
	assert_float(_rules.ghost_timeout_s).is_equal(30.0)
	assert_float(_rules.attack_gun_duration_s).is_equal(20.0)
	assert_float(_rules.patrol_engage_radius_m).is_equal(1200.0)
	assert_float(_rules.escort_engage_radius_m).is_equal(1000.0)
	assert_float(_rules.guard_orbit_radius_m).is_equal(600.0)
	assert_float(_rules.guard_engage_radius_m).is_equal(1500.0)
	assert_float(_rules.hold_orbit_radius_m).is_equal(250.0)
	assert_int(_rules.patrol_points_max).is_equal(8)


func test_wire_size_arithmetic_matches_04() -> void:
	assert_int(OrderSpec.wire_size(1, 0)).is_equal(13)
	assert_int(OrderSpec.wire_size(32, 14)).is_equal(249)
	assert_bool(OrderSpec.fits_wire(32, 14)).is_true()
	assert_bool(OrderSpec.fits_wire(32, 15)).is_false()
	assert_bool(OrderSpec.fits_wire(29, 16)).is_true()   # 253 B
	assert_bool(OrderSpec.fits_wire(30, 16)).is_false()
	assert_bool(OrderSpec.fits_wire(0, 0)).is_false()
	assert_bool(OrderSpec.fits_wire(33, 0)).is_false()
	assert_bool(OrderSpec.fits_wire(1, 16)).is_true()
	assert_bool(OrderSpec.fits_wire(1, 17)).is_false()
	assert_int(OrderSpec.wire_size(1, 16)).is_equal(141)
	assert_int(OrderSpec.wire_size(32, 0, OrderSpec.Kind.ESCORT)).is_equal(143)            # R0 B.16 A-91
	assert_int(OrderSpec.wire_size(32, 0, OrderSpec.Kind.MOVE)).is_equal(OrderSpec.wire_size(32, 0))
	assert_bool(OrderSpec.fits_wire(32, 0, OrderSpec.Kind.ESCORT)).is_true()
	assert_bool(OrderSpec.fits_wire(32, 15, OrderSpec.Kind.ESCORT)).is_false()             # 263 B


func test_spec_copy_and_equals() -> void:
	var a: OrderSpec = _spec(K.PATROL, OrderSpec.FLAG_LOW)
	a.issuer = 3
	a.progress = 1
	var b: OrderSpec = OrderSpec.new()
	b.copy_from(a)
	assert_bool(a.equals(b)).is_true()
	b.points[0] = Vector3(9.0, 9.0, 9.0)
	assert_bool(a.equals(b)).is_false()
	assert_str(OrderSpec.kind_name(K.HARVEST_HERE)).is_equal("harvest_here")
	assert_int(OrderSpec.kind_from_name("guard")).is_equal(K.GUARD)
	assert_int(OrderSpec.kind_from_name("nope")).is_equal(-1)
