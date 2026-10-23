class_name WelcomeInfo extends RefCounted
## One WELCOME (0x80) message (04 s2.2, s2.3) as decoded by SessionCodec: the slot / team the server gave this
## client, the reconnect credentials, the server clock at send time, the map, the opaque MatchConfig bytes and the
## player table. `config` is kept as bytes (MatchConfig is server/, 04 s9.3).

var conn_id: int = 0
var slot: int = Protocol.SLOT_SPECTATOR
var team: int = 0
var session_id: int = 0
var secret: PackedByteArray = PackedByteArray()
var tick: int = 0
var server_ms: int = 0
var map_id: String = ""
var map_hash: PackedByteArray = PackedByteArray()
var config: PackedByteArray = PackedByteArray()
var player_slot: PackedInt32Array = PackedInt32Array()
var player_team: PackedInt32Array = PackedInt32Array()
var player_kind: PackedInt32Array = PackedInt32Array()
var player_doctrine: PackedInt32Array = PackedInt32Array()
var player_input: PackedInt32Array = PackedInt32Array()
var player_name: PackedStringArray = PackedStringArray()


func add_player(p_slot: int, p_team: int, kind: int, doctrine: int, input_class: int, p_name: String) -> void:
	var _a: bool = player_slot.push_back(p_slot)
	var _b: bool = player_team.push_back(p_team)
	var _c: bool = player_kind.push_back(kind)
	var _d: bool = player_doctrine.push_back(doctrine)
	var _e: bool = player_input.push_back(input_class)
	var _f: bool = player_name.push_back(p_name)


func clear_players() -> void:
	player_slot.clear()
	player_team.clear()
	player_kind.clear()
	player_doctrine.clear()
	player_input.clear()
	player_name.clear()
