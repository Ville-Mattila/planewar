class_name PlayerTable extends RefCounted
## 03 s3.2 `PlayerState` / `TeamState` side tables of one `SimWorld`: per player slot (0..SLOTS-1, R0 B.6 slot ids,
## the u8 `owner` of the entity store) and per team. Written by `SimWorld.add_player` / `remove_player` (lobby
## level, outside the tick) and by command application in step 1; read by the validator and `LocalSimView`.
## Team pools start at `economy.start_ore` / `start_ice` (Economy, a later task, moves them).

const SLOTS: int = 8
## PlayerKind ordinals (R0 B.3: 0 HUMAN, 1 BOT, 2 OPEN) until the `PlayerKind` holder lands (sim/MODULE.md Open items).
const KIND_HUMAN: int = 0
const KIND_BOT: int = 1
const KIND_OPEN: int = 2
const TEAMS: int = 8
const _STATE: PackedStringArray = ["active", "team", "kind", "doctrine", "connected", "disconnect_tick", "possessed",
	"adjutant_profile", "adjutant_toggles", "eliminated", "team_ore", "team_ice"]

var active: PackedByteArray = PackedByteArray()          ## 1 when add_player has run for the slot
var team: PackedInt32Array = PackedInt32Array()
var kind: PackedInt32Array = PackedInt32Array()          ## KIND_*
var doctrine: PackedStringArray = PackedStringArray()
var connected: PackedByteArray = PackedByteArray()
var disconnect_tick: PackedInt32Array = PackedInt32Array()   ## -1 while connected
var possessed: PackedInt64Array = PackedInt64Array()      ## EntityId or 0 (03 s3.4 `possessed` list); 64-bit: gen >= 2048 ids exceed i32
var adjutant_profile: PackedInt32Array = PackedInt32Array()   ## -1 off
var adjutant_toggles: PackedInt32Array = PackedInt32Array()
var eliminated: PackedByteArray = PackedByteArray()
var team_ore: PackedInt32Array = PackedInt32Array()
var team_ice: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	var e: int = active.resize(SLOTS) | team.resize(SLOTS) | kind.resize(SLOTS) | doctrine.resize(SLOTS)
	e |= connected.resize(SLOTS) | disconnect_tick.resize(SLOTS) | possessed.resize(SLOTS)
	e |= adjutant_profile.resize(SLOTS) | adjutant_toggles.resize(SLOTS) | eliminated.resize(SLOTS)
	e |= team_ore.resize(TEAMS) | team_ice.resize(TEAMS)
	assert(e == OK)
	active.fill(0)
	team.fill(-1)
	kind.fill(PlayerTable.KIND_OPEN)
	connected.fill(0)
	disconnect_tick.fill(-1)
	possessed.fill(0)
	adjutant_profile.fill(-1)
	adjutant_toggles.fill(0)
	eliminated.fill(0)
	team_ore.fill(0)
	team_ice.fill(0)


func is_active(slot: int) -> bool:
	return slot >= 0 and slot < SLOTS and active[slot] != 0


## True when `slot`'s queued items may be cancelled by a teammate (S12, R0 C3-08): disconnected, eliminated or a bot.
func cancel_delegable(slot: int) -> bool:
	if not is_active(slot):
		return true
	return connected[slot] == 0 or eliminated[slot] != 0 or kind[slot] == PlayerTable.KIND_BOT


## Player slots on `t`, ascending.
func members(t: int, out: PackedInt32Array) -> void:
	var _r: int = out.resize(0)
	for s: int in SLOTS:
		if active[s] != 0 and team[s] == t:
			var _a: bool = out.push_back(s)


func write_state(buf: StreamPeerBuffer) -> void:
	StateIO.put_props(buf, self, _STATE)


func read_state(buf: StreamPeerBuffer) -> bool:
	if not StateIO.get_props(buf, self, _STATE):
		return false
	if not StateIO.sizes_ok(self, _STATE.slice(0, _STATE.size() - 2), SLOTS) or not StateIO.sizes_ok(self, ["team_ore", "team_ice"], TEAMS):
		return false
	return StateIO.ints_in(team, SLOTS, -1, TEAMS - 1)
