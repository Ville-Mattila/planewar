extends GdUnitTestSuite
## AI-23 contract: the opening-book condition grammar of 05 s7.3: `t>=60`, `ore>=X`, `ice>=X`, `have:<def>>=N`,
## `power01<1.1`, `enemy_seen`, `affordable`, `presence`, combined with `&` (and) and `|` (or, lower precedence).

var _idx: Dictionary = {&"outpost": 3, &"dart": 5, &"solar_array": 7}


func _ctx() -> BookContext:
	var c: BookContext = BookContext.new()
	c.size_defs(DefRanges.END)
	return c


func _eval(src: String, c: BookContext) -> bool:
	var cond: BookCondition = BookCondition.compile(src, _idx)
	assert_object(cond).override_failure_message("'%s' must compile" % src).is_not_null()
	return cond.eval(c)


func test_empty_condition_is_true() -> void:
	assert_bool(_eval("", _ctx())).is_true()


func test_time_and_resource_atoms() -> void:
	var c: BookContext = _ctx()
	c.t_s = 150.0
	c.ore = 899.0
	c.ice = 40.0
	assert_bool(_eval("t>=150", c)).is_true()
	assert_bool(_eval("t>=151", c)).is_false()
	assert_bool(_eval("ore>=900", c)).is_false()
	assert_bool(_eval("ore>=899", c)).is_true()
	assert_bool(_eval("ice>=50", c)).is_false()
	assert_bool(_eval("t>150", c)).is_false()
	assert_bool(_eval("t<=150", c)).is_true()
	assert_bool(_eval("t<150", c)).is_false()


func test_power_and_flags() -> void:
	var c: BookContext = _ctx()
	c.power01 = 1.05
	c.enemy_seen = true
	assert_bool(_eval("power01<1.1", c)).is_true()
	assert_bool(_eval("power01<1.0", c)).is_false()
	assert_bool(_eval("enemy_seen", c)).is_true()
	c.enemy_seen = false
	assert_bool(_eval("enemy_seen", c)).is_false()
	c.affordable = true
	assert_bool(_eval("affordable", c)).is_true()
	c.presence = false
	assert_bool(_eval("presence", c)).is_false()
	c.presence = true
	assert_bool(_eval("presence", c)).is_true()


func test_have_counts_finished_not_sites() -> void:
	var c: BookContext = _ctx()
	c.have_done[3] = 0
	c.have_all[3] = 1   # one Outpost site under construction
	assert_bool(_eval("have:outpost>=1", c)).is_false()
	c.have_done[3] = 1
	assert_bool(_eval("have:outpost>=1", c)).is_true()
	assert_bool(_eval("have:dart>=3", c)).is_false()
	c.have_done[5] = 3
	assert_bool(_eval("have:dart>=3", c)).is_true()


func test_skip_if_have_counts_sites_too() -> void:
	var c: BookContext = _ctx()
	c.have_all[7] = 1
	var skip: BookCondition = BookCondition.compile("solar_array>=1", _idx, true)
	assert_object(skip).is_not_null()
	assert_bool(skip.eval(c)).is_true()
	assert_bool(BookCondition.compile("solar_array>=2", _idx, true).eval(c)).is_false()


func test_and_binds_tighter_than_or() -> void:
	var c: BookContext = _ctx()
	c.t_s = 420.0
	c.ore = 0.0
	c.have_done[5] = 0
	# t>=300 & have:dart>=3 | ore>=900  ==  (t>=300 & have:dart>=3) | ore>=900
	assert_bool(_eval("t>=300&have:dart>=3|ore>=900", c)).is_false()
	c.ore = 900.0
	assert_bool(_eval("t>=300&have:dart>=3|ore>=900", c)).is_true()
	c.ore = 0.0
	c.have_done[5] = 3
	assert_bool(_eval("t>=300&have:dart>=3|ore>=900", c)).is_true()
	# the or-operator on its own (the 05 s7.3 contested-field step)
	c.t_s = 100.0
	c.have_done[5] = 0
	assert_bool(_eval("t>=420|ore>=900", c)).is_false()
	c.t_s = 420.0
	assert_bool(_eval("t>=420|ore>=900", c)).is_true()


func test_whitespace_is_ignored() -> void:
	var c: BookContext = _ctx()
	c.t_s = 10.0
	assert_bool(_eval(" t >= 10 & presence ", c)).is_false()
	c.presence = true
	assert_bool(_eval(" t >= 10 & presence ", c)).is_true()


func test_flags_report_what_a_condition_reads() -> void:
	assert_bool(BookCondition.compile("presence", _idx).uses_presence).is_true()
	assert_bool(BookCondition.compile("t>=3|presence", _idx).uses_presence).is_true()
	assert_bool(BookCondition.compile("t>=3", _idx).uses_presence).is_false()
	assert_bool(BookCondition.compile("affordable&t>=3", _idx).uses_affordable).is_true()


func test_bad_conditions_do_not_compile() -> void:
	for bad: String in ["t>=", "t>=x", "ore", "have:ghost>=1", "have:dart", "t>=3&", "|t>=3", "presence>=1", "wat>=3", "t=>3", "t>=3&&t>=4"]:
		assert_object(BookCondition.compile(bad, _idx)).override_failure_message("'%s' must not compile" % bad).is_null()


func _waits(src: String, t_s: float, ore: float) -> bool:
	var c: BookContext = _ctx()
	c.t_s = t_s
	c.ore = ore
	c.affordable = false
	var cond: BookCondition = BookCondition.compile(src, Ai23Kit.content().entity_index)
	return cond.waits_on_clock(c)


func test_waits_on_clock_follows_the_a163_table() -> void:
	assert_bool(_waits("t>=330", 300.0, 400.0)).is_true()
	assert_bool(_waits("t>=420|ore>=900", 300.0, 400.0)).is_true()
	assert_bool(_waits("t>=270&ore>=900", 300.0, 400.0)).is_false()   # the clock is met, the step waits for Ore
	assert_bool(_waits("", 300.0, 400.0)).is_false()                   # absent when: funds short is the book's fault
	assert_bool(_waits("presence", 300.0, 400.0)).is_false()
	assert_bool(_waits("t>=330", 300.0, 1000.0)).is_true()
	assert_bool(_waits("t>=100", 300.0, 400.0)).is_false()             # true already
