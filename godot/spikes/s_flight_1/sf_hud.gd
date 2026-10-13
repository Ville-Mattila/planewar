class_name SfHud extends Control
## Chase HUD stub (06 s6, Sonnet's lane owns the real one): boresight, mouse-aim circle, lead pips, target and
## pad markers, speed/altitude/AoA block, consumables, landing guide gauges (06 s6.4: vertical speed 8/15,
## horizontal 15/25, nose from vertical 25/45; green safe, amber damage, red destruction), bomb time to
## impact, toasts and the forced-release message (01 s3.1.5).

const GREEN: Color = Color(0.3, 1.0, 0.4)
const AMBER: Color = Color(1.0, 0.75, 0.2)
const RED: Color = Color(1.0, 0.3, 0.25)
const WHITE: Color = Color(1, 1, 1, 0.9)

var world: SfWorld
var view: SfView
var cam: SfChaseCamera
var inp: SfInput
var defs: SfDefs
var hint: String = ""
var fps_text: String = ""
var _toast: String = ""
var _toast_col: Color = WHITE
var _toast_t: float
var _fs: int = 14


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func toast(text: String, col: Color, seconds: float) -> void:
	_toast = text
	_toast_col = col
	_toast_t = seconds


func _process(delta: float) -> void:
	_toast_t = maxf(_toast_t - delta, 0.0)
	_fs = maxi(int(size.y / 48.0), 12)
	queue_redraw()


func _draw() -> void:
	if world == null:
		return
	var font: Font = ThemeDB.fallback_font
	_draw_markers(font)
	_draw_reticle()
	_draw_block(font)
	_draw_landing_guide(font)
	if _toast_t > 0.0:
		draw_string(font, Vector2(0.0, size.y * 0.22), _toast, HORIZONTAL_ALIGNMENT_CENTER, size.x, _fs + 8, _toast_col)
	if world.state == SfWorld.State.FORCED:
		draw_string(font, Vector2(0.0, size.y * 0.30), "Uplink lost above %d m. Autopilot is descending." %
			int(defs.rules.ceiling_hard_m), HORIZONTAL_ALIGNMENT_CENTER, size.x, _fs + 2, AMBER)
	elif world.state == SfWorld.State.DOCKED:
		draw_string(font, Vector2(0.0, size.y * 0.30), "DOCKED - servicing. Thrust to launch.",
			HORIZONTAL_ALIGNMENT_CENTER, size.x, _fs + 2, GREEN)
	draw_string(font, Vector2(8.0, size.y - 8.0), hint, HORIZONTAL_ALIGNMENT_LEFT, size.x - 16.0, _fs - 2,
		Color(1, 1, 1, 0.6))


func _project(p: Vector3) -> Vector3:
	# x, y screen; z = 1 when in front of the camera
	if cam.is_position_behind(p):
		return Vector3(0, 0, 0)
	var s: Vector2 = cam.unproject_position(p)
	return Vector3(s.x, s.y, 1.0)


func _draw_reticle() -> void:
	if world.state == SfWorld.State.DEAD:
		return
	var bore: Vector3 = _project(view.render_p + view.render_fwd * defs.gun_range_m)
	if bore.z > 0.0:
		var c: Vector2 = Vector2(bore.x, bore.y)
		draw_arc(c, 10.0, 0.0, TAU, 24, WHITE, 2.0)
		draw_line(c + Vector2(-22, 0), c + Vector2(-12, 0), WHITE, 2.0)
		draw_line(c + Vector2(12, 0), c + Vector2(22, 0), WHITE, 2.0)
	if inp.aim != Vector3.ZERO:
		var a: Vector3 = _project(view.render_p + inp.aim * defs.gun_range_m)
		if a.z > 0.0:
			draw_arc(Vector2(a.x, a.y), 5.0, 0.0, TAU, 16, Color(0.4, 0.9, 1.0), 2.0)


func _draw_markers(font: Font) -> void:
	var a: SfArena = world.arena
	var range_m: float = SfDefs.num(defs.render, "marker_range_m")
	for i: int in a.t_pos.size():
		if not a.alive(i):
			continue
		var dist: float = view.render_p.distance_to(a.t_pos[i])
		if dist > range_m:
			continue
		var sp: Vector3 = _project(a.t_pos[i])
		if sp.z <= 0.0:
			continue
		var c: Vector2 = Vector2(sp.x, sp.y)
		var col: Color = RED if a.t_ground[i] == 0 else AMBER
		draw_rect(Rect2(c - Vector2(9, 9), Vector2(18, 18)), col, false, 1.5)
		draw_string(font, c + Vector2(12, -4), "%d" % int(dist), HORIZONTAL_ALIGNMENT_LEFT, -1, _fs - 3, col)
		if a.t_ground[i] == 0 and dist <= defs.gun_range_m:
			var l: Vector3 = _project(SfArena.lead(world.s.p, world.s.v, a.t_pos[i], defs.slug.speed_mps))
			if l.z > 0.0:
				draw_circle(Vector2(l.x, l.y), 3.5, col)
	var pp: Vector3 = _project(world.pad_p)
	var pd: float = view.render_p.distance_to(world.pad_p)
	if pp.z > 0.0:
		var c2: Vector2 = Vector2(pp.x, pp.y)
		draw_polyline(PackedVector2Array([c2 + Vector2(0, -12), c2 + Vector2(12, 0), c2 + Vector2(0, 12),
			c2 + Vector2(-12, 0), c2 + Vector2(0, -12)]), Color(0.3, 0.9, 1.0), 2.0)
		draw_string(font, c2 + Vector2(14, 4), "PAD %d m" % int(pd), HORIZONTAL_ALIGNMENT_LEFT, -1, _fs - 2,
			Color(0.3, 0.9, 1.0))
	else:
		var dir: Vector3 = (world.pad_p - view.render_p)
		var right: Vector3 = cam.global_transform.basis.x
		var up: Vector3 = cam.global_transform.basis.y
		var v2: Vector2 = Vector2(dir.dot(right), -dir.dot(up)).normalized()
		var c3: Vector2 = size * 0.5 + v2 * minf(size.x, size.y) * 0.4
		draw_circle(c3, 6.0, Color(0.3, 0.9, 1.0))
		draw_string(font, c3 + Vector2(10, 4), "PAD %d m" % int(pd), HORIZONTAL_ALIGNMENT_LEFT, -1, _fs - 2,
			Color(0.3, 0.9, 1.0))


func _draw_block(font: Font) -> void:
	var s: ShipState = world.s
	var n: Vector3 = s.p.normalized()
	var lines: PackedStringArray = PackedStringArray()
	var boost: String = "ACTIVE" if s.boost_time > 0.0 else ("ready" if s.boost_time <= -defs.ship.boost_cooldown_s
		else "%.0fs" % (s.boost_time + defs.ship.boost_cooldown_s))
	var flip: String = "ready" if s.flip_time <= -defs.ship.flip_cooldown_s else "cool"
	var _l: bool = lines.push_back("SPD %3d m/s   fwd %3d" % [int(s.v.length()), int(s.v.dot(s.fwd))])
	_l = lines.push_back("ALT %4d m   VS %+5.1f" % [int(world.altitude()), s.v.dot(n)])
	var aoa: String = ("%+5.1f deg" % world.aoa_deg()) if s.v.length() > SfDefs.num(defs.camera, "look_vel_min_mps") else "-"
	_l = lines.push_back("AoA %s   pitch %+3d" % [aoa, int(rad_to_deg(asin(clampf(s.fwd.dot(n), -1.0, 1.0))))])
	_l = lines.push_back("THR %3d%%   FUEL %3d%%   HP %3d" % [int(world.input.thrust * 100.0), int(100.0 * s.fuel / defs.ship.fuel_s), int(world.hp)])
	_l = lines.push_back("AMMO %d   BOMB %d   BOOST %s   FLIP %s" % [world.ammo, world.bombs, boost, flip])
	_l = lines.push_back("%s %s  lift %s%s" % [SfInput.CLASS_NAMES[inp.input_class], "FULL" if inp.current_tier() == SfInput.Tier.FULL else "RAW",
		defs.rules.lift_model, "  ASSIST" if world.assist_on else ""])
	_l = lines.push_back(fps_text)
	if world.arena.pred_valid and world.bombs > 0:
		_l = lines.push_back("BOMB impact in %.1f s%s" % [world.arena.pred_t, "  ON TARGET" if world.arena.pred_on_target else ""])
	var y: float = 8.0 + float(_fs)
	for t: String in lines:
		draw_string(font, Vector2(10.0, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, WHITE)
		y += float(_fs) + 4.0


# 06 s6.4: shown when the pad is <= 1,500 m away and below 400 m AGL (or fuel < 25 %).
func _draw_landing_guide(font: Font) -> void:
	var s: ShipState = world.s
	if world.state != SfWorld.State.FLYING:
		return
	var dist: float = s.p.distance_to(world.pad_p)
	if dist > 1500.0 or (world.altitude() > 400.0 and s.fuel > 0.25 * defs.ship.fuel_s):
		return
	var n: Vector3 = world.pad_n
	var c: FlightCommonDef = defs.common
	var vv: float = -s.v.dot(n)
	var vh: float = (s.v - n * s.v.dot(n)).length()
	var tilt: float = rad_to_deg(s.fwd.angle_to(n))
	var x0: float = size.x - 380.0
	var y0: float = size.y * 0.36
	_gauge(font, Vector2(x0, y0), "SINK", vv, c.landing_safe_v_vert, c.landing_damage_v_vert)
	_gauge(font, Vector2(x0 + 120.0, y0), "DRIFT", vh, c.landing_safe_v_hor, c.landing_damage_v_hor)
	_gauge(font, Vector2(x0 + 240.0, y0), "NOSE", tilt, c.landing_safe_pitch_deg, SfDefs.num(defs.landing, "tilt_damage_deg"))
	var rel: Vector3 = s.p - world.pad_p
	var off: float = (rel - n * rel.dot(n)).length()
	var msg: String = "pad %d m  off-centre %.1f m" % [int(dist), off]
	if dist <= c.auto_dock_radius_m:
		msg += "   DOCK: hold F / X / DOCK" if inp.current_tier() == SfInput.Tier.FULL else "   (RAW: manual landing)"
	elif dist < 400.0 and tilt > 60.0:
		msg += "   pitch up, hold thrust"
	draw_string(font, Vector2(x0, y0 + 70.0), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs - 1, WHITE)


func _gauge(font: Font, at: Vector2, label: String, value: float, safe: float, dmg: float) -> void:
	var w: float = 100.0
	var full: float = dmg * 1.4
	draw_rect(Rect2(at, Vector2(w * safe / full, 12.0)), Color(GREEN, 0.5), true)
	draw_rect(Rect2(at + Vector2(w * safe / full, 0.0), Vector2(w * (dmg - safe) / full, 12.0)), Color(AMBER, 0.5), true)
	draw_rect(Rect2(at + Vector2(w * dmg / full, 0.0), Vector2(w * (full - dmg) / full, 12.0)), Color(RED, 0.5), true)
	var x: float = clampf(value / full, 0.0, 1.0) * w
	var col: Color = GREEN if value <= safe else (AMBER if value <= dmg else RED)
	draw_rect(Rect2(at + Vector2(x - 2.0, -4.0), Vector2(4.0, 20.0)), col, true)
	draw_string(font, at + Vector2(0.0, 32.0), "%s %.1f" % [label, value], HORIZONTAL_ALIGNMENT_LEFT, -1, _fs - 2, col)
