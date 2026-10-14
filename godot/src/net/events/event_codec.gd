class_name EventCodec
## EVENTS (0x87) wire codec (04 s3.6, R0 C2-03). Packet: id u8, tick u32, count u8, events[] x (kind u8, size u8,
## payload). Payload layouts are table driven: SCHEMA holds the field widths per `SimEvent.Kind` (1 = u8, 2 = u16
## little-endian, POS = vec3q 8 B), 0 ends a row; kind 17 (MATCH_END, message 0x8E) has an empty row and is invalid
## here. The decoder validates the whole packet (kinds, exact sizes, positions, no trailing bytes) before it
## builds anything: anything else returns -1, never throws, changes nothing.

const POS: int = 8
const ROW: int = 8                          # SCHEMA stride (max 7 fields + terminator)
const KIND_COUNT: int = 34
const HEADER_BYTES: int = 6
const EVENT_HEADER_BYTES: int = 2
const COUNT_MAX: int = 255
const NONE_REF: int = 0xFFFF                # roster index of an entity outside the client's roster
const SCHEMA: PackedInt32Array = [
	2, 2, 1, 0, 0, 0, 0, 0,                 # 0 SPAWN: roster, def, owner
	2, 2, 1, 0, 0, 0, 0, 0,                 # 1 DEATH: roster, killer, cause
	2, 2, 1, 2, 1, 0, 0, 0,                 # 2 HIT: target, attacker, seed, damage u16, part
	8, 2, 1, 0, 0, 0, 0, 0,                 # 3 BOMB_IMPACT: pos, projectile def, owner
	2, 2, 0, 0, 0, 0, 0, 0,                 # 4 DOCKED
	2, 2, 1, 0, 0, 0, 0, 0,                 # 5 SERVICED
	2, 2, 0, 0, 0, 0, 0, 0,                 # 6 LAUNCHED
	2, 1, 0, 0, 0, 0, 0, 0,                 # 7 ORDER_DONE
	2, 1, 1, 0, 0, 0, 0, 0,                 # 8 ORDER_FAILED
	2, 1, 0, 0, 0, 0, 0, 0,                 # 9 POSSESSED
	2, 1, 1, 0, 0, 0, 0, 0,                 # 10 RELEASED
	2, 2, 1, 0, 0, 0, 0, 0,                 # 11 BUILD_STARTED
	2, 2, 0, 0, 0, 0, 0, 0,                 # 12 BUILD_DONE
	2, 2, 2, 0, 0, 0, 0, 0,                 # 13 STRUCTURE_LOST
	1, 1, 0, 0, 0, 0, 0, 0,                 # 14 LOW_POWER
	1, 2, 8, 1, 0, 0, 0, 0,                 # 15 ALERT
	1, 0, 0, 0, 0, 0, 0, 0,                 # 16 CORE_EXPOSURE
	0, 0, 0, 0, 0, 0, 0, 0,                 # 17 MATCH_END (never in EVENTS)
	1, 1, 0, 0, 0, 0, 0, 0,                 # 18 CAP_REACHED
	2, 2, 2, 0, 0, 0, 0, 0,                 # 19 WRECK_SPAWNED
	2, 2, 2, 0, 0, 0, 0, 0,                 # 20 WRECK_SALVAGED
	2, 1, 0, 0, 0, 0, 0, 0,                 # 21 CEILING_RELEASE
	2, 1, 1, 0, 0, 0, 0, 0,                 # 22 HANDOVER
	1, 1, 0, 0, 0, 0, 0, 0,                 # 23 PLAYER_ELIMINATED
	2, 2, 0, 0, 0, 0, 0, 0,                 # 24 LOCK_ACQUIRED
	2, 2, 0, 0, 0, 0, 0, 0,                 # 25 LOCK_BROKEN
	2, 1, 1, 0, 0, 0, 0, 0,                 # 26 CAPTURE_PROGRESS
	2, 1, 0, 0, 0, 0, 0, 0,                 # 27 CAPTURED
	2, 2, 2, 0, 0, 0, 0, 0,                 # 28 SALVAGE_DELIVERED
	2, 2, 1, 1, 1, 1, 1, 0,                 # 29 LANDING
	2, 0, 0, 0, 0, 0, 0, 0,                 # 30 SHIELD_COLLAPSE
	2, 1, 0, 0, 0, 0, 0, 0,                 # 31 POSSESS_REQUESTED
	2, 1, 0, 0, 0, 0, 0, 0,                 # 32 CANISTER_DEPLOYED
	2, 2, 0, 0, 0, 0, 0, 0,                 # 33 CANISTER_COLLECTED
]


static var _fields: PackedInt32Array = PackedInt32Array()
static var _payload: PackedInt32Array = PackedInt32Array()


static func _static_init() -> void:
	var _r1: int = _fields.resize(KIND_COUNT)
	var _r2: int = _payload.resize(KIND_COUNT)
	for k: int in KIND_COUNT:
		var n: int = 0
		var bytes: int = 0
		while n < ROW and SCHEMA[k * ROW + n] != 0:
			bytes += SCHEMA[k * ROW + n]
			n += 1
		_fields[k] = n
		_payload[k] = bytes


## True for a kind that travels in EVENTS.
static func is_valid_kind(kind: int) -> bool:
	return kind >= 0 and kind < KIND_COUNT and _fields[kind] != 0


## Payload bytes of `kind` (excluding kind+size), 0 for an invalid kind.
static func payload_bytes(kind: int) -> int:
	return _payload[kind] if kind >= 0 and kind < KIND_COUNT else 0


## Field count of `kind` (position counts as one field).
static func field_count(kind: int) -> int:
	return _fields[kind] if kind >= 0 and kind < KIND_COUNT else 0


## Starts a packet: id, tick, count 0. `buf` must hold >= HEADER_BYTES. Returns the first event offset.
static func write_header(buf: PackedByteArray, tick: int) -> int:
	buf[0] = Protocol.EVENTS
	var _n: int = Codec.write_u32(buf, 1, tick)
	buf[5] = 0
	return HEADER_BYTES


## Writes one event at `at`: values in table order (`pos_q` is used for the POS field). Returns the next offset,
## or -1 without writing when it does not fit in `buf` or the kind is invalid.
static func write_event(buf: PackedByteArray, at: int, kind: int, vals: PackedInt32Array, pos_q: int) -> int:
	if not is_valid_kind(kind):
		return -1
	var size: int = payload_bytes(kind)
	if at < 0 or at + EVENT_HEADER_BYTES + size > buf.size():
		return -1
	buf[at] = kind
	buf[at + 1] = size
	var p: int = at + EVENT_HEADER_BYTES
	for i: int in field_count(kind):
		var w: int = SCHEMA[kind * ROW + i]
		if w == POS:
			var _n: int = Codec.write_pos(buf, p, pos_q)
		elif w == 2:
			buf.encode_u16(p, vals[i] & 0xFFFF)
		else:
			buf[p] = vals[i] & 0xFF
		p += w
	return p


## Validates `bytes` completely, then appends one WireEvent per entry to `out`. Returns the event count, or -1
## (nothing appended) for a wrong id, bad length, count 0, an invalid kind, a size that differs from the table,
## an invalid position cell, truncation or trailing bytes.
static func decode(bytes: PackedByteArray, out: Array[WireEvent]) -> int:
	var n: int = _validate(bytes)
	if n < 0:
		return -1
	var tick: int = Codec.read_u32(bytes, 1)
	var at: int = HEADER_BYTES
	for _i: int in n:
		var e: WireEvent = WireEvent.new()
		e.kind = bytes[at]
		e.tick = tick
		e.count = field_count(e.kind)
		var _r: int = e.v.resize(e.count)
		var p: int = at + EVENT_HEADER_BYTES
		for f: int in e.count:
			var w: int = SCHEMA[e.kind * ROW + f]
			if w == POS:
				e.pos_q = Codec.read_pos(bytes, p)
				e.pos = Codec.dequantize_pos(e.pos_q)
			elif w == 2:
				e.v[f] = bytes.decode_u16(p)
			else:
				e.v[f] = bytes[p]
			p += w
		at += EVENT_HEADER_BYTES + bytes[at + 1]
		out.append(e)
	return n


static func _validate(bytes: PackedByteArray) -> int:
	var total: int = bytes.size()
	if total < HEADER_BYTES + EVENT_HEADER_BYTES or total > Protocol.MAX_UNRELIABLE_BYTES or bytes[0] != Protocol.EVENTS:
		return -1
	var n: int = bytes[5]
	if n == 0:
		return -1
	var at: int = HEADER_BYTES
	for _i: int in n:
		if at + EVENT_HEADER_BYTES > total:
			return -1
		var kind: int = bytes[at]
		if not is_valid_kind(kind) or bytes[at + 1] != payload_bytes(kind) or at + EVENT_HEADER_BYTES + bytes[at + 1] > total:
			return -1
		if not _positions_ok(bytes, at, kind):
			return -1
		at += EVENT_HEADER_BYTES + bytes[at + 1]
	return n if at == total else -1


static func _positions_ok(bytes: PackedByteArray, at: int, kind: int) -> bool:
	var p: int = at + EVENT_HEADER_BYTES
	for f: int in field_count(kind):
		var w: int = SCHEMA[kind * ROW + f]
		if w == POS and Codec.read_pos(bytes, p) == Codec.POS_INVALID:
			return false
		p += w
	return true
