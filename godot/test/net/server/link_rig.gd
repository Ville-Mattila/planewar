class_name LinkRig extends Transport
## Test helper (NET-14): a recording Transport stub plus builders for the client -> server messages a ClientLink parses.
## `sent` rows are [conn, channel, bytes]; `closed` holds the conn ids passed to close().

var sent: Array[PackedByteArray] = []
var sent_channels: PackedInt32Array = PackedInt32Array()
var closed: PackedInt32Array = PackedInt32Array()


func send(_conn: int, channel: int, bytes: PackedByteArray, _reliable: bool) -> void:
	sent.append(bytes)
	var _p: bool = sent_channels.push_back(channel)


func close(conn: int, _reason: int) -> void:
	var _p: bool = closed.push_back(conn)


func ids_sent() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for b: PackedByteArray in sent:
		var _p: bool = out.push_back(b[0])
	return out


static func new_link(now_ms: int = 0, limits: LinkLimits = null) -> ClientLink:
	return ClientLink.new(7, LinkRig.new(), limits if limits != null else LinkLimits.new(), now_ms)


static func rig_of(link: ClientLink) -> LinkRig:
	return link.transport as LinkRig


static func hash32(fill: int) -> PackedByteArray:
	var b: PackedByteArray = PackedByteArray()
	var _r: int = b.resize(Protocol.HASH_BYTES)
	b.fill(fill)
	return b


static func hello(token_len: int = 4) -> PackedByteArray:
	var tok: PackedByteArray = PackedByteArray()
	var _r: int = tok.resize(token_len)
	return SessionCodec.encode_hello(hash32(1), tok, 3, Protocol.Platform.LINUX, Protocol.WireInputClass.POINTER,
			Protocol.Role.PLAYER)


static func welcome(map_fill: int = 9) -> WelcomeInfo:
	var w: WelcomeInfo = WelcomeInfo.new()
	w.conn_id = 7
	w.slot = 2
	w.team = 1
	w.session_id = 77
	w.secret = hash32(5).slice(0, Protocol.SECRET_BYTES)
	w.tick = 10
	w.map_id = "tiny_test"
	w.map_hash = hash32(map_fill)
	w.add_player(2, 1, Protocol.PlayerKind.HUMAN, Protocol.DOCTRINE_HIDDEN, Protocol.WireInputClass.POINTER, "ace")
	return w


static func command(seq: int, tick: int = 0) -> PackedByteArray:
	var c: Command = Command.new()
	c.kind = Command.Kind.RELEASE
	c.target = 5
	return CommandCodec.encode_message(seq, tick, c)


static func chat() -> PackedByteArray:
	var b: PackedByteArray = PackedByteArray([Protocol.CHAT, 0, 0, 0, 0, 0, 2, 0, 104, 105])
	return b


static func quick_ping() -> PackedByteArray:
	var b: PackedByteArray = PackedByteArray()
	var _r: int = b.resize(14)
	b[0] = Protocol.QUICK_PING
	return b


static func keyframe_request() -> PackedByteArray:
	return PackedByteArray([Protocol.REQUEST_KEYFRAME, Protocol.KeyframeRequest.DESYNC])


## A link already through HELLO and WELCOME, in LOADING at `now_ms`.
static func loading_link(now_ms: int = 0) -> ClientLink:
	var l: ClientLink = new_link(now_ms)
	var _v: int = l.on_packet(Protocol.CH_CONTROL, hello(), now_ms)
	var _a: bool = l.accept(welcome(), now_ms)
	return l
