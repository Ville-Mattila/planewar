class_name StateIO
## Byte form of sim state for `SimWorld.serialize` (S4): named script properties written in a fixed order with
## `StreamPeerBuffer.put_var` (packed arrays as raw little-endian blocks, ints as i64, floats as f64), read back with
## a type check per property. Same machine, same build: the bytes are a function of the state alone.


## Writes `o.get(n)` for every name, in order.
static func put_props(buf: StreamPeerBuffer, o: Object, names: PackedStringArray) -> void:
	for n: String in names:
		buf.put_var(o.get(n))


## Reads every name in order into `o`; false (stop) on missing bytes or a type mismatch. Callers check sizes.
static func get_props(buf: StreamPeerBuffer, o: Object, names: PackedStringArray) -> bool:
	for n: String in names:
		if buf.get_available_bytes() <= 0:
			return false
		var v: Variant = buf.get_var()
		if typeof(v) != typeof(o.get(n)):
			return false
		o.set(n, v)
	return true


## Element count of a packed array / String array value, -1 for any other type.
static func size_of(v: Variant) -> int:
	match typeof(v):
		TYPE_PACKED_BYTE_ARRAY:
			var a: PackedByteArray = v
			return a.size()
		TYPE_PACKED_INT32_ARRAY:
			var b: PackedInt32Array = v
			return b.size()
		TYPE_PACKED_INT64_ARRAY:
			var c: PackedInt64Array = v
			return c.size()
		TYPE_PACKED_FLOAT32_ARRAY:
			var d: PackedFloat32Array = v
			return d.size()
		TYPE_PACKED_FLOAT64_ARRAY:
			var e: PackedFloat64Array = v
			return e.size()
		TYPE_PACKED_VECTOR3_ARRAY:
			var f: PackedVector3Array = v
			return f.size()
		TYPE_PACKED_STRING_ARRAY:
			var g: PackedStringArray = v
			return g.size()
	return -1


## True when every property in `names` of `o` is a packed array of exactly `n` elements.
static func sizes_ok(o: Object, names: PackedStringArray, n: int) -> bool:
	for name: String in names:
		if size_of(o.get(name)) != n:
			return false
	return true


## True when `v` (a PackedInt32Array element list) holds values in [lo, hi] for its first `count` entries.
static func ints_in(v: PackedInt32Array, count: int, lo: int, hi: int) -> bool:
	if count < 0 or count > v.size():
		return false
	for i: int in count:
		if v[i] < lo or v[i] > hi:
			return false
	return true
