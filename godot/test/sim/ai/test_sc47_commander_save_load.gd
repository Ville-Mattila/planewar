extends GdUnitTestSuite
## SC-47 save_load_ai_state, the Commander half (AI-23, on AI-33's pin): a Normal bot mid-opening-book (cursor inside the
## book, a step rejected once, the book chosen from the AI RNG) is saved through SimWorld.serialize() (S4: world + hook
## bytes, `AiDriver` FORMAT 3 carries the Commander section) and restored into a world whose driver is configured as a
## session does (brains, class table, intel, books, before deserialize). Pass: the driver bytes round-trip, and the first
## 20 s after the load match a continuous run in the book cursor and outcomes every tick and in the full S4 bytes every
## second tick. Saved at 0:40 (cursor mid-book) and at 2:30 (orders flown, Outpost site pending).

const HZ: int = Ai23Kit.HZ
const AFTER_TICKS: int = 20 * HZ


func test_sc47_commander_state_round_trips() -> void:
	for save_s: int in [40, 150]:
		var w: SimWorld = Ai23Kit.world(47)
		var cb: CommanderBrain = Ai23Kit.commander()   # all six books: the pick by doctrine is RNG state
		var d: AiDriver = Ai23Kit.driver(w, cb, [0, 2])
		var _e: Array[SimEvent] = Ai23Kit.run(w, save_s * HZ)
		var run: BookRun = cb.run_of(0)
		assert_object(run).is_not_null()
		assert_int(run.cursor).override_failure_message("saved at %d s with the cursor at the start" % save_s).is_greater(0)
		var bytes: PackedByteArray = w.serialize()
		var d2: AiDriver = Ai14Kit.make_driver(w.terrain())
		var cb2: CommanderBrain = Ai23Kit.commander()
		d2.set_brain(15, cb2, true)
		var w2: SimWorld = SimWorld.deserialize(bytes, Ai23Kit.content(), d2)
		assert_object(w2).is_not_null()
		d2.set_terrain(w2.terrain())
		Ai23Kit.add_economy(d2, w2, false)
		assert_bool(d2.serialize() == d.serialize()).override_failure_message("AI bytes do not round-trip at %d s" % save_s).is_true()
		assert_bool(w2.serialize() == bytes).is_true()
		for slot: int in [0, 2]:
			assert_bool(cb2.run_of(slot).serialize() == cb.run_of(slot).serialize()).is_true()
			assert_str(String(cb2.book_of(slot).id)).is_equal(String(cb.book_of(slot).id))
		for k: int in AFTER_TICKS:
			w.step()
			w2.step()
			var _x: Array[SimEvent] = w.drain_events()
			var _y: Array[SimEvent] = w2.drain_events()
			for slot: int in [0, 2]:
				var ra: BookRun = cb.run_of(slot)
				var rb: BookRun = cb2.run_of(slot)
				assert_bool(ra.cursor == rb.cursor and ra.outcome == rb.outcome and ra.done == rb.done).override_failure_message("slot %d diverges at +%d (saved %d s)" % [slot, k, save_s]).is_true()
			if k % 2 == 0:
				assert_bool(w2.serialize() == w.serialize()).override_failure_message("S4 bytes diverge at +%d (saved %d s)" % [k, save_s]).is_true()
		assert_bool(d2.serialize() == d.serialize()).is_true()
