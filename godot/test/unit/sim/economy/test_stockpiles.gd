extends GdUnitTestSuite
## Stockpiles (GD-11; 02 s8.6, R0 O-4): caps 3,000 + 1,500 per Refinery, 60 Ore/min trickle, atomic try_spend,
## STORAGE_FULL once per crossing, S4 round trip of the notice flags, determinism, EventCodec round trip of the alert.

const K := preload("res://test/unit/sim/economy_test_kit.gd")


func _fill(w: SimWorld) -> Economy:
	var e: Economy = w.economy().economy
	e.credit(0, 1000000, 1000000)
	return e


func test_caps_core_plus_refinery_and_ice() -> void:
	var e: Economy = K.solo_world().economy().economy
	assert_int(e.caps(0).x).is_equal(3000 + 1500)
	assert_int(e.caps(0).y).is_equal(800 + 500)
	assert_bool(e.caps(1) == Vector2i.ZERO).is_true()


func test_trickle_is_sixty_ore_per_minute() -> void:
	var w: SimWorld = K.solo_world()
	var before: int = K.ore(w)
	var hz: int = WorldTestKit.content().rules.tick_hz
	var _ev: Array[SimEvent] = K.run(w, 60 * hz)
	assert_int(K.ore(w) - before).is_equal(60)


func test_try_spend_is_atomic_per_resource() -> void:
	var w: SimWorld = K.solo_world()
	var e: Economy = w.economy().economy
	var ice: int = e.stockpile(0).y
	assert_bool(e.try_spend(0, 10, ice + 1)).is_false()          # Ore affordable, Ice not: nothing is taken
	assert_int(K.ore(w)).is_equal(800)
	assert_int(e.stockpile(0).y).is_equal(ice)
	assert_bool(e.try_spend(0, -1, 0)).is_false()
	assert_bool(e.try_spend(0, 800, ice)).is_true()
	assert_bool(e.stockpile(0) == Vector2i.ZERO).is_true()


func test_storage_full_alerts_once_per_crossing() -> void:
	var w: SimWorld = K.solo_world()
	var e: Economy = _fill(w)
	assert_int(K.count_alert(K.run(w, 1), AlertKind.Kind.STORAGE_FULL)).is_equal(2)   # Ore and Ice
	e.credit(0, 0, 0)                                            # a zero credit into a full pool does not re-arm
	e.credit(0, 5, 0)
	assert_int(K.count_alert(K.run(w, 1), AlertKind.Kind.STORAGE_FULL)).is_equal(0)
	assert_bool(e.try_spend(0, 100, 0)).is_true()
	e.credit(0, 50, 0)                                           # below the cap again, no overflow
	assert_int(K.count_alert(K.run(w, 1), AlertKind.Kind.STORAGE_FULL)).is_equal(0)
	e.credit(0, 500, 0)                                          # second crossing
	assert_int(K.count_alert(K.run(w, 1), AlertKind.Kind.STORAGE_FULL)).is_equal(1)


func test_s4_round_trip_keeps_the_notice_flags() -> void:
	var w: SimWorld = K.solo_world()
	var e: Economy = _fill(w)
	var _a: Array[SimEvent] = K.run(w, 3)
	var copy: SimWorld = SimWorld.deserialize(w.serialize(), WorldTestKit.content(), null)
	assert_bool(copy.serialize() == w.serialize()).is_true()
	e.credit(0, 5, 0)
	copy.economy().economy.credit(0, 5, 0)
	assert_int(K.count_alert(K.run(copy, 2), AlertKind.Kind.STORAGE_FULL)).is_equal(0)   # still reported, not re-raised
	var _b: Array[SimEvent] = K.run(w, 2)
	assert_bool(copy.serialize() == w.serialize()).is_true()


func test_determinism_with_overflow() -> void:
	var a: SimWorld = K.solo_world()
	var b: SimWorld = K.solo_world()
	var _x: Economy = _fill(a)
	var _y: Economy = _fill(b)
	var _e1: Array[SimEvent] = K.run(a, 400)
	var _e2: Array[SimEvent] = K.run(b, 400)
	assert_bool(a.serialize() == b.serialize()).is_true()


func test_storage_full_alert_wire_round_trip() -> void:
	var w: SimWorld = K.solo_world()
	var _e: Economy = _fill(w)
	var events: Array[SimEvent] = K.run(w, 1)
	var aud: EventAudience = EventAudience.new(Roster.new())
	aud.unfiltered = true
	aud.player = 0
	aud.team = 0
	var router: EventRouter = EventRouter.new()
	var auds: Array[EventAudience] = [aud]
	router.route(w.tick(), events, auds)
	var out: Array[WireEvent] = []
	for p: PackedByteArray in aud.outbox:
		assert_int(EventCodec.decode(p, out)).is_greater_equal(0)
	var seen: Array[int] = []
	for we: WireEvent in out:
		if we.kind == SimEvent.Kind.ALERT and we.v[0] == AlertKind.Kind.STORAGE_FULL:
			seen.append(we.v[1])
	seen.sort()
	assert_array(seen).is_equal([1, 2])                          # alert kind, subject = resource bit
