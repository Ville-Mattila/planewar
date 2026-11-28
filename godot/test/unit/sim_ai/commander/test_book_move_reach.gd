extends GdUnitTestSuite
## AI-51 contract (AI-24 review F1; 05 s7.3, R0 B.33 A-162/A-163): a book `order move` to an Outpost site keeps its escort
## inside Outpost presence reach on its nominal MOVE hold orbit, and the presence retry orders an undocked unit first.

const HZ: int = Ai23Kit.HZ


func test_the_nominal_hold_orbit_lies_inside_presence_reach_minus_the_slack() -> void:
	var c: ContentSet = Ai23Kit.content()
	var p: BookParams = Ai23Kit.params()
	var hold: float = float(c.order_rules.raw["hold_orbit_radius_m"])
	var reach: float = c.economy.outpost_presence_radius_m - p.presence_slack_cells * BookParams.cell_m()
	assert_float(BookParams.cell_m()).is_equal_approx(Sphere.PLANET_RADIUS * PI * 0.5 / float(Sphere.GRID_BUILD), 0.001)
	assert_float(p.reach_m(c.economy.outpost_presence_radius_m)).is_equal_approx(reach, 0.001)
	assert_float(p.presence_slack_cells).is_greater_equal(3.0)
	# the unit orbits `hold` m (horizontal) from the order point, `move_agl_m` above the site's ground point
	assert_float(p.orbit_dist_m(hold)).is_equal_approx(sqrt(hold * hold + p.move_agl_m * p.move_agl_m), 0.001)
	assert_float(p.orbit_dist_m(hold)).override_failure_message("orbit %.1f m > reach %.1f m" % [p.orbit_dist_m(hold), reach]).is_less_equal(reach)


func test_from_dict_requires_the_slack_key() -> void:
	var d: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string(Ai23Kit.PARAMS)) as Dictionary).duplicate()
	assert_object(BookParams.from_dict(d)).is_not_null()
	var _e: bool = d.erase("presence_slack_cells")
	assert_object(BookParams.from_dict(d)).is_null()


func _book() -> OpeningBook:
	var errs: Array[String] = []
	var b: OpeningBook = OpeningBook.compile({"id": "retry", "doctrine": "vanguard", "steps": [
		{"do": "order", "kind": "move", "unit": "dart", "to": "outpost_site:home_trap", "when": "t>=9999"},
		{"do": "build", "def": "outpost", "near": "outpost_site:home_trap", "when": "presence"}]}, Ai23Kit.content(), errs)
	assert_object(b).override_failure_message(str(errs)).is_not_null()
	return b


func _rig(seed_value: int, cb: CommanderBrain) -> SimWorld:
	var w: SimWorld = Ai23Kit.world(seed_value, &"cradle", false)
	var d: AiDriver = Ai14Kit.driver(w, true, 3)
	d.set_brain(15, cb, true)
	d.schedule_bot(0, 1)
	return w


func test_the_retry_orders_the_airborne_dart_not_the_docked_one() -> void:
	var book: OpeningBook = _book()
	var cb: CommanderBrain = Ai23Kit.commander(&"cradle", [book])
	var w: SimWorld = _rig(51, cb)
	var home: Vector3 = Ai23Kit.sites().slot_dir(0)
	var docked: int = IntelKit.spawn(w, &"dart", 0, 0, IntelKit.at(w, home, 60.0, 60.0, 5.0))
	var air: int = IntelKit.spawn(w, &"dart", 0, 0, IntelKit.at(w, home, 700.0, 100.0, 250.0))
	var _e: Array[SimEvent] = Ai23Kit.run(w, 4 * HZ)
	var run: BookRun = cb.run_of(0)
	assert_object(run).is_not_null()
	assert_int(run.cursor).is_equal(0)
	# the docked Dart is the nearer one to the site: nearest-only would pick it
	w.store().flags[EntityId.slot(docked)] |= EntityStore.F_DOCKED
	w.store().pos[EntityId.slot(docked)] = IntelKit.at(w, home, 0.0, 0.0, 0.0)
	run.cursor = 1
	var p: BookParams = Ai23Kit.params()
	var tick: int = 5 * HZ
	assert_bool(book._retry_move(1, run, cb.host, tick, HZ, p)).is_false()   # the first call arms the clock
	assert_bool(book._retry_move(1, run, cb.host, tick + int(p.presence_retry_s) * HZ + 1, HZ, p)).is_true()
	var head: OrderSpec = w.view().order_head(air)
	assert_object(head).is_not_null()
	assert_int(head.kind).is_equal(OrderSpec.Kind.MOVE)
	var dh: OrderSpec = w.view().order_head(docked)
	assert_bool(dh == null or dh.kind != OrderSpec.Kind.MOVE).is_true()


func test_a_docked_dart_is_ordered_only_when_no_undocked_one_exists() -> void:
	var book: OpeningBook = _book()
	var cb: CommanderBrain = Ai23Kit.commander(&"cradle", [book])
	var w: SimWorld = _rig(52, cb)
	var home: Vector3 = Ai23Kit.sites().slot_dir(0)
	var docked: int = IntelKit.spawn(w, &"dart", 0, 0, IntelKit.at(w, home, 60.0, 60.0, 5.0))
	var _e: Array[SimEvent] = Ai23Kit.run(w, 4 * HZ)
	w.store().flags[EntityId.slot(docked)] |= EntityStore.F_DOCKED
	var run: BookRun = cb.run_of(0)
	run.cursor = 1
	var p: BookParams = Ai23Kit.params()
	var _a: bool = book._retry_move(1, run, cb.host, 5 * HZ, HZ, p)
	assert_bool(book._retry_move(1, run, cb.host, 5 * HZ + int(p.presence_retry_s) * HZ + 1, HZ, p)).is_true()
	var head: OrderSpec = w.view().order_head(docked)
	assert_object(head).is_not_null()
	assert_int(head.kind).is_equal(OrderSpec.Kind.MOVE)
