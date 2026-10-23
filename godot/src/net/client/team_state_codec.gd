class_name TeamStateCodec
## TEAM_STATE (0x85, channel 2, <= 72 B) codec (04 s2.3): id u8, tick u32, ore u32, ice u32, ore_cap u32, ice_cap u32,
## power_supply u16, power_demand u16, unit_cap u16, structure_cap u16, flags u8 (TeamStateView bits, only the low four
## defined), member_count u8 (0-8), members[] x (slot u8 0-7, unit_count u16, structure_count u16). Little-endian.
## decode validates the whole message (id, exact length, count, reserved flag bits, member slots unique and < 8,
## tick > 0) before writing `out`; anything else returns false and changes nothing. Static, never throws.

const FIXED_BYTES: int = 31
const MEMBER_BYTES: int = 5
const MEMBERS_MAX: int = 8
const FLAGS_MASK: int = 0x0F
const SLOTS: int = 8


## Empty when a field is out of its wire range or there are more than 8 members.
static func encode(w: TeamStateWire) -> PackedByteArray:
	var n: int = w.member_slot.size()
	if n > MEMBERS_MAX or w.member_units.size() != n or w.member_structures.size() != n or w.tick <= 0 \
			or (w.flags & ~FLAGS_MASK) != 0:
		return PackedByteArray()
	for v: int in [w.ore, w.ice, w.ore_cap, w.ice_cap]:
		if v < 0 or v > 0xFFFFFFFF:
			return PackedByteArray()
	for v: int in [w.power_supply, w.power_demand, w.unit_cap, w.structure_cap]:
		if v < 0 or v > 0xFFFF:
			return PackedByteArray()
	var b: PackedByteArray = PackedByteArray()
	var _r: int = b.resize(FIXED_BYTES + n * MEMBER_BYTES)
	b[0] = Protocol.TEAM_STATE
	b.encode_u32(1, w.tick)
	b.encode_u32(5, w.ore)
	b.encode_u32(9, w.ice)
	b.encode_u32(13, w.ore_cap)
	b.encode_u32(17, w.ice_cap)
	b.encode_u16(21, w.power_supply)
	b.encode_u16(23, w.power_demand)
	b.encode_u16(25, w.unit_cap)
	b.encode_u16(27, w.structure_cap)
	b[29] = w.flags
	b[30] = n
	for k: int in n:
		var at: int = FIXED_BYTES + k * MEMBER_BYTES
		if w.member_slot[k] < 0 or w.member_slot[k] >= SLOTS or w.member_units[k] < 0 or w.member_units[k] > 0xFFFF \
				or w.member_structures[k] < 0 or w.member_structures[k] > 0xFFFF:
			return PackedByteArray()
		b[at] = w.member_slot[k]
		b.encode_u16(at + 1, w.member_units[k])
		b.encode_u16(at + 3, w.member_structures[k])
	return b


static func decode(b: PackedByteArray, out: TeamStateWire) -> bool:
	if not valid(b):
		return false
	out.tick = b.decode_u32(1)
	out.ore = b.decode_u32(5)
	out.ice = b.decode_u32(9)
	out.ore_cap = b.decode_u32(13)
	out.ice_cap = b.decode_u32(17)
	out.power_supply = b.decode_u16(21)
	out.power_demand = b.decode_u16(23)
	out.unit_cap = b.decode_u16(25)
	out.structure_cap = b.decode_u16(27)
	out.flags = b[29]
	out.member_slot.clear()
	out.member_units.clear()
	out.member_structures.clear()
	for k: int in b[30]:
		var at: int = FIXED_BYTES + k * MEMBER_BYTES
		out.add_member(b[at], b.decode_u16(at + 1), b.decode_u16(at + 3))
	return true


static func valid(b: PackedByteArray) -> bool:
	if b.size() < FIXED_BYTES or b.size() > Protocol.max_bytes(Protocol.TEAM_STATE) or b[0] != Protocol.TEAM_STATE:
		return false
	var n: int = b[30]
	if n > MEMBERS_MAX or b.size() != FIXED_BYTES + n * MEMBER_BYTES or (b[29] & ~FLAGS_MASK) != 0 or b.decode_u32(1) == 0:
		return false
	var seen: int = 0
	for k: int in n:
		var s: int = b[FIXED_BYTES + k * MEMBER_BYTES]
		if s >= SLOTS or (seen & (1 << s)) != 0:
			return false
		seen |= 1 << s
	return true


## Tick of a TEAM_STATE message, or -1 when too short.
static func tick_of(b: PackedByteArray) -> int:
	return b.decode_u32(1) if b.size() >= 5 else -1
