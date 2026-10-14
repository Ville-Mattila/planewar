extends GdUnitTestSuite
## The SimEvents TA-19 emits first (STRUCTURE_LOST, BUILD_STARTED, CAP_REACHED) against the 04 s3.6 payload layouts:
## each is routed through net/events EventRouter, encoded by EventCodec and decoded back, and every field is checked.

const K := preload("res://test/unit/sim/economy_test_kit.gd")


func _wire(w: SimWorld, events: Array[SimEvent], kind: SimEvent.Kind, player: int = 0) -> WireEvent:
	var aud: EventAudience = EventAudience.new(Roster.new())
	aud.unfiltered = true
	aud.player = player
	aud.team = player
	var router: EventRouter = EventRouter.new()
	var auds: Array[EventAudience] = [aud]
	router.route(w.tick(), events, auds)
	var out: Array[WireEvent] = []
	for p: PackedByteArray in aud.outbox:
		assert_int(EventCodec.decode(p, out)).is_greater_equal(0)
	for we: WireEvent in out:
		if we.kind == kind:
			return we
	return null


func test_structure_lost_carries_structure_def_and_killer() -> void:
	var w: SimWorld = K.solo_world()
	var refinery: int = K.find(w, &"refinery")
	var killer: int = w.store().id_of(K.find(w, &"shipyard"))
	var id: int = w.store().id_of(refinery)
	w.store().attacker[refinery] = killer
	assert_int(K.code(w, CommandPayload.debug_set(0, id, CommandPayload.SET_KILL, 0.0))).is_equal(CommandResult.Code.ACCEPTED)
	var events: Array[SimEvent] = K.run(w, 1)
	var we: WireEvent = _wire(w, events, SimEvent.Kind.STRUCTURE_LOST)
	assert_object(we).is_not_null()
	assert_int(we.v[0]).is_equal(refinery)                       # structure
	assert_int(we.v[1]).is_equal(K.def(&"refinery"))             # def u16 from extra[0..1]
	assert_int(we.v[2]).is_equal(EntityId.slot(killer))          # killer, not the def index


func test_build_started_carries_the_placing_player() -> void:
	var w: SimWorld = K.solo_world()
	assert_bool(w.spawn_start_kit(1, Vector3.LEFT, Vector3.UP)).is_true()
	var a: float = 250.0 / Sphere.PLANET_RADIUS
	var cell: int = Sphere.cell_of(Vector3(-cos(a), -sin(a), 0.0), Sphere.GRID_BUILD)
	assert_int(K.code(w, Command.build(1, K.def(&"solar_array"), cell, 0))).is_equal(CommandResult.Code.ACCEPTED)
	var events: Array[SimEvent] = K.run(w, 1)
	var we: WireEvent = _wire(w, events, SimEvent.Kind.BUILD_STARTED, 1)
	assert_object(we).is_not_null()
	assert_int(we.v[1]).is_equal(K.def(&"solar_array"))
	assert_int(we.v[2]).is_equal(1)                              # player u8 from extra[0]


func test_cap_reached_carries_player_and_cap_kind() -> void:
	var r: MatchRules = WorldTestKit.rules()
	r.caps.units = 2
	var w: SimWorld = K.solo_world(true, 7, r)
	var yard: int = w.store().id_of(K.find(w, &"shipyard"))
	assert_int(K.code(w, Command.produce(0, yard, K.def(&"dart"), 1))).is_equal(CommandResult.Code.ACCEPTED)
	assert_int(K.code(w, CommandPayload.debug_spawn(0, K.def(&"dart"), 0, 0, WorldTestKit.at(500.0), Vector3.ZERO, Vector3.UP))).is_equal(CommandResult.Code.ACCEPTED)
	var events: Array[SimEvent] = K.run(w, 3)
	var we: WireEvent = _wire(w, events, SimEvent.Kind.CAP_REACHED, 0)
	assert_object(we).is_not_null()
	assert_int(we.v[0]).is_equal(0)                              # player
	assert_int(we.v[1]).is_equal(Production.CAP_UNITS)           # cap kind: units
