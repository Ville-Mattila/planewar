extends GdUnitTestSuite
## BUG-6 (R0 B.33 A-158; 03 s6.4) through the whole SimWorld tick on the SlopedMapKit ground (Pad, pad_radius_m 10,
## radial up, the sim terrain not flattened): a Dart settling 8 m uphill of the pad centre on 5 and on 15 degree ground
## is graded (LANDING) and DOCKED at pos[pad] + up x r; 8 m downhill it docks too; and a save taken while a ship
## settles on the slope reloads byte-equal and continues like the original (S4; Collision adds no state, no FORMAT
## change). The L4-L6 closed loop on the 15 degree pad: test/sim/test_sloped_pad_auto_dock.gd.

const OFF: float = 8.0
const SETTLE_TICKS: int = 30
const CONTINUE: int = 60


func after() -> void:
	SlopedMapKit.remove_all()


func _world(slope_deg: float) -> SimWorld:
	var w: SimWorld = WorldTestKit.world(11)
	SlopedMapKit.load_into(w.terrain(), slope_deg)
	return w


## A finished Pad of player 0 on the slope at +X (fwd +Y = uphill, up radial, A-157).
func _pad(w: SimWorld) -> int:
	return WorldTestKit.spawn(w, &"pad", 0, 0, w.terrain().surface_point(Vector3.RIGHT))


## A tail-down Dart resting on its own ground `off` m along the pad's fwd, `above` m over that rest, sinking 1 m/s.
func _settling(w: SimWorld, pad: int, off: float, above: float = 0.0) -> int:
	var id: int = DockingTestKit.ship_over(w, &"dart", 0, 0, pad, DockingTestKit.HIGH)
	var st: EntityStore = w.store()
	var s: int = EntityId.slot(id)
	var p: int = EntityId.slot(pad)
	st.pos[s] = SlopedMapKit.resting(w.terrain(), st, p, off, st.radius[s] + above)
	st.vel[s] = -st.up[p]
	return id


## Steps until `id` is DOCKED (at most `ticks`); returns the events of those ticks.
func _until_docked(w: SimWorld, id: int, ticks: int) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for _t: int in ticks:
		w.step()
		out.append_array(w.drain_events())
		if w.view().dock_state(id) == 2:
			break
	return out


## Asserts the landing of `id` on `pad` among `events` and the docked pose; returns its grade (-1 none).
func _assert_docked(w: SimWorld, id: int, pad: int, events: Array[SimEvent], what: String) -> int:
	var st: EntityStore = w.store()
	var s: int = EntityId.slot(id)
	var p: int = EntityId.slot(pad)
	assert_int(w.view().dock_state(id)).override_failure_message(what + ": not docked").is_equal(2)
	var landings: Array[SimEvent] = DockingTestKit.of_kind(events, SimEvent.Kind.LANDING)
	assert_int(landings.size()).override_failure_message(what + ": LANDING").is_equal(1)
	assert_int(DockingTestKit.of_kind(events, SimEvent.Kind.DOCKED).size()).is_equal(1)
	if landings.is_empty():
		return -1
	var grade: int = landings[0].extra[0]
	assert_int(grade).override_failure_message(what + ": grade").is_not_equal(LandingGrade.Grade.CRASH)
	assert_int(w.view().landing_grade_last(id)).is_equal(grade)
	assert_int(st.link[s]).is_equal(pad)
	assert_vector(st.pos[s]).is_equal_approx(st.pos[p] + st.up[p] * st.radius[s], Vector3.ONE * 1e-3)
	assert_float(st.hp[s]).is_equal(float(DockingTestKit.ship_def(&"dart").hp))
	return grade


func test_a_dart_settling_8_m_uphill_docks_on_5_and_15_degrees() -> void:
	for deg: float in [5.0, 15.0]:
		var w: SimWorld = _world(deg)
		var pad: int = _pad(w)
		var id: int = _settling(w, pad, OFF)
		var st: EntityStore = w.store()
		var p: int = EntityId.slot(pad)
		var alt: float = (st.pos[EntityId.slot(id)] - st.pos[p]).dot(st.up[p])
		assert_float(alt).is_greater(st.radius[EntityId.slot(id)] + 0.5)     # outside the A-31 band (BUG-6)
		var events: Array[SimEvent] = _until_docked(w, id, SETTLE_TICKS)
		assert_int(_assert_docked(w, id, pad, events, "%.0f deg uphill" % deg)).is_equal(LandingGrade.Grade.AUTO)


func test_a_dart_settling_8_m_downhill_docks() -> void:
	for deg: float in [5.0, 15.0]:
		var w: SimWorld = _world(deg)
		var pad: int = _pad(w)
		var id: int = _settling(w, pad, -OFF)
		var grade: int = _assert_docked(w, id, pad, _until_docked(w, id, SETTLE_TICKS), "%.0f deg downhill" % deg)
		assert_int(grade).is_equal(LandingGrade.Grade.AUTO)


func test_a_save_while_settling_on_the_slope_reloads_and_continues_byte_equal() -> void:
	var w: SimWorld = _world(15.0)
	var pad: int = _pad(w)
	var id: int = _settling(w, pad, OFF, 2.0)
	var _e: Array[SimEvent] = w.drain_events()
	var bytes: PackedByteArray = w.serialize()
	var r: SimWorld = SimWorld.deserialize(bytes, WorldTestKit.content(), null)
	assert_object(r).is_not_null()
	SlopedMapKit.load_into(r.terrain(), 15.0)
	assert_bool(r.serialize() == bytes).override_failure_message("reload differs").is_true()
	var docked_at: int = -1
	for t: int in CONTINUE:
		w.step()
		r.step()
		var ew: Array[SimEvent] = w.drain_events()
		var er: Array[SimEvent] = r.drain_events()
		assert_array(Array(WorldTestKit.kinds(er))).is_equal(Array(WorldTestKit.kinds(ew)))
		if docked_at < 0 and w.view().dock_state(id) == 2:
			docked_at = t
	assert_int(docked_at).override_failure_message("never docked in the window").is_greater_equal(1)
	assert_bool(r.serialize() == w.serialize()).override_failure_message("continued state differs").is_true()
