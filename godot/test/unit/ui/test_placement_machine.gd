extends GdUnitTestSuite
## PlacementMachine (UX-21): every edge of the docs/06 s7.3 state diagram.

const S := PlacementMachine.State


func _positioning(repeat: bool = false) -> PlacementMachine:
	var m: PlacementMachine = PlacementMachine.new()
	assert_bool(m.arm(&"pylon")).is_true()
	assert_bool(m.set_camera(1000.0, 55)).is_true()
	m.repeat = repeat
	return m


func test_starts_idle_and_arm_goes_to_armed() -> void:
	var m: PlacementMachine = PlacementMachine.new()
	assert_int(m.state).is_equal(S.IDLE)
	assert_bool(m.is_active()).is_false()
	assert_bool(m.arm(&"pylon")).is_true()
	assert_int(m.state).is_equal(S.ARMED)
	assert_str(String(m.def_id)).is_equal("pylon")
	assert_bool(m.is_active()).is_true()


func test_armed_waits_for_the_camera_at_1200_or_lower() -> void:
	var m: PlacementMachine = PlacementMachine.new()
	var _a: bool = m.arm(&"pylon")
	assert_bool(m.set_camera(1950.0, 7)).is_false()
	assert_int(m.state).is_equal(S.ARMED)
	assert_bool(m.set_camera(1200.1, 7)).is_false()
	assert_bool(m.set_camera(1200.0, 7)).is_true()
	assert_int(m.state).is_equal(S.POSITIONING)
	assert_int(m.cell).is_equal(7)                          # the ghost starts at the focus
	assert_bool(m.set_camera(500.0, 9)).is_false()          # already positioning: the ghost stays
	assert_int(m.cell).is_equal(7)


func test_move_and_rotate_only_while_positioning() -> void:
	var m: PlacementMachine = PlacementMachine.new()
	assert_bool(m.move_to(3)).is_false()
	var _a: bool = m.arm(&"pylon")
	assert_bool(m.move_to(3)).is_false()
	assert_bool(m.rotate_by(1)).is_false()
	var _c: bool = m.set_camera(100.0, 5)
	assert_bool(m.move_to(8)).is_true()
	assert_int(m.cell).is_equal(8)
	assert_bool(m.move_to(8)).is_false()                    # unchanged
	assert_bool(m.rotate_by(1)).is_true()
	assert_int(m.rotation).is_equal(1)
	var _r: bool = m.rotate_by(1) and m.rotate_by(1)
	assert_int(m.rotation).is_equal(3)
	var _w: bool = m.rotate_by(1)
	assert_int(m.rotation).is_equal(0)                      # four rotations wrap
	var _b: bool = m.rotate_by(-1)
	assert_int(m.rotation).is_equal(3)


func test_confirm_needs_a_valid_ghost() -> void:
	var m: PlacementMachine = _positioning()
	assert_bool(m.confirm(false)).is_false()
	assert_int(m.state).is_equal(S.POSITIONING)
	assert_bool(m.confirm(true)).is_true()
	assert_int(m.state).is_equal(S.SENT)
	assert_bool(m.confirm(true)).is_false()                 # one in flight


func test_accepted_returns_to_idle_or_positioning_with_repeat() -> void:
	var m: PlacementMachine = _positioning()
	var _c: bool = m.confirm(true)
	assert_bool(m.result(true)).is_true()
	assert_int(m.state).is_equal(S.IDLE)
	var r: PlacementMachine = _positioning(true)
	var _c2: bool = r.confirm(true)
	assert_bool(r.result(true)).is_true()
	assert_int(r.state).is_equal(S.POSITIONING)
	assert_str(String(r.def_id)).is_equal("pylon")
	assert_int(r.cell).is_equal(55)


func test_rejected_returns_to_positioning_even_without_repeat() -> void:
	var m: PlacementMachine = _positioning()
	var _c: bool = m.confirm(true)
	assert_bool(m.result(false)).is_true()
	assert_int(m.state).is_equal(S.POSITIONING)


func test_result_outside_sent_is_ignored() -> void:
	var m: PlacementMachine = _positioning()
	assert_bool(m.result(true)).is_false()
	assert_int(m.state).is_equal(S.POSITIONING)


func test_cancel_from_armed_and_positioning_but_not_sent() -> void:
	var a: PlacementMachine = PlacementMachine.new()
	var _x: bool = a.arm(&"pylon")
	assert_bool(a.cancel()).is_true()
	assert_int(a.state).is_equal(S.IDLE)
	var p: PlacementMachine = _positioning()
	assert_bool(p.cancel()).is_true()
	assert_int(p.state).is_equal(S.IDLE)
	var s: PlacementMachine = _positioning()
	var _c: bool = s.confirm(true)
	assert_bool(s.cancel()).is_false()
	assert_int(s.state).is_equal(S.SENT)
	assert_bool(PlacementMachine.new().cancel()).is_false()


func test_rearm_while_armed_replaces_the_def_and_resets_the_ghost() -> void:
	var m: PlacementMachine = _positioning()
	var _r: bool = m.rotate_by(1)
	assert_bool(m.arm(&"outpost")).is_true()
	assert_int(m.state).is_equal(S.ARMED)
	assert_int(m.rotation).is_equal(0)
	assert_str(String(m.def_id)).is_equal("outpost")
	var _c: bool = m.set_camera(10.0, 4)
	var _s: bool = m.confirm(true)
	assert_bool(m.arm(&"reactor")).is_false()               # not while a command is in flight
