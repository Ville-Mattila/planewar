class_name LandingGuideView extends Control
## Landing guide (docs/06 s6.4): vertical speed, horizontal speed and "nose from vertical" gauges (green safe, amber
## damage, red destruction), the flare cue, and in the hover phase the pad ring with a drift arrow. All numbers in
## LandingMath / hud.json; this script only draws a LandingHudData.

const GAUGE_UNIT: Dictionary = {"vert": "mps", "horiz": "mps", "nose": "deg"}

var data: LandingHudData = LandingHudData.new()
var profile: UiScale.Profile = UiScale.Profile.REGULAR


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_data(d: LandingHudData) -> void:
	data = d
	visible = d.visible and not d.docked
	queue_redraw()


func _draw() -> void:
	if not data.visible or data.docked:
		return
	var fs: int = HudText.font_size(profile)
	var w: float = HudMath.param("gauge_width_du")
	var step: float = float(fs) * 2.4
	_gauge(0, &"hud.land.vert", data.v_vert, "vert", LandingMath.zone_vert(data.v_vert), fs, step)
	_gauge(1, &"hud.land.horiz", data.v_horiz, "horiz", LandingMath.zone_horiz(data.v_horiz), fs, step)
	_gauge(2, &"hud.land.nose", data.nose_deg, "nose", LandingMath.zone_nose(data.nose_deg), fs, step)
	var y: float = 3.0 * step + float(fs)
	if data.pad_occupied:
		HudText.text(self, Vector2(0.0, y), tr(&"hud.land.occupied"), UiTokens.UI_TEXT_DIM, fs)
	elif data.phase == LandingMath.Phase.FLARE:
		HudText.text(self, Vector2(0.0, y), tr(&"hud.land.flare"), UiTokens.UI_ACCENT, fs)
	elif data.phase == LandingMath.Phase.HOVER:
		HudText.text(self, Vector2(0.0, y), tr(&"hud.land.hover"), UiTokens.UI_ACCENT, fs)
		_draw_pad_ring(Vector2(w + 60.0, step))


func _gauge(row: int, key: StringName, value: float, kind: String, z: LandingMath.Zone, fs: int, step: float) -> void:
	var safe: float = HudMath.param("gauge_%s_safe_%s" % [kind, GAUGE_UNIT[kind]])
	var damage: float = HudMath.param("gauge_%s_damage_%s" % [kind, GAUGE_UNIT[kind]])
	var at: Vector2 = Vector2(0.0, float(row) * step)
	var col: Color = LandingMath.zone_color(z)
	HudText.text(self, at + Vector2(0.0, fs), tr(key) + " " + str(int(roundf(value))), col, fs)
	HudText.bar(self, Rect2(at + Vector2(0.0, fs + 3.0), Vector2(HudMath.param("gauge_width_du"), HudMath.param("gauge_height_du"))),
			LandingMath.fill01(value, damage), col, LandingMath.safe_tick01(safe, damage))


func _draw_pad_ring(c: Vector2) -> void:
	var r: float = HudMath.param("drift_arrow_du")
	var col: Color = UiTokens.UI_TEXT_DIM if data.pad_occupied else UiTokens.UI_OK
	draw_arc(c, r, 0.0, TAU, 32, col, HudMath.param("line_du"))
	if data.drift != Vector2.ZERO:
		draw_line(c, c + data.drift, UiTokens.UI_WARN, HudMath.param("line_du") + 1.0)
		draw_circle(c + data.drift, 2.0, UiTokens.UI_WARN)
