class_name CommandPayload
## Offsets and typed readers of the sim form of `Command.payload` (see command.gd; 04 s2.5 field order), plus the
## builders the public `Command` API does not carry (cancels, handover, debug). Readers return a sentinel
## (-1 / false) on a short or malformed payload so `CommandValidator` answers REJECTED_MALFORMED.
## DEBUG_SPAWN (03-defined, R0 B.3 14): u16 def_id, u8 owner, u8 team, f64 x 3 pos, vel, fwd (76 bytes).
## DEBUG_SET (15): target entity; u8 field (SET_HP, SET_FUEL, SET_KILL), f64 value (9 bytes).

const ORDER_MAX_IDS: int = OrderSpec.WIRE_MAX_IDS
const ORDER_MAX_POINTS: int = OrderSpec.WIRE_MAX_POINTS
const PILOT_BYTES: int = 33
const DEBUG_SPAWN_BYTES: int = 76
const DEBUG_SET_BYTES: int = 9
const SET_HP: int = 0
const SET_FUEL: int = 1
const SET_KILL: int = 2


## Fills `spec` and `ids` from an ORDER payload; false when malformed (count 0 or > 32, > 16 points, short).
static func read_order(cmd: Command, spec: OrderSpec, ids: PackedInt32Array) -> bool:
	var b: PackedByteArray = cmd.payload
	if b.size() < OrderSpec.WIRE_HEADER_BYTES:
		return false
	var n: int = b.decode_u8(3)
	if n < 1 or n > ORDER_MAX_IDS or b.size() < OrderSpec.WIRE_HEADER_BYTES + 4 * n:
		return false
	var np: int = b.decode_u8(OrderSpec.WIRE_HEADER_BYTES - 1 + 4 * n)
	var k: int = b.decode_u8(0)
	var esc: bool = k == OrderSpec.Kind.ESCORT
	var base: int = OrderSpec.WIRE_HEADER_BYTES + 4 * n + 24 * np
	if np > ORDER_MAX_POINTS or b.size() != base + (OrderSpec.ESCORT_TRAILER_BYTES if esc else 0):
		return false
	var hm: int = b.decode_u8(2)
	if k >= OrderSpec.KIND_COUNT or hm > OrderSpec.HaulMode.CAPTURE:
		return false
	if esc and b.decode_u8(base) > OrderSpec.EscortMode.BREAK:
		return false
	spec.kind = k as OrderSpec.Kind
	spec.flags = b.decode_u8(1)
	spec.haul_mode = hm as OrderSpec.HaulMode
	spec.target = b.decode_u32(4 + 4 * n)
	spec.point = Vector3.ZERO
	spec.escort_mode = OrderSpec.EscortMode.FORM
	spec.escort_slot = -1
	spec.focus = 0
	if esc:
		_read_escort_trailer(b, base, spec)
	var _r: int = spec.points.resize(0)
	var _s: int = ids.resize(n)
	for i: int in n:
		ids[i] = b.decode_u32(4 + 4 * i)
	for q: int in np:
		var v: Vector3 = v3_at(b, 9 + 4 * n + 24 * q)
		if spec.kind == OrderSpec.Kind.PATROL:
			var _a: bool = spec.points.push_back(v)
		elif q == 0:
			spec.point = v
	return true


static func _read_escort_trailer(b: PackedByteArray, off: int, spec: OrderSpec) -> void:
	spec.escort_mode = b.decode_u8(off) as OrderSpec.EscortMode
	var sl: int = b.decode_u8(off + 1)
	spec.escort_slot = -1 if sl == OrderSpec.ESCORT_SLOT_NONE_WIRE else sl
	spec.focus = b.decode_u32(off + 2)


## Fills `out` from a PILOT_INPUT payload; false when short.
static func read_pilot(cmd: Command, out: PilotInput) -> bool:
	var b: PackedByteArray = cmd.payload
	if b.size() != PILOT_BYTES:
		return false
	out.thrust = b.decode_double(0)
	out.pitch = b.decode_double(8)
	out.yaw = b.decode_double(16)
	out.roll = b.decode_double(24)
	out.buttons = b.decode_u8(32)
	return true


## u8 at `off`, or -1 when the payload is too short.
static func u8_at(cmd: Command, off: int) -> int:
	return cmd.payload.decode_u8(off) if cmd.payload.size() > off else -1


## u16 at `off`, or -1 when the payload is too short.
static func u16_at(cmd: Command, off: int) -> int:
	return cmd.payload.decode_u16(off) if cmd.payload.size() >= off + 2 else -1


## u32 at `off`, or -1 when the payload is too short.
static func u32_at(cmd: Command, off: int) -> int:
	return cmd.payload.decode_u32(off) if cmd.payload.size() >= off + 4 else -1


static func v3_at(b: PackedByteArray, off: int) -> Vector3:
	return Vector3(b.decode_double(off), b.decode_double(off + 8), b.decode_double(off + 16))


static func cancel_build(player: int, structure: int) -> Command:
	return _make(player, Command.Kind.CANCEL_BUILD, structure, PackedByteArray())


static func cancel_produce(player: int, factory: int, queue_index: int) -> Command:
	return _make(player, Command.Kind.CANCEL_PRODUCE, factory, PackedByteArray([queue_index & 0xFF]))


static func handover(player: int, id: int, to_slot: int) -> Command:
	return _make(player, Command.Kind.HANDOVER, id, PackedByteArray([to_slot & 0xFF]))


static func simple(player: int, kind: Command.Kind, target: int) -> Command:
	return _make(player, kind, target, PackedByteArray())


static func debug_spawn(player: int, def_id: int, owner: int, team: int, p: Vector3, v: Vector3, fwd: Vector3) -> Command:
	var b: PackedByteArray = PackedByteArray()
	var _r: int = b.resize(DEBUG_SPAWN_BYTES)
	b.encode_u16(0, def_id)
	b.encode_u8(2, owner & 0xFF)
	b.encode_u8(3, team & 0xFF)
	_put_v3(b, 4, p)
	_put_v3(b, 28, v)
	_put_v3(b, 52, fwd)
	return _make(player, Command.Kind.DEBUG_SPAWN, 0, b)


static func debug_set(player: int, target: int, field: int, value: float) -> Command:
	var b: PackedByteArray = PackedByteArray()
	var _r: int = b.resize(DEBUG_SET_BYTES)
	b.encode_u8(0, field)
	b.encode_double(1, value)
	return _make(player, Command.Kind.DEBUG_SET, target, b)


static func _make(player: int, kind: Command.Kind, target: int, b: PackedByteArray) -> Command:
	var c: Command = Command.new()
	c.player = player
	c.kind = kind
	c.target = target
	c.payload = b
	return c


static func _put_v3(b: PackedByteArray, off: int, v: Vector3) -> void:
	b.encode_double(off, v.x)
	b.encode_double(off + 8, v.y)
	b.encode_double(off + 16, v.z)
