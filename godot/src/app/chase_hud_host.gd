class_name ChaseHudHost extends Node
## Feeds the Chase HUD widgets every frame from the active SimView for the possessed entity (UX-51). The match
## controller sets `view` and `possessed_id` (EntityId or 0); the GroundUnitDef is looked up here, not in the HUD.

var hud: ChaseHud
var view: SimView
var local_player: int = 0
var possessed_id: int = 0
var shield_until_s: float = 0.0     ## match_rules core_shield_until_s


func _process(_delta: float) -> void:
	refresh()


## The id to show: `possessed_id` while it is alive and flown by the local player, else 0.
func active_id() -> int:
	if view == null or possessed_id <= 0 or not view.alive(possessed_id):
		return 0
	return possessed_id if view.possessor(possessed_id) == local_player else 0


func refresh() -> void:
	if hud == null:
		return
	if view == null:
		hud.hide_all()
		return
	var id: int = active_id()
	var g: GroundUnitDef = ContentDB.ground_unit(view.def_id(id)) if id > 0 else null
	hud.feed(view, id, g, shield_until_s)
