extends GdUnitTestSuite
## PickMath, SelectionSet, ControlGroups, RallyMath (UX-20; docs/06 s7.2).


func test_pick_radii_per_class() -> void:
	assert_float(PickMath.radius_du(PickMath.PickDevice.TOUCH)).is_equal(22.0)
	assert_float(PickMath.radius_du(PickMath.PickDevice.POINTER)).is_equal(10.0)
	assert_float(PickMath.radius_du(PickMath.PickDevice.GAMEPAD)).is_equal(28.0)


func test_pick_radius_limits() -> void:
	var s: PackedVector2Array = PackedVector2Array([Vector2(21.0, 0.0)])
	var c: PackedInt32Array = PackedInt32Array([0])
	var d: PackedFloat32Array = PackedFloat32Array([1.0])
	assert_int(PickMath.pick(Vector2.ZERO, s, c, d, PickMath.PickDevice.TOUCH)).is_equal(0)
	assert_int(PickMath.pick(Vector2.ZERO, s, c, d, PickMath.PickDevice.POINTER)).is_equal(-1)
	s[0] = Vector2(27.0, 0.0)
	assert_int(PickMath.pick(Vector2.ZERO, s, c, d, PickMath.PickDevice.GAMEPAD)).is_equal(0)
	assert_int(PickMath.pick(Vector2.ZERO, s, c, d, PickMath.PickDevice.TOUCH)).is_equal(-1)


func test_pick_nearest_wins() -> void:
	var s: PackedVector2Array = PackedVector2Array([Vector2(8.0, 0.0), Vector2(3.0, 0.0)])
	var c: PackedInt32Array = PackedInt32Array([PickMath.Category.OWN_UNIT, PickMath.Category.OTHER])
	var d: PackedFloat32Array = PackedFloat32Array([1.0, 1.0])
	assert_int(PickMath.pick(Vector2.ZERO, s, c, d, PickMath.PickDevice.POINTER)).is_equal(1)


func test_pick_tie_category_then_depth() -> void:
	var s: PackedVector2Array = PackedVector2Array([Vector2(4.0, 0.0), Vector2(4.0, 0.0), Vector2(4.0, 0.0)])
	var c: PackedInt32Array = PackedInt32Array([PickMath.Category.OTHER, PickMath.Category.OWN_STRUCTURE, PickMath.Category.OWN_UNIT])
	var d: PackedFloat32Array = PackedFloat32Array([1.0, 1.0, 9.0])
	assert_int(PickMath.pick(Vector2.ZERO, s, c, d, PickMath.PickDevice.POINTER)).is_equal(2)
	c = PackedInt32Array([PickMath.Category.OTHER, PickMath.Category.OTHER, PickMath.Category.OTHER])
	d = PackedFloat32Array([5.0, 2.0, 9.0])
	assert_int(PickMath.pick(Vector2.ZERO, s, c, d, PickMath.PickDevice.POINTER)).is_equal(1)


func test_pick_empty() -> void:
	assert_int(PickMath.pick(Vector2.ZERO, PackedVector2Array(), PackedInt32Array(), PackedFloat32Array(), PickMath.PickDevice.TOUCH)).is_equal(-1)


func test_paint_radius_growth() -> void:
	assert_float(PickMath.paint_radius_du(0.0)).is_equal(30.0)
	assert_float(PickMath.paint_radius_du(0.6)).is_equal_approx(135.0, 0.001)
	assert_float(PickMath.paint_radius_du(1.2)).is_equal(240.0)
	assert_float(PickMath.paint_radius_du(5.0)).is_equal(240.0)


func test_box_units_only_else_structures() -> void:
	var ids: PackedInt32Array = PackedInt32Array([1, 2, 3])
	assert_array(PickMath.box_filter(ids, PackedByteArray([0, 1, 0]))).contains_exactly([2])
	assert_array(PickMath.box_filter(ids, PackedByteArray([0, 0, 0]))).contains_exactly([1, 2, 3])


func test_same_type() -> void:
	var r: PackedInt32Array = PickMath.same_type(PackedInt32Array([1, 2, 3]), PackedInt32Array([7, 8, 7]), 7)
	assert_array(r).contains_exactly([1, 3])


func test_selection_set_ops() -> void:
	var s: SelectionSet = SelectionSet.new()
	s.set_ids(PackedInt32Array([1, 2, 2, 3]))
	assert_int(s.size()).is_equal(3)
	s.toggle(2)
	assert_bool(s.has(2)).is_false()
	s.add(9)
	s.add(9)
	assert_int(s.size()).is_equal(3)
	s.prune(func(id: int) -> bool: return id != 9)
	assert_bool(s.has(9)).is_false()
	s.clear()
	assert_int(s.size()).is_equal(0)


func test_selection_chunks() -> void:
	var s: SelectionSet = SelectionSet.new()
	var v: PackedInt32Array = PackedInt32Array()
	for i: int in 33:
		v.append(i + 1)
	s.set_ids(v)
	var ch: Array[PackedInt32Array] = s.chunks()
	assert_int(ch.size()).is_equal(2)
	assert_int(ch[0].size()).is_equal(32)
	assert_int(ch[1].size()).is_equal(1)


func test_control_groups() -> void:
	var g: ControlGroups = ControlGroups.new()
	assert_int(g.count()).is_equal(10)
	g.assign(3, PackedInt32Array([4, 5, 6]))
	g.add_to(3, PackedInt32Array([6, 7]))
	assert_array(g.get_group(3)).contains_exactly([4, 5, 6, 7])
	var live: PackedInt32Array = g.recall(3, func(id: int) -> bool: return id != 5)
	assert_array(live).contains_exactly([4, 6, 7])
	assert_array(g.get_group(3)).contains_exactly([4, 6, 7])
	assert_int(g.get_group(99).size()).is_equal(0)
	g.assign(-1, PackedInt32Array([1]))
	g.clear()
	assert_int(g.get_group(3).size()).is_equal(0)


func test_rally_line() -> void:
	var a: Vector3 = Vector3(0.0, 6000.0, 0.0)
	var b: Vector3 = Vector3(6000.0, 0.0, 0.0)
	var pts: PackedVector3Array = RallyMath.line_points(a, b)
	assert_int(pts.size()).is_equal(14)
	assert_vector(pts[0]).is_equal_approx(a, Vector3(0.01, 0.01, 0.01))
	assert_vector(pts[12]).is_equal_approx(b, Vector3(0.01, 0.01, 0.01))
	assert_float(pts[13].length()).is_equal_approx(6006.0, 0.01)
	assert_float(pts[6].length()).is_equal_approx(6000.0, 0.01)
	assert_int(RallyMath.line_points(Vector3.ZERO, b).size()).is_equal(0)
	assert_int(RallyMath.line_points(a, a).size()).is_equal(14)
