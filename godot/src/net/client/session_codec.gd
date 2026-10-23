class_name SessionCodec
## Session messages of the ClientSession state machine (04 s2.2, s2.3), little-endian. Client -> server encoders:
## HELLO, LOADED, PING, SNAPSHOT_ACK. Server -> client decoders (with the server-side encoders tests and NET-15 use):
## WELCOME, REFUSE, MATCH_STATE, PONG, and the fixed head of MATCH_END (winner, reason, tick; the per-player tail is
## the result screen's, bounded by the 640 B parser limit). Every decoder validates the whole message (id, exact
## length, string / blob bounds, enum ranges) before writing its output; anything else returns false, writes
## nothing and never throws. Static.

const HELLO_FIXED_BYTES: int = 67          # id + version 2 + hash 32 + token len 1 + build 4 + 3 x u8 + session 8 + secret 16
const TOKEN_MAX: int = 160
const WELCOME_FIXED_BYTES: int = 37        # id .. server_ms
const MAP_ID_MAX: int = 64
const CONFIG_MAX: int = 256
const NAME_MAX: int = 24
const PLAYERS_MAX: int = 8
const PONG_BYTES: int = 13
const PING_BYTES: int = 5
const ACK_BYTES: int = 7
const MATCH_STATE_BYTES: int = 9
const REFUSE_FIXED_BYTES: int = 5          # id, reason, server_version u16, text len
const REFUSE_TEXT_MAX: int = 120
const MATCH_END_HEAD_BYTES: int = 39       # id, winner, reason, tick u32, result_hash 32


static func encode_hello(content_hash: PackedByteArray, join_token: PackedByteArray, build: int, platform: int,
		input_class: int, role: int, session_id: int = 0, secret: PackedByteArray = PackedByteArray()) -> PackedByteArray:
	if content_hash.size() != Protocol.HASH_BYTES or join_token.size() > TOKEN_MAX \
			or (not secret.is_empty() and secret.size() != Protocol.SECRET_BYTES):
		return PackedByteArray()
	var b: PackedByteArray = PackedByteArray([Protocol.HELLO, 0, 0])
	b.encode_u16(1, Protocol.PROTOCOL_VERSION)
	b.append_array(content_hash)
	var _a: bool = b.push_back(join_token.size())
	b.append_array(join_token)
	var at: int = b.size()
	var _r: int = b.resize(at + 15)
	b.encode_u32(at, build & 0xFFFFFFFF)
	b[at + 4] = platform & 0xFF
	b[at + 5] = input_class & 0xFF
	b[at + 6] = role & 0xFF
	b.encode_s64(at + 7, session_id)
	var sec: PackedByteArray = secret.duplicate()
	var _s: int = sec.resize(Protocol.SECRET_BYTES)
	b.append_array(sec)
	return b


static func encode_loaded(map_hash: PackedByteArray) -> PackedByteArray:
	if map_hash.size() != Protocol.HASH_BYTES:
		return PackedByteArray()
	var b: PackedByteArray = PackedByteArray([Protocol.LOADED])
	b.append_array(map_hash)
	return b


static func encode_ping(client_ms: int) -> PackedByteArray:
	var b: PackedByteArray = PackedByteArray([Protocol.PING, 0, 0, 0, 0])
	b.encode_u32(1, client_ms & 0xFFFFFFFF)
	return b


## The newest complete tick (BaselineStore.complete_tick, R0 B.10 A-36) and the last applied keyframe_seq.
static func encode_snapshot_ack(ack_tick: int, keyframe_seq: int) -> PackedByteArray:
	var b: PackedByteArray = PackedByteArray([Protocol.SNAPSHOT_ACK, 0, 0, 0, 0, 0, 0])
	b.encode_u32(1, ack_tick & 0xFFFFFFFF)
	b.encode_u16(5, keyframe_seq & 0xFFFF)
	return b


static func encode_pong(client_ms: int, server_tick: int, server_ms: int) -> PackedByteArray:
	var b: PackedByteArray = PackedByteArray()
	var _r: int = b.resize(PONG_BYTES)
	b[0] = Protocol.PONG
	b.encode_u32(1, client_ms & 0xFFFFFFFF)
	b.encode_u32(5, server_tick & 0xFFFFFFFF)
	b.encode_u32(9, server_ms & 0xFFFFFFFF)
	return b


## out = [client_ms, server_tick, server_ms].
static func decode_pong(b: PackedByteArray, out: PackedInt64Array) -> bool:
	if b.size() != PONG_BYTES or b[0] != Protocol.PONG:
		return false
	var _r: int = out.resize(3)
	out[0] = b.decode_u32(1)
	out[1] = b.decode_u32(5)
	out[2] = b.decode_u32(9)
	return true


static func encode_match_state(phase: int, tick: int, countdown_ticks: int, loaded_mask: int) -> PackedByteArray:
	var b: PackedByteArray = PackedByteArray()
	var _r: int = b.resize(MATCH_STATE_BYTES)
	b[0] = Protocol.MATCH_STATE
	b[1] = phase & 0xFF
	b.encode_u32(2, tick & 0xFFFFFFFF)
	b.encode_u16(6, countdown_ticks & 0xFFFF)
	b[8] = loaded_mask & 0xFF
	return b


## out = [phase (Protocol.SessionPhase), tick, countdown_ticks, loaded_mask].
static func decode_match_state(b: PackedByteArray, out: PackedInt64Array) -> bool:
	if b.size() != MATCH_STATE_BYTES or b[0] != Protocol.MATCH_STATE or b[1] >= Protocol.SessionPhase.size():
		return false
	var _r: int = out.resize(4)
	out[0] = b[1]
	out[1] = b.decode_u32(2)
	out[2] = b.decode_u16(6)
	out[3] = b[8]
	return true


static func encode_refuse(reason: int, server_version: int, text: String) -> PackedByteArray:
	var t: PackedByteArray = text.to_utf8_buffer().slice(0, REFUSE_TEXT_MAX)
	var b: PackedByteArray = PackedByteArray([Protocol.REFUSE, reason & 0xFF, 0, 0, t.size()])
	b.encode_u16(2, server_version & 0xFFFF)
	b.append_array(t)
	return b


## out = [reason (Protocol.RefuseReason), server_version].
static func decode_refuse(b: PackedByteArray, out: PackedInt64Array) -> bool:
	if b.size() < REFUSE_FIXED_BYTES or b[0] != Protocol.REFUSE or b[1] >= Protocol.RefuseReason.size() \
			or b[4] > REFUSE_TEXT_MAX or b.size() != REFUSE_FIXED_BYTES + b[4] or not utf8_ok(b, REFUSE_FIXED_BYTES, b.size()):
		return false
	var _r: int = out.resize(2)
	out[0] = b[1]
	out[1] = b.decode_u16(2)
	return true


## out = [winner_team, reason (Protocol.MatchEndReason), tick]; the tail is only bounded (<= 640 B).
static func decode_match_end_head(b: PackedByteArray, out: PackedInt64Array) -> bool:
	if b.size() < MATCH_END_HEAD_BYTES or b.size() > Protocol.max_bytes(Protocol.MATCH_END) or b[0] != Protocol.MATCH_END \
			or b[2] >= Protocol.MatchEndReason.size():
		return false
	var _r: int = out.resize(3)
	out[0] = b[1]
	out[1] = b[2]
	out[2] = b.decode_u32(3)
	return true


static func encode_welcome(w: WelcomeInfo) -> PackedByteArray:
	var map_b: PackedByteArray = w.map_id.to_utf8_buffer()
	var n: int = w.player_slot.size()
	if map_b.size() > MAP_ID_MAX or w.config.size() > CONFIG_MAX or n > PLAYERS_MAX or w.map_hash.size() != Protocol.HASH_BYTES \
			or w.secret.size() != Protocol.SECRET_BYTES:
		return PackedByteArray()
	var b: PackedByteArray = PackedByteArray()
	var _r: int = b.resize(WELCOME_FIXED_BYTES)
	b[0] = Protocol.WELCOME
	b.encode_u16(1, w.conn_id & 0xFFFF)
	b[3] = w.slot & 0xFF
	b[4] = w.team & 0xFF
	b.encode_s64(5, w.session_id)
	for k: int in Protocol.SECRET_BYTES:
		b[13 + k] = w.secret[k]
	b.encode_u32(29, w.tick & 0xFFFFFFFF)
	b.encode_u32(33, w.server_ms & 0xFFFFFFFF)
	var _a: bool = b.push_back(map_b.size())
	b.append_array(map_b)
	b.append_array(w.map_hash)
	var at: int = b.size()
	var _c: int = b.resize(at + 2)
	b.encode_u16(at, w.config.size())
	b.append_array(w.config)
	var _d: bool = b.push_back(n)
	for k: int in n:
		var nm: PackedByteArray = w.player_name[k].to_utf8_buffer().slice(0, NAME_MAX)
		b.append_array(PackedByteArray([w.player_slot[k], w.player_team[k], w.player_kind[k], w.player_doctrine[k],
				w.player_input[k], nm.size()]))
		b.append_array(nm)
	return b if b.size() <= Protocol.max_bytes(Protocol.WELCOME) else PackedByteArray()


static func decode_welcome(b: PackedByteArray, out: WelcomeInfo) -> bool:
	var end: int = _welcome_end(b)
	if end < 0 or end != b.size():
		return false
	out.conn_id = b.decode_u16(1)
	out.slot = b[3]
	out.team = b[4]
	out.session_id = b.decode_s64(5)
	out.secret = b.slice(13, 29)
	out.tick = b.decode_u32(29)
	out.server_ms = b.decode_u32(33)
	var ml: int = b[37]
	out.map_id = b.slice(38, 38 + ml).get_string_from_utf8()
	out.map_hash = b.slice(38 + ml, 70 + ml)
	var cl: int = b.decode_u16(70 + ml)
	out.config = b.slice(72 + ml, 72 + ml + cl)
	var at: int = 72 + ml + cl
	out.clear_players()
	for _k: int in b[at]:
		var p: int = at + 1
		out.add_player(b[p], b[p + 1], b[p + 2], b[p + 3], b[p + 4], b.slice(p + 6, p + 6 + b[p + 5]).get_string_from_utf8())
		at += 6 + b[p + 5]
	return true


## Byte length WELCOME would have by walking its blobs, or -1 on any violation (bounds, ranges, > 700 B).
static func _welcome_end(b: PackedByteArray) -> int:
	if b.size() < WELCOME_FIXED_BYTES + 1 or b.size() > Protocol.max_bytes(Protocol.WELCOME) or b[0] != Protocol.WELCOME:
		return -1
	if b[3] >= PLAYERS_MAX and b[3] != Protocol.SLOT_SPECTATOR:
		return -1
	var ml: int = b[37]
	if ml > MAP_ID_MAX or 72 + ml > b.size() or not utf8_ok(b, 38, 38 + ml):
		return -1
	var cl: int = b.decode_u16(70 + ml)
	var at: int = 72 + ml + cl
	if cl > CONFIG_MAX or at + 1 > b.size() or b[at] > PLAYERS_MAX:
		return -1
	var n: int = b[at]
	at += 1
	for _k: int in n:
		if at + 6 > b.size() or b[at] >= PLAYERS_MAX or b[at + 2] >= Protocol.PlayerKind.size() or b[at + 5] > NAME_MAX:
			return -1
		var nb: int = at + 6
		at = nb + b[nb - 1]
		if at > b.size() or not utf8_ok(b, nb, at):
			return -1
	return at


## True when b[from, to) is well-formed UTF-8 without NUL (no overlong forms, surrogates or code points above U+10FFFF), so
## get_string_from_utf8 never reports a parse error on wire text.
static func utf8_ok(b: PackedByteArray, from: int, to: int) -> bool:
	var i: int = from
	while i < to:
		var c: int = b[i]
		var n: int = 0
		var lo: int = 0x80
		if c == 0:
			return false                        # get_string_from_utf8 stops at NUL: never canonical wire text
		if c < 0x80:
			i += 1
			continue
		elif c >= 0xC2 and c <= 0xDF:
			n = 1
		elif c >= 0xE0 and c <= 0xEF:
			n = 2
			lo = 0xA0 if c == 0xE0 else 0x80
		elif c >= 0xF0 and c <= 0xF4:
			n = 3
			lo = 0x90 if c == 0xF0 else 0x80
		else:
			return false
		if i + n >= to:
			return false
		var hi: int = 0x9F if c == 0xED else (0x8F if c == 0xF4 else 0xBF)
		for k: int in n:
			var d: int = b[i + 1 + k]
			if d < (lo if k == 0 else 0x80) or d > (hi if k == 0 else 0xBF):
				return false
		i += n + 1
	return true
