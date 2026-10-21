class_name ReplayReader extends RefCounted
## Reads a `.pwr` (04 s13.1-s13.2). open_bytes / open inflate the stream, parse the HEADER, then the FOOTER and INDEX;
## a file without a valid footer (crash, truncated download) opens as RECOVERED: every complete frame is kept and
## the keyframe index is rebuilt by scanning. next_frame() applies one FRAME to the replicated state (`roster`, the
## decoder's baseline frames, read through current()) and exposes its events / chat / inputs; seek(tick) restores the
## newest keyframe at or before `tick` and fast-forwards silently. A malformed frame stops the reader (CORRUPT),
## it never throws. The whole stream is held inflated (~100 MB for 30 minutes of the canonical scene).

const NO_FRAME: int = 0

var header: ReplayHeader = ReplayHeader.new()
var roster: Roster = Roster.new()
var decoder: SnapshotDecoder = null
var status: int = ReplayFormat.Status.IO_ERROR
var tick: int = 0                           # tick of the last frame applied
var frame_type: int = NO_FRAME              # type of the last frame
var result_hash: PackedByteArray = PackedByteArray()
var ended_tick: int = 0
var has_footer: bool = false
var index_tick: PackedInt32Array = PackedInt32Array()
var index_offset: PackedInt32Array = PackedInt32Array()
## The last frame's packets (wire messages) and decoded side channels.
var packets: Array[PackedByteArray] = []
var events: Array[WireEvent] = []
var chat_id: PackedInt64Array = PackedInt64Array()
var chat_sender: PackedInt32Array = PackedInt32Array()
var chat_scope: PackedInt32Array = PackedInt32Array()
var chat_text: PackedStringArray = PackedStringArray()
var input_slot: PackedInt32Array = PackedInt32Array()
var input_entity: PackedInt32Array = PackedInt32Array()
var input_bytes: PackedByteArray = PackedByteArray()
var _raw: PackedByteArray = PackedByteArray()
var _pos: int = 0
var _end: int = 0


func _init(gravity_mps2: float = 0.0, tick_hz: int = 30) -> void:
	decoder = SnapshotDecoder.new(gravity_mps2, tick_hz, ReplayFormat.REPLAY_TEAM, roster)


func open(path: String) -> int:
	var data: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if data.is_empty():
		status = ReplayFormat.Status.IO_ERROR
		return status
	return open_bytes(data)


## `file` = the gzip bytes.
func open_bytes(file: PackedByteArray) -> int:
	var ok: PackedByteArray = PackedByteArray([1])
	return open_raw(ReplayFormat.gunzip(file, ok), ok[0] == 0)


## `raw` = the inflated stream; `cut` = the gzip stream was incomplete.
func open_raw(raw: PackedByteArray, cut: bool = false) -> int:
	_raw = raw
	status = header.parse(raw)
	if status != ReplayFormat.Status.OK:
		return status
	_end = raw.size()
	has_footer = _read_footer()
	if not has_footer:
		_scan_index()
		status = ReplayFormat.Status.RECOVERED
	elif cut:
		status = ReplayFormat.Status.RECOVERED
	rewind()
	return status


## Back to the first frame with empty state.
func rewind() -> void:
	_pos = header.length
	tick = 0
	frame_type = NO_FRAME
	roster.clear()
	decoder.reset()


## Inflated bytes of the frames: [begin, end) (end excludes INDEX and FOOTER when the footer is valid).
func frames_begin() -> int:
	return header.length


func frames_end() -> int:
	return _end


func at_end() -> bool:
	return _pos + ReplayFormat.FRAME_HEADER_BYTES > _end


## Tick of the next frame without applying it, or -1 at the end.
func peek_tick() -> int:
	return -1 if at_end() else _raw.decode_u32(_pos + 1)


## Reads the next complete frame: its type, or NO_FRAME at the end / on a bad frame (`status` CORRUPT when bad).
## `apply` false only exposes `packets` (ReplayTransport), leaving state untouched.
func next_frame(apply: bool = true) -> int:
	_clear_frame()
	if at_end():
		return NO_FRAME
	var type: int = _raw[_pos]
	var t: int = _raw.decode_u32(_pos + 1)
	var n: int = _raw.decode_u32(_pos + 5)
	var at: int = _pos + ReplayFormat.FRAME_HEADER_BYTES
	if type < ReplayFormat.FrameType.KEYFRAME or type > ReplayFormat.FrameType.INPUT_SUMMARY or at + n > _end:
		return _bad()
	var body: PackedByteArray = _raw.slice(at, at + n)
	var ok: bool = _parse(type, t, body, apply)
	if not ok:
		return _bad()
	_pos = at + n
	tick = t
	frame_type = type
	return type


## Restores the state at `target` (the newest frame with tick <= target): newest keyframe at or before it, then the
## frames up to it. False when the file has no keyframe at or before `target`.
func seek(target: int) -> bool:
	var k: int = seek_keyframe(target)
	if k < 0:
		return false
	while not at_end() and peek_tick() <= target:
		if next_frame() == NO_FRAME:
			return false
	return true


## Positions on the newest keyframe at or before `target` without applying it; returns its tick or -1.
func seek_keyframe(target: int) -> int:
	var best: int = -1
	for i: int in index_tick.size():
		if index_tick[i] <= target:
			best = i
	if best < 0:
		return -1
	rewind()
	_pos = index_offset[best]
	return index_tick[best]


func current() -> BaselineFrame:
	return decoder.current()


## World position of roster index `slot` at the last frame's tick: its baseline entry dead-reckoned forward (an
## entity that moves as predicted writes no record, 04 s3.4). ZERO when the slot has no state.
func position_of(slot: int) -> Vector3:
	var f: BaselineFrame = decoder.current()
	if f == null or slot < 0 or slot >= Roster.CAPACITY or f.present[slot] == 0:
		return Vector3.ZERO
	var def_id: int = roster.def_of(slot)
	var grav: bool = (def_id >= 0 and def_id < decoder.gravity_def.size() and decoder.gravity_def[def_id] != 0)
	var dr: Vector3i = f.shown_levels(slot, f.tick, grav, decoder.gravity, decoder.dt)
	if not DeadReckon.levels_ok(dr):
		return Codec.dequantize_pos(f.pos[slot])
	return Codec.dequantize_pos(Codec.pack_pos(Codec.pos_cell(f.pos[slot]), dr.x, dr.y, dr.z))


func _clear_frame() -> void:
	packets.clear()
	events.clear()
	chat_id.clear()
	chat_sender.clear()
	chat_scope.clear()
	chat_text.clear()
	input_slot.clear()
	input_entity.clear()
	input_bytes.clear()


func _bad() -> int:
	status = ReplayFormat.Status.CORRUPT
	_pos = _end
	return NO_FRAME


func _parse(type: int, t: int, body: PackedByteArray, apply: bool) -> bool:
	if type == ReplayFormat.FrameType.CHAT:
		return _parse_chat(body)
	if type == ReplayFormat.FrameType.INPUT_SUMMARY:
		return _parse_inputs(body)
	if not _split(body):
		return false
	if not apply:
		return true
	if type == ReplayFormat.FrameType.KEYFRAME:
		roster.clear()
		decoder.reset()
	for p: PackedByteArray in packets:
		if not _apply_packet(type, t, p):
			return false
	return true


func _split(body: PackedByteArray) -> bool:
	if body.size() < 2:
		return false
	var count: int = body.decode_u16(0)
	var at: int = 2
	for _i: int in count:
		if at + 2 > body.size():
			return false
		var n: int = body.decode_u16(at)
		at += 2
		if n == 0 or at + n > body.size():
			return false
		packets.append(body.slice(at, at + n))
		at += n
	return at == body.size()


func _apply_packet(type: int, t: int, p: PackedByteArray) -> bool:
	var id: int = p[0]
	var tmp: PackedInt32Array = PackedInt32Array()
	if id == Protocol.ENTITY_META:
		return RosterCodec.decode_meta(p, roster, tmp) >= 0
	if id == Protocol.ROSTER_REMOVE:
		return RosterCodec.decode_remove(p, roster, tmp) >= 0
	if id == Protocol.SNAPSHOT:
		if p.size() > SnapshotCodec.HEADER_BYTES and (p[9] >> Protocol.SNAP_INDEX_SHIFT) == 0:
			decoder.forget_tick(t)
		return decoder.decode(p) == SnapshotDecoder.Status.OK
	if id == Protocol.EVENTS:
		return EventCodec.decode(p, events) >= 0 if type == ReplayFormat.FrameType.EVENTS else false
	return false


func _parse_chat(b: PackedByteArray) -> bool:
	if b.size() < 12:
		return false
	var n: int = b.decode_u16(10)
	if 12 + n != b.size():
		return false
	var _a: bool = chat_id.push_back(b.decode_s64(0))
	var _b: bool = chat_sender.push_back(b[8])
	var _c: bool = chat_scope.push_back(b[9])
	var _d: bool = chat_text.push_back(b.slice(12, 12 + n).get_string_from_utf8())
	return true


func _parse_inputs(b: PackedByteArray) -> bool:
	if b.is_empty():
		return false
	var n: int = b[0]
	if 1 + n * ReplayFormat.INPUT_ENTRY_BYTES != b.size():
		return false
	var per: int = ReplayFormat.INPUT_SUMMARY_TICKS * PilotWire.BYTES
	for i: int in n:
		var at: int = 1 + i * ReplayFormat.INPUT_ENTRY_BYTES
		var _a: bool = input_slot.push_back(b[at])
		var _b: bool = input_entity.push_back(b.decode_u32(at + 1))
		input_bytes.append_array(b.slice(at + 5, at + 5 + per))
	return true


## FOOTER + INDEX; false (nothing kept) when absent or inconsistent.
func _read_footer() -> bool:
	var size: int = _raw.size()
	if size < header.length + ReplayFormat.FOOTER_BYTES or _raw.slice(size - 4, size) != ReplayFormat.END_MAGIC:
		return false
	var f: int = size - ReplayFormat.FOOTER_BYTES
	var idx: int = _raw.decode_u32(f)
	if idx < header.length or idx + 4 > f:
		return false
	var count: int = _raw.decode_u32(idx)
	if idx + 4 + count * 8 != f:
		return false
	index_tick.clear()
	index_offset.clear()
	for i: int in count:
		var off: int = _raw.decode_u32(idx + 8 + i * 8)
		if off < header.length or off >= idx:
			return false
		var _a: bool = index_tick.push_back(_raw.decode_u32(idx + 4 + i * 8))
		var _b: bool = index_offset.push_back(off)
	result_hash = _raw.slice(f + 4, f + 36)
	ended_tick = _raw.decode_u32(f + 36)
	_end = idx
	return true


## No footer: walk the complete frames, remember keyframes, and end at the last whole frame.
func _scan_index() -> void:
	index_tick.clear()
	index_offset.clear()
	var at: int = header.length
	var size: int = _raw.size()
	while at + ReplayFormat.FRAME_HEADER_BYTES <= size:
		var type: int = _raw[at]
		var n: int = _raw.decode_u32(at + 5)
		if type < ReplayFormat.FrameType.KEYFRAME or type > ReplayFormat.FrameType.INPUT_SUMMARY \
				or at + ReplayFormat.FRAME_HEADER_BYTES + n > size:
			break
		if type == ReplayFormat.FrameType.KEYFRAME:
			var _a: bool = index_tick.push_back(_raw.decode_u32(at + 1))
			var _b: bool = index_offset.push_back(at)
		ended_tick = _raw.decode_u32(at + 1)
		at += ReplayFormat.FRAME_HEADER_BYTES + n
	_end = at
