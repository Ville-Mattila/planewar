class_name ReplayHeader extends RefCounted
## The `.pwr` HEADER (04 s13.1): magic, protocol version, content and map hashes, map id, match id, MatchConfig bytes,
## seed, start time, tick rate and the player table. `header_len` (u32, last field, counts itself) lets a redaction
## rewrite names in place without moving any later offset (ReplayRedactor).

var protocol_version: int = Protocol.PROTOCOL_VERSION
var content_hash: PackedByteArray = PackedByteArray()
var map_hash: PackedByteArray = PackedByteArray()
var map_id: String = ""
var match_id: PackedByteArray = PackedByteArray()
var config: PackedByteArray = PackedByteArray()
var seed_value: int = 0
var started_unix: int = 0
var tick_rate: int = 30
var slot: PackedInt32Array = PackedInt32Array()
var team: PackedInt32Array = PackedInt32Array()
var kind: PackedInt32Array = PackedInt32Array()
var doctrine: PackedInt32Array = PackedInt32Array()
var input_class: PackedInt32Array = PackedInt32Array()
var user_id: Array[PackedByteArray] = []
var player_name: PackedStringArray = PackedStringArray()
## Byte length of the parsed or written header (filled by to_bytes / parse).
var length: int = 0
## Offsets in the header of each player's user_id (16 B) and name length byte, set by parse (ReplayRedactor).
var uid_at: PackedInt32Array = PackedInt32Array()
var name_at: PackedInt32Array = PackedInt32Array()


func add_player(slot_id: int, team_id: int, kind_id: int, doctrine_id: int, input_class_id: int, uid: PackedByteArray,
		display_name: String) -> void:
	var _a: bool = slot.push_back(slot_id)
	var _b: bool = team.push_back(team_id)
	var _c: bool = kind.push_back(kind_id)
	var _d: bool = doctrine.push_back(doctrine_id)
	var _e: bool = input_class.push_back(input_class_id)
	var padded: PackedByteArray = uid.slice(0, ReplayFormat.ID_BYTES)
	var _r: int = padded.resize(ReplayFormat.ID_BYTES)
	user_id.append(padded)
	var _f: bool = player_name.push_back(display_name)


func player_count() -> int:
	return slot.size()


func to_bytes() -> PackedByteArray:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	var _m: Error = b.put_data(ReplayFormat.MAGIC)
	b.put_u16(protocol_version)
	_put_fixed(b, content_hash, ReplayFormat.HASH_BYTES)
	_put_fixed(b, map_hash, ReplayFormat.HASH_BYTES)
	_put_str8(b, map_id)
	_put_fixed(b, match_id, ReplayFormat.ID_BYTES)
	b.put_u16(config.size())
	_m = b.put_data(config)
	b.put_u64(seed_value)
	b.put_u32(started_unix)
	b.put_u8(tick_rate)
	b.put_u8(player_count())
	for i: int in player_count():
		b.put_u8(slot[i])
		b.put_u8(team[i])
		b.put_u8(kind[i])
		b.put_u8(doctrine[i])
		b.put_u8(input_class[i])
		_put_fixed(b, user_id[i], ReplayFormat.ID_BYTES)
		_put_str8(b, player_name[i])
	length = b.get_size() + 4
	b.put_u32(length)
	return b.data_array


## Parses a header at offset 0 of `buf`. Returns ReplayFormat.Status (OK, BAD_MAGIC, UNSUPPORTED_VERSION, CORRUPT).
func parse(buf: PackedByteArray) -> int:
	if buf.size() < 4 or buf.slice(0, 4) != ReplayFormat.MAGIC:
		return ReplayFormat.Status.BAD_MAGIC
	if buf.size() < 6:
		return ReplayFormat.Status.CORRUPT
	protocol_version = buf.decode_u16(4)
	if protocol_version != Protocol.PROTOCOL_VERSION:
		return ReplayFormat.Status.UNSUPPORTED_VERSION
	var at: int = 6
	var tmp: PackedStringArray = PackedStringArray([""])
	if at + 64 > buf.size():
		return ReplayFormat.Status.CORRUPT
	content_hash = buf.slice(at, at + 32)
	map_hash = buf.slice(at + 32, at + 64)
	at = ReplayFormat.read_str8(buf, at + 64, tmp)
	map_id = tmp[0]
	if at < 0 or at + 18 > buf.size():
		return ReplayFormat.Status.CORRUPT
	match_id = buf.slice(at, at + 16)
	var cfg: int = buf.decode_u16(at + 16)
	at += 18
	if at + cfg + 15 > buf.size():
		return ReplayFormat.Status.CORRUPT
	config = buf.slice(at, at + cfg)
	at += cfg
	seed_value = buf.decode_s64(at)
	started_unix = buf.decode_u32(at + 8)
	tick_rate = buf[at + 12]
	var n: int = buf[at + 13]
	at += 14
	slot.clear()
	team.clear()
	kind.clear()
	doctrine.clear()
	input_class.clear()
	user_id.clear()
	player_name.clear()
	uid_at.clear()
	name_at.clear()
	for _i: int in n:
		if at + 21 > buf.size():
			return ReplayFormat.Status.CORRUPT
		var _a: bool = slot.push_back(buf[at])
		var _b: bool = team.push_back(buf[at + 1])
		var _c: bool = kind.push_back(buf[at + 2])
		var _d: bool = doctrine.push_back(buf[at + 3])
		var _e: bool = input_class.push_back(buf[at + 4])
		user_id.append(buf.slice(at + 5, at + 21))
		var _g: bool = uid_at.push_back(at + 5)
		var _h: bool = name_at.push_back(at + 21)
		at = ReplayFormat.read_str8(buf, at + 21, tmp)
		if at < 0:
			return ReplayFormat.Status.CORRUPT
		var _f: bool = player_name.push_back(tmp[0])
	if at + 4 > buf.size() or buf.decode_u32(at) != at + 4:
		return ReplayFormat.Status.CORRUPT
	length = at + 4
	return ReplayFormat.Status.OK


static func _put_fixed(b: StreamPeerBuffer, data: PackedByteArray, n: int) -> void:
	var d: PackedByteArray = data.slice(0, n)
	var _r: int = d.resize(n)
	var _e: Error = b.put_data(d)


static func _put_str8(b: StreamPeerBuffer, text: String) -> void:
	var u: PackedByteArray = text.to_utf8_buffer().slice(0, 255)
	b.put_u8(u.size())
	var _e: Error = b.put_data(u)
