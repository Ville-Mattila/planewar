class_name PlayerStateView extends RefCounted
## Read-only view of 03 s3.2 `PlayerState` (R0 B.8 A-8); 04 TEAM_DETAIL players and PLAYER_STATUS.
## `SimView.player_state(slot)` returns one reused instance per slot, refilled on every call (S3).

var slot: int = 0
var team: int = 0
var kind: int = PlayerTable.KIND_OPEN
var unknown: bool = false
var doctrine: StringName = &""
var possessed: int = 0
var commander_rights: bool = false
var eliminated: bool = false
var connected: bool = false
var disconnect_tick: int = -1
var adjutant_profile: int = -1
var adjutant_toggles: int = 0
var unit_count: int = 0
var structure_count: int = 0
var early_spend_left_ore: int = -1
