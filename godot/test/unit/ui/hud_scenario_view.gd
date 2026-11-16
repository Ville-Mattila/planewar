class_name HudScenarioView extends SimView
## A hand-scripted SimView "recording" for the UX-19 widget tests: entities are set per id, nothing is simulated.

var ents: Dictionary = {}          # id -> Dictionary(pos, team, def, ctl, pilot)
var rockets_at: Dictionary = {}    # id -> incoming rocket count
var pending: Dictionary = {}       # id -> OrderSpec
var hidden: Dictionary = {}        # id -> true when not visible to the viewing team
var ship_ids: PackedInt32Array = PackedInt32Array()


func add(id: int, def: StringName, team_slot: int, p: Vector3, ctl: int = 0, pilot: int = -1) -> void:
	var d: int = ContentDB.def_index(def)
	ents[id] = {"pos": p, "team": team_slot, "def": d, "ctl": ctl, "pilot": pilot}
	if DefRanges.kind_of(d) == DefRanges.K_SHIP:
		var _a: bool = ship_ids.append(id)


func alive(id: int) -> bool:
	return ents.has(id)


func pos(id: int) -> Vector3:
	return ents[id]["pos"] if ents.has(id) else Vector3.ZERO


func team(id: int) -> int:
	return ents[id]["team"] if ents.has(id) else -1


func def_id(id: int) -> int:
	return ents[id]["def"] if ents.has(id) else -1


func control_state(id: int) -> int:
	return ents[id]["ctl"] if ents.has(id) else 0


func possessor(id: int) -> int:
	return ents[id]["pilot"] if ents.has(id) else -1


func ships() -> PackedInt32Array:
	return ship_ids


func visible_to(_team: int, id: int) -> bool:
	return not hidden.has(id)


func incoming_rockets(id: int) -> int:
	return rockets_at.get(id, 0)


func pending_order(id: int) -> OrderSpec:
	return pending.get(id, null)


func ids_near(p: Vector3, radius: float, mask: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for id: int in ents:
		var is_ship: bool = DefRanges.kind_of(ents[id]["def"]) == DefRanges.K_SHIP
		var bit: int = 2 if is_ship else 1
		if (mask & bit) != 0 and (ents[id]["pos"] as Vector3).distance_to(p) <= radius:
			var _a: bool = out.append(id)
	return out
