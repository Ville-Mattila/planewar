class_name InputSlots extends RefCounted
## The per-entity input slots kinematics reads in step 5 (03 s3.5, R0 B.5 steps 2-4) and the per-player slots
## PILOT_INPUT writes (S1's one immediate mutation). f64 axes, so a value written equals the value read on server
## and in client prediction. Main-range entity slots only (wrecks take no input). A slot holds its last value until
## written again; possession changes clear it. Serialized with the world (S4).

const ENTITY_SLOTS: int = EntityId.WRECK_SLOT_MIN
const _STATE: PackedStringArray = ["e_thrust", "e_pitch", "e_yaw", "e_roll", "e_buttons",
	"p_thrust", "p_pitch", "p_yaw", "p_roll", "p_buttons"]

var e_thrust: PackedFloat64Array = PackedFloat64Array()
var e_pitch: PackedFloat64Array = PackedFloat64Array()
var e_yaw: PackedFloat64Array = PackedFloat64Array()
var e_roll: PackedFloat64Array = PackedFloat64Array()
var e_buttons: PackedByteArray = PackedByteArray()
var p_thrust: PackedFloat64Array = PackedFloat64Array()
var p_pitch: PackedFloat64Array = PackedFloat64Array()
var p_yaw: PackedFloat64Array = PackedFloat64Array()
var p_roll: PackedFloat64Array = PackedFloat64Array()
var p_buttons: PackedByteArray = PackedByteArray()


func _init() -> void:
	var n: int = ENTITY_SLOTS
	var m: int = PlayerTable.SLOTS
	var e: int = e_thrust.resize(n) | e_pitch.resize(n) | e_yaw.resize(n) | e_roll.resize(n) | e_buttons.resize(n)
	e |= p_thrust.resize(m) | p_pitch.resize(m) | p_yaw.resize(m) | p_roll.resize(m) | p_buttons.resize(m)
	assert(e == OK)
	for s: int in n:
		clear_entity(s)
	for p: int in m:
		clear_player(p)


func set_entity(slot: int, input: PilotInput) -> void:
	e_thrust[slot] = input.thrust
	e_pitch[slot] = input.pitch
	e_yaw[slot] = input.yaw
	e_roll[slot] = input.roll
	e_buttons[slot] = input.buttons & 0xFF


func read_entity(slot: int, out: PilotInput) -> void:
	out.thrust = e_thrust[slot]
	out.pitch = e_pitch[slot]
	out.yaw = e_yaw[slot]
	out.roll = e_roll[slot]
	out.buttons = e_buttons[slot]


func clear_entity(slot: int) -> void:
	e_thrust[slot] = 0.0
	e_pitch[slot] = 0.0
	e_yaw[slot] = 0.0
	e_roll[slot] = 0.0
	e_buttons[slot] = 0


func set_player(player: int, input: PilotInput) -> void:
	p_thrust[player] = input.thrust
	p_pitch[player] = input.pitch
	p_yaw[player] = input.yaw
	p_roll[player] = input.roll
	p_buttons[player] = input.buttons & 0xFF


func clear_player(player: int) -> void:
	p_thrust[player] = 0.0
	p_pitch[player] = 0.0
	p_yaw[player] = 0.0
	p_roll[player] = 0.0
	p_buttons[player] = 0


## Step 2: the player's stored input becomes the possessed entity's input for this tick.
func copy_player_to_entity(player: int, slot: int) -> void:
	e_thrust[slot] = p_thrust[player]
	e_pitch[slot] = p_pitch[player]
	e_yaw[slot] = p_yaw[player]
	e_roll[slot] = p_roll[player]
	e_buttons[slot] = p_buttons[player]


func write_state(buf: StreamPeerBuffer) -> void:
	StateIO.put_props(buf, self, _STATE)


func read_state(buf: StreamPeerBuffer) -> bool:
	return StateIO.get_props(buf, self, _STATE) and e_thrust.size() == ENTITY_SLOTS and p_thrust.size() == PlayerTable.SLOTS
