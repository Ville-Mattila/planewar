extends GdUnitTestSuite
## UX-19 overlay scene: instantiates headless, takes the widget data and reports what it shows (scenes/ui/threat_overlay.tscn).

const SCENE: String = "res://scenes/ui/threat_overlay.tscn"
const R: float = Sphere.PLANET_RADIUS


func _make() -> ThreatOverlayView:
	var s: ThreatOverlayView = (load(SCENE) as PackedScene).instantiate() as ThreatOverlayView
	add_child(s)
	return s


func test_scene_instantiates_and_starts_empty() -> void:
	var o: ThreatOverlayView = _make()
	assert_object(o).is_not_null()
	assert_int(o.lines().size()).is_equal(0)
	assert_int(o.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	o.free()


func test_lines_list_every_active_widget_in_a_fixed_order() -> void:
	var o: ThreatOverlayView = _make()
	var t: ThreatData = ThreatData.new()
	t.rocket_lock = true
	t.rockets = 1
	o.set_threats(t)
	var h: TowerHint = TowerHint.new()
	h.def = &"flak_battery"
	h.rule = TowerHint.Rule.BELOW
	h.limit_m = 150.0
	o.set_hints([h] as Array[TowerHint])
	var p: PendingLine = PendingLine.new()
	p.kind = OrderSpec.Kind.HOLD
	p.issuer_name = "Aino"
	o.set_pending(p)
	var toast: HandoverToast = HandoverToast.new()
	toast.requester_name = "Aino"
	toast.entity = 2
	toast.left_s = 5.0
	o.set_toast(toast)
	var ls: PackedStringArray = o.lines()
	assert_int(ls.size()).is_equal(4)
	assert_str(ls[0]).is_equal(tr(&"hud.threat.lock"))
	assert_str(ls[1]).contains("150")
	assert_str(ls[2]).contains("Aino")
	assert_str(ls[3]).contains("Aino")
	o.free()


func test_font_never_below_the_9_du_floor() -> void:
	var o: ThreatOverlayView = _make()
	o.profile = UiScale.Profile.COMPACT
	assert_int(o.font_size()).is_greater_equal(int(HudMath.param("font_du_min")))
	o.free()


func test_draw_runs_with_every_widget_visible() -> void:
	var r: Result = ContentDB.load_all()
	assert_bool(r.ok).is_true()
	var o: ThreatOverlayView = _make()
	var v: HudScenarioView = HudScenarioView.new()
	v.add(1, &"dart", 0, Vector3(0.0, R + 300.0, 0.0), 2, 0)
	v.add(2, &"dart", 1, Vector3(500.0, R + 400.0, -300.0))
	v.add(4, &"bomber", 0, Vector3(50.0, R + 100.0, 0.0), 2, 1)
	v.add(20, &"flak_battery", 1, Vector3(0.0, R, -800.0))
	v.rockets_at[1] = 1
	var names: Dictionary = {0: "Ville", 1: "Aino"}
	o.set_threats(ThreatData.from_view(v, 1, 0))
	o.set_hints(TowerHint.from_view(v, 1, 0, 300.0))
	var spec: OrderSpec = OrderSpec.make(OrderSpec.Kind.HOLD)
	spec.issuer = 1
	v.pending[1] = spec
	o.set_pending(PendingLine.from_view(v, 1, names, Callable()))
	var toast: HandoverToast = HandoverToast.new()
	var e: SimEvent = SimEvent.new()
	e.kind = SimEvent.Kind.POSSESS_REQUESTED
	e.a = 1
	e.b = 1
	var _opened: bool = toast.on_event(e, v, 0, names)
	o.set_toast(toast)
	var bp: BeaconPip = BeaconPip.new()
	bp.x = 20.0
	o.set_beacons([bp] as Array[BeaconPip])
	o.set_badges(PilotedBadges.from_view(v, 0, 0, names), PackedVector2Array([Vector2(300.0, 200.0)]))
	var drawn: Array[int] = [0]
	o.draw.connect(func() -> void: drawn[0] += 1)
	o.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(drawn[0]).is_greater(0)
	assert_int(o.lines().size()).is_equal(4)
	o.free()
