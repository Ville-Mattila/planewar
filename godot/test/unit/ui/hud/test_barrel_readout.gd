extends GdUnitTestSuite
## Unit tests for UX-49: HudMath.barrel_deg / barrel_fill01, BarrelReadoutData and BarrelReadoutView (06 s3.2, s6.1).


func _def(slew: float, lo: float, hi: float) -> GroundUnitDef:
	var g: GroundUnitDef = GroundUnitDef.new()
	g.barrel_slew_dps = slew
	g.barrel_min_deg = lo
	g.barrel_max_deg = hi
	return g


func test_barrel_deg_rounds_to_whole_degrees() -> void:
	assert_int(HudMath.barrel_deg(deg_to_rad(12.4), 0.0, 45.0)).is_equal(12)
	assert_int(HudMath.barrel_deg(deg_to_rad(12.6), 0.0, 45.0)).is_equal(13)
	assert_int(HudMath.barrel_deg(0.0, 0.0, 45.0)).is_equal(0)


func test_barrel_deg_clamps_to_def_limits() -> void:
	assert_int(HudMath.barrel_deg(deg_to_rad(80.0), 0.0, 45.0)).is_equal(45)
	assert_int(HudMath.barrel_deg(deg_to_rad(-10.0), 0.0, 45.0)).is_equal(0)
	assert_int(HudMath.barrel_deg(deg_to_rad(5.0), 45.0, 0.0)).is_equal(5)   # reversed limits swap


func test_barrel_fill01() -> void:
	assert_float(HudMath.barrel_fill01(0.0, 0.0, 45.0)).is_equal_approx(0.0, 0.0001)
	assert_float(HudMath.barrel_fill01(22.5, 0.0, 45.0)).is_equal_approx(0.5, 0.0001)
	assert_float(HudMath.barrel_fill01(90.0, 0.0, 45.0)).is_equal_approx(1.0, 0.0001)
	assert_float(HudMath.barrel_fill01(5.0, 10.0, 10.0)).is_equal_approx(0.0, 0.0001)
	assert_float(HudMath.barrel_fill01(0.0, -10.0, 30.0)).is_equal_approx(0.25, 0.0001)


func test_data_for_a_barrel_def() -> void:
	var d: BarrelReadoutData = BarrelReadoutData.from_def(_def(10.0, 0.0, 45.0), deg_to_rad(17.2), true)
	assert_bool(d.shown).is_true()
	assert_int(d.deg).is_equal(17)
	assert_int(d.min_deg).is_equal(0)
	assert_int(d.max_deg).is_equal(45)
	assert_float(d.fill01).is_equal_approx(17.2 / 45.0, 0.001)


func test_data_hidden_without_barrel_or_def() -> void:
	assert_bool(BarrelReadoutData.from_def(_def(0.0, 0.0, 0.0), 0.3, true).shown).is_false()
	assert_bool(BarrelReadoutData.from_def(null, 0.3, true).shown).is_false()


func test_data_hidden_when_field_not_received() -> void:
	assert_bool(BarrelReadoutData.from_def(_def(10.0, 0.0, 45.0), 0.3, false).shown).is_false()


func test_view_lines_empty_when_hidden_and_marked_when_shown() -> void:
	var v: BarrelReadoutView = auto_free(load("res://scenes/ui/barrel_readout.tscn").instantiate()) as BarrelReadoutView
	assert_int(v.lines().size()).is_equal(0)
	v.set_data(BarrelReadoutData.from_def(_def(10.0, 0.0, 45.0), deg_to_rad(20.0), true))
	var ls: PackedStringArray = v.lines()
	assert_int(ls.size()).is_equal(3)
	assert_str(ls[0]).contains("20")
	assert_str(ls[1]).is_equal("0")
	assert_str(ls[2]).is_equal("45")
