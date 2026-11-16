extends GdUnitTestSuite
## UX-19 overlay scene: instantiates headless, takes the widget data and reports what it shows (scenes/ui/threat_overlay.tscn).

const SCENE: String = "res://scenes/ui/threat_overlay.tscn"
const R: float = 6000.0


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
