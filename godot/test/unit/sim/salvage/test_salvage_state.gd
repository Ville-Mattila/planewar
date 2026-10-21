extends GdUnitTestSuite
## GD-19 W9 (sim/salvage/MODULE.md, S4): wrecks and tows add no saved state of their own; save / restore / continue is
## byte-exact at any point of a wreck's life (mid-lifetime, mid-tow, across expiry and delivery) and the format policy
## still refuses another FORMAT with wrecks alive.

const K: GDScript = preload("res://test/unit/sim/salvage/salvage_test_kit.gd")


func _restore(w: SimWorld) -> SimWorld:
	var _pending: Array[SimEvent] = w.drain_events()                         # events not yet drained are not saved
	var r: SimWorld = SimWorld.deserialize(w.serialize(), WorldTestKit.content(), null)
	assert_object(r).is_not_null()
	return r


func _same_events(a: Array[SimEvent], b: Array[SimEvent]) -> bool:
	if a.size() != b.size():
		return false
	for i: int in a.size():
		if a[i].kind != b[i].kind or a[i].a != b[i].a or a[i].b != b[i].b or a[i].value != b[i].value or a[i].tick != b[i].tick:
			return false
	return true


# Runs both worlds `n` ticks, asserting equal bytes every `every` ticks and equal events each tick.
func _run_equal(a: SimWorld, b: SimWorld, n: int, every: int) -> void:
	for i: int in n:
		a.step()
		b.step()
		assert_bool(_same_events(a.drain_events(), b.drain_events())).override_failure_message("events differ at tick %d" % a.tick()).is_true()
		if i % every == 0:
			assert_array(a.serialize()).override_failure_message("bytes differ at tick %d" % a.tick()).is_equal(b.serialize())
	assert_array(a.serialize()).is_equal(b.serialize())


func test_save_restore_continue_mid_lifetime_is_byte_exact_across_expiry() -> void:
	var w: SimWorld = K.world()
	var _ev: Array[SimEvent] = K.kill(w, K.put(w, &"core", 0, 0, 0.0))
	var _more: Array[SimEvent] = K.kill(w, K.put(w, &"bomber", 0, 0, 300.0, 600.0))
	assert_int(w.store().wrecks.size()).is_equal(8)
	var _mid: Array[SimEvent] = K.steps(w, 1000)
	var r: SimWorld = _restore(w)
	assert_array(r.serialize()).is_equal(w.serialize())                          # deserialize(b).serialize() == b
	assert_int(r.store().wrecks.size()).is_equal(8)
	_run_equal(w, r, 1800, 150)                                                 # past tick 2,700 of the oldest wreck
	assert_int(w.store().wrecks.size()).is_equal(0)
	assert_int(r.store().wrecks.size()).is_equal(0)


func test_expiry_lands_on_the_same_tick_after_a_restore() -> void:
	var w: SimWorld = K.world()
	var _ev: Array[SimEvent] = K.kill(w, K.put(w, &"shipyard", 0, 0, 0.0))
	var life: int = 90 * WorldTestKit.rules().tick_hz
	var _a: Array[SimEvent] = K.steps(w, life - 20)
	var r: SimWorld = _restore(w)
	var died: int = -1
	for i: int in 40:
		w.step()
		r.step()
		var ew: Array[SimEvent] = K.of_kind(w.drain_events(), SimEvent.Kind.DEATH)
		var er: Array[SimEvent] = K.of_kind(r.drain_events(), SimEvent.Kind.DEATH)
		assert_int(ew.size()).is_equal(er.size())
		if not ew.is_empty() and died < 0:
			died = i
	assert_int(died).is_greater_equal(0)
	assert_array(w.serialize()).is_equal(r.serialize())


func test_save_restore_continue_mid_tow_is_byte_exact_through_delivery() -> void:
	var w: SimWorld = K.world()
	var h: int = K.put(w, &"hauler", K.FOUNDRY_SLOT, 0, 20.0, 3060.0)
	var a: int = K.wreck_at(w, &"shipyard", 80.0, K.at(0.0, 3060.0))
	var b: int = K.wreck_at(w, &"shipyard", 80.0, K.at(0.0, 3064.0))
	assert_int(w.economy().salvage.try_attach(h, a)).is_equal(Salvage.Hook.OK)
	assert_int(w.economy().salvage.try_attach(h, b)).is_equal(Salvage.Hook.OK)
	var _s: Array[SimEvent] = K.steps(w, 3)
	var r: SimWorld = _restore(w)
	assert_int(r.economy().salvage.towed_count(h)).is_equal(2)
	assert_int(r.store().link[a]).is_equal(w.store().id_of(h))
	assert_bool(K.tethered(r, h)).is_true()
	var _ref: int = K.put(w, &"refinery", 0, 0, 0.0, 3000.0)                    # the same Refinery in both worlds
	var _ref2: int = K.put(r, &"refinery", 0, 0, 0.0, 3000.0)
	_run_equal(w, r, 60, 5)
	assert_int(w.store().wrecks.size()).is_equal(0)
	assert_int(r.store().wrecks.size()).is_equal(0)
	assert_int(EconomyTestKit.ore(r)).is_equal(EconomyTestKit.ore(w))


func test_a_restored_tow_order_hooks_like_the_original() -> void:
	var w: SimWorld = K.world()
	var h: int = K.put(w, &"hauler", 0, 0, 20.0, 3000.0)
	var wr: int = K.wreck_at(w, &"dart", 60.0, K.at(0.0, 3000.0))
	K.haul(w, h, OrderSpec.HaulMode.TOW, w.store().id_of(wr))
	var r: SimWorld = _restore(w)
	_run_equal(w, r, 5, 1)
	assert_bool(K.tethered(r, wr)).is_true()


func test_another_format_is_refused_with_wrecks_alive() -> void:
	var w: SimWorld = K.world()
	var _ev: Array[SimEvent] = K.kill(w, K.put(w, &"shipyard", 0, 0, 0.0))
	var bytes: PackedByteArray = w.serialize()
	assert_int(SimSerialize.check(bytes)).is_equal(SimSerialize.Status.OK)
	var older: PackedByteArray = bytes.duplicate()
	older.encode_u32(4, SimSerialize.FORMAT - 1)
	var newer: PackedByteArray = bytes.duplicate()
	newer.encode_u32(4, SimSerialize.FORMAT + 1)
	assert_int(SimSerialize.check(older)).is_equal(SimSerialize.Status.OLD_FORMAT)
	assert_int(SimSerialize.check(newer)).is_equal(SimSerialize.Status.NEWER_FORMAT)
	assert_object(SimWorld.deserialize(older, WorldTestKit.content(), null)).is_null()
	assert_object(SimWorld.deserialize(newer, WorldTestKit.content(), null)).is_null()
