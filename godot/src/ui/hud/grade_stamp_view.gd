class_name GradeStampView extends Control
## Grade stamp (docs/06 s6.4): the LandingGrade of a LANDING event with its points, the hot multiplier and the
## dead-stick bonus (A-121), shown for hud.json `stamp_hold_s`, then hidden. The Sortie Card follows (UX-22).

signal finished

var stamp: LandingStamp = null
var profile: UiScale.Profile = UiScale.Profile.REGULAR
var left_s: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## Shows the stamp built from `e`; ignores anything that is not a LANDING event. Returns whether it showed.
func show_event(e: SimEvent) -> bool:
	var s: LandingStamp = LandingStamp.from_event(e)
	if s == null:
		return false
	stamp = s
	left_s = HudMath.param("stamp_hold_s")
	visible = true
	queue_redraw()
	return true


func _process(delta: float) -> void:
	if not visible:
		return
	left_s -= delta
	if left_s <= 0.0:
		visible = false
		finished.emit()


## Text lines of the stamp: grade, points, then the hot and dead-stick tags (keys resolved by tr).
func lines() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if stamp == null:
		return out
	var _a: bool = out.append(tr(stamp.label_key()))
	if stamp.total_points() > 0:
		var _b: bool = out.append("+%d %s" % [stamp.total_points(), tr(&"hud.grade.pts")])
	if stamp.hot:
		var _c: bool = out.append("%s x%s" % [tr(&"hud.grade.hot"), String.num(stamp.hot_mult, 1)])
	if stamp.dead_stick:
		var _d: bool = out.append("%s +%d" % [tr(&"hud.grade.dead_stick"), stamp.bonus_points])
	return out


func _draw() -> void:
	if stamp == null:
		return
	var fs: int = HudText.font_size(profile)
	var ls: PackedStringArray = lines()
	for i: int in ls.size():
		var big: bool = i == 0
		var size_px: int = fs * 3 if big else fs
		HudText.text(self, Vector2(0.0, float(fs) * 3.0 + float(i) * float(fs) * 1.6), ls[i],
				stamp.color() if big or i == 1 else UiTokens.UI_WARN, size_px)
