class_name PilotBlock extends RefCounted
## The 15-byte pilot block of SNAPSHOT (04 s3.3, s3.5), own possessed unit only, little-endian:
## fuel u16 (0.1 s), ammo u16, bombs u8, rockets u8, hull u16 (exact HP), incoming_rockets u8, boost_state u8
## (bits 0-1 READY / ACTIVE / COOLDOWN, bits 2-7 remaining fraction in 1/63), flip_cooldown01 u8, dock_state u8
## (Protocol.DockState), service_progress 3 x u8 (refuel, rearm, repair; 255 complete, 0 when not docked).
## Values are stored as wire integers and clamp on write.

const BYTES: int = 15
enum Boost { READY, ACTIVE, COOLDOWN }

var fuel_ds: int = 0
var ammo: int = 0
var bombs: int = 0
var rockets: int = 0
var hull: int = 0
var incoming_rockets: int = 0
var boost_state: int = 0
var flip_cooldown: int = 0
var dock_state: int = 0
var service_refuel: int = 0
var service_rearm: int = 0
var service_repair: int = 0


## boost_state byte from a Boost phase and the remaining fraction of its timer.
static func boost_byte(phase: int, remaining01: float) -> int:
	return (phase & 3) | (clampi(roundi(clampf(remaining01, 0.0, 1.0) * 63.0), 0, 63) << 2)


## Writes BYTES at `at`; returns the next offset, or -1 (nothing written) when it does not fit.
func write(buf: PackedByteArray, at: int) -> int:
	if at < 0 or at + BYTES > buf.size():
		return -1
	buf.encode_u16(at, clampi(fuel_ds, 0, 0xFFFF))
	buf.encode_u16(at + 2, clampi(ammo, 0, 0xFFFF))
	buf[at + 4] = clampi(bombs, 0, 255)
	buf[at + 5] = clampi(rockets, 0, 255)
	buf.encode_u16(at + 6, clampi(hull, 0, 0xFFFF))
	buf[at + 8] = clampi(incoming_rockets, 0, 255)
	buf[at + 9] = boost_state & 0xFF
	buf[at + 10] = clampi(flip_cooldown, 0, 255)
	buf[at + 11] = clampi(dock_state, 0, 255)
	buf[at + 12] = clampi(service_refuel, 0, 255)
	buf[at + 13] = clampi(service_rearm, 0, 255)
	buf[at + 14] = clampi(service_repair, 0, 255)
	return at + BYTES


## Reads BYTES at `at`; false (unchanged) when short.
func read(buf: PackedByteArray, at: int) -> bool:
	if at < 0 or at + BYTES > buf.size():
		return false
	fuel_ds = buf.decode_u16(at)
	ammo = buf.decode_u16(at + 2)
	bombs = buf[at + 4]
	rockets = buf[at + 5]
	hull = buf.decode_u16(at + 6)
	incoming_rockets = buf[at + 8]
	boost_state = buf[at + 9]
	flip_cooldown = buf[at + 10]
	dock_state = buf[at + 11]
	service_refuel = buf[at + 12]
	service_rearm = buf[at + 13]
	service_repair = buf[at + 14]
	return true


func copy_from(o: PilotBlock) -> void:
	var tmp: PackedByteArray = PackedByteArray()
	var _r: int = tmp.resize(BYTES)
	var _w: int = o.write(tmp, 0)
	var _ok: bool = read(tmp, 0)


func to_bytes() -> PackedByteArray:
	var tmp: PackedByteArray = PackedByteArray()
	var _r: int = tmp.resize(BYTES)
	var _w: int = write(tmp, 0)
	return tmp
