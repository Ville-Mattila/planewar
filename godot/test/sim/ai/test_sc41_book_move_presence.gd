extends GdUnitTestSuite
## SC-41 addendum (AI-51, AI-24 review F1): on the SC-41 world (cradle, slots 0 and 2, seed 41, the shipped books) a Dart
## ordered by a book `order move` to `outpost_site:home_trap` reports presence on >= 95 % of the Commander's thinks from its
## arrival at the order point to its RTB (the head leaves MOVE). Before AI-51 the nominal orbit lay outside the reach.

const HZ: int = Ai23Kit.HZ
const TOTAL_S: int = 330
const SHARE: float = 0.95


func test_a_book_move_escort_stays_present_from_arrival_to_rtb() -> void:
	var book: OpeningBook = null
	for b: OpeningBook in Ai23Kit.shipped_books():
		if b.id == &"vanguard_standard":
			book = b
	assert_object(book).is_not_null()
	var w: SimWorld = Ai23Kit.world(41, &"cradle", true, book.doctrine, book.doctrine)
	var cb: CommanderBrain = Ai23Kit.commander(&"cradle", [book])
	var _d: AiDriver = Ai23Kit.driver(w, cb, [0])   # one bot: the host is bound to slot 0 on every think
	var outpost: int = Ai23Kit.def(&"outpost")
	var tok: SiteToken = null
	for i: int in book.n_steps:
		if book.kind_of(i) == OpeningBook.Do.BUILD and book.def_of(i) == outpost:
			tok = book.token_of(i)
			break
	assert_object(tok).is_not_null()
	var thinks: int = 0
	var present: int = 0
	var arrived: bool = false
	var mover: int = 0
	var last_thinks: int = 0
	var view: SimView = w.view()
	var st: EntityStore = w.store()
	var dart: int = Ai23Kit.def(&"dart")
	var site: Vector3 = Vector3.ZERO
	for tick: int in TOTAL_S * HZ:
		w.step()
		var _e: Array[SimEvent] = w.drain_events()
		if site == Vector3.ZERO and cb.run_of(0) != null and cb.run_of(0).cursor > 0:
			site = cb.host.planner.anchor(tok, 0, 0)
		if site == Vector3.ZERO or cb.st_thinks == last_thinks:
			continue
		last_thinks = cb.st_thinks
		if mover == 0:
			for s: int in st.ships:
				if st.def_id[s] == dart and st.owner[s] == 0:
					var h: OrderSpec = view.order_head(st.id_of(s))
					if h != null and h.kind == OrderSpec.Kind.MOVE and h.issuer == 0 and Guidance.ground_dist(st.pos[s], h.point) <= 150.0:
						mover = st.id_of(s)   # arrived (the Dart's arrival radius): the window opens
		if mover == 0:
			continue
		var mh: OrderSpec = view.order_head(mover) if view.alive(mover) else null
		if mh == null or mh.kind != OrderSpec.Kind.MOVE:
			break   # the head left MOVE (RTB) or the Dart is gone: the window is over
		arrived = true
		thinks += 1
		if cb.host.presence(tok, outpost):
			present += 1
	assert_bool(arrived).override_failure_message("no Dart reached the book move's point").is_true()
	assert_int(thinks).is_greater(5)
	assert_float(float(present) / float(thinks)).override_failure_message("presence on %d of %d thinks" % [present, thinks]).is_greater_equal(SHARE)
