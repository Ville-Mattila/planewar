class_name ThreatOverlayView extends Control
## Situational HUD layer (docs/06 s6.1, UX-19): threat ring around the reticle, tower hint, pending order and hand-over
## toast lines, canister compass pips and piloted-by badges. Thin: data classes and maths do the work. The Control spans
## the HUD root; the ring is centred on it.

var profile: UiScale.Profile = UiScale.Profile.REGULAR

var _threats: ThreatData = ThreatData.new()
var _hints: Array[TowerHint] = []
var _pending: PendingLine = null
var _toast: HandoverToast = null
var _beacons: Array[BeaconPip] = []
var _badges: Array[PilotBadge] = []
var _badge_xy: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_threats(d: ThreatData) -> void:
	_threats = d
	queue_redraw()


func set_hints(h: Array[TowerHint]) -> void:
	_hints = h
	queue_redraw()


func set_pending(p: PendingLine) -> void:
	_pending = p
	queue_redraw()


func set_toast(t: HandoverToast) -> void:
	_toast = t
	queue_redraw()


func set_beacons(p: Array[BeaconPip]) -> void:
	_beacons = p
	queue_redraw()


## `screen` holds one projected position (du) per badge; badges whose point is off screen are passed as (-1, -1).
func set_badges(b: Array[PilotBadge], screen: PackedVector2Array) -> void:
	_badges = b
	_badge_xy = screen
	queue_redraw()


func font_size() -> int:
	return maxi(HudText.font_size(profile), int(HudMath.param("font_du_min")))


## Text lines in draw order: rocket lock, tower hints, pending order, toast.
func lines() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if _threats.rocket_lock:
		var _a: bool = out.append(tr(&"hud.threat.lock"))
	for h: TowerHint in _hints:
		var _b: bool = out.append(h.text())
	if _pending != null:
		var _c: bool = out.append(_pending.text())
	if _toast != null and _toast.active():
		var _d: bool = out.append(_toast.text())
	return out


func _draw() -> void:
	var fs: int = font_size()
	var c: Vector2 = size * 0.5
	var ring: float = HudMath.param("threat_ring_du")
	var arrow: float = HudMath.param("threat_arrow_du")
	for a: ThreatArrow in _threats.arrows:
		_draw_arrow(c + ThreatMath.ring_pos(a.angle, ring), a, arrow)
	var y: float = c.y + ring + float(fs) * 2.0
	for i: int in lines().size():
		var s: String = lines()[i]
		var col: Color = UiTokens.UI_DANGER if (i == 0 and _threats.rocket_lock) else UiTokens.UI_WARN
		HudText.text(self, Vector2(0.0, y), s, col, fs, HORIZONTAL_ALIGNMENT_CENTER, size.x)
		y += float(fs) * 1.5
	_draw_beacons(fs)
	for i: int in mini(_badges.size(), _badge_xy.size()):
		if _badge_xy[i].x >= 0.0:
			HudText.text(self, _badge_xy[i], _badges[i].label, UiTokens.RELATION_ALLY, fs)


func _draw_arrow(at: Vector2, a: ThreatArrow, r: float) -> void:
	var dir: Vector2 = (at - size * 0.5).normalized()
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var col: Color = UiTokens.RELATION_ENEMY
	col.a = 0.35 + 0.65 * a.intensity if a.ahead else 0.2 + 0.4 * a.intensity
	var pts: PackedVector2Array = PackedVector2Array([at + dir * r * 0.5, at - dir * r * 0.5 + perp * r * 0.4,
			at - dir * r * 0.5 - perp * r * 0.4])
	draw_colored_polygon(pts, col)


func _draw_beacons(fs: int) -> void:
	var cx: float = size.x * 0.5
	var pip: float = HudMath.param("beacon_pip_du")
	for p: BeaconPip in _beacons:
		var at: Vector2 = Vector2(cx + p.x, float(fs) * 3.0)
		draw_circle(at, pip, UiTokens.UI_ACCENT)
		HudText.text(self, at + Vector2(-pip * 4.0, float(fs) + pip), tr(&"hud.beacon.canister"), UiTokens.UI_ACCENT, fs,
				HORIZONTAL_ALIGNMENT_CENTER, pip * 8.0)
