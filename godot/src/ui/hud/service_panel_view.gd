class_name ServicePanelView extends Control
## DOCKED service panel (docs/06 s6.4): three service bars (fuel, ammo, repair), the waiting-for-Ice / Ore note and
## "thrust to launch". Draws a LandingHudData; nothing is computed here.

const BARS: Array[StringName] = [&"hud.service.fuel", &"hud.service.ammo", &"hud.service.repair"]

var data: LandingHudData = LandingHudData.new()
var profile: UiScale.Profile = UiScale.Profile.REGULAR


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_data(d: LandingHudData) -> void:
	data = d
	visible = d.docked
	queue_redraw()


## The bar fills in display order (fuel, ammo, repair).
func fills() -> PackedFloat32Array:
	return PackedFloat32Array([data.service.x, data.service.y, data.service.z])


func _draw() -> void:
	if not data.docked:
		return
	var fs: int = HudText.font_size(profile)
	var w: float = HudMath.param("service_bar_width_du")
	var f: PackedFloat32Array = fills()
	var step: float = float(fs) * 2.2
	for i: int in BARS.size():
		var y: float = float(i) * step
		var col: Color = UiTokens.UI_OK if f[i] >= 1.0 else UiTokens.RES_ICE
		HudText.text(self, Vector2(0.0, y + fs), tr(BARS[i]), UiTokens.UI_TEXT, fs)
		HudText.bar(self, Rect2(Vector2(float(fs) * 5.0, y + 2.0), Vector2(w, float(fs) * 0.8)), f[i], col)
	var y2: float = float(BARS.size()) * step + float(fs)
	if data.waiting != 0:
		var key: StringName = &"hud.service.wait_ice" if data.waiting == 1 else &"hud.service.wait_ore"
		HudText.text(self, Vector2(0.0, y2), tr(key), UiTokens.UI_WARN, fs)
		y2 += step
	HudText.text(self, Vector2(0.0, y2), tr(&"hud.service.launch"), UiTokens.UI_ACCENT, fs)
