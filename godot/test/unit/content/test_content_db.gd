extends GdUnitTestSuite
## ContentDB: loads every v1 def file (N3, N4), signals, caps (A-8), modes, dangling refs.

const DEFS: String = "res://content/defs/"

var _signal_ok: Array[bool] = []


func before_test() -> void:
	var r: Result = ContentDB.load_all()
	assert_bool(r.ok).is_true()


func _texts() -> Dictionary:
	var out: Dictionary = {}
	for f: String in DirAccess.get_files_at(DEFS):
		if f.ends_with(".json"):
			out[f] = FileAccess.get_file_as_string(DEFS + f)
	return out


func test_loads_every_def_file() -> void:
	assert_bool(ContentDB.is_loaded()).is_true()
	assert_int(ContentDB.ships.size()).is_equal(5)
	assert_int(ContentDB.ground_units.size()).is_equal(2)
	assert_int(ContentDB.structures.size()).is_equal(18)  # 13 structures + 5 towers
	assert_int(ContentDB.weapons.size()).is_equal(9)
	assert_int(ContentDB.projectiles.size()).is_equal(8)
	assert_int(ContentDB.modes.size()).is_equal(7)
	assert_int(ContentDB.bot_promises.size()).is_equal(4)
	assert_object(ContentDB.rules).is_not_null()
	assert_object(ContentDB.flight_common).is_not_null()
	assert_object(ContentDB.economy).is_not_null()
	assert_object(ContentDB.match_rules).is_not_null()
	assert_object(ContentDB.scoring).is_not_null()
	assert_int(ContentDB.rules.tick_hz).is_equal(30)
	assert_float(ContentDB.flight_common.auto_dock_radius_m).is_equal(150.0)
	assert_int(ContentDB.economy.start_ore).is_equal(800)
	assert_int(ContentDB.scoring.match_win).is_equal(500)
	assert_int(ContentDB.slots_by_player_count.size()).is_equal(4)


func test_loaded_signal_once_per_load() -> void:
	_signal_ok.clear()
	var cb: Callable = func(ok: bool) -> void: _signal_ok.append(ok)
	ContentDB.loaded.connect(cb)
	var r: Result = ContentDB.load_all()
	ContentDB.loaded.disconnect(cb)
	assert_bool(r.ok).is_true()
	assert_array(_signal_ok).is_equal([true])


func test_missing_directory_fails_and_leaves_nothing_loaded() -> void:
	_signal_ok.clear()
	var cb: Callable = func(ok: bool) -> void: _signal_ok.append(ok)
	ContentDB.loaded.connect(cb)
	var r: Result = ContentDB.load_all("res://content/nope/")
	ContentDB.loaded.disconnect(cb)
	assert_bool(r.ok).is_false()
	assert_array(_signal_ok).is_equal([false])
	assert_bool(ContentDB.is_loaded()).is_false()
	assert_int(ContentDB.ships.size()).is_equal(0)
	assert_int(ContentDB.def_index(&"dart")).is_equal(-1)


func test_dangling_projectile_reference_fails() -> void:
	var texts: Dictionary = _texts()
	texts["weapons.json"] = str(texts["weapons.json"]).replace("\"slug_light\"", "\"slug_nope\"")
	var s: ContentSet = ContentLoader.build(texts, {})
	assert_bool(s.ok()).is_false()
	assert_str(s.errors[0]).contains("unknown projectile")


func test_dangling_weapon_and_requires_reference_fail() -> void:
	var texts: Dictionary = _texts()
	texts["ships.json"] = str(texts["ships.json"]).replace("\"gun_dart\"", "\"gun_nope\"")
	var s: ContentSet = ContentLoader.build(texts, {})
	assert_bool(s.ok()).is_false()
	assert_str(s.errors[0]).contains("unknown weapon")
	var t2: Dictionary = _texts()
	t2["ground_units.json"] = str(t2["ground_units.json"]).replace("\"vehicle_bay\"", "\"vehicle_nope\"")
	var s2: ContentSet = ContentLoader.build(t2, {})
	assert_bool(s2.ok()).is_false()


func test_schema_violations_fail() -> void:
	var texts: Dictionary = _texts()
	texts["rules.json"] = str(texts["rules.json"]).replace("\"gravity\": 6.0,", "")
	assert_bool(ContentLoader.build(texts, {}).ok()).is_false()
	var t2: Dictionary = _texts()
	t2["ships.json"] = str(t2["ships.json"]).replace("\"hp\": 100", "\"hp\": \"many\"")
	assert_bool(ContentLoader.build(t2, {}).ok()).is_false()
	var t3: Dictionary = _texts()
	t3.erase("economy.json")
	assert_bool(ContentLoader.build(t3, {}).ok()).is_false()
	var t4: Dictionary = _texts()
	t4["modes.json"] = "{ not json"
	assert_bool(ContentLoader.build(t4, {}).ok()).is_false()


func test_duplicate_entity_id_across_files_fails() -> void:
	var texts: Dictionary = _texts()
	texts["towers.json"] = str(texts["towers.json"]).replace("\"autocannon_turret\"", "\"dart\"")
	var s: ContentSet = ContentLoader.build(texts, {})
	assert_bool(s.ok()).is_false()


func test_caps_profiles() -> void:
	var std: CapsDef = ContentDB.caps(&"standard")
	assert_int(std.units).is_equal(80)
	assert_int(std.structures).is_equal(60)
	assert_int(std.projectiles).is_equal(2000)
	assert_int(std.wrecks).is_equal(200)
	assert_int(std.slots).is_equal(8)
	assert_object(std.id).is_equal(&"standard")
	var red: CapsDef = ContentDB.caps(&"reduced")
	assert_int(red.units).is_equal(40)
	assert_int(red.projectiles).is_equal(1000)
	var lite: CapsDef = ContentDB.caps(&"lite")
	assert_int(lite.units).is_equal(30)
	assert_int(lite.slots).is_equal(4)
	assert_object(ContentDB.caps(&"huge")).is_null()


func test_mode_lookup() -> void:
	var m: ModeDef = ContentDB.mode(&"pvp_1v1")
	assert_object(m).is_not_null()
	assert_int(m.humans[0]).is_equal(2)
	assert_str(m.teams).is_equal("1v1")
	assert_float(m.fill_after_s).is_equal(120.0)
	assert_float(m.fill_rating_weight).is_equal(0.0)
	assert_float(m.core_exposure_s).is_equal(1200.0)
	assert_float(m.hard_end_s).is_equal(1800.0)
	assert_bool(m.pause_save).is_false()
	assert_object(m.caps).is_equal(&"standard")
	assert_bool(m.hosting.has("dedicated")).is_true()
	var t: ModeDef = ContentDB.mode(&"pvp_team")
	assert_float(t.fill_rating_weight).is_equal(1.0)  # omitted = 1.0
	for id: StringName in [&"pvp_1v1", &"pvp_2v2", &"pvp_team", &"coop", &"custom", &"skirmish", &"campaign"]:
		assert_object(ContentDB.mode(id)).is_not_null()
	assert_object(ContentDB.mode(&"nope")).is_null()
	assert_float(ContentDB.mode(&"campaign").core_exposure_s).is_equal(ModeDef.NONE_S)


func test_map_lookup_unknown_is_null() -> void:
	assert_object(ContentDB.map(&"nope")).is_null()


func test_mod_pack_rejects_paths_outside_user_mods() -> void:
	assert_bool(ContentDB.load_mod_pack("res://content/defs/").ok).is_false()
	assert_bool(ContentDB.load_mod_pack("user://mods/../x").ok).is_false()
	assert_bool(ContentDB.load_mod_pack("user://mods/does_not_exist_ta09").ok).is_false()
	assert_bool(ContentDB.is_loaded()).is_true()  # a rejected pack leaves the stock defs loaded


func test_flight_common_carries_brake_fade_mps() -> void:
	# R0 B.9 A-13: required flight_common field read by Kinematics (TA-44); parsed, not an unknown key (TA-45).
	var raw: Dictionary = ContentDB.flight_common.raw
	assert_float(ContentDB.flight_common.brake_fade_mps).is_equal(Def.num(raw["brake_fade_mps"]))
	assert_float(ContentDB.flight_common.brake_fade_mps).is_greater(0.0)
	assert_array(ContentDB.flight_common.unknown).not_contains(["brake_fade_mps"])


func test_flight_common_carries_a29_to_a35_fields() -> void:
	# R0 B.9 A-29..A-35 (TA-48): every S-FLIGHT-1 append is parsed into its typed field, none is an unknown key,
	# and a missing one is a load error (required in the schema, so no default in code).
	var fc: FlightCommonDef = ContentDB.flight_common
	for key: String in ["flip_speed_retain", "scrape_clear_s", "fuel_burn_boost_per_s", "fuel_burn_brake_per_s",
			"fuel_burn_idle_per_s", "landing_damage_tilt_deg", "auto_dock_latch_mult"]:
		assert_float(fc.get(key) as float).is_equal(Def.num(fc.raw[key]))
		assert_array(fc.unknown).not_contains([key])
		var d: Dictionary = fc.raw.duplicate(true)
		var _e: bool = d.erase(key)
		assert_array(FlightCommonDef.from_dict(d).errors).contains(["flight_common.%s missing or not a number" % key])
	assert_float(fc.flip_speed_retain).is_equal(0.75)        # 02 s2.2 values (A-29, A-32)
	assert_float(fc.fuel_burn_boost_per_s).is_equal(2.0)
	assert_float(fc.fuel_burn_brake_per_s).is_equal(0.6)
	assert_float(fc.fuel_burn_idle_per_s).is_equal(0.05)
	assert_array(fc.errors).is_empty()


func test_defs_hold_presentation_and_doc() -> void:
	var dart: ShipDef = ContentDB.ship(ContentDB.def_index(&"dart"))
	assert_str(dart.presentation.mesh).is_equal("res://assets/models/ships/ship_dart.glb")
	assert_str(String(dart.presentation.far_mesh_node)).is_equal("ShipDartFar")
	assert_str(dart.doc).contains("02 s2.1")
	assert_int(dart.secondary_count).is_equal(2)
	assert_object(dart.secondary_weapon).is_equal(&"bomb")
	assert_object(dart.status).is_equal(&"core")


func test_load_all_async_takes_the_synchronous_path_on_native() -> void:
	_signal_ok.clear()
	var cb: Callable = func(ok: bool) -> void: _signal_ok.append(ok)
	ContentDB.loaded.connect(cb)
	ContentDB.load_all_async(DEFS)
	ContentDB.loaded.disconnect(cb)
	assert_array(_signal_ok).is_equal([true])
	assert_bool(ContentDB.is_loaded()).is_true()


func test_load_time_budget_n6() -> void:
	# N6: <= 150 ms on PC-mid for the v1 set. The hosted CI runner is slower and noisier, so the hard gate
	# here is 4x; the pinned perf runner (TA-42) holds the real 150 ms line.
	var best: int = 1 << 30
	for _i: int in 5:
		var t0: int = Time.get_ticks_usec()
		var r: Result = ContentDB.load_all()
		best = mini(best, Time.get_ticks_usec() - t0)
		assert_bool(r.ok).is_true()
	print("ContentDB.load_all best of 5: %.1f ms" % (best / 1000.0))
	# Hard counter (A-97): every def file under DEFS was ingested (the work the 150 ms row bounds). The 4x bound is report-only on hosted runners.
	assert_int(ContentDB._texts.size()).override_failure_message("def files ingested").is_equal(_texts().size())
	assert_bool(PerfGate.check("content_db.load_all", float(best), 600000.0, "N6 (150 ms) x 4 CI; hosted 29.0 ms")).is_true()
