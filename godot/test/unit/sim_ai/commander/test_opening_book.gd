extends GdUnitTestSuite
## AI-23 contract: `OpeningBook` (05 s7.3): compile a `build_orders.json` entry, then run it in order against a host: a
## step waits for its `when`, `skip_if_have` skips, REJECTED_PLACEMENT makes the planner try the next candidate and three
## rejections skip the step, a step that is due but cannot complete for `stall_s` is skipped, an Outpost step waits for
## presence, the book hands over to the reactive planner after the last step or at `book_end_s`.

const HZ: int = 30


class FakeHost extends BookHost:
	var calls: Array[String] = []
	var answers: Dictionary = {}   # "build:solar_array" -> Array[int] of outcomes, consumed front first; default DONE
	var near: bool = false
	var funds: bool = true
	var asked: int = 0
	var ks: Array[int] = []

	func _next(key: String) -> int:
		calls.append(key)
		var q: Array = answers.get(key, [])
		return int(q.pop_front()) if not q.is_empty() else OpeningBook.Out.DONE

	func presence(_tok: SiteToken, _def_id: int) -> bool:
		return near

	func affordable(_kind: int, _def_id: int, _n: int) -> bool:
		asked += 1
		return funds

	func build(def_id: int, _tok: SiteToken, k: int, _issued: int) -> int:
		ks.append(k)
		next_k = k + 3
		return _next("build:%d" % def_id)

	func produce(def_id: int, count: int) -> int:
		return _next("produce:%d:%d" % [def_id, count])

	func replenish(def_id: int, n: int) -> int:
		return _next("replenish:%d:%d" % [def_id, n])

	func order(kind: int, _classes: PackedInt32Array, tok: SiteToken) -> int:
		return _next("order:%d:%s" % [kind, tok.src])

	func raid(target: StringName, with: StringName) -> int:
		return _next("raid:%s:%s" % [target, with])


func _def(id: StringName) -> int:
	return Ai23Kit.def(id)


func _book(steps: Array, extra: Dictionary = {}) -> OpeningBook:
	var e: Dictionary = {"id": "t_book", "doctrine": "vanguard", "steps": steps}
	e.merge(extra, true)
	var errs: Array[String] = []
	var b: OpeningBook = OpeningBook.compile(e, Ai23Kit.content(), errs)
	assert_array(errs).is_empty()
	assert_object(b).is_not_null()
	return b


func _ctx(t_s: float = 0.0) -> BookContext:
	var c: BookContext = BookContext.new()
	c.size_defs(DefRanges.END)
	c.t_s = t_s
	c.affordable = true
	return c


func _think(b: OpeningBook, r: BookRun, c: BookContext, h: FakeHost, tick: int, budget: int = 8) -> int:
	c.t_s = float(tick) / float(HZ)
	return b.think(r, c, h, tick, HZ, Ai23Kit.params(), budget)


func test_shipped_fixture_books_compile() -> void:
	var books: Array[OpeningBook] = Ai23Kit.books()
	assert_int(books.size()).is_equal(6)
	var doctrines: Dictionary = {}
	for b: OpeningBook in books:
		doctrines[b.doctrine] = true
		assert_int(b.n_steps).is_greater(5)
	assert_int(doctrines.size()).is_equal(3)


func test_vanguard_standard_steps_are_read() -> void:
	var b: OpeningBook = Ai23Kit.book(&"vanguard_standard")
	assert_int(b.n_steps).is_equal(14)
	assert_int(b.kind_of(0)).is_equal(OpeningBook.Do.BUILD)
	assert_int(b.def_of(0)).is_equal(_def(&"solar_array"))
	assert_int(b.kind_of(1)).is_equal(OpeningBook.Do.PRODUCE)
	assert_int(b.kind_of(3)).is_equal(OpeningBook.Do.ORDER)
	assert_int(b.order_kind_of(3)).is_equal(OrderSpec.Kind.MOVE)
	assert_int(b.classes_of(3).size()).is_equal(2)
	assert_str(b.token_of(4).src).is_equal("outpost_site:home_trap")
	assert_bool(b.when_of(4).uses_presence).is_true()
	assert_int(b.kind_of(11)).is_equal(OpeningBook.Do.SET_REPLENISH)
	assert_int(b.kind_of(12)).is_equal(OpeningBook.Do.ORDER)   # the dead raid step is gone (A-163 3c)
	assert_float(b.weight).is_equal(2.0)


func test_compile_refuses_bad_entries() -> void:
	var bad: Array = [
		{"id": "x", "steps": [{"do": "build", "def": "ghost", "near": "core"}]},
		{"id": "x", "steps": [{"do": "dance"}]},
		{"id": "x", "steps": [{"do": "build", "def": "solar_array", "near": "nowhere"}]},
		{"id": "x", "steps": [{"do": "build", "def": "solar_array", "near": "core", "when": "t>="}]},
		{"id": "x", "steps": [{"do": "produce", "def": "dart", "n": 0}]},
		{"id": "x", "steps": [{"do": "order", "kind": "fly", "unit": "dart", "to": "core"}]},
		{"id": "x", "steps": [{"do": "order", "kind": "move", "unit": "ghost", "to": "core"}]},
		{"id": "x", "steps": [{"do": "build", "def": "storage_silo", "near": "core"}]},
		{"steps": []},
		{"id": "x", "steps": [{"do": "order", "kind": "move", "unit": "dart", "to": "nowhere"},
			{"do": "build", "def": "outpost", "near": "nowhere", "when": "presence"}]},
		{"id": "x", "steps": [{"do": "build", "def": "outpost", "near": "nowhere", "when": "presence"}]},
	]
	for e: Variant in bad:
		var errs: Array[String] = []
		assert_object(OpeningBook.compile(e, Ai23Kit.content(), errs)).override_failure_message(str(e)).is_null()
		assert_array(errs).is_not_empty()


func test_every_build_outpost_needs_a_move_and_presence() -> void:
	var no_when: Array = [{"do": "order", "kind": "move", "unit": "dart", "to": "contested_field", "when": "t>=10"},
		{"do": "build", "def": "outpost", "near": "contested_field"}]
	var no_move: Array = [{"do": "build", "def": "outpost", "near": "contested_field", "when": "presence"}]
	var other_site: Array = [{"do": "order", "kind": "move", "unit": "dart", "to": "contested_field"},
		{"do": "build", "def": "outpost", "near": "outpost_site:home_trap", "when": "presence"}]
	var good: Array = [{"do": "order", "kind": "move", "unit": "dart", "to": "contested_field"},
		{"do": "build", "def": "outpost", "near": "contested_field", "when": "t>=5&presence"}]
	for steps: Array in [no_when, no_move, other_site]:
		var errs: Array[String] = []
		assert_object(OpeningBook.compile({"id": "o", "steps": steps}, Ai23Kit.content(), errs)).is_null()
		assert_bool(" ".join(errs).contains("presence") or " ".join(errs).contains("order move")).is_true()
	var errs2: Array[String] = []
	assert_object(OpeningBook.compile({"id": "o", "steps": good}, Ai23Kit.content(), errs2)).is_not_null()


func test_steps_run_in_order_and_stop_at_a_wait() -> void:
	var b: OpeningBook = _book([
		{"do": "build", "def": "solar_array", "near": "core"},
		{"do": "produce", "def": "dart", "n": 1},
		{"do": "produce", "def": "harvester", "n": 1}])
	var r: BookRun = BookRun.new(b)
	var h: FakeHost = FakeHost.new()
	h.answers["produce:%d:1" % _def(&"dart")] = [OpeningBook.Out.WAIT, OpeningBook.Out.DONE]
	var n: int = _think(b, r, _ctx(), h, 0)
	assert_int(n).is_equal(1)   # the solar array went; the Dart waits; the Harvester behind it does not jump the queue
	assert_int(r.cursor).is_equal(1)
	assert_int(h.calls.size()).is_equal(2)
	h.calls.clear()
	var _n2: int = _think(b, r, _ctx(), h, 30)
	assert_int(r.cursor).is_equal(3)
	assert_bool(r.done).is_true()
	assert_array(h.calls).has_size(2)


func test_budget_caps_the_commands_of_one_think() -> void:
	var b: OpeningBook = _book([
		{"do": "produce", "def": "dart", "n": 1}, {"do": "produce", "def": "dart", "n": 1},
		{"do": "produce", "def": "dart", "n": 1}, {"do": "produce", "def": "dart", "n": 1}])
	var r: BookRun = BookRun.new(b)
	var h: FakeHost = FakeHost.new()
	assert_int(_think(b, r, _ctx(), h, 0, 2)).is_equal(2)
	assert_int(r.cursor).is_equal(2)
	assert_int(_think(b, r, _ctx(), h, 30, 2)).is_equal(2)
	assert_bool(r.done).is_true()


func test_when_blocks_until_true() -> void:
	var b: OpeningBook = _book([
		{"do": "produce", "def": "dart", "n": 1, "when": "t>=10"},
		{"do": "produce", "def": "harvester", "n": 1}])
	var r: BookRun = BookRun.new(b)
	var h: FakeHost = FakeHost.new()
	assert_int(_think(b, r, _ctx(), h, 0)).is_equal(0)
	assert_int(_think(b, r, _ctx(), h, 9 * HZ)).is_equal(0)
	assert_array(h.calls).is_empty()
	assert_int(_think(b, r, _ctx(), h, 10 * HZ)).is_equal(2)


func test_skip_if_have_skips_without_calling_the_host() -> void:
	var b: OpeningBook = _book([
		{"do": "build", "def": "solar_array", "near": "core", "skip_if_have": "solar_array>=1"},
		{"do": "produce", "def": "dart", "n": 1}])
	var r: BookRun = BookRun.new(b)
	var h: FakeHost = FakeHost.new()
	var c: BookContext = _ctx()
	c.have_all[_def(&"solar_array")] = 1   # a site counts
	var _n: int = _think(b, r, c, h, 0)
	assert_int(r.outcome[0]).is_equal(BookRun.SKIPPED_HAVE)
	assert_int(r.outcome[1]).is_equal(BookRun.DONE)
	assert_int(h.calls.size()).is_equal(1)


func test_a_rejected_placement_tries_the_next_candidate_and_three_skip() -> void:
	var b: OpeningBook = _book([
		{"do": "build", "def": "solar_array", "near": "core"}, {"do": "produce", "def": "dart", "n": 1}])
	var r: BookRun = BookRun.new(b)
	var h: FakeHost = FakeHost.new()
	var key: String = "build:%d" % _def(&"solar_array")
	h.answers[key] = [OpeningBook.Out.REJECT, OpeningBook.Out.REJECT, OpeningBook.Out.REJECT]
	assert_int(_think(b, r, _ctx(), h, 0)).is_equal(0)
	assert_int(_think(b, r, _ctx(), h, 30)).is_equal(0)
	assert_int(r.cursor).is_equal(0)
	assert_int(_think(b, r, _ctx(), h, 60)).is_equal(1)   # the third rejection skips the step; the Dart behind it runs at once
	assert_array(h.ks).is_equal([0, 3, 6])   # each retry starts at the host's next_k
	assert_int(r.outcome[0]).is_equal(BookRun.SKIPPED_REJECTS)
	assert_bool(r.done).is_true()


func test_two_rejections_then_success_do_not_skip() -> void:
	var b: OpeningBook = _book([{"do": "build", "def": "solar_array", "near": "core"}])
	var r: BookRun = BookRun.new(b)
	var h: FakeHost = FakeHost.new()
	h.answers["build:%d" % _def(&"solar_array")] = [OpeningBook.Out.REJECT, OpeningBook.Out.REJECT, OpeningBook.Out.DONE]
	for i: int in 3:
		var _n: int = _think(b, r, _ctx(), h, i * 30)
	assert_int(r.outcome[0]).is_equal(BookRun.DONE)


func test_an_unresolvable_step_is_skipped_at_once() -> void:
	var b: OpeningBook = _book([{"do": "build", "def": "refinery", "near": "ore_field:home_2"}, {"do": "produce", "def": "dart", "n": 1}])
	var r: BookRun = BookRun.new(b)
	var h: FakeHost = FakeHost.new()
	h.answers["build:%d" % _def(&"refinery")] = [OpeningBook.Out.FAIL]
	var n: int = _think(b, r, _ctx(), h, 0)
	assert_int(r.outcome[0]).is_equal(BookRun.SKIPPED_FAIL)
	assert_int(n).is_equal(1)   # the Dart behind it ran in the same think


func test_produce_asks_for_n_units_in_one_command() -> void:
	var b: OpeningBook = _book([{"do": "produce", "def": "dart", "n": 3}, {"do": "set_replenish", "def": "dart", "n": 4}])
	var r: BookRun = BookRun.new(b)
	var h: FakeHost = FakeHost.new()
	var _n: int = _think(b, r, _ctx(), h, 0)
	assert_array(h.calls).is_equal(["produce:%d:3" % _def(&"dart"), "replenish:%d:4" % _def(&"dart")])


func test_a_step_that_cannot_complete_is_skipped_after_stall_s() -> void:
	var b: OpeningBook = _book([{"do": "produce", "def": "dart", "n": 1}, {"do": "produce", "def": "harvester", "n": 1}])
	var r: BookRun = BookRun.new(b)
	var h: FakeHost = FakeHost.new()
	var waits: Array = []
	for i: int in 60:
		waits.append(OpeningBook.Out.WAIT)
	h.answers["produce:%d:1" % _def(&"dart")] = waits
	var stall: int = int(Ai23Kit.params().stall_s) * HZ
	var _a: int = _think(b, r, _ctx(), h, 0)
	var _b: int = _think(b, r, _ctx(), h, stall - HZ)
	assert_int(r.cursor).is_equal(0)
	var _c: int = _think(b, r, _ctx(), h, stall + HZ)
	assert_int(r.outcome[0]).is_equal(BookRun.SKIPPED_STALL)


func test_the_stall_clock_starts_when_the_condition_holds() -> void:
	var b: OpeningBook = _book([{"do": "produce", "def": "dart", "n": 1, "when": "t>=100"}])
	var r: BookRun = BookRun.new(b)
	var h: FakeHost = FakeHost.new()
	h.answers["produce:%d:1" % _def(&"dart")] = [OpeningBook.Out.WAIT, OpeningBook.Out.WAIT, OpeningBook.Out.WAIT]
	var _a: int = _think(b, r, _ctx(), h, 0)
	var _b: int = _think(b, r, _ctx(), h, 99 * HZ)   # 99 s on `when` are not a stall (stall_s is 90)
	assert_int(r.cursor).is_equal(0)
	var _c: int = _think(b, r, _ctx(), h, 100 * HZ)   # due now, WAIT: the stall clock starts
	assert_int(r.cursor).is_equal(0)
	var _d: int = _think(b, r, _ctx(), h, 100 * HZ + int(Ai23Kit.params().stall_s) * HZ + HZ)
	assert_int(r.outcome[0]).is_equal(BookRun.SKIPPED_STALL)


func test_an_outpost_waits_for_presence_and_reissues_the_move() -> void:
	var b: OpeningBook = _book([
		{"do": "order", "kind": "move", "unit": "dart|scout", "to": "contested_field", "when": "t>=10"},
		{"do": "build", "def": "outpost", "near": "contested_field", "when": "presence"}])
	var r: BookRun = BookRun.new(b)
	var h: FakeHost = FakeHost.new()
	var _a: int = _think(b, r, _ctx(), h, 10 * HZ)
	assert_int(r.cursor).is_equal(1)
	assert_int(h.calls.size()).is_equal(1)
	var _b: int = _think(b, r, _ctx(), h, 20 * HZ)   # still not there: wait quietly
	assert_int(h.calls.size()).is_equal(1)
	var retry: int = int(Ai23Kit.params().presence_retry_s) * HZ
	var _c: int = _think(b, r, _ctx(), h, 10 * HZ + retry + HZ)   # the unit died or was taken: order again
	assert_int(h.calls.size()).is_equal(2)
	assert_str(h.calls[1]).starts_with("order:")
	h.near = true
	var _d: int = _think(b, r, _ctx(), h, 10 * HZ + retry + 2 * HZ)
	assert_bool(r.done).is_true()
	assert_str(h.calls[2]).starts_with("build:")


func test_raid_is_handed_to_the_host() -> void:
	var b: OpeningBook = _book([{"do": "raid", "target": "harvester_line", "with": "dart:3", "when": "t>=5"}])
	var r: BookRun = BookRun.new(b)
	var h: FakeHost = FakeHost.new()
	var _n: int = _think(b, r, _ctx(), h, 5 * HZ)
	assert_array(h.calls).is_equal(["raid:harvester_line:dart:3"])


func test_the_book_hands_over_at_book_end_s() -> void:
	var b: OpeningBook = _book([{"do": "produce", "def": "dart", "n": 1, "when": "t>=1000"}])
	var r: BookRun = BookRun.new(b)
	var h: FakeHost = FakeHost.new()
	var _a: int = _think(b, r, _ctx(), h, 100 * HZ)
	assert_bool(r.done).is_false()
	var _b: int = _think(b, r, _ctx(), h, int(Ai23Kit.params().book_end_s) * HZ)
	assert_bool(r.done).is_true()
	assert_int(r.outcome[0]).is_equal(BookRun.PENDING)   # never executed: handed over
	assert_int(_think(b, r, _ctx(), h, 400 * HZ)).is_equal(0)


func test_run_state_round_trips_and_resumes_identically() -> void:
	var b: OpeningBook = Ai23Kit.book(&"vanguard_standard")
	var r: BookRun = BookRun.new(b)
	var h: FakeHost = FakeHost.new()
	h.answers["build:%d" % _def(&"autocannon_turret")] = [OpeningBook.Out.REJECT, OpeningBook.Out.WAIT]
	for i: int in 4:
		var _n: int = _think(b, r, _ctx(), h, i * 30, 2)
	var bytes: PackedByteArray = r.serialize()
	var r2: BookRun = BookRun.new(b)
	assert_bool(r2.deserialize(bytes)).is_true()
	assert_bool(r2.serialize() == bytes).is_true()
	var h2: FakeHost = FakeHost.new()
	h2.answers = h.answers.duplicate(true)
	h.calls.clear()
	for i: int in range(4, 12):
		var _x: int = _think(b, r, _ctx(), h, i * 30, 2)
		var _y: int = _think(b, r2, _ctx(), h2, i * 30, 2)
	assert_array(h2.calls).is_equal(h.calls)
	assert_bool(r2.serialize() == r.serialize()).is_true()


func test_run_refuses_bytes_of_another_book() -> void:
	var r: BookRun = BookRun.new(Ai23Kit.book(&"vanguard_standard"))
	var other: BookRun = BookRun.new(Ai23Kit.book(&"vanguard_rush"))
	assert_bool(other.deserialize(r.serialize())).is_false()
	assert_bool(other.deserialize(PackedByteArray())).is_false()


func test_a_funds_wait_is_never_a_stall_and_blocks_the_steps_behind() -> void:
	var b: OpeningBook = _book([{"do": "produce", "def": "dart", "n": 1}, {"do": "produce", "def": "harvester", "n": 1}])
	var r: BookRun = BookRun.new(b)
	var h: FakeHost = FakeHost.new()
	h.funds = false
	var stall: int = int(Ai23Kit.params().stall_s) * HZ
	for k: int in 3:
		var _a: int = _think(b, r, _ctx(), h, k * stall)   # up to 2 x stall_s of waiting for funds
	assert_int(r.cursor).is_equal(0)
	assert_int(r.outcome[0]).is_equal(BookRun.PENDING)
	assert_array(h.calls).is_empty()   # the Harvester behind did not jump the queue
	h.funds = true
	var _n: int = _think(b, r, _ctx(), h, 2 * stall + HZ)
	assert_bool(r.done).is_true()
	assert_int(r.outcome[0]).is_equal(BookRun.DONE)


func test_an_explicit_when_is_also_affordable() -> void:
	var b: OpeningBook = _book([{"do": "produce", "def": "dart", "n": 1, "when": "t>=10"}])
	var r: BookRun = BookRun.new(b)
	var h: FakeHost = FakeHost.new()
	h.funds = false
	assert_int(_think(b, r, _ctx(), h, 20 * HZ)).is_equal(0)
	h.funds = true
	assert_int(_think(b, r, _ctx(), h, 21 * HZ)).is_equal(1)


func test_a_step_without_a_cost_never_asks_for_funds() -> void:
	var b: OpeningBook = _book([
		{"do": "order", "kind": "move", "unit": "dart", "to": "contested_field"},
		{"do": "set_replenish", "def": "dart", "n": 2},
		{"do": "raid", "target": "harvester_line", "with": "dart:3"}])
	var r: BookRun = BookRun.new(b)
	var h: FakeHost = FakeHost.new()
	h.funds = false
	assert_int(_think(b, r, _ctx(), h, 0)).is_equal(3)
	assert_int(h.asked).is_equal(0)


func test_a_due_affordable_step_blocked_by_a_prerequisite_still_stalls() -> void:
	var b: OpeningBook = _book([{"do": "produce", "def": "dart", "n": 1}])
	var r: BookRun = BookRun.new(b)
	var h: FakeHost = FakeHost.new()
	var waits: Array = []
	for i: int in 60:
		waits.append(OpeningBook.Out.WAIT)
	h.answers["produce:%d:1" % _def(&"dart")] = waits
	var stall: int = int(Ai23Kit.params().stall_s) * HZ
	var _a: int = _think(b, r, _ctx(), h, 0)
	var _b: int = _think(b, r, _ctx(), h, stall + HZ)
	assert_int(r.outcome[0]).is_equal(BookRun.SKIPPED_STALL)


func test_the_presence_retry_stops_while_presence_holds_and_funds_are_short() -> void:
	var b: OpeningBook = _book([
		{"do": "order", "kind": "move", "unit": "dart|scout", "to": "contested_field"},
		{"do": "build", "def": "outpost", "near": "contested_field", "when": "presence"}])
	var r: BookRun = BookRun.new(b)
	var h: FakeHost = FakeHost.new()
	h.funds = false
	h.near = true
	var retry: int = int(Ai23Kit.params().presence_retry_s) * HZ
	var _a: int = _think(b, r, _ctx(), h, 0)
	var _b: int = _think(b, r, _ctx(), h, retry + HZ)
	var _c: int = _think(b, r, _ctx(), h, 3 * retry)
	assert_int(h.calls.size()).is_equal(1)   # the move went once; no re-send while the unit is in place
	assert_int(r.cursor).is_equal(1)
