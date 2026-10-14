extends GdUnitTestSuite
## NET-10 event_filter_test: scope per kind (roster, team, all, cell, lock, possessor), roster masking so an enemy
## entity outside vision never appears in any event, stale generations, packet splitting, determinism.

var _rig: EventRig


func before_test() -> void:
	_rig = EventRig.new()


func _enemy(slot: int = EventRig.ENEMY_FIRST) -> int:
	return EventRig.id(slot)


func _route(events: Array[SimEvent]) -> Array[WireEvent]:
	return EventRig.roundtrip(events, _rig.aud)


func test_roster_scope_requires_subject_in_roster() -> void:
	var mine: SimEvent = EventRig.ev(SimEvent.Kind.DEATH, EventRig.id(5), _enemy(), 0.0, 0, PackedByteArray([1]))
	var theirs: SimEvent = EventRig.ev(SimEvent.Kind.DEATH, _enemy(), EventRig.id(5), 0.0, 1, PackedByteArray([1]))
	var out: Array[WireEvent] = _route([mine, theirs])
	assert_int(out.size()).is_equal(1)
	assert_int(out[0].v[0]).is_equal(5)
	assert_int(out[0].v[1]).is_equal(EventCodec.NONE_REF)      # killer outside the roster is masked


func test_enemy_outside_vision_never_appears_in_any_event() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 77
	var events: Array[SimEvent] = []
	for _n: int in 600:
		var k: int = rng.randi() % EventCodec.KIND_COUNT
		var a: int = EventRig.id(rng.randi_range(1, 39))
		var b: int = EventRig.id(rng.randi_range(1, 39))
		var team: int = rng.randi_range(-1, 1)
		events.append(EventRig.ev(k as SimEvent.Kind, a, b, rng.randf() * 100.0, team,
				PackedByteArray([rng.randi() & 0xFF, rng.randi() & 0xFF, 1, 2, 3]), _rig.site))
	var out: Array[WireEvent] = _route(events)
	assert_int(out.size()).is_greater(50)
	for w: WireEvent in out:
		for f: int in w.count:
			if _is_ref_field(w.kind, f):
				var ref: int = w.v[f]
				assert_bool(ref == EventCodec.NONE_REF or _rig.roster.has(ref)).is_true()
				assert_bool(ref >= EventRig.ENEMY_FIRST and ref <= EventRig.ENEMY_LAST).is_false()


## A field is an entity reference when EventRouter.SOURCES says REF_A / REF_B.
func _is_ref_field(kind: int, f: int) -> bool:
	var src: int = EventRouter.SOURCES[kind * EventCodec.ROW + f]
	return src == EventRouter.Src.REF_A or src == EventRouter.Src.REF_B


func test_stale_generation_is_masked() -> void:
	var stale: SimEvent = EventRig.ev(SimEvent.Kind.SHIELD_COLLAPSE, EventRig.id(5, 2), 0)
	assert_int(_route([stale]).size()).is_equal(0)
	var live: SimEvent = EventRig.ev(SimEvent.Kind.SHIELD_COLLAPSE, EventRig.id(5, 1), 0)
	assert_int(_route([live]).size()).is_equal(1)


func test_team_scope_only_reaches_own_team() -> void:
	var own: SimEvent = EventRig.ev(SimEvent.Kind.BUILD_DONE, EventRig.id(5), 9, 0.0, 0)
	var foe: SimEvent = EventRig.ev(SimEvent.Kind.BUILD_DONE, EventRig.id(5), 9, 0.0, 1)
	var power_foe: SimEvent = EventRig.ev(SimEvent.Kind.LOW_POWER, 0, 0, 0.3, 1)
	var power_own: SimEvent = EventRig.ev(SimEvent.Kind.LOW_POWER, 0, 0, 0.3, 0)
	var out: Array[WireEvent] = _route([own, foe, power_foe, power_own])
	assert_int(out.size()).is_equal(2)
	assert_int(out[0].kind).is_equal(SimEvent.Kind.BUILD_DONE)
	assert_int(out[1].kind).is_equal(SimEvent.Kind.LOW_POWER)
	assert_int(out[1].v[0]).is_equal(0)


func test_enemy_team_client_gets_roster_events_but_not_team_events() -> void:
	var foe_rig: EventRig = EventRig.new()
	foe_rig.aud.team = 1
	var team_ev: SimEvent = EventRig.ev(SimEvent.Kind.SERVICED, EventRig.id(5), EventRig.id(6), 0.0, 0, PackedByteArray([1]))
	var roster_ev: SimEvent = EventRig.ev(SimEvent.Kind.DOCKED, EventRig.id(5), EventRig.id(6), 0.0, 0)
	var out: Array[WireEvent] = EventRig.roundtrip([team_ev, roster_ev], foe_rig.aud)
	assert_int(out.size()).is_equal(1)
	assert_int(out[0].kind).is_equal(SimEvent.Kind.DOCKED)


func test_all_scope_reaches_everyone() -> void:
	var evs: Array[SimEvent] = [
		EventRig.ev(SimEvent.Kind.CORE_EXPOSURE, 0, 0, 0.0, -1),
		EventRig.ev(SimEvent.Kind.PLAYER_ELIMINATED, 3, 1, 0.0, 1),
		EventRig.ev(SimEvent.Kind.CAPTURED, _enemy(), 1, 0.0, 1),
	]
	var other: EventRig = EventRig.new()
	other.aud.team = 5
	var out: Array[WireEvent] = EventRig.roundtrip(evs, other.aud)
	assert_int(out.size()).is_equal(3)
	assert_int(out[2].v[0]).is_equal(EventCodec.NONE_REF)      # captured site not in the roster: no slot leaks


func test_cell_scope_follows_interest_cells() -> void:
	var bomb: SimEvent = EventRig.ev(SimEvent.Kind.BOMB_IMPACT, 1, 2, 0.0, 1, PackedByteArray(), _rig.site)
	assert_int(_route([bomb]).size()).is_equal(1)
	_rig.aud.set_cells(PackedInt32Array([(_rig.cell + 1) % Codec.CELL_COUNT]))
	assert_int(_route([bomb]).size()).is_equal(0)


func test_lock_events_reach_target_possessor_and_shooter_team() -> void:
	var at_me: SimEvent = EventRig.ev(SimEvent.Kind.LOCK_ACQUIRED, _enemy(), EventRig.id(5), 0.0, 1)     # target = my slot 5
	var elsewhere: SimEvent = EventRig.ev(SimEvent.Kind.LOCK_ACQUIRED, _enemy(), EventRig.id(6), 0.0, 1)
	var mine_shooting: SimEvent = EventRig.ev(SimEvent.Kind.LOCK_BROKEN, EventRig.id(6), _enemy(), 0.0, 0)
	var out: Array[WireEvent] = _route([at_me, elsewhere, mine_shooting])
	assert_int(out.size()).is_equal(2)
	assert_int(out[0].v[0]).is_equal(EventCodec.NONE_REF)      # unseen shooter masked
	assert_int(out[0].v[1]).is_equal(5)
	assert_int(out[1].v[0]).is_equal(6)
	assert_int(out[1].v[1]).is_equal(EventCodec.NONE_REF)      # unseen target masked


func test_possess_requested_only_to_possessor() -> void:
	var e5: SimEvent = EventRig.ev(SimEvent.Kind.POSSESS_REQUESTED, EventRig.id(5), 3)
	var e6: SimEvent = EventRig.ev(SimEvent.Kind.POSSESS_REQUESTED, EventRig.id(6), 3)
	var out: Array[WireEvent] = _route([e5, e6])
	assert_int(out.size()).is_equal(1)
	assert_int(out[0].v[0]).is_equal(5)


func test_structure_lost_team_plus_roster_masks_killer() -> void:
	var lost: SimEvent = EventRig.ev(SimEvent.Kind.STRUCTURE_LOST, EventRig.id(5), _enemy(), 0.0, 0, PackedByteArray([1, 0]))
	var seen_by_foe: EventRig = EventRig.new()
	seen_by_foe.aud.team = 1
	var out: Array[WireEvent] = EventRig.roundtrip([lost], seen_by_foe.aud)
	assert_int(out.size()).is_equal(1)
	assert_int(out[0].v[2]).is_equal(EventCodec.NONE_REF)
	var unseen: SimEvent = EventRig.ev(SimEvent.Kind.STRUCTURE_LOST, _enemy(), EventRig.id(5), 0.0, 1, PackedByteArray([1, 0]))
	assert_int(_route([unseen]).size()).is_equal(0)           # enemy structure, enemy team, not in roster


func test_cap_reached_goes_to_that_player() -> void:
	var mine: SimEvent = EventRig.ev(SimEvent.Kind.CAP_REACHED, 2, 1, 0.0, -1)
	var other: SimEvent = EventRig.ev(SimEvent.Kind.CAP_REACHED, 3, 1, 0.0, -1)
	assert_int(_route([mine, other]).size()).is_equal(1)


func test_unfiltered_audience_gets_everything_with_slots() -> void:
	_rig.aud.unfiltered = true
	var e: SimEvent = EventRig.ev(SimEvent.Kind.DEATH, _enemy(), EventRig.id(5), 0.0, 1, PackedByteArray([0]))
	var out: Array[WireEvent] = _route([e])
	assert_int(out.size()).is_equal(1)
	assert_int(out[0].v[0]).is_equal(EventRig.ENEMY_FIRST)


func test_packets_split_at_1200_bytes_and_255_events_in_order() -> void:
	var evs: Array[SimEvent] = []
	for n: int in 1000:
		evs.append(EventRig.ev(SimEvent.Kind.HIT, EventRig.id(5), EventRig.id(6), float(n), 0, PackedByteArray([0, n & 0xFF])))
	var router: EventRouter = EventRouter.new()
	var auds: Array[EventAudience] = [_rig.aud]
	router.route(7, evs, auds)
	assert_int(_rig.aud.outbox.size()).is_greater(1)
	var out: Array[WireEvent] = []
	for p: PackedByteArray in _rig.aud.outbox:
		assert_int(p.size()).is_less_equal(Protocol.MAX_UNRELIABLE_BYTES)
		assert_int(p[5]).is_less_equal(255)
		assert_int(EventCodec.decode(p, out)).is_greater(0)
	assert_int(out.size()).is_equal(1000)
	for n: int in 1000:
		assert_int(out[n].v[3]).is_equal(n)


func test_routing_is_deterministic() -> void:
	var evs: Array[SimEvent] = [EventRig.ev(SimEvent.Kind.HIT, EventRig.id(5), _enemy(), 99.0, 0, PackedByteArray([1, 2]))]
	var r1: EventRig = EventRig.new()
	var r2: EventRig = EventRig.new()
	var a1: Array[EventAudience] = [r1.aud]
	var a2: Array[EventAudience] = [r2.aud]
	EventRouter.new().route(7, evs, a1)
	EventRouter.new().route(7, evs, a2)
	assert_array(r1.aud.outbox[0]).is_equal(r2.aud.outbox[0])
