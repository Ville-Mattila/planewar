class_name StatusClusterView extends Control
## Consumables (fuel, ammo, bombs, rockets), cooldown rings (flip, boost) and the Core shield timer badge
## (docs/06 s6.4, s7.1; UX-18). Draws a LandingHudData plus the shield numbers; maths in StatusMath.

var data: LandingHudData = LandingHudData.new()
var profile: UiScale.Profile = UiScale.Profile.REGULAR
var shield_left_s: float = 0.0
var shield_ring01: float = 0.0
var shield_shown: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_data(d: LandingHudData) -> void:
	data = d
	queue_redraw()


## `until_s` = match_rules core_shield_until_s, `clock_s` = SimView.match_clock_s(), `team_flags` = TeamStateView.flags.
func set_shield(team_flags: int, until_s: float, clock_s: float) -> void:
	shield_shown = StatusMath.shield_visible(team_flags, until_s, clock_s)
	shield_left_s = StatusMath.shield_remaining_s(until_s, clock_s)
	shield_ring01 = StatusMath.shield_ring01(until_s, clock_s)
	queue_redraw()


## Consumable rows in draw order: label and value.
func rows() -> Array[PackedStringArray]:
	var out: Array[PackedStringArray] = []
	out.append(PackedStringArray([tr(&"hud.cons.fuel"), "%d%%" % int(roundf(data.fuel01 * 100.0))]))
	out.append(PackedStringArray([tr(&"hud.cons.ammo"), str(data.ammo)]))
	out.append(PackedStringArray([tr(&"hud.cons.bombs"), str(data.bombs)]))
	out.append(PackedStringArray([tr(&"hud.cons.rockets"), str(data.rockets)]))
	return out


func _boost_color() -> Color:
	if data.boost == StatusMath.Boost.ACTIVE:
		return UiTokens.UI_ACCENT
	return UiTokens.UI_WARN if data.boost == StatusMath.Boost.COOLING else UiTokens.UI_OK


func _draw() -> void:
	var fs: int = HudText.font_size(profile)
	var r: float = HudMath.param("cooldown_ring_du")
	var rs: Array[PackedStringArray] = rows()
	for i: int in rs.size():
		var low: bool = i == 0 and data.fuel01 < HudMath.param("landing_guide_fuel01")
		HudText.text(self, Vector2(0.0, float(i + 1) * float(fs) * 1.3), rs[i][0] + " " + rs[i][1],
				UiTokens.UI_WARN if low else UiTokens.UI_TEXT, fs)
	var c: Vector2 = Vector2(r + 2.0, float(rs.size() + 1) * float(fs) * 1.3 + r)
	HudText.ring(self, c, r, StatusMath.ring_fill(data.flip_cd01),
			UiTokens.UI_OK if StatusMath.ring_ready(data.flip_cd01) else UiTokens.UI_WARN)
	HudText.text(self, c + Vector2(-r, r + float(fs)), tr(&"hud.cd.flip"), UiTokens.UI_TEXT_DIM, fs)
	var c2: Vector2 = c + Vector2(r * 3.5, 0.0)
	HudText.ring(self, c2, r, StatusMath.boost_fill(data.boost), _boost_color())
	HudText.text(self, c2 + Vector2(-r, r + float(fs)), tr(&"hud.cd.boost"), UiTokens.UI_TEXT_DIM, fs)
	if shield_shown:
		var sr: float = HudMath.param("shield_ring_du")
		var c3: Vector2 = c2 + Vector2(r * 3.5 + float(fs) * 2.0, 0.0)
		HudText.ring(self, c3, sr, shield_ring01, UiTokens.RELATION_SELF)
		HudText.text(self, c3 + Vector2(-r, sr + float(fs)),
				tr(&"hud.shield") + " " + Fmt.duration(int(ceilf(shield_left_s))), UiTokens.UI_TEXT, fs)
