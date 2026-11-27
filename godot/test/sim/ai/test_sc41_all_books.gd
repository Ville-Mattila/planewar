extends GdUnitTestSuite
## SC-41 commander_opening_all_books (05 s11.2; AI-23): every book of the book file on the 1v1 slot layout (cradle slots 0
## and 2, 90 degrees apart, O-5): two Normal bots, each on the book under test. Pass per book: the book completes without
## stall (no step skipped for a stall, rejections or an impossible site; only an Expansion pair waiting on the clock may still be pending at the 5:00 hand-over (A-163)), the first
## Outpost stands by 6:00, no REJECTED_LOCKED, no REJECTED_PLACEMENT repeated for one site, and every command the Commander submits is accepted by the sim.

const HZ: int = Ai23Kit.HZ
const TOTAL_S: int = 360


func test_sc41_every_book_completes_and_places_its_first_outpost() -> void:
	for book: OpeningBook in Ai23Kit.books():
		_run_book(book)


func _run_book(book: OpeningBook) -> void:
	var w: SimWorld = Ai23Kit.world(41, &"cradle", true, book.doctrine, book.doctrine)
	var cb: CommanderBrain = Ai23Kit.commander(&"cradle", [book])
	var _d: AiDriver = Ai23Kit.driver(w, cb, [0, 2])
	var outpost: int = Ai23Kit.def(&"outpost")
	var first: Array[int] = [-1, -1]
	var st: EntityStore = w.store()
	for tick: int in TOTAL_S * HZ:
		w.step()
		var _e: Array[SimEvent] = w.drain_events()
		if tick % HZ == 0:
			for s: int in st.structures:
				if st.def_id[s] == outpost and (st.flags[s] & EntityStore.F_BUILDING) == 0 and st.owner[s] != EntityStore.NONE_U8:
					var slot: int = 0 if st.owner[s] == 0 else 1
					if first[slot] < 0:
						first[slot] = tick
	for k: int in 2:
		var slot: int = 0 if k == 0 else 2
		var run: BookRun = cb.run_of(slot)
		assert_object(run).override_failure_message("%s slot %d: no run" % [book.id, slot]).is_not_null()
		assert_bool(run.done).override_failure_message("%s slot %d: book not done" % [book.id, slot]).is_true()
		_assert_no_stall(book, run, slot, cb.host.st_waits, cb._ctx)
		assert_int(first[k]).override_failure_message("%s slot %d: no finished Outpost by 6:00" % [book.id, slot]).is_greater_equal(0)
		assert_int(first[k]).is_less_equal(TOTAL_S * HZ)
	assert_int(cb.host.st_locked).override_failure_message("%s: REJECTED_LOCKED" % book.id).is_equal(0)
	assert_int(cb.host.st_repeat_rejects).override_failure_message("%s: a site was rejected twice" % book.id).is_equal(0)
	assert_int(cb.host.st_cmds - cb.host.st_accepted).override_failure_message("%s: %d of %d commands refused (by Build.Reject %s, by code %s)" % [book.id, cb.host.st_cmds - cb.host.st_accepted, cb.host.st_cmds, str(cb.host.st_by_reject), str(cb.host.st_by_code)]).is_equal(0)
	assert_int(cb.host.st_placement_rejects).override_failure_message("%s: placement rejects" % book.id).is_equal(0)
	assert_float(float(cb.host.st_accepted) / float(maxi(cb.host.st_cmds, 1))).override_failure_message("%s: accepted %d of %d" % [book.id, cb.host.st_accepted, cb.host.st_cmds]).is_greater_equal(0.7)


# "Completes without stall" (R0 B.33 A-163): `run.done` alone is set at the 5:00 hand-over, so read the outcomes. No step is
# skipped for a stall, rejections or an impossible site (only `skip_if_have`); a step still PENDING at the hand-over passes
# only behind a cursor that is the `order move` of an Expansion pair waiting on the clock.
func _assert_no_stall(book: OpeningBook, run: BookRun, slot: int, cb_waits: PackedInt32Array, ctx: BookContext) -> void:
	var clock: bool = run.cursor < book.n_steps and expansion_waits_on_clock(book, run.cursor, ctx)
	for i: int in book.n_steps:
		var o: int = run.outcome[i]
		var ok: bool = o == BookRun.DONE or o == BookRun.SKIPPED_HAVE or (o == BookRun.PENDING and clock and i >= run.cursor)
		assert_bool(ok).override_failure_message("%s slot %d step %d (%s): outcome %d, outcomes %s" % [book.id, slot, i, book.when_of(i).src, o, str(run.outcome) + " waits " + str(cb_waits)]).is_true()


## Step `i` is the `order move` of an Expansion pair (a `build outpost` to the same site follows) and waits on the clock.
static func expansion_waits_on_clock(book: OpeningBook, i: int, ctx: BookContext) -> bool:
	if book.kind_of(i) != OpeningBook.Do.ORDER or book.order_kind_of(i) != OrderSpec.Kind.MOVE or i + 1 >= book.n_steps:
		return false
	var nxt: SiteToken = book.token_of(i + 1)
	if book.kind_of(i + 1) != OpeningBook.Do.BUILD or nxt == null or book.token_of(i) == null or nxt.src != book.token_of(i).src:
		return false
	return book.when_of(i).waits_on_clock(ctx)
