extends GdUnitTestSuite
## CONTENT-4: typed capture fields (R0 B.30 A-148): StructureDef.capture_s / contest_radius_m and ShipDef.captures.


func before_test() -> void:
	var r: Result = ContentDB.load_all()
	assert_bool(r.ok).is_true()


func _relay() -> StructureDef:
	return ContentDB.structure(ContentDB.def_index(&"relay_station"))


func _hauler() -> ShipDef:
	return ContentDB.ship(ContentDB.def_index(&"hauler"))


func test_relay_station_capture_fields() -> void:
	var s: StructureDef = _relay()
	assert_float(s.capture_s).is_equal(20.0)
	assert_float(s.contest_radius_m).is_equal(300.0)


func test_hauler_captures() -> void:
	assert_bool(_hauler().captures).is_true()


func test_absent_capture_keys_read_zero_and_false() -> void:
	var sd: Dictionary = _relay().raw.duplicate(true)
	sd.erase("capture_s")
	sd.erase("contest_radius_m")
	var s: StructureDef = StructureDef.from_dict(sd)
	assert_float(s.capture_s).is_equal(0.0)
	assert_float(s.contest_radius_m).is_equal(0.0)
	var hd: Dictionary = _hauler().raw.duplicate(true)
	hd.erase("captures")
	var h: ShipDef = ShipDef.from_dict(hd)
	assert_bool(h.captures).is_false()
