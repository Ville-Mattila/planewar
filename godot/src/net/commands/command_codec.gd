class_name CommandCodec
## COMMAND (0x03, channel 0) payload codecs for all 16 `Command.Kind`s (04 s2.5, R0 C2-06, B.14 A-85, NET-04).
## The sim form of `Command.payload` (command.gd) has the same field order but f64 positions; the wire form carries
## positions as vec3q (8 B). `encode_payload` maps sim form -> wire bytes, `decode_payload` wire bytes -> a `Command`
## in sim form (player and tick are the receiver's to set). Decoders check shape only (sizes, counts, enum ranges that
## the sim reader also rejects) and return null on anything malformed: never an exception, never a partial command.
## Legality (rights, ownership, escort_slot range, order rules) belongs to the sim validator. PILOT_INPUT is never a
## COMMAND (input rides INPUT 0x04) and is refused both ways. Message: id u8, seq u16, tick u32, kind u8, target u32,
## len u16, payload (270 B max).

const HEADER_BYTES: int = 14           # id + seq + tick + kind + target + len
const MESSAGE_MAX_BYTES: int = HEADER_BYTES + Protocol.COMMAND_PAYLOAD_MAX
const ORDER_HEADER_BYTES: int = 9      # kind, flags, haul_mode, count, target u32, point_count (04's "8" omits point_count)
const ORDER_MAX_IDS: int = 32
const ORDER_MAX_POINTS: int = 16
const ORDER_KIND_COUNT: int = 12       # OrderSpec.Kind 0-11
const ORDER_KIND_ESCORT: int = 3
const HAUL_MODE_MAX: int = 2           # CAPTURE
const ESCORT_MODE_MAX: int = 2         # BREAK
const ESCORT_TRAILER_BYTES: int = 6
const POINT_WIRE_BYTES: int = 8        # vec3q
const POINT_SIM_BYTES: int = 24        # 3 x f64
const BUILD_BYTES: int = 7
const PRODUCE_BYTES: int = 3
const SET_RALLY_WIRE_BYTES: int = 8
const SET_RALLY_SIM_BYTES: int = 24
const SET_ADJUTANT_BYTES: int = 3
const REPLENISH_PAIR_BYTES: int = 3
const REPLENISH_PAIRS_MAX: int = 8
const DEBUG_SPAWN_BYTES: int = 76
const DEBUG_SET_BYTES: int = 9
const DEBUG_SET_FIELD_MAX: int = 2
const OFF_SEQ: int = 1
const OFF_TICK: int = 3
const OFF_KIND: int = 7
const OFF_TARGET: int = 8
const OFF_LEN: int = 12
const KIND_COUNT: int = 16


## Wire size of an ORDER payload (the sum of its fields plus the ESCORT trailer).
static func order_wire_size(count: int, point_count: int, is_escort: bool) -> int:
	return ORDER_HEADER_BYTES + 4 * count + POINT_WIRE_BYTES * point_count + (ESCORT_TRAILER_BYTES if is_escort else 0)


## True when an ORDER of this shape has legal counts and fits the 256 B payload limit.
static func order_fits(count: int, point_count: int, is_escort: bool) -> bool:
	return count >= 1 and count <= ORDER_MAX_IDS and point_count >= 0 and point_count <= ORDER_MAX_POINTS \
			and order_wire_size(count, point_count, is_escort) <= Protocol.COMMAND_PAYLOAD_MAX


## Sim-form `cmd` -> wire payload in `out` (cleared first). False when `cmd` is not encodable: PILOT_INPUT, a
## malformed or oversize payload, a non-finite or out-of-range position. `out` is empty then.
static func encode_payload(cmd: Command, out: PackedByteArray) -> bool:
	var _c: int = out.resize(0)
	if cmd == null:
		return false
	var b: PackedByteArray = cmd.payload
	match cmd.kind:
		Command.Kind.ORDER:
			return _encode_order(b, out)
		Command.Kind.SET_RALLY:
			if b.size() != SET_RALLY_SIM_BYTES:
				return false
			return _put_point(out, 0, b, 0, true)
		Command.Kind.PILOT_INPUT:
			return false
	if not _shape_ok(cmd.kind, b):
		return false
	out.append_array(b)
	return true


## Wire payload -> sim-form Command (kind, target, payload set; player -1, tick 0). Null when malformed.
static func decode_payload(kind: int, target: int, wire: PackedByteArray) -> Command:
	if kind < 0 or kind >= KIND_COUNT or kind == Command.Kind.PILOT_INPUT or wire.size() > Protocol.COMMAND_PAYLOAD_MAX:
		return null
	var sim: PackedByteArray = PackedByteArray()
	if kind == Command.Kind.ORDER:
		if not _convert_order(wire, sim, false):
			return null
	elif kind == Command.Kind.SET_RALLY:
		if wire.size() != SET_RALLY_WIRE_BYTES or not _put_point(sim, 0, wire, 0, false):
			return null
	else:
		if not _shape_ok(kind, wire):
			return null
		sim = wire
	var c: Command = Command.new()
	c.kind = kind as Command.Kind
	c.target = target & 0xFFFFFFFF
	c.payload = sim
	return c


## Full COMMAND message (0x03) for `cmd`; empty when the payload is not encodable.
static func encode_message(seq: int, tick: int, cmd: Command) -> PackedByteArray:
	var wire: PackedByteArray = PackedByteArray()
	var out: PackedByteArray = PackedByteArray()
	if not encode_payload(cmd, wire):
		return out
	var _r: int = out.resize(HEADER_BYTES + wire.size())
	out[0] = Protocol.COMMAND
	out.encode_u16(OFF_SEQ, seq & 0xFFFF)
	out.encode_u32(OFF_TICK, tick & 0xFFFFFFFF)
	out[OFF_KIND] = cmd.kind
	out.encode_u32(OFF_TARGET, cmd.target & 0xFFFFFFFF)
	out.encode_u16(OFF_LEN, wire.size())
	for i: int in wire.size():
		out[HEADER_BYTES + i] = wire[i]
	return out


## Parses a COMMAND message into a sim-form Command whose `tick` is the sender's stamp; null when malformed.
static func decode_message(bytes: PackedByteArray) -> Command:
	if bytes.size() < HEADER_BYTES or bytes.size() > MESSAGE_MAX_BYTES or bytes[0] != Protocol.COMMAND:
		return null
	var n: int = bytes.decode_u16(OFF_LEN)
	if bytes.size() != HEADER_BYTES + n:
		return null
	var c: Command = decode_payload(bytes[OFF_KIND], bytes.decode_u32(OFF_TARGET), bytes.slice(HEADER_BYTES))
	if c != null:
		c.tick = bytes.decode_u32(OFF_TICK)
	return c


## Sequence number of a message that decoded; -1 when too short.
static func seq_of(bytes: PackedByteArray) -> int:
	return bytes.decode_u16(OFF_SEQ) if bytes.size() >= HEADER_BYTES else -1


## Shapes of the kinds whose bytes are identical in wire and sim form.
static func _shape_ok(kind: int, b: PackedByteArray) -> bool:
	var n: int = b.size()
	match kind:
		Command.Kind.BUILD:
			return n == BUILD_BYTES and b[6] <= 3
		Command.Kind.PRODUCE:
			return n == PRODUCE_BYTES
		Command.Kind.CANCEL_BUILD, Command.Kind.POSSESS, Command.Kind.RELEASE, Command.Kind.REQUEST_POSSESS, \
				Command.Kind.SURRENDER:
			return n == 0
		Command.Kind.CANCEL_PRODUCE, Command.Kind.HANDOVER:
			return n == 1
		Command.Kind.TOGGLE_AUTO_REPLENISH:
			return n >= 1 and (n - 1) % REPLENISH_PAIR_BYTES == 0 and n <= 1 + REPLENISH_PAIR_BYTES * REPLENISH_PAIRS_MAX and b[0] <= 1
		Command.Kind.SET_ADJUTANT:
			return n == SET_ADJUTANT_BYTES and b[1] <= 2   # enabled: any byte, non-zero = on (as the sim)
		Command.Kind.DEBUG_SPAWN:
			return n == DEBUG_SPAWN_BYTES
		Command.Kind.DEBUG_SET:
			return n == DEBUG_SET_BYTES and b[0] <= DEBUG_SET_FIELD_MAX
	return false


## Converts the point at `src_at` of `src` into `dst` at `dst_at` (growing dst). `to_wire`: src is f64 x 3, dst gets
## vec3q (false when non-finite, at the origin, or outside the codable range). Otherwise src is vec3q and dst gets
## f64 x 3 (false for an invalid cell or a point outside the codable band).
static func _put_point(dst: PackedByteArray, dst_at: int, src: PackedByteArray, src_at: int, to_wire: bool) -> bool:
	if to_wire:
		var v: Vector3 = Vector3(src.decode_double(src_at), src.decode_double(src_at + 8), src.decode_double(src_at + 16))
		if not v.is_finite() or v.length_squared() < 1.0 or not Codec.pos_in_range(v):
			return false
		var _r: int = dst.resize(dst_at + POINT_WIRE_BYTES)
		dst.encode_u64(dst_at, Codec.quantize_pos(v))
		return true
	var q: int = src.decode_u64(src_at)
	if (q & 0xFFFF) >= Codec.CELL_COUNT:
		return false
	var p: Vector3 = Codec.dequantize_pos(q)
	if p.length_squared() < 1.0 or not Codec.pos_in_range(p):
		return false   # outside the codable altitude band: would not re-encode
	var _s: int = dst.resize(dst_at + POINT_SIM_BYTES)
	dst.encode_double(dst_at, p.x)
	dst.encode_double(dst_at + 8, p.y)
	dst.encode_double(dst_at + 16, p.z)
	return true


## Point count of an ORDER payload whose points are `pt_bytes` each, or -1 when the shape is malformed.
static func _order_points(b: PackedByteArray, pt_bytes: int) -> int:
	if b.size() < ORDER_HEADER_BYTES:
		return -1
	var n: int = b[3]
	if n < 1 or n > ORDER_MAX_IDS or b.size() < ORDER_HEADER_BYTES + 4 * n:
		return -1
	var np: int = b[8 + 4 * n]
	var esc: bool = b[0] == ORDER_KIND_ESCORT
	if np > ORDER_MAX_POINTS or b[0] >= ORDER_KIND_COUNT or b[2] > HAUL_MODE_MAX:
		return -1
	var base: int = ORDER_HEADER_BYTES + 4 * n + pt_bytes * np
	if b.size() != base + (ESCORT_TRAILER_BYTES if esc else 0):
		return -1
	if esc and b[base] > ESCORT_MODE_MAX:
		return -1
	return np


## ORDER between the forms: header, ids and trailer are copied; points are converted.
static func _convert_order(src: PackedByteArray, dst: PackedByteArray, to_wire: bool) -> bool:
	var sp: int = POINT_SIM_BYTES if to_wire else POINT_WIRE_BYTES
	var dp: int = POINT_WIRE_BYTES if to_wire else POINT_SIM_BYTES
	var np: int = _order_points(src, sp)
	if np < 0:
		return false
	var head: int = ORDER_HEADER_BYTES + 4 * src[3]
	var _r: int = dst.resize(head)
	for i: int in head:
		dst[i] = src[i]
	for k: int in np:
		if not _put_point(dst, head + k * dp, src, head + k * sp, to_wire):
			return false
	if src[0] == ORDER_KIND_ESCORT:
		for i: int in ESCORT_TRAILER_BYTES:
			var _a: bool = dst.push_back(src[head + np * sp + i])
	return true


static func _encode_order(sim: PackedByteArray, out: PackedByteArray) -> bool:
	if not _convert_order(sim, out, true) or out.size() > Protocol.COMMAND_PAYLOAD_MAX:
		var _c: int = out.resize(0)
		return false
	return true
