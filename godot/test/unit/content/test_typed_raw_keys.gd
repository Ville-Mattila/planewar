extends GdUnitTestSuite
## CONTENT-3: typed fields for def keys the sim read raw (R0 B.25 A-130/A-135).


func before_test() -> void:
	var r: Result = ContentDB.load_all()
	assert_bool(r.ok).is_true()


func _proj(id: StringName) -> ProjectileDef:
	return ContentDB.projectile(ContentDB.projectile_index(id))


func test_flak_shell_fuse_delay() -> void:
	assert_float(_proj(&"flak_shell").fuse_delay_s).is_equal(0.3)


func test_absent_optional_reads_zero() -> void:
	var p: ProjectileDef = ProjectileDef.from_dict(
		{"id": "x", "behaviour": "straight", "transport": false, "shield_absorbed": false, "hp": 0}
	)
	assert_array(p.errors).is_empty()
	assert_float(p.fuse_delay_s).is_equal(0.0)
	assert_float(p.lock_break_agl_m).is_equal(0.0)
	assert_float(p.lock_break_flip_min_m).is_equal(0.0)
	assert_float(p.lock_break_flip_max_m).is_equal(0.0)


func test_lock_break_keys_parse() -> void:
	var p: ProjectileDef = ProjectileDef.from_dict(
		{
			"id": "x", "behaviour": "guided", "transport": true, "shield_absorbed": true, "hp": 0,
			"lock_break_agl_m": 40, "lock_break_flip_min_m": 100, "lock_break_flip_max_m": 500,
		}
	)
	assert_float(p.lock_break_agl_m).is_equal(40.0)
	assert_float(p.lock_break_flip_min_m).is_equal(100.0)
	assert_float(p.lock_break_flip_max_m).is_equal(500.0)


func test_rocket_lock_break_if_shipped() -> void:
	var p: ProjectileDef = _proj(&"rocket")
	if not p.raw.has("lock_break_agl_m"):
		return  # arrives with GD-09 (PR #132)
	assert_float(p.lock_break_agl_m).is_equal(40.0)
	assert_float(p.lock_break_flip_min_m).is_equal(100.0)
	assert_float(p.lock_break_flip_max_m).is_equal(500.0)


func test_crash_pad_damage() -> void:
	assert_float(ContentDB.flight_common.crash_pad_damage).is_equal(100.0)


func test_crash_pad_damage_required() -> void:
	var d: Dictionary = ContentDB.flight_common.raw.duplicate(true)
	d.erase("crash_pad_damage")
	assert_bool(FlightCommonDef.from_dict(d).errors.is_empty()).is_false()


func test_pad_queue_radius() -> void:
	assert_float(ContentDB.economy.pad_queue_radius_m).is_equal(500.0)


func test_pad_queue_radius_required() -> void:
	var d: Dictionary = ContentDB.economy.raw.duplicate(true)
	d.erase("pad_queue_radius_m")
	assert_bool(EconomyDef.from_dict(d).errors.is_empty()).is_false()
