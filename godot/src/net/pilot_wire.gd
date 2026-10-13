class_name PilotWire
## The 8-byte wire form of one `PilotInput` (04 s2.4, R0 C2-09). All static and pure. Layout: thrust u8
## (round(t * 255)), pitch/yaw/roll i8 (round(a * 127)), buttons u8 (bit 7 reserved, masked), bytes 5-6 reserved
## (always written 0; V-INP rejects anything else), tick_lo u8. `quantized` gives the values both ends use, so the
## client predicts with exactly what the server receives (01 s9.4).

const BYTES: int = 8
const THRUST_SCALE: float = 255.0
const AXIS_SCALE: float = 127.0
const BUTTONS_MASK: int = 0x7F
const OFF_RESERVED_A: int = 5
const OFF_RESERVED_B: int = 6
const OFF_TICK_LO: int = 7


## Writes the input at `at`; returns the next offset, or -1 (nothing written) when the buffer is too short.
static func write_into(buf: PackedByteArray, at: int, input: PilotInput, tick: int) -> int:
	if at < 0 or at + BYTES > buf.size():
		return -1
	buf[at] = clampi(roundi(input.thrust * THRUST_SCALE), 0, 255)
	buf[at + 1] = axis_byte(input.pitch)
	buf[at + 2] = axis_byte(input.yaw)
	buf[at + 3] = axis_byte(input.roll)
	buf[at + 4] = input.buttons & BUTTONS_MASK
	buf[at + OFF_RESERVED_A] = 0
	buf[at + OFF_RESERVED_B] = 0
	buf[at + OFF_TICK_LO] = tick & 0xFF
	return at + BYTES


static func to_wire(input: PilotInput, tick: int) -> PackedByteArray:
	var b: PackedByteArray = PackedByteArray()
	var _e: Error = b.resize(BYTES)
	var _n: int = write_into(b, 0, input, tick)
	return b


## Decodes 8 bytes at `offset` into `into` (a fresh PilotInput when null). Null when the buffer is short.
## Reserved bytes are not checked here; `InputCodec.validate` does (V-INP).
static func from_wire(bytes: PackedByteArray, offset: int, into: PilotInput = null) -> PilotInput:
	if offset < 0 or offset + BYTES > bytes.size():
		return null
	var p: PilotInput = into if into != null else PilotInput.new()
	p.thrust = float(bytes[offset]) / THRUST_SCALE
	p.pitch = axis_value(bytes[offset + 1])
	p.yaw = axis_value(bytes[offset + 2])
	p.roll = axis_value(bytes[offset + 3])
	p.buttons = bytes[offset + 4] & BUTTONS_MASK
	return p


static func tick_lo_at(bytes: PackedByteArray, offset: int) -> int:
	return bytes[offset + OFF_TICK_LO]


static func reserved_zero(bytes: PackedByteArray, offset: int) -> bool:
	return bytes[offset + OFF_RESERVED_A] == 0 and bytes[offset + OFF_RESERVED_B] == 0


## The input as the server will see it; apply this to prediction.
static func quantized(input: PilotInput) -> PilotInput:
	var b: PackedByteArray = to_wire(input, 0)
	return from_wire(b, 0)


static func axis_byte(a: float) -> int:
	return clampi(roundi(a * AXIS_SCALE), -127, 127) & 0xFF


static func axis_value(b: int) -> float:
	var s: int = b - 256 if b >= 128 else b
	return float(maxi(s, -127)) / AXIS_SCALE
