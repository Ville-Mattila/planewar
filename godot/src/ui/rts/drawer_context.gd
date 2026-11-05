class_name DrawerContext extends RefCounted
## The player and team numbers the production drawer needs, as plain data. `ui` may name only SimView of the sim's
## read views (tools/deps.json), not PlayerStateView / TeamStateView, so the host (app) fills this from
## `SimView.player_state` / `team_state` at 4 Hz (needs app: the adapter; test/unit/ui/drawer_context_kit.gd is the
## reference). `lock_left_ore` is PlayerStateView.early_spend_left_ore (-1 = no lock).

var player: int = 0
var team: int = 0
var doctrine: StringName = &""
var commander_rights: bool = true      ## PlayerStateView.commander_rights
var eliminated: bool = false
var ore: int = 0                       ## team stock
var ice: int = 0
var unit_cap: int = 0                  ## per player (TeamStateView.unit_cap)
var structure_cap: int = 0
var unit_count: int = 0                ## the local player's units
var lock_left_ore: int = -1

var _others: Dictionary = {}           ## slot -> PackedInt32Array [team, kind, connected, eliminated]


## Another player's cancel-relevant state (the queuer of an item, the placer of a site).
func set_player(slot: int, p_team: int, kind: int, connected: bool, p_eliminated: bool) -> void:
	_others[slot] = PackedInt32Array([p_team, kind, 1 if connected else 0, 1 if p_eliminated else 0])


func has_player(slot: int) -> bool:
	return _others.has(slot)


func player_team(slot: int) -> int:
	return _row(slot, 0, -1)


func player_kind(slot: int) -> int:
	return _row(slot, 1, DrawerMath.KIND_OPEN)


func player_connected(slot: int) -> bool:
	return _row(slot, 2, 0) != 0


func player_eliminated(slot: int) -> bool:
	return _row(slot, 3, 0) != 0


func stock() -> Vector2i:
	return Vector2i(ore, ice)


func _row(slot: int, i: int, fallback: int) -> int:
	if not _others.has(slot):
		return fallback
	var r: PackedInt32Array = _others[slot]
	return r[i]
