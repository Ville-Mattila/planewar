extends GdUnitTestSuite
## Unit tests for ui/i18n/fmt.gd (UX-29; docs/06 s11): en and fi number, distance and time formats.

const NNBSP: String = " "


func test_integer_en_fi() -> void:
	assert_str(Fmt.integer(12400, "en")).is_equal("12,400")
	assert_str(Fmt.integer(12400, "fi")).is_equal("12" + NNBSP + "400")
	assert_str(Fmt.integer(0, "en")).is_equal("0")
	assert_str(Fmt.integer(999, "fi")).is_equal("999")
	assert_str(Fmt.integer(1000, "en")).is_equal("1,000")
	assert_str(Fmt.integer(-1234567, "en")).is_equal("-1,234,567")
	assert_str(Fmt.integer(-1234567, "fi")).is_equal("-1" + NNBSP + "234" + NNBSP + "567")


func test_decimal_en_fi() -> void:
	assert_str(Fmt.decimal(92.5, 1, "en")).is_equal("92.5")
	assert_str(Fmt.decimal(92.5, 1, "fi")).is_equal("92,5")
	assert_str(Fmt.decimal(1234.05, 2, "fi")).is_equal("1" + NNBSP + "234,05")
	assert_str(Fmt.decimal(0.04, 1, "en")).is_equal("0.0")
	assert_str(Fmt.decimal(-0.04, 1, "en")).is_equal("0.0")
	assert_str(Fmt.decimal(-3.25, 1, "en")).is_equal("-3.3")
	assert_str(Fmt.decimal(7.0, 0, "fi")).is_equal("7")


func test_distance() -> void:
	assert_str(Fmt.distance_m(1200.0, "en")).is_equal("1.2 km")
	assert_str(Fmt.distance_m(1200.0, "fi")).is_equal("1,2 km")
	assert_str(Fmt.distance_m(850.4, "en")).is_equal("850 m")
	assert_str(Fmt.distance_m(1000.0, "en")).is_equal("1.0 km")
	assert_str(Fmt.distance_m(12400.0, "fi")).is_equal("12,4 km")


func test_clock_is_24_hour_for_every_locale() -> void:
	assert_str(Fmt.clock_24h(0)).is_equal("00:00")
	assert_str(Fmt.clock_24h(13 * 3600 + 5 * 60)).is_equal("13:05")
	assert_str(Fmt.clock_24h(86400 + 60)).is_equal("00:01")
	assert_str(Fmt.clock_24h(-60)).is_equal("23:59")


func test_duration() -> void:
	assert_str(Fmt.duration(65)).is_equal("1:05")
	assert_str(Fmt.duration(3725)).is_equal("1:02:05")
	assert_str(Fmt.duration(-4)).is_equal("0:00")


func test_normalize_maps_os_locale_names() -> void:
	assert_str(Fmt.normalize("fi_FI")).is_equal("fi")
	assert_str(Fmt.normalize("FI")).is_equal("fi")
	assert_str(Fmt.normalize("de_DE")).is_equal("en")
	assert_str(Fmt.normalize("")).is_equal("en")
	assert_str(Fmt.normalize("f")).is_equal("en")
