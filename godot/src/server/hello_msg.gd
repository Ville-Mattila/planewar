class_name HelloMsg extends RefCounted
## One parsed HELLO (0x01, 04 s2.3). `decode` is total: exact length, token bound, enum ranges; null on anything else.
## Token and secret verification is ServerSession's (04 s11.1); this only carries the bytes.

var version: int = 0
var content_hash: PackedByteArray = PackedByteArray()
var token: PackedByteArray = PackedByteArray()
var build: int = 0
var platform: int = 0
var input_class: int = 0
var role: int = 0
var session_id: int = 0
var secret: PackedByteArray = PackedByteArray()


static func decode(b: PackedByteArray) -> HelloMsg:
	if b.size() < SessionCodec.HELLO_FIXED_BYTES or b.size() > Protocol.max_bytes(Protocol.HELLO) or b[0] != Protocol.HELLO:
		return null
	var tl: int = b[35]
	if tl > SessionCodec.TOKEN_MAX or b.size() != SessionCodec.HELLO_FIXED_BYTES + tl:
		return null
	var at: int = 36 + tl
	if b[at + 4] >= Protocol.Platform.size() or b[at + 5] >= Protocol.WireInputClass.size() or b[at + 6] >= Protocol.Role.size():
		return null
	var m: HelloMsg = HelloMsg.new()
	m.version = b.decode_u16(1)
	m.content_hash = b.slice(3, 35)
	m.token = b.slice(36, at)
	m.build = b.decode_u32(at)
	m.platform = b[at + 4]
	m.input_class = b[at + 5]
	m.role = b[at + 6]
	m.session_id = b.decode_s64(at + 7)
	m.secret = b.slice(at + 15, at + 15 + Protocol.SECRET_BYTES)
	return m
