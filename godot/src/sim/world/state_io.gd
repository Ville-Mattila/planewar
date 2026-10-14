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
