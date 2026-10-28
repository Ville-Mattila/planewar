class_name PilotTrack extends RefCounted
## The "manual" half of the landing grade (02 s17.1, 03 s6.4, 05 s5.5): a landing is manual when the ship is POSSESSED at
## touchdown and no tick in the final `manual_window_m` (150 m) of the approach was flown by anything but its pilot.
## Per player slot (<= 8 possessed ships) this keeps the possessed EntityId and where it was on its last non-human
## tick: the tick before the possession began (the autopilot flew it; none when it was DOCKED then) and every assist
## tick since (an overlay on the possessed ship, i.e. LINK_BRIDGE substitution, or `note_assist` from the auto-dock
## seam). At touchdown the landing is manual iff that point is absent or farther than `manual_window_m` horizontally
## (pad frame) from the pad: every tick after it was the pilot's, so the final approach inside the window was too.
## `track` runs in step 4 after the assist substitution; `dock_held` is this tick's DOCK button (derived, not saved).

var h_id: PackedInt32Array = PackedInt32Array()       ## per player slot: possessed ship EntityId being tracked, 0 none
var h_has: PackedByteArray = PackedByteArray()        ## per player slot: 1 when `h_pos` holds a non-human tick
var h_pos: PackedVector3Array = PackedVector3Array()  ## per player slot: position on the last non-human tick
var dock_held: PackedByteArray = PackedByteArray()    ## per player slot: DOCK held this tick (step 4; not state)

const _STATE: PackedStringArray = ["h_id", "h_has", "h_pos"]

var _store: EntityStore
var _players: PlayerTable
var _in: PilotInput = PilotInput.new()


func _init(store: EntityStore, players: PlayerTable) -> void:
	_store = store
	_players = players
	var n: int = PlayerTable.SLOTS
	var e: int = h_id.resize(n) | h_has.resize(n) | h_pos.resize(n) | dock_held.resize(n)
	assert(e == OK)
	h_id.fill(0)
	h_has.fill(0)
	h_pos.fill(Vector3.ZERO)
	dock_held.fill(0)


## Step 4, after the assist substitution: follows every player's possessed ship (<= 8, no allocation).
func track(inputs: InputSlots) -> void:
	for p: int in PlayerTable.SLOTS:
		var id: int = _players.possessed[p]
		dock_held[p] = 0
		if id == 0 or not _store.alive(id) or _store.kind[EntityId.slot(id)] != EntityStore.K_SHIP:
			h_id[p] = 0
			continue
		var s: int = EntityId.slot(id)
		if h_id[p] != id:
			h_id[p] = id
			var parked: bool = (_store.flags[s] & EntityStore.F_DOCKED) != 0
			h_has[p] = 0 if parked else 1
			h_pos[p] = _store.pos[s]
		elif _store.overlay[s] != ControlMachine.Overlay.NONE:
			note_assist(s)
		if s < InputSlots.ENTITY_SLOTS:
			inputs.read_entity(s, _in)
			dock_held[p] = 1 if (_in.buttons & PilotInput.DOCK) != 0 else 0


## An assist tick on ship slot `s` (LINK_BRIDGE, or `Assist.auto_dock` acting when AI-10 / NET-18 wire it): the
## landing that follows inside the manual window grades AUTO.
func note_assist(s: int) -> void:
	var id: int = _store.id_of(s)
	for p: int in PlayerTable.SLOTS:
		if h_id[p] == id:
			h_has[p] = 1
			h_pos[p] = _store.pos[s]


## True when ship `id` lands manually on the pad at `pad_pos` (normal `pad_up`): possessed by the player tracking it and
## its last non-human tick absent or beyond `window_m` horizontally.
func manual(id: int, pad_pos: Vector3, pad_up: Vector3, window_m: float) -> bool:
	for p: int in PlayerTable.SLOTS:
		if h_id[p] == id and _players.possessed[p] == id:
			if h_has[p] == 0:
				return true
			var rel: Vector3 = h_pos[p] - pad_pos
			return (rel - pad_up * rel.dot(pad_up)).length() > window_m
	return false


func write_state(buf: StreamPeerBuffer) -> void:
	StateIO.put_props(buf, self, _STATE)


func read_state(buf: StreamPeerBuffer) -> bool:
	return StateIO.get_props(buf, self, _STATE) and StateIO.sizes_ok(self, _STATE, PlayerTable.SLOTS)
