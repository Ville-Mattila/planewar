class_name DrawerMockView extends SimView
## Mocked SimView for the production drawer tests (UX-22): structures, queues, tech and counts set by hand.

const BUILDING: int = 16   ## EntityStore.F_BUILDING (sim/MODULE.md flags)

var struct_ids: PackedInt32Array = PackedInt32Array()
var def_of: Dictionary = {}       # id -> def id
var team_of: Dictionary = {}      # id -> team
var owner_of: Dictionary = {}     # id -> player
var flags_of: Dictionary = {}     # id -> flags
var hp_of: Dictionary = {}        # id -> hp01
var pos_of: Dictionary = {}       # id -> Vector3
var queues: Dictionary = {}       # factory id -> PackedInt32Array of unit def ids
var progress: Dictionary = {}     # factory id -> float
var missing_tech: Dictionary = {} # def id -> true when its tech is not available
var repl: Dictionary = {}         # unit def id -> target
var players: Dictionary = {}      # slot -> PlayerStateView
var team_view: TeamStateView = TeamStateView.new()
var units: int = 0


func add_structure(id: int, def: StringName, owner_slot: int, team: int, p: Vector3 = Vector3.ZERO, flags: int = 0) -> void:
	var _a: bool = struct_ids.append(id)
	def_of[id] = ContentDB.def_index(def)
	owner_of[id] = owner_slot
	team_of[id] = team
	flags_of[id] = flags
	hp_of[id] = 1.0
	pos_of[id] = p


func add_player(slot: int, team: int, kind: int = 0, connected: bool = true, eliminated: bool = false) -> PlayerStateView:
	var ps: PlayerStateView = PlayerStateView.new()
	ps.slot = slot
	ps.team = team
	ps.kind = kind
	ps.connected = connected
	ps.eliminated = eliminated
	ps.commander_rights = not eliminated and kind != 2
	players[slot] = ps
	return ps


func alive(id: int) -> bool:
	return def_of.has(id)


func def_id(id: int) -> int:
	return def_of.get(id, -1)


func team(id: int) -> int:
	return team_of.get(id, -1)


func owner(id: int) -> int:
	return owner_of.get(id, -1)


func flags(id: int) -> int:
	return flags_of.get(id, 0)


func hp01(id: int) -> float:
	return hp_of.get(id, 0.0)


func pos(id: int) -> Vector3:
	return pos_of.get(id, Vector3.ZERO)


func structures() -> PackedInt32Array:
	return struct_ids


func production_queue(f: int) -> PackedInt32Array:
	return queues.get(f, PackedInt32Array())


func production_progress01(f: int) -> float:
	return progress.get(f, 0.0)


func tech_available(_team: int, d: int) -> bool:
	return not missing_tech.has(d)


func auto_replenish_target(_player: int, d: int) -> int:
	return repl.get(d, 0)


func unit_count(_player: int) -> int:
	return units


func team_state(_team: int) -> TeamStateView:
	return team_view


func player_state(slot: int) -> PlayerStateView:
	return players.get(slot, null)
