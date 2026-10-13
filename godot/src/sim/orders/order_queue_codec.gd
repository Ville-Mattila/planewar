class_name OrderQueueCodec extends RefCounted
## Deterministic byte form of an OrderQueue for SimWorld.serialize (03 s3.3 side tables), little-endian:
## u8 format, u16 used-slot count, then per slot (ascending) u16 slot, u8 standing n, u8 pending n and the records:
## u8 kind, flags, haul_mode, escort_mode, point_count; i32 target, focus, escort_slot, issuer, issue_tick, progress;
## 3 x f32 point; point_count x 3 x f32. Not the 04 ORDER wire layout (that one is NET-04's).

const FORMAT: int = 1
const _FIXED: int = 41   # bytes of a record without its patrol points


static func serialize(q: OrderQueue) -> PackedByteArray:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	var used: int = 0
	for s: int in range(1, OrderQueue.SLOTS):
		used += 1 if q.count(s, OrderQueue.STANDING) + q.count(s, OrderQueue.PENDING) > 0 else 0
	buf.put_u8(FORMAT)
	buf.put_u16(used)
	var spec: OrderSpec = OrderSpec.new()
	for s: int in range(1, OrderQueue.SLOTS):
		var ns: int = q.count(s, OrderQueue.STANDING)
		var np: int = q.count(s, OrderQueue.PENDING)
		if ns + np == 0:
			continue
		buf.put_u16(s)
		buf.put_u8(ns)
		buf.put_u8(np)
		for w: int in 2:
			for i: int in ns if w == OrderQueue.STANDING else np:
				var _ok: bool = q.read(s, w, i, spec)
				_put_spec(buf, spec)
	return buf.data_array


## Replaces every queue in `q` from `bytes` and re-syncs the head cache; false (queues emptied) on malformed input.
static func deserialize(q: OrderQueue, bytes: PackedByteArray) -> bool:
	q.reset()
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.data_array = bytes
	var ok: bool = bytes.size() >= 3 and buf.get_u8() == FORMAT
	var used: int = buf.get_u16() if ok else 0
	var seen: int = 0
	while ok and seen < used:
		ok = buf.get_available_bytes() >= 4 and _read_slot(q, buf)
		seen += 1
	ok = ok and buf.get_available_bytes() == 0
	if not ok:
		q.reset()
	q.resync_heads()
	return ok


static func _read_slot(q: OrderQueue, buf: StreamPeerBuffer) -> bool:
	var s: int = buf.get_u16()
	var counts: PackedInt32Array = PackedInt32Array([buf.get_u8(), buf.get_u8()])
	if s < 1 or s >= OrderQueue.SLOTS or counts[0] > OrderQueue.QUEUE_MAX or counts[1] > OrderQueue.QUEUE_MAX \
			or q.count(s, OrderQueue.STANDING) + q.count(s, OrderQueue.PENDING) > 0:
		return false
	var spec: OrderSpec = OrderSpec.new()
	for w: int in 2:
		for _i: int in counts[w]:
			if not _get_spec(buf, spec) or q.restore(s, w, spec) != OrderQueue.Push.OK:
				return false
	return true


static func _put_spec(buf: StreamPeerBuffer, o: OrderSpec) -> void:
	buf.put_u8(o.kind)
	buf.put_u8(o.flags & 0xFF)
	buf.put_u8(o.haul_mode)
	buf.put_u8(o.escort_mode)
	buf.put_u8(o.points.size())
	buf.put_32(o.target)
	buf.put_32(o.focus)
	buf.put_32(o.escort_slot)
	buf.put_32(o.issuer)
	buf.put_32(o.issue_tick)
	buf.put_32(o.progress)
	_put_v3(buf, o.point)
	for p: Vector3 in o.points:
		_put_v3(buf, p)


static func _get_spec(buf: StreamPeerBuffer, o: OrderSpec) -> bool:
	if buf.get_available_bytes() < _FIXED:
		return false
	var k: int = buf.get_u8()
	var f: int = buf.get_u8()
	var h: int = buf.get_u8()
	var em: int = buf.get_u8()
	var np: int = buf.get_u8()
	if k >= OrderSpec.KIND_COUNT or np > OrderQueue.BLOCK_POINTS or h > OrderSpec.HaulMode.CAPTURE \
			or em > OrderSpec.EscortMode.BREAK or buf.get_available_bytes() < _FIXED - 5 + 12 * np:
		return false
	o.kind = k as OrderSpec.Kind
	o.flags = f
	o.haul_mode = h as OrderSpec.HaulMode
	o.escort_mode = em as OrderSpec.EscortMode
	o.target = buf.get_32()
	o.focus = buf.get_32()
	o.escort_slot = buf.get_32()
	o.issuer = buf.get_32()
	o.issue_tick = buf.get_32()
	o.progress = buf.get_32()
	o.point = _get_v3(buf)
	var _e: int = o.points.resize(np)
	for i: int in np:
		o.points[i] = _get_v3(buf)
	return true


static func _put_v3(buf: StreamPeerBuffer, v: Vector3) -> void:
	buf.put_float(v.x)
	buf.put_float(v.y)
	buf.put_float(v.z)


static func _get_v3(buf: StreamPeerBuffer) -> Vector3:
	var x: float = buf.get_float()
	var y: float = buf.get_float()
	return Vector3(x, y, buf.get_float())
