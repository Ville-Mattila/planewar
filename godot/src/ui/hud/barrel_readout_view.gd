class_name BarrelReadoutView extends Control
## Chase HUD barrel elevation readout (UX-49): "ELEV 12" with a bar and the def's min and max as end marks.
## Draws a BarrelReadoutData; draws nothing when it is not shown.

var data: BarrelReadoutData = BarrelReadoutData.new()
var profile: UiScale.Profile = UiScale.Profile.REGULAR


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_data(d: BarrelReadoutData) -> void:
	data = d
	queue_redraw()


## Text lines: the elevation label with the value, then the min and max end marks.
func lines() -> PackedStringArray:
	if not data.shown:
		return PackedStringArray()
	return PackedStringArray([tr(&"hud.barrel") + " " + str(data.deg) + "°", str(data.min_deg), str(data.max_deg)])


func _draw() -> void:
	var ls: PackedStringArray = lines()
	if ls.is_empty():
		return
	var fs: int = HudText.font_size(profile)
	var w: float = HudMath.param("barrel_bar_du")
	var bar: Rect2 = Rect2(0.0, float(fs) * 1.6, w, HudMath.param("barrel_bar_h_du"))
	HudText.text(self, Vector2(0.0, float(fs)), ls[0], UiTokens.UI_TEXT, fs)
	HudText.bar(self, bar, data.fill01, UiTokens.UI_ACCENT)
	var y: float = bar.end.y + float(fs) * 1.1
	HudText.text(self, Vector2(0.0, y), ls[1], UiTokens.UI_TEXT_DIM, fs)
	HudText.text(self, Vector2(w, y), ls[2], UiTokens.UI_TEXT_DIM, fs, HORIZONTAL_ALIGNMENT_RIGHT)
