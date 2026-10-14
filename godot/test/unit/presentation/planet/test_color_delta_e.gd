extends GdUnitTestSuite
## ColorDeltaE (golden tooling, ART-14): CIEDE2000 against Sharma, Wu, Dalal (2005) reference pairs, plus the
## biome palette itself: the 07 s2.1 ramp stops (tools/moonbake/ramp.py output) are within dE00 <= 6 of the hex.


func test_sharma_reference_pairs() -> void:
	assert_float(ColorDeltaE.de00_lab(Vector3(50.0, 2.6772, -79.7751), Vector3(50.0, 0.0, -82.7485))).is_equal_approx(2.0425, 0.0001)
	assert_float(ColorDeltaE.de00_lab(Vector3(50.0, 3.1571, -77.2803), Vector3(50.0, 0.0, -82.7485))).is_equal_approx(2.8615, 0.0001)
	assert_float(ColorDeltaE.de00_lab(Vector3(50.0, 2.5, 0.0), Vector3(73.0, 25.0, -18.0))).is_equal_approx(27.1492, 0.0001)
	assert_float(ColorDeltaE.de00_lab(Vector3(50.0, 2.5, 0.0), Vector3(50.0, 2.5, 0.0))).is_equal(0.0)


func test_identical_srgb_is_zero_and_white_black_is_large() -> void:
	assert_float(ColorDeltaE.de00(Color("#404552"), Color("#404552"))).is_equal(0.0)
	assert_float(ColorDeltaE.de00(Color.WHITE, Color.BLACK)).is_greater(90.0)


func test_ramp_texture_stops_match_the_07_hex() -> void:
	var img: Image = (load(MoonTerrain.RAMP_PATH) as Texture2D).get_image()
	var stops: Array = [
		[0, "#30343F", "#404552", "#51576A"], [1, "#7A7770", "#959189", "#B1ACA1"], [2, "#2A2C34", "#353840", "#43474F"],
		[3, "#A8A396", "#C0BBAE", "#D6D1C4"], [4, "#34485E", "#5B7C9E", "#B5D8EC"], [5, "#6B5B3F", "#8D7648", "#AA9158"],
		[6, "#B9B5AA", "#D0CCC0", "#E3DFD2"], [7, "#22242B", "#2C2F37", "#373B44"]]
	for s: Array in stops:
		var row: int = s[0]
		assert_float(ColorDeltaE.de00(img.get_pixel(0, row), Color(s[1] as String))).is_less(1.0)
		assert_float(ColorDeltaE.de00(img.get_pixel(31, row), Color(s[2] as String))).is_less(6.0)
		assert_float(ColorDeltaE.de00(img.get_pixel(63, row), Color(s[3] as String))).is_less(1.0)
