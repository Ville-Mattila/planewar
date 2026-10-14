class_name EventAudience extends RefCounted
## Per-client routing state for `EventRouter` (04 s3.6): the client's roster, team, player slot, possessed
## entity slot and the interest cells it sees (A/B tiers, set by Interest, NET-08). `outbox` collects EVENTS
## packets for CH_EVENTS (reliable), `shot_out` PROJECTILE_BATCH packets for CH_SNAPSHOT; the caller drains both.
## `unfiltered` (replay writer, spectator with full reveal) bypasses scope rules, never the roster masking.

var roster: Roster = null
var team: int = -1
var player: int = -1
var possessed_slot: int = -1
var unfiltered: bool = false
var cells: PackedByteArray = PackedByteArray()
var outbox: Array[PackedByteArray] = []
var shot_out: Array[PackedByteArray] = []
var shots_last: Array[PackedByteArray] = []     # packets of the previous tick, re-sent once (R0 C2-35)


func _init(r: Roster = null) -> void:
	roster = r if r != null else Roster.new()
	var _e: Error = cells.resize(Codec.CELL_COUNT)


func set_cells(ids: PackedInt32Array) -> void:
	cells.fill(0)
	for c: int in ids:
		if c >= 0 and c < Codec.CELL_COUNT:
			cells[c] = 1


func sees_cell(cell: int) -> bool:
	return cell >= 0 and cell < Codec.CELL_COUNT and cells[cell] != 0


func clear_out() -> void:
	outbox.clear()
	shot_out.clear()
