extends GdUnitTestSuite
## PlacementRules (UX-21; docs/06 s7.3, R0 C2-12): the Build.Reject mirror, the 13-reason priority, locale keys, the
## CommandResult mapping and the client-known rejects.

const R := PlacementRules
const NAMES: PackedStringArray = ["ELIMINATED", "PREREQ", "NO_RADIUS", "NO_PRESENCE", "ENEMY_RADIUS", "NOT_VISIBLE", "NODE", "OCCUPIED",
		"SLOPE", "SPACING", "SPEND_LOCKED", "FUNDS", "CAP"]


func before_test() -> void:
	var res: Result = ContentDB.load_all()
	assert_bool(res.ok).is_true()


func test_mirror_equals_build_reject() -> void:
	assert_int(R.OK).is_equal(Build.Reject.OK)
	assert_int(R.ELIMINATED).is_equal(Build.Reject.ELIMINATED)
	assert_int(R.PREREQ).is_equal(Build.Reject.PREREQ)
	assert_int(R.CAP).is_equal(Build.Reject.CAP)
	assert_int(R.OCCUPIED).is_equal(Build.Reject.OCCUPIED)
	assert_int(R.SLOPE).is_equal(Build.Reject.SLOPE)
	assert_int(R.NODE).is_equal(Build.Reject.NODE)
	assert_int(R.NOT_VISIBLE).is_equal(Build.Reject.NOT_VISIBLE)
	assert_int(R.ENEMY_RADIUS).is_equal(Build.Reject.ENEMY_RADIUS)
	assert_int(R.NO_RADIUS).is_equal(Build.Reject.NO_RADIUS)
	assert_int(R.NO_PRESENCE).is_equal(Build.Reject.NO_PRESENCE)
	assert_int(R.SPACING).is_equal(Build.Reject.SPACING)
	assert_int(R.FUNDS).is_equal(Build.Reject.FUNDS)
	assert_int(R.SPEND_LOCKED).is_equal(Build.Reject.SPEND_LOCKED)
	assert_int(R.COUNT).is_equal(Build.Reject.size())


func test_priority_is_the_06_order_over_all_13() -> void:
	var o: PackedInt32Array = R.order()
	assert_int(o.size()).is_equal(13)
	for i: int in NAMES.size():
		assert_int(o[i]).is_equal(Build.Reject[NAMES[i]])
	for r: int in o:
		assert_int(R.rank(r)).is_equal(o.find(r))
	assert_int(R.rank(R.OK)).is_less(0)


func test_top_picks_the_highest_priority() -> void:
	assert_int(R.top(PackedInt32Array())).is_equal(R.OK)
	assert_int(R.top(PackedInt32Array([R.OK]))).is_equal(R.OK)
	assert_int(R.top(PackedInt32Array([R.CAP, R.FUNDS]))).is_equal(R.FUNDS)
	assert_int(R.top(PackedInt32Array([R.SLOPE, R.OCCUPIED, R.NODE]))).is_equal(R.NODE)
	assert_int(R.top(PackedInt32Array([R.FUNDS, R.ELIMINATED, R.NO_RADIUS]))).is_equal(R.ELIMINATED)
	assert_int(R.top(PackedInt32Array([R.NOT_VISIBLE, R.ENEMY_RADIUS]))).is_equal(R.ENEMY_RADIUS)   # 06 order, not the sim's
	assert_int(R.top(PackedInt32Array([R.SPEND_LOCKED, R.FUNDS]))).is_equal(R.SPEND_LOCKED)
	for i: int in NAMES.size() - 1:
		assert_int(R.top(PackedInt32Array([Build.Reject[NAMES[i + 1]], Build.Reject[NAMES[i]]]))).is_equal(Build.Reject[NAMES[i]])


func test_every_reject_has_a_distinct_key_present_in_the_locale() -> void:
	var en: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/locale/en.json"))
	assert_bool(en is Dictionary).is_true()
	var table: Dictionary = en
	var seen: Dictionary = {}
	assert_str(String(R.key(R.OK))).is_empty()
	for name: String in NAMES:
		var k: StringName = R.key(Build.Reject[name])
		assert_str(String(k)).is_equal("ui.place.reject." + name.to_lower())
		assert_bool(table.has(String(k))).is_true()
		assert_bool(seen.has(k)).is_false()
		seen[k] = true
	assert_bool(table.has("ui.place.reject.generic")).is_true()
	assert_str(String(R.key(R.GENERIC))).is_equal("ui.place.reject.generic")


func test_args_carry_the_numbers_from_content() -> void:
	var ec: EconomyDef = ContentDB.economy
	assert_float(float(R.args(R.NO_PRESENCE, {})["m"])).is_equal(ec.outpost_presence_radius_m)
	assert_float(float(R.args(R.SLOPE, {})["max"])).is_equal(ec.build_max_slope_deg)
	assert_int(int(R.args(R.SLOPE, {"deg": 22})["deg"])).is_equal(22)
	assert_str(String(R.args(R.SPEND_LOCKED, {})["time"])).is_equal(Fmt.duration(int(DrawerMath.lock_end_s())))
	assert_str(String(R.args(R.PREREQ, {"need": &"shipyard"})["need"])).is_equal(DrawerCatalog.name_key(&"shipyard"))


func test_reason_is_translated_and_never_the_key() -> void:
	for name: String in NAMES:
		var s: String = R.reason(Build.Reject[name], {})
		assert_str(s).is_not_empty()
		assert_bool(s.begins_with("ui.place.")).is_false()
	assert_str(R.reason(R.OK, {})).is_empty()


func test_command_result_codes_map_to_rejects() -> void:
	var C := CommandResult.Code
	assert_int(R.from_result(C.REJECTED_PLACEMENT, Build.Reject.SLOPE)).is_equal(R.SLOPE)
	assert_int(R.from_result(C.REJECTED_LOCKED, 0)).is_equal(R.SPEND_LOCKED)
	assert_int(R.from_result(C.REJECTED_COST, 0)).is_equal(R.FUNDS)
	assert_int(R.from_result(C.REJECTED_CAP, 0)).is_equal(R.CAP)
	assert_int(R.from_result(C.REJECTED_PREREQ, 0)).is_equal(R.PREREQ)
	assert_int(R.from_result(C.REJECTED_NO_RIGHTS, 0)).is_equal(R.ELIMINATED)
	assert_int(R.from_result(C.REJECTED_RATE, 0)).is_equal(R.GENERIC)
	assert_int(R.from_result(C.REJECTED_PLACEMENT, 99)).is_equal(R.GENERIC)
	assert_int(R.from_result(C.ACCEPTED, 0)).is_equal(R.OK)


func test_client_rejects_from_the_drawer_context() -> void:
	var ctx: DrawerContext = DrawerContext.new()
	ctx.ore = 1000
	ctx.ice = 500
	ctx.commander_rights = true
	ctx.lock_left_ore = -1
	assert_int(R.top(R.client_rejects(ctx, &"outpost"))).is_equal(R.OK)
	ctx.ore = 100
	assert_int(R.top(R.client_rejects(ctx, &"outpost"))).is_equal(R.FUNDS)
	ctx.ore = 1000
	ctx.lock_left_ore = 100
	assert_int(R.top(R.client_rejects(ctx, &"outpost"))).is_equal(R.SPEND_LOCKED)
	ctx.eliminated = true
	assert_int(R.top(R.client_rejects(ctx, &"outpost"))).is_equal(R.ELIMINATED)
	ctx.eliminated = false
	ctx.commander_rights = false
	assert_int(R.top(R.client_rejects(ctx, &"outpost"))).is_equal(R.ELIMINATED)


func test_tint_and_params() -> void:
	assert_object(R.tint(R.OK)).is_equal(UiTokens.UI_OK)
	assert_object(R.tint(R.SLOPE)).is_equal(UiTokens.UI_WARN)
	assert_object(R.tint(R.OCCUPIED)).is_equal(UiTokens.UI_DANGER)
	assert_float(R.arm_alt_m()).is_equal(1200.0)
	assert_int(R.haptic_ms()).is_equal(8)
