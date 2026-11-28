extends GdUnitTestSuite
## BUG-6 (R0 B.33 A-158) closed loop: the landing autopilot's L4-L6 (05 s5.5; `Assist.auto_dock`, TRANSITION,
## HOVER-DESCENT, FLARE) flies a possessed Dart holding DOCK onto a Pad on the 15 degree SlopedMapKit ground through the
## whole SimWorld tick (Kinematics' terrain push-out, Collision's landing volume, Touchdown), from the downhill and the
## uphill side and from a hover offset across the slope. Each tick the test builds the ship and pad snapshots from the
## store (ground_h = Terrain.height_at under the ship, as LandingPilot fills it), runs the assist and sends its
## PilotInput as the player's PILOT_INPUT (SimWorld's step-4 wiring of auto_dock is AI-10 / NET-18's).

const SLOPE_DEG: float = 15.0
const TICKS: int = 1800                   ## 60 s at 30 Hz
const HOVER_ALT: float = 60.0             ## above the ground under the start point
const HOVER_OFF: float = 100.0            ## inside flight_common.auto_dock_radius_m (150)


func after() -> void:
	SlopedMapKit.remove_all()


## Flies one approach from `off` (pad frame: x along fwd = uphill, y across) and returns the events up to DOCKED.
func _approach(off: Vector2) -> String:
	var w: SimWorld = WorldTestKit.world(13)
	SlopedMapKit.load_into(w.terrain(), SLOPE_DEG)
	var pad: int = WorldTestKit.spawn(w, &"pad", 0, 0, w.terrain().surface_point(Vector3.RIGHT))
	var id: int = DockingTestKit.ship_over(w, &"dart", 0, 0, pad, DockingTestKit.HIGH)
	if not DockingTestKit.possess(w, id):
		return "possess failed"
	var st: EntityStore = w.store()
	var s: int = EntityId.slot(id)
	var p: int = EntityId.slot(pad)
	var side: Vector3 = st.up[p].cross(st.fwd[p])
	var start: Vector3 = (st.pos[p] + st.fwd[p] * off.x + side * off.y).normalized()
	DockingTestKit.pose(w, id, pad, 0.0, 0.0, Vector3.ZERO)
	st.pos[s] = start * (Sphere.PLANET_RADIUS + w.terrain().height_at(start) + st.radius[s] + HOVER_ALT)
	var def: ShipDef = DockingTestKit.ship_def(&"dart")
	var common: FlightCommonDef = DockingTestKit.common()
	var rules: RulesDef = WorldTestKit.content().rules
	var prm: LandingParams = Ai09Kit.landing(rules)
	var g: FlightGains = Ai05Kit.gains(def, rules)
	var pad_s: PadSnapshot = PadSnapshot.new()
	pad_s.p = st.pos[p]
	pad_s.n = st.up[p]
	pad_s.radius_m = DockingTestKit.pad_radius(w, pad)
	pad_s.valid = true
	var ls: LandingState = LandingState.new()
	var snap: ShipSnapshot = ShipSnapshot.new()
	var events: Array[SimEvent] = []
	for _t: int in TICKS:
		var ss: ShipState = FlightTestKit.spawn(def, st.pos[s], st.fwd[s], st.up[s], st.vel[s])
		Ai09Kit.snapshot(ss, def, common, rules, snap, w.terrain().height_at(st.pos[s]))
		var inp: PilotInput = PilotInput.new()
		inp.buttons = PilotInput.DOCK
		var _on: bool = Assist.auto_dock(ls, snap, pad_s, prm, g, common.auto_dock_radius_m, common.auto_dock_latch_mult, inp)
		var _r: CommandResult = w.apply_command(Command.pilot(0, w.tick() + 1, inp))
		w.step()
		events.append_array(w.drain_events())
		if w.view().dock_state(id) == 2 or not st.alive(id):
			break
	return _verdict(w, id, pad, events)


func _verdict(w: SimWorld, id: int, pad: int, events: Array[SimEvent]) -> String:
	var st: EntityStore = w.store()
	var s: int = EntityId.slot(id)
	var p: int = EntityId.slot(pad)
	var landings: Array[SimEvent] = DockingTestKit.of_kind(events, SimEvent.Kind.LANDING)
	if w.view().dock_state(id) != 2 or landings.size() != 1:
		var rel: Vector3 = st.pos[s] - st.pos[p]
		return "not docked: alive %s alt %.2f landings %d" % [st.alive(id), rel.dot(st.up[p]), landings.size()]
	var grade: int = landings[0].extra[0]
	if grade == LandingGrade.Grade.CRASH or grade == LandingGrade.Grade.BENT:
		return "grade %d" % grade
	if not st.pos[s].is_equal_approx(st.pos[p] + st.up[p] * st.radius[s]):
		return "docked pose off"
	return ""


func test_auto_dock_docks_on_the_15_degree_pad() -> void:
	var fails: PackedStringArray = PackedStringArray()
	for off: Vector2 in [Vector2(-HOVER_OFF, 0.0), Vector2(HOVER_OFF, 0.0), Vector2(0.0, HOVER_OFF)]:
		var v: String = _approach(off)
		if v != "":
			var _b: bool = fails.push_back("from %s: %s" % [off, v])
	assert_int(fails.size()).override_failure_message("; ".join(fails)).is_equal(0)
