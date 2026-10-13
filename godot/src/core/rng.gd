class_name Rng extends RefCounted
## PCG32 (XSH-RR 64/32), deterministic given seed and stream, serialisable (03 s2, C6).
## Forks are derived from the origin key stored with the state, so fork() never
## advances the parent and a restored parent yields identical forks.

const _MULT: int = 6364136223846793005
const _FNV_OFFSET: int = -3750763034362895579
const _FNV_PRIME: int = 1099511628211
const _SM_GAMMA: int = -7046029254386353131
const _SM_C1: int = -4658895280553007687
const _SM_C2: int = -7723592293110705685
const _FORK_SALT: int = 6616326156522464677
const _U32_RANGE: int = 4294967296
const _U32_MASK: int = 0xFFFFFFFF
const STATE_BYTES: int = 24

var _state: int = 0
var _inc: int = 1
var _origin: int = 0


## Parameter is named seed_value because `seed` is a GDScript global function.
func _init(seed_value: int, stream: int = 0) -> void:
	_origin = _mix64(seed_value ^ _mix64(stream))
	_inc = (stream << 1) | 1
	_state = 0
	var _r: int = next_u32()
	_state = _state + seed_value
	_r = next_u32()


## Next uniform 32-bit output in [0, 2^32).
func next_u32() -> int:
	var old: int = _state
	_state = old * _MULT + _inc
	var xs: int = _lsr(_lsr(old, 18) ^ old, 27) & _U32_MASK
	var rot: int = _lsr(old, 59) & 31
	return ((xs >> rot) | (xs << ((-rot) & 31))) & _U32_MASK


## Uniform float in [0, 1).
func next_float() -> float:
	return float(next_u32()) / float(_U32_RANGE)


## Unbiased uniform integer in [lo, hi_inclusive].
func range_i(lo: int, hi_inclusive: int) -> int:
	var span: int = hi_inclusive - lo + 1
	if span <= 1:
		return lo
	if span > _U32_RANGE:
		Log.error(&"rng", "range_i span exceeds 2^32: %d" % span)
		return lo
	var threshold: int = (_U32_RANGE - span) % span
	var r: int = next_u32()
	while r < threshold:
		r = next_u32()
	return lo + (r % span)


## Uniform float in [lo, hi).
func range_f(lo: float, hi: float) -> float:
	return lo + (hi - lo) * next_float()


## Serialise: state, increment and origin key, 24 bytes little-endian.
func state() -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	var _e: Error = bytes.resize(STATE_BYTES)
	bytes.encode_s64(0, _state)
	bytes.encode_s64(8, _inc)
	bytes.encode_s64(16, _origin)
	return bytes


static func from_state(bytes: PackedByteArray) -> Rng:
	var r: Rng = Rng.new(0)
	if bytes.size() != STATE_BYTES:
		Log.error(&"rng", "from_state: expected %d bytes, got %d" % [STATE_BYTES, bytes.size()])
		return r
	r._state = bytes.decode_s64(0)
	r._inc = bytes.decode_s64(8)
	r._origin = bytes.decode_s64(16)
	return r


## Deterministic sub-stream keyed by name (e.g. &"ai"). Does not advance this Rng.
func fork(stream: StringName) -> Rng:
	var key: int = _origin ^ _fnv1a(String(stream))
	return Rng.new(_mix64(key), _mix64(key ^ _FORK_SALT))


static func _lsr(x: int, n: int) -> int:
	return (x >> n) & ((1 << (64 - n)) - 1)


static func _mix64(x: int) -> int:
	var z: int = x + _SM_GAMMA
	z = (z ^ _lsr(z, 30)) * _SM_C1
	z = (z ^ _lsr(z, 27)) * _SM_C2
	return z ^ _lsr(z, 31)


static func _fnv1a(text: String) -> int:
	var bytes: PackedByteArray = text.to_utf8_buffer()
	var h: int = _FNV_OFFSET
	for i: int in range(bytes.size()):
		h = (h ^ bytes[i]) * _FNV_PRIME
	return h
