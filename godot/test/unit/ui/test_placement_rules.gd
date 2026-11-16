extends GdUnitTestSuite
## PlacementRules (UX-21; docs/06 s7.3, R0 C2-12): the Build.Reject mirror, the 13-reason priority, locale keys, the
## CommandResult mapping and the client-known rejects.

const NAMES: PackedStringArray = ["ELIMINATED", "PREREQ", "NO_RADIUS", "NO_PRESENCE", "ENEMY_RADIUS", "NOT_VISIBLE", "NODE", "OCCUPIED",
		"SLOPE", "SPACING", "SPEND_LOCKED", "FUNDS", "CAP"]


func before_test() -> void:
	var res: Result = ContentDB.load_all()
	assert_bool(res.ok).is_true()


func test_mirror_equals_build_reject() -> void:
	assert_int(PlacementRules.OK).is_equal(Build.Reject.OK)
	assert_int(PlacementRules.ELIMINATED).is_equal(Build.Reject.ELIMINATED)
	assert_int(PlacementRules.PREREQ).is_equal(Build.Reject.PREREQ)
	assert_int(PlacementRules.CAP).is_equal(Build.Reject.CAP)
	assert_int(PlacementRules.OCCUPIED).is_equal(Build.Reject.OCCUPIED)
	assert_int(PlacementRules.SLOPE).is_equal(Build.Reject.SLOPE)
	assert_int(PlacementRules.NODE).is_equal(Build.Reject.NODE)
	assert_int(PlacementRules.NOT_VISIBLE).is_equal(Build.Reject.NOT_VISIBLE)
	assert_int(PlacementRules.ENEMY_RADIUS).is_equal(Build.Reject.ENEMY_RADIUS)
	assert_int(PlacementRules.NO_RADIUS).is_equal(Build.Reject.NO_RADIUS)
	assert_int(PlacementRules.NO_PRESENCE).is_equal(Build.Reject.NO_PRESENCE)
	assert_int(PlacementRules.SPACING).is_equal(Build.Reject.SPACING)
	assert_int(PlacementRules.FUNDS).is_equal(Build.Reject.FUNDS)
	assert_int(PlacementRules.SPEND_LOCKED).is_equal(Build.Reject.SPEND_LOCKED)
	assert_int(PlacementRules.COUNT).is_equal(Build.Reject.size())


func test_priority_is_the_06_order_over_all_13() -> void:
	var o: PackedInt32Array = PlacementRules.order()
	assert_int(o.size()).is_equal(13)
	for i: int in NAMES.size():
		assert_int(o[i]).is_equal(Build.Reject[NAMES[i]])
	for r: int in o:
		assert_int(PlacementRules.rank(r)).is_equal(o.find(r))
	assert_int(PlacementRules.rank(PlacementRules.OK)).is_less(0)


func test_top_picks_the_highest_priority() -> void:
	assert_int(PlacementRules.top(PackedInt32Array())).is_equal(PlacementRules.OK)
	assert_int(PlacementRules.top(PackedInt32Array([PlacementRules.OK]))).is_equal(PlacementRules.OK)
	assert_int(PlacementRules.top(PackedInt32Array([PlacementRules.CAP, PlacementRules.FUNDS]))).is_equal(PlacementRules.FUNDS)
	assert_int(PlacementRules.top(PackedInt32Array([PlacementRules.SLOPE, PlacementRules.OCCUPIED, PlacementRules.NODE]))).is_equal(PlacementRules.NODE)
	assert_int(PlacementRules.top(PackedInt32Array([PlacementRules.FUNDS, PlacementRules.ELIMINATED, PlacementRules.NO_RADIUS]))).is_equal(PlacementRules.ELIMINATED)
	assert_int(PlacementRules.top(PackedInt32Array([PlacementRules.NOT_VISIBLE, PlacementRules.ENEMY_RADIUS]))).is_equal(PlacementRules.ENEMY_RADIUS)   # 06 order, not the sim's
	assert_int(PlacementRules.top(PackedInt32Array([PlacementRules.SPEND_LOCKED, PlacementRules.FUNDS]))).is_equal(PlacementRules.SPEND_LOCKED)
	for i: int in NAMES.size() - 1:
		assert_int(PlacementRules.top(PackedInt32Array([Build.Reject[NAMES[i + 1]], Build.Reject[NAMES[i]]]))).is_equal(Build.Reject[NAMES[i]])


func test_every_reject_has_a_distinct_key_present_in_the_locale() -> void:
	var en: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/locale/en.json"))
	assert_bool(en is Dictionary).is_true()
	var table: Dictionary = en
	var seen: Dictionary = {}
	assert_str(String(PlacementRules.key(PlacementRules.OK))).is_empty()
	for name: String in NAMES:
		var k: StringName = PlacementRules.key(Build.Reject[name])
		assert_str(String(k)).is_equal("ui.place.reject." + name.to_lower())
		assert_bool(table.has(String(k))).is_true()
		assert_bool(seen.has(k)).is_false()
		seen[k] = true
	assert_bool(table.has("ui.place.reject.generic")).is_true()
	assert_str(String(PlacementRules.key(PlacementRules.GENERIC))).is_equal("ui.place.reject.generic")


func test_args_carry_the_numbers_from_content() -> void:
	var ec: EconomyDef = ContentDB.economy
	assert_float(float(PlacementRules.args(PlacementRules.NO_PRESENCE, {})["m"])).is_equal(ec.outpost_presence_radius_m)
	assert_float(float(PlacementRules.args(PlacementRules.SLOPE, {})["max"])).is_equal(ec.build_max_slope_deg)
	assert_int(int(PlacementRules.args(PlacementRules.SLOPE, {"deg": 22})["deg"])).is_equal(22)
	assert_str(String(PlacementRules.args(PlacementRules.SPEND_LOCKED, {})["time"])).is_equal(Fmt.duration(int(DrawerMath.lock_end_s())))
	assert_str(String(PlacementRules.args(PlacementRules.PREREQ, {"need": &"shipyard"})["need"])).is_equal(DrawerCatalog.name_key(&"shipyard"))


func test_reason_is_translated_and_never_the_key() -> void:
	for name: String in NAMES:
		var s: String = PlacementRules.reason(Build.Reject[name], {})
		assert_str(s).is_not_empty()
		assert_bool(s.begins_with("ui.place.")).is_false()
	assert_str(PlacementRules.reason(PlacementRules.OK, {})).is_empty()


func test_command_result_codes_map_to_rejects() -> void:
	var C := CommandResult.Code
	assert_int(PlacementRules.from_result(C.REJECTED_PLACEMENT, Build.Reject.SLOPE)).is_equal(PlacementRules.SLOPE)
	assert_int(PlacementRules.from_result(C.REJECTED_LOCKED, 0)).is_equal(PlacementRules.SPEND_LOCKED)
	assert_int(PlacementRules.from_result(C.REJECTED_COST, 0)).is_equal(PlacementRules.FUNDS)
	assert_int(PlacementRules.from_result(C.REJECTED_CAP, 0)).is_equal(PlacementRules.CAP)
	assert_int(PlacementRules.from_result(C.REJECTED_PREREQ, 0)).is_equal(PlacementRules.PREREQ)
	assert_int(PlacementRules.from_result(C.REJECTED_NO_RIGHTS, 0)).is_equal(PlacementRules.ELIMINATED)
	assert_int(PlacementRules.from_result(C.REJECTED_RATE, 0)).is_equal(PlacementRules.GENERIC)
	assert_int(PlacementRules.from_result(C.REJECTED_PLACEMENT, 99)).is_equal(PlacementRules.GENERIC)
	assert_int(PlacementRules.from_result(C.ACCEPTED, 0)).is_equal(PlacementRules.OK)


func test_client_rejects_from_the_drawer_context() -> void:
	var ctx: DrawerContext = DrawerContext.new()
	ctx.ore = 1000
	ctx.ice = 500
	ctx.commander_rights = true
	ctx.lock_left_ore = -1
	assert_int(PlacementRules.top(PlacementRules.client_rejects(ctx, &"outpost"))).is_equal(PlacementRules.OK)
	ctx.ore = 100
	assert_int(PlacementRules.top(PlacementRules.client_rejects(ctx, &"outpost"))).is_equal(PlacementRules.FUNDS)
	ctx.ore = 1000
	ctx.lock_left_ore = 100
	assert_int(PlacementRules.top(PlacementRules.client_rejects(ctx, &"outpost"))).is_equal(PlacementRules.SPEND_LOCKED)
	ctx.eliminated = true
	assert_int(PlacementRules.top(PlacementRules.client_rejects(ctx, &"outpost"))).is_equal(PlacementRules.ELIMINATED)
	ctx.eliminated = false
	ctx.commander_rights = false
	assert_int(PlacementRules.top(PlacementRules.client_rejects(ctx, &"outpost"))).is_equal(PlacementRules.ELIMINATED)


func test_tint_and_params() -> void:
	assert_object(PlacementRules.tint(PlacementRules.OK)).is_equal(UiTokens.UI_OK)
	assert_object(PlacementRules.tint(PlacementRules.SLOPE)).is_equal(UiTokens.UI_WARN)
	assert_object(PlacementRules.tint(PlacementRules.OCCUPIED)).is_equal(UiTokens.UI_DANGER)
	assert_float(PlacementRules.arm_alt_m()).is_equal(1200.0)
	assert_int(PlacementRules.haptic_ms()).is_equal(8)
