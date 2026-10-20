class_name Command extends RefCounted
## One player command (01 s9.4, R0 B.3 `Command.Kind`, ordinals frozen). `SimWorld.apply_command` validates and
## queues it; step 1 of the next `step()` applies it (S1). `payload` is the sim form of the 04 s2.5 layouts:
## same field order, little-endian, but positions are 3 x f64 instead of 04's `vec3q` (quantisation belongs to
## net's codec, NET-04) and PILOT_INPUT carries its four axes as f64 plus `u8 buttons`, so the server applies the
## exact values client prediction used. Field offsets and the readers live in `sim/world/command_payload.gd`.

enum Kind { ORDER, BUILD, CANCEL_BUILD, PRODUCE, CANCEL_PRODUCE, SET_RALLY, POSSESS, RELEASE, REQUEST_POSSESS, HANDOVER,
		PILOT_INPUT, TOGGLE_AUTO_REPLENISH, SURRENDER, SET_ADJUTANT, DEBUG_SPAWN, DEBUG_SET }

var tick: int = 0
var player: int = -1
var kind: Kind = Kind.ORDER
var target: int = 0
var payload: PackedByteArray = PackedByteArray()


## ORDER for `ids` (1-32 entities): u8 order kind, u8 flags, u8 haul_mode, u8 count, u32 ids[count], u32 target,
## u8 point_count, f64 x 3 per point, then for ESCORT only the 6-byte trailer u8 escort_mode, u8 escort_slot
## (0xFF = -1), u32 focus (R0 B.14 A-85). PATROL sends `spec.points`; other kinds send `spec.point` when non-zero.
static func order(_player: int, ids: PackedInt32Array, spec: OrderSpec) -> Command:
	var pts: PackedVector3Array = spec.points
	if spec.kind != OrderSpec.Kind.PATROL:
		pts = PackedVector3Array() if spec.point == Vector3.ZERO else PackedVector3Array([spec.point])
	var n: int = ids.size()
	var b: PackedByteArray = PackedByteArray()
	var esc: bool = spec.kind == OrderSpec.Kind.ESCORT
	var base: int = 9 + 4 * n + 24 * pts.size()
	var _r: int = b.resize(base + (OrderSpec.ESCORT_TRAILER_BYTES if esc else 0))
	b.encode_u8(0, spec.kind)
	b.encode_u8(1, spec.flags)
	b.encode_u8(2, spec.haul_mode)
	b.encode_u8(3, n)
	for i: int in n:
		b.encode_u32(4 + 4 * i, ids[i])
	b.encode_u32(4 + 4 * n, spec.target)
	b.encode_u8(8 + 4 * n, pts.size())
	for k: int in pts.size():
		_put_v3(b, 9 + 4 * n + 24 * k, pts[k])
	if esc:
		b.encode_u8(base, spec.escort_mode)
		b.encode_u8(base + 1, OrderSpec.ESCORT_SLOT_NONE_WIRE if spec.escort_slot < 0 else spec.escort_slot)
		b.encode_u32(base + 2, spec.focus)
	return _make(_player, Kind.ORDER, 0, b)


## BUILD: u16 structure def_id, u32 build cell, u8 rotation (0-3).
static func build(_player: int, def_id: int, cell: int, rotation: int) -> Command:
	var b: PackedByteArray = PackedByteArray()
	var _r: int = b.resize(7)
	b.encode_u16(0, def_id)
	b.encode_u32(2, cell)
	b.encode_u8(6, rotation)
	return _make(_player, Kind.BUILD, 0, b)


## PRODUCE at `factory`: u16 unit def_id, u8 count (1-5).
static func produce(_player: int, factory: int, def_id: int, count: int) -> Command:
	var b: PackedByteArray = PackedByteArray()
	var _r: int = b.resize(3)
	b.encode_u16(0, def_id)
	b.encode_u8(2, count)
	return _make(_player, Kind.PRODUCE, factory, b)


## SET_RALLY at `factory`: f64 x 3 rally position (04 s2.5 `pos`, unquantised in the sim form).
static func set_rally(_player: int, factory: int, pos: Vector3) -> Command:
	var b: PackedByteArray = PackedByteArray()
	var _r: int = b.resize(24)
	_put_v3(b, 0, pos)
	return _make(_player, Kind.SET_RALLY, factory, b)


## TOGGLE_AUTO_REPLENISH (target: one of the player's factories): u8 enabled, then 0-8 pairs of u16 unit def_id, u8 count.
## The roster replaces the player's targets; disabled clears them. `roster` is [def_id, count, def_id, count, ...].
static func toggle_auto_replenish(_player: int, factory: int, enabled: bool, roster: PackedInt32Array) -> Command:
	var b: PackedByteArray = PackedByteArray()
	var _r: int = b.resize(1 + 3 * (roster.size() >> 1))
	b.encode_u8(0, 1 if enabled else 0)
	for k: int in roster.size() >> 1:
		b.encode_u16(1 + 3 * k, roster[2 * k])
		b.encode_u8(3 + 3 * k, roster[2 * k + 1])
	return _make(_player, Kind.TOGGLE_AUTO_REPLENISH, factory, b)


static func possess(_player: int, id: int) -> Command:
	return _make(_player, Kind.POSSESS, id, PackedByteArray())


## RELEASE of the player's current possession (target 0 = whatever it is).
static func release(_player: int) -> Command:
	return _make(_player, Kind.RELEASE, 0, PackedByteArray())


## PILOT_INPUT for the player's possessed entity: f64 thrust, pitch, yaw, roll, u8 buttons.
static func pilot(_player: int, _tick: int, input: PilotInput) -> Command:
	var b: PackedByteArray = PackedByteArray()
	var _r: int = b.resize(33)
	b.encode_double(0, input.thrust)
	b.encode_double(8, input.pitch)
	b.encode_double(16, input.yaw)
	b.encode_double(24, input.roll)
	b.encode_u8(32, input.buttons & 0xFF)
	var c: Command = _make(_player, Kind.PILOT_INPUT, 0, b)
	c.tick = _tick
	return c


## SET_ADJUTANT: u8 enabled, u8 profile (0 assist, 1 caretaker, 2 economy), u8 toggles (bit0..3).
static func set_adjutant(_player: int, enabled: bool, profile: int, toggles: int) -> Command:
	var b: PackedByteArray = PackedByteArray([1 if enabled else 0, profile & 0xFF, toggles & 0xFF])
	return _make(_player, Kind.SET_ADJUTANT, 0, b)


static func _make(p: int, k: Kind, t: int, b: PackedByteArray) -> Command:
	var c: Command = Command.new()
	c.player = p
	c.kind = k
	c.target = t
	c.payload = b
	return c


static func _put_v3(b: PackedByteArray, off: int, v: Vector3) -> void:
	b.encode_double(off, v.x)
	b.encode_double(off + 8, v.y)
	b.encode_double(off + 16, v.z)
