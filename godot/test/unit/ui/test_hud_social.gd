extends GdUnitTestSuite
## UX-19 piloted-by badges, pending order line, hand-over toast and canister beacon from scripted SimView states and
## SimEvents (docs/06 s6.1, s7.6; ui/hud/piloted_badges.gd, pending_line.gd, handover_toast.gd, beacon_tracker.gd).

const EPS: float = 0.0001
const R: float = Sphere.PLANET_RADIUS
const POSSESSED: int = 2   # SimView.control_state ordinal, sim/MODULE.md

var _v: HudScenarioView
var _names: Dictionary = {0: "Ville", 1: "Aino", 2: "Matti"}


func before_test() -> void:
	var r: Result = ContentDB.load_all()
	assert_bool(r.ok).is_true()
	_v = HudScenarioView.new()


func _event(kind: SimEvent.Kind, a: int, b: int, p: Vector3 = Vector3.ZERO, team: int = 0) -> SimEvent:
	var e: SimEvent = SimEvent.new()
	e.kind = kind
	e.a = a
	e.b = b
	e.pos = p
	e.team = team
	return e


# --- piloted-by badges ---------------------------------------------------------------------------------------------

func test_badges_only_for_teammate_flown_ships() -> void:
	_v.add(1, &"dart", 0, Vector3(0, R + 100, 0), POSSESSED, 0)        # the local player's own ship
	_v.add(2, &"bomber", 0, Vector3(50, R + 100, 0), POSSESSED, 1)     # flown by Aino
	_v.add(3, &"dart", 0, Vector3(80, R + 100, 0), 0, -1)              # autopilot
	_v.add(4, &"dart", 1, Vector3(90, R + 100, 0), POSSESSED, 2)       # enemy pilot
	var out: Array[PilotBadge] = PilotedBadges.from_view(_v, 0, 0, _names)
	assert_int(out.size()).is_equal(1)
	assert_int(out[0].entity).is_equal(2)
	assert_int(out[0].slot).is_equal(1)
	assert_str(out[0].label).is_equal("Aino")
	assert_vector(out[0].pos).is_equal(Vector3(50, R + 100, 0))


func test_badge_without_a_roster_name_falls_back_to_a_localised_slot_label() -> void:
	_v.add(2, &"bomber", 0, Vector3(50, R + 100, 0), POSSESSED, 5)
	var out: Array[PilotBadge] = PilotedBadges.from_view(_v, 0, 0, _names)
	assert_str(out[0].label).is_not_empty()
	assert_str(out[0].label).is_not_equal("hud.badge.slot")


# --- pending order -------------------------------------------------------------------------------------------------

func test_pending_order_line_names_issuer_verb_and_target() -> void:
	_v.add(1, &"dart", 0, Vector3(0, R + 100, 0), POSSESSED, 0)
	_v.add(7, &"bomber", 0, Vector3(50, R + 100, 0))
	var spec: OrderSpec = OrderSpec.make(OrderSpec.Kind.ESCORT, 7)
	spec.issuer = 1
	_v.pending[1] = spec
	var p: PendingLine = PendingLine.from_view(_v, 1, _names, func(_id: int) -> String: return "Bomber 2")
	assert_object(p).is_not_null()
	assert_int(p.kind).is_equal(OrderSpec.Kind.ESCORT)
	assert_str(p.issuer_name).is_equal("Aino")
	assert_str(p.text()).is_equal("Order from Aino: escort Bomber 2 (on release)")


func test_no_pending_order_means_no_line() -> void:
	_v.add(1, &"dart", 0, Vector3(0, R + 100, 0))
	assert_object(PendingLine.from_view(_v, 1, _names, Callable())).is_null()


func test_every_order_kind_has_a_verb_key_in_the_locale() -> void:
	for k: int in OrderSpec.KIND_COUNT:
		var key: StringName = PendingLine.verb_key(k)
		assert_str(tr(key)).is_not_equal(String(key))


func test_point_order_without_target_uses_the_marker_wording() -> void:
	_v.add(1, &"dart", 0, Vector3(0, R + 100, 0))
	var spec: OrderSpec = OrderSpec.make(OrderSpec.Kind.MOVE, 0, Vector3(0, R, 100))
	spec.issuer = 0
	_v.pending[1] = spec
	var p: PendingLine = PendingLine.from_view(_v, 1, _names, Callable())
	assert_str(p.text()).is_equal("Order from Ville: move to marker (on release)")


# --- hand-over toast -----------------------------------------------------------------------------------------------

func test_request_for_the_local_pilot_shows_the_toast_for_8_s() -> void:
	_v.add(2, &"bomber", 0, Vector3(50, R + 100, 0), POSSESSED, 0)
	var t: HandoverToast = HandoverToast.new()
	assert_bool(t.on_event(_event(SimEvent.Kind.POSSESS_REQUESTED, 2, 1), _v, 0, _names)).is_true()
	assert_bool(t.active()).is_true()
	assert_str(t.requester_name).is_equal("Aino")
	assert_float(t.left_s).is_equal_approx(HudMath.param("toast_s"), EPS)
	assert_float(HudMath.param("toast_s")).is_equal_approx(8.0, EPS)
	t.tick(7.9)
	assert_bool(t.active()).is_true()
	t.tick(0.2)
	assert_bool(t.active()).is_false()


func test_request_for_another_pilot_or_other_events_are_ignored() -> void:
	_v.add(2, &"bomber", 0, Vector3(50, R + 100, 0), POSSESSED, 2)
	var t: HandoverToast = HandoverToast.new()
	assert_bool(t.on_event(_event(SimEvent.Kind.POSSESS_REQUESTED, 2, 1), _v, 0, _names)).is_false()
	assert_bool(t.on_event(_event(SimEvent.Kind.DEATH, 2, 1), _v, 2, _names)).is_false()
	assert_bool(t.active()).is_false()


func test_accept_builds_a_handover_command_to_the_requester_and_closes() -> void:
	_v.add(2, &"bomber", 0, Vector3(50, R + 100, 0), POSSESSED, 0)
	var t: HandoverToast = HandoverToast.new()
	var _ok: bool = t.on_event(_event(SimEvent.Kind.POSSESS_REQUESTED, 2, 1), _v, 0, _names)
	var c: Command = t.accept(0)
	assert_object(c).is_not_null()
	assert_int(c.kind).is_equal(Command.Kind.HANDOVER)
	assert_int(c.target).is_equal(2)
	assert_int(c.player).is_equal(0)
	assert_int(c.payload.decode_u8(0)).is_equal(1)
	assert_bool(t.active()).is_false()
	assert_object(t.accept(0)).is_null()


func test_handover_event_or_release_of_the_entity_closes_the_toast() -> void:
	_v.add(2, &"bomber", 0, Vector3(50, R + 100, 0), POSSESSED, 0)
	var t: HandoverToast = HandoverToast.new()
	var _ok: bool = t.on_event(_event(SimEvent.Kind.POSSESS_REQUESTED, 2, 1), _v, 0, _names)
	var _c: bool = t.on_event(_event(SimEvent.Kind.RELEASED, 2, 0), _v, 0, _names)
	assert_bool(t.active()).is_false()


# --- canister beacon -----------------------------------------------------------------------------------------------

func test_beacon_added_on_deploy_removed_on_collect_and_team_filtered() -> void:
	var b: BeaconTracker = BeaconTracker.new()
	b.on_event(_event(SimEvent.Kind.CANISTER_DEPLOYED, 40, 1, Vector3(0, R, -500), 0), 0)
	b.on_event(_event(SimEvent.Kind.CANISTER_DEPLOYED, 41, 3, Vector3(0, R, 500), 1), 0)   # enemy team
	assert_int(b.count()).is_equal(1)
	b.on_event(_event(SimEvent.Kind.CANISTER_COLLECTED, 40, 9), 0)
	assert_int(b.count()).is_equal(0)


func test_beacon_pip_sits_on_the_compass_tape_by_bearing() -> void:
	var b: BeaconTracker = BeaconTracker.new()
	var ship_pos: Vector3 = Vector3(R * 0.5, R * 0.8, 0.0)
	var spot: Vector3 = ship_pos + Vector3(0.0, 0.0, -500.0)   # a little off the nose
	b.on_event(_event(SimEvent.Kind.CANISTER_DEPLOYED, 40, 1, spot, 0), 0)
	var n: Vector3 = ship_pos.normalized()
	var heading: float = HudMath.heading_deg(Vector3(0, 0, -1), n)
	var pips: Array[BeaconPip] = b.pips(ship_pos, heading, 280.0, 90.0)
	assert_int(pips.size()).is_equal(1)
	assert_float(pips[0].dist).is_equal_approx(ship_pos.distance_to(spot), 0.01)
	var bearing: float = HudMath.heading_deg(spot - ship_pos, n)
	assert_float(pips[0].x).is_equal_approx(HudMath.tape_x(bearing, heading, 280.0, 90.0), EPS)
	assert_bool(pips[0].on_tape).is_true()


func test_beacon_beyond_the_tape_span_is_pinned_to_the_edge() -> void:
	var b: BeaconTracker = BeaconTracker.new()
	var ship_pos: Vector3 = Vector3(R * 0.5, R * 0.8, 0.0)
	b.on_event(_event(SimEvent.Kind.CANISTER_DEPLOYED, 40, 1, ship_pos + Vector3(0, 0, 500), 0), 0)
	var n: Vector3 = ship_pos.normalized()
	var heading: float = HudMath.heading_deg(Vector3(0, 0, -1), n)   # flying away from the canister
	var pips: Array[BeaconPip] = b.pips(ship_pos, heading, 280.0, 90.0)
	assert_bool(pips[0].on_tape).is_false()
	assert_float(absf(pips[0].x)).is_equal_approx(140.0, EPS)
