class_name ChaseHud extends Control
## The Chase HUD widget host scene (scenes/ui/chase_hud.tscn; UX-51, 06 s3.2): the status cluster and the barrel
## readout at their anchors, fed each frame for the possessed entity. Both hide when nothing is possessed.
## Thin: data comes from LandingHudData / BarrelReadoutData, placement from ChaseLayout.

@onready var status: StatusClusterView = $StatusCluster as StatusClusterView
@onready var barrel: BarrelReadoutView = $BarrelReadout as BarrelReadoutView

var profile: UiScale.Profile = UiScale.Profile.REGULAR


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide_all()


## Anchors both widgets inside a canvas of `canvas_du`.
func layout(canvas_du: Vector2) -> void:
	size = canvas_du
	status.position = ChaseLayout.status_pos(canvas_du, status.content_rect())
	barrel.position = ChaseLayout.barrel_pos(canvas_du, status.content_rect(), barrel.size)


func set_profile(p: UiScale.Profile) -> void:
	profile = p
	status.profile = p
	barrel.profile = p
	status.queue_redraw()
	barrel.queue_redraw()


func hide_all() -> void:
	status.visible = false
	barrel.visible = false


## `id` = the possessed entity (0 or dead = none); `ground` = ContentDB.ground_unit(v.def_id(id)) looked up by the host
## (null for a ship or structure); `shield_until_s` = match_rules core_shield_until_s.
func feed(v: SimView, id: int, ground: GroundUnitDef, shield_until_s: float) -> void:
	if id <= 0 or not v.alive(id):
		hide_all()
		return
	status.visible = true
	status.set_data(LandingHudData.from_view(v, id, 0.0, 0.0))   # agl / pad radius feed only the landing guide
	status.set_shield(v.team_state(v.team(id)).flags, shield_until_s, v.match_clock_s())
	var b: BarrelReadoutData = BarrelReadoutData.from_view(v, id, ground)
	barrel.visible = b.shown
	barrel.set_data(b)
