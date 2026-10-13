class_name InputCodec
## INPUT (0x04, channel 1, 04 s2.4): id, epoch u16, base_tick u32, ack_tick u32, count u8 (1-3), count x 8-byte
## PilotInput for base_tick .. base_tick + count - 1, newest last (3-tick redundancy). Static, allocation-free
## on the read side. `validate` is the shape half of V-INP (04 s11.3); the epoch and tick window are checked by
## `InputBuffer`, which knows the possession and the server tick.

const HEADER_BYTES: int = 12
const OFF_EPOCH: int = 1
const OFF_BASE: int = 3
const OFF_ACK: int = 7
const OFF_COUNT: int = 11
enum Status { OK, MALFORMED }


static func packet_bytes(count: int) -> int:
	return HEADER_BYTES + count * PilotWire.BYTES


## Builds a packet from `count` consecutive inputs (oldest first) for ticks base_tick .. base_tick + count - 1.
## Empty packet when count is outside 1-3 or inputs is shorter than count.
static func encode(epoch: int, base_tick: int, ack_tick: int, inputs: Array[PilotInput], count: int) -> PackedByteArray:
	var b: PackedByteArray = PackedByteArray()
	if count < 1 or count > Protocol.INPUT_MAX_COUNT or inputs.size() < count:
		return b
	var _e: Error = b.resize(packet_bytes(count))
	b[0] = Protocol.INPUT
	b.encode_u16(OFF_EPOCH, epoch & 0xFFFF)
	b.encode_u32(OFF_BASE, base_tick & 0xFFFFFFFF)
	b.encode_u32(OFF_ACK, ack_tick & 0xFFFFFFFF)
	b[OFF_COUNT] = count
	for i: int in count:
		var _n: int = PilotWire.write_into(b, HEADER_BYTES + i * PilotWire.BYTES, inputs[i], base_tick + i)
	return b


static func validate(bytes: PackedByteArray) -> int:
	if bytes.size() < HEADER_BYTES or bytes[0] != Protocol.INPUT:
		return Status.MALFORMED
	var count: int = bytes[OFF_COUNT]
	if count < 1 or count > Protocol.INPUT_MAX_COUNT or bytes.size() != packet_bytes(count):
		return Status.MALFORMED
	var base: int = bytes.decode_u32(OFF_BASE)
	for i: int in count:
		var at: int = HEADER_BYTES + i * PilotWire.BYTES
		if not PilotWire.reserved_zero(bytes, at) or PilotWire.tick_lo_at(bytes, at) != ((base + i) & 0xFF):
			return Status.MALFORMED
	return Status.OK


static func epoch_of(bytes: PackedByteArray) -> int:
	return bytes.decode_u16(OFF_EPOCH)


static func base_tick_of(bytes: PackedByteArray) -> int:
	return bytes.decode_u32(OFF_BASE)


static func ack_tick_of(bytes: PackedByteArray) -> int:
	return bytes.decode_u32(OFF_ACK)


static func count_of(bytes: PackedByteArray) -> int:
	return bytes[OFF_COUNT]
