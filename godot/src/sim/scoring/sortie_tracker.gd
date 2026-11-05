class_name SortieTracker extends RefCounted
## One sortie per ship flight a player flew (02 s17.1 `sorties`; BAL-16, the two_speeds medal, the 08 SL-1 Sortie Card):
## the first possession of a flying ship, or the launch of a ship its player holds, counts; further possessions of the same
## flight (release and re-possess, a teammate's handover aside) do not; the DOCKED event ends the flight. Per ship slot it
## keeps the EntityId of the flight and a bit per player already counted. Part of S4.

const _STATE: PackedStringArray = ["flown_id", "flown_mask"]

var flown_id: PackedInt32Array = PackedInt32Array()
var flown_mask: PackedByteArray = PackedByteArray()


func _init() -> void:
	var e: int = flown_id.resize(InputSlots.ENTITY_SLOTS) | flown_mask.resize(InputSlots.ENTITY_SLOTS)
	assert(e == OK)
	flown_id.fill(0)
	flown_mask.fill(0)


## True the first time `player` flies `ship_id` in its current flight.
func note(ship_id: int, player: int) -> bool:
	var s: int = EntityId.slot(ship_id)
	if s >= flown_id.size() or player < 0 or player >= PlayerTable.SLOTS:
		return false
	if flown_id[s] != ship_id:
		flown_id[s] = ship_id
		flown_mask[s] = 0
	if ((flown_mask[s] >> player) & 1) != 0:
		return false
	flown_mask[s] |= 1 << player
	return true


## The flight of `ship_id` is over (it docked).
func land(ship_id: int) -> void:
	var s: int = EntityId.slot(ship_id)
	if ship_id > 0 and s < flown_id.size():
		flown_id[s] = 0


func write_state(buf: StreamPeerBuffer) -> void:
	StateIO.put_props(buf, self, _STATE)


func read_state(buf: StreamPeerBuffer) -> bool:
	return StateIO.get_props(buf, self, _STATE) and StateIO.sizes_ok(self, _STATE, InputSlots.ENTITY_SLOTS)
