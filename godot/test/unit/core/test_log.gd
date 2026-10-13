extends GdUnitTestSuite
## Unit tests for core/log.gd. The autoload script is instantiated directly so the
## sink can be captured without touching the global Log.

const LogScript := preload("res://src/core/log.gd")

var _log: Node
var _captured: Array = []


func before_test() -> void:
	_log = LogScript.new()
	_captured = []
	_log.set_sink(func(level: int, tag: StringName, msg: String) -> void: _captured.append([level, tag, msg]))
	_log.set_level(LogScript.Level.INFO)


func after_test() -> void:
	_log.free()


func test_sink_receives_level_tag_and_message() -> void:
	_log.info(&"net", "hello")
	assert_int(_captured.size()).is_equal(1)
	assert_int(_captured[0][0]).is_equal(LogScript.Level.INFO)
	assert_that(_captured[0][1]).is_equal(&"net")
	assert_str(_captured[0][2]).is_equal("hello")


func test_level_filter_drops_lines_below_threshold() -> void:
	_log.debug(&"t", "hidden")
	_log.warn(&"t", "w")
	_log.error(&"t", "e")
	assert_int(_captured.size()).is_equal(2)
	assert_int(_captured[0][0]).is_equal(LogScript.Level.WARN)
	assert_int(_captured[1][0]).is_equal(LogScript.Level.ERROR)


func test_set_level_debug_lets_debug_through() -> void:
	_log.set_level(LogScript.Level.DEBUG)
	_log.debug(&"t", "d")
	assert_int(_captured.size()).is_equal(1)


func test_invalid_sink_restores_printing() -> void:
	_log.set_sink(Callable())
	_log.error(&"t", "printed, not captured")
	assert_int(_captured.size()).is_equal(0)
