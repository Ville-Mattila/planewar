class_name FlightInstruments extends Control
## Chase-tier flight instruments (docs/06 s6.1-6.2): pitch ladder with bank, limb tick, heading tape,
## speed and altitude blocks with band, uplink meter. Draws from a FlightHudData; all maths in HudMath.
## Sizes are design units (du); COMPACT enlarges the font to keep >= font_du_min on small screens.

const BAND_KEYS: Array[StringName] = [&"hud.band.deck", &"hud.band.low", &"hud.band.high", &"hud.band.fade"]

var data: FlightHudData = FlightHudData.new()
var profile: UiScale.Profile = UiScale.Profile.REGULAR
var time_s: float


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_data(d: FlightHudData) -> void:
	data = d
	queue_redraw()


func _process(delta: float) -> void:
	time_s += delta
	if data.link_visible:
		queue_redraw()


func font_size() -> int:
	var base: float = HudMath.param("font_du")
	if profile == UiScale.Profile.COMPACT:
		base += 2.0
	return int(maxf(base, HudMath.param("font_du_min")))


func _draw() -> void:
	var c: Vector2 = size * 0.5
	_draw_ladder(c)
	_draw_tape(Vector2(c.x, 0.0))
	_draw_blocks()
	if data.link_visible:
		_draw_uplink(Vector2(c.x, size.y - 4.0 * font_size()))


func _text(pos: Vector2, s: String, col: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, w: float = -1.0) -> void:
	draw_string(ThemeDB.fallback_font, pos, s, align, w, font_size(), col)


func _draw_ladder(c: Vector2) -> void:
	var ppd: float = HudMath.param("ladder_px_per_deg")
	var half_w: float = HudMath.param("ladder_width_du") * 0.5
	var lw: float = HudMath.param("line_du")
	var half: float = HudMath.param("ladder_half_range_deg")
	draw_set_transform(c, data.bank_rad, Vector2.ONE)
	var marks: PackedFloat32Array = HudMath.ladder_marks(data.pitch_rad, HudMath.param("ladder_step_deg"), half)
	for m: float in marks:
		var y: float = HudMath.ladder_y(m, data.pitch_rad, ppd)
		var level: bool = is_zero_approx(m)
		var w: float = half_w if level else half_w * 0.5
		var col: Color = UiTokens.UI_TEXT if level else UiTokens.UI_TEXT_DIM
		draw_line(Vector2(-w, y), Vector2(-w * 0.3, y), col, lw)
		draw_line(Vector2(w * 0.3, y), Vector2(w, y), col, lw)
		if not level:
			_text(Vector2(w + 4.0, y + font_size() * 0.35), str(int(absf(m))), col)
	var ly: float = HudMath.limb_y(data.pitch_rad, data.alt_m, ppd)
	draw_line(Vector2(-half_w * 0.2, ly), Vector2(half_w * 0.2, ly), UiTokens.UI_ACCENT, lw)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_line(c + Vector2(-10, 0), c + Vector2(-4, 0), UiTokens.UI_TEXT, lw)
	draw_line(c + Vector2(4, 0), c + Vector2(10, 0), UiTokens.UI_TEXT, lw)


func _draw_tape(top: Vector2) -> void:
	var w: float = HudMath.param("tape_width_du")
	var span: float = HudMath.param("tape_deg_span")
	var tick: float = HudMath.param("tape_tick_deg")
	var fs: float = font_size()
	if data.pole or is_nan(data.heading):
		_text(top + Vector2(-w * 0.5, fs + 2.0), tr(&"hud.heading.pole"), UiTokens.UI_WARN, HORIZONTAL_ALIGNMENT_CENTER, w)
		return
	var h: float = data.heading
	var first: float = floorf((h - span * 0.5) / tick) * tick
	var m: float = first
	while m <= h + span * 0.5:
		var x: float = top.x + HudMath.tape_x(m, h, w, span)
		draw_line(Vector2(x, top.y + fs + 6.0), Vector2(x, top.y + fs + 12.0), UiTokens.UI_TEXT_DIM, 1.0)
		var wm: int = int(HudMath.wrap_deg(m))
		if wm % 30 == 0:
			var label: String = tr(&"hud.heading.north") if wm == 0 else str(int(float(wm) / 10.0))
			_text(Vector2(x - 12.0, top.y + fs + 2.0), label, UiTokens.UI_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, 24.0)
		m += tick
	_text(Vector2(top.x - 20.0, top.y + fs * 2.0 + 22.0), "%03d" % int(roundf(h)), UiTokens.UI_TEXT, HORIZONTAL_ALIGNMENT_CENTER, 40.0)
	if not is_nan(data.home_bearing):
		var hx: float = clampf(HudMath.tape_x(data.home_bearing, h, w, span), -w * 0.5, w * 0.5)
		draw_rect(Rect2(Vector2(top.x + hx - 3.0, top.y + fs + 14.0), Vector2(6, 6)), UiTokens.RELATION_ALLY)


func _band_color() -> Color:
	match data.band:
		HudMath.Band.DECK:
			return UiTokens.UI_WARN
		HudMath.Band.LOW:
			return UiTokens.UI_TEXT
		HudMath.Band.HIGH:
			return UiTokens.UI_ACCENT
	return UiTokens.UI_WARN


## Left (speed) and right (band, altitude) readout rects in this control's local space; the control
## is a child of HudRoot, so local space is inside the safe rect.
func readout_rects() -> Array[Rect2]:
	var fs: float = font_size()
	var w: float = HudMath.param("readout_width_du")
	var y: float = size.y * 0.5
	return [Rect2(Vector2(0.0, y - fs), Vector2(w, fs * 1.4)),
		Rect2(Vector2(size.x - w, y - fs * 2.2), Vector2(w, fs * 4.9))]


func _draw_blocks() -> void:
	var fs: float = font_size()
	var y: float = size.y * 0.5
	var r: Array[Rect2] = readout_rects()
	_text(Vector2(0.0, y), tr(&"hud.speed") + " " + str(int(roundf(data.speed_mps))), UiTokens.UI_TEXT)
	var x: float = r[1].position.x
	var w: float = r[1].size.x
	_text(Vector2(x, y - fs * 1.2), tr(BAND_KEYS[data.band]), _band_color(), HORIZONTAL_ALIGNMENT_RIGHT, w)
	_text(Vector2(x, y), tr(&"hud.alt") + " " + str(int(roundf(data.alt_m))), UiTokens.UI_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, w)
	_text(Vector2(x, y + fs * 1.2), tr(&"hud.agl") + " " + str(int(roundf(data.agl_m))), UiTokens.UI_TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT, w)
	_text(Vector2(x, y + fs * 2.4), tr(&"hud.vs") + " " + "%+d" % int(roundf(data.vs_mps)), UiTokens.UI_TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT, w)


func _draw_uplink(at: Vector2) -> void:
	var w: float = 120.0
	var pulse: float = HudMath.uplink_pulse(data.alt_m, time_s)
	var col: Color = UiTokens.UI_WARN.lerp(UiTokens.UI_DANGER, pulse) if pulse > 0.0 else UiTokens.UI_WARN
	var label: String = tr(&"hud.uplink.lost") if data.link_lost else tr(&"hud.uplink") + " %d%%" % int(roundf(data.link01 * 100.0))
	_text(at + Vector2(-w, -4.0), label, col, HORIZONTAL_ALIGNMENT_CENTER, w * 2.0)
	draw_rect(Rect2(at + Vector2(-w * 0.5, 0.0), Vector2(w, 6.0)), UiTokens.UI_LINE, false, 1.0)
	draw_rect(Rect2(at + Vector2(-w * 0.5, 0.0), Vector2(w * data.link01, 6.0)), col)
