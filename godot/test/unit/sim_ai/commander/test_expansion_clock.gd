extends GdUnitTestSuite
## AI-50 (R0 B.33 A-163): SC-41's verdict helper `Ai23Kit.expansion_waits_on_clock` on small compiled books: only the
## `order move` of an Expansion pair that waits on the clock may be left pending at the hand-over.


func _book(steps: Array) -> OpeningBook:
	var errs: Array[String] = []
	var b: OpeningBook = OpeningBook.compile({"id": "t_book", "doctrine": "vanguard", "steps": steps}, Ai23Kit.content(), errs)
	assert_array(errs).is_empty()
	return b


func _pair(move_when: String) -> OpeningBook:
	return _book([
		{"do": "order", "kind": "move", "unit": "dart|scout", "to": "contested_field", "when": move_when},
		{"do": "build", "def": "outpost", "near": "contested_field", "when": "presence"}])


func _ctx(t_s: float, ore: float) -> BookContext:
	var c: BookContext = BookContext.new()
	c.size_defs(DefRanges.END)
	c.t_s = t_s
	c.ore = ore
	return c


func test_the_pairs_move_waiting_on_the_clock_passes() -> void:
	assert_bool(Ai23Kit.expansion_waits_on_clock(_pair("t>=420|ore>=900"), 0, _ctx(300.0, 400.0))).is_true()
	assert_bool(Ai23Kit.expansion_waits_on_clock(_pair("t>=330"), 0, _ctx(300.0, 400.0))).is_true()


func test_the_same_move_with_ore_met_fails() -> void:
	# its own `when` is true: the step is stuck on something else (no free unit), not on the clock; per-slot Ore matters
	assert_bool(Ai23Kit.expansion_waits_on_clock(_pair("t>=420|ore>=900"), 0, _ctx(300.0, 950.0))).is_false()
	assert_bool(Ai23Kit.expansion_waits_on_clock(_pair("t>=270&ore>=900"), 0, _ctx(300.0, 400.0))).is_false()


func test_a_build_outpost_left_pending_on_presence_fails() -> void:
	assert_bool(Ai23Kit.expansion_waits_on_clock(_pair("t>=100"), 1, _ctx(300.0, 400.0))).is_false()


func test_an_order_move_without_a_build_outpost_behind_it_fails() -> void:
	var b: OpeningBook = _book([
		{"do": "order", "kind": "move", "unit": "dart", "to": "contested_field", "when": "t>=420"},
		{"do": "produce", "def": "dart", "n": 1}])
	assert_bool(Ai23Kit.expansion_waits_on_clock(b, 0, _ctx(300.0, 400.0))).is_false()


func test_an_absent_when_with_funds_short_fails() -> void:
	assert_bool(Ai23Kit.expansion_waits_on_clock(_pair(""), 0, _ctx(300.0, 0.0))).is_false()
