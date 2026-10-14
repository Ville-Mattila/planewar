class_name ReplayWriter extends RefCounted
## Writes a `.pwr` (04 s13.1, ADR-10): a pseudo-client whose interest set is everything, fed from the SnapshotCodec's
## shared per-tick cache (prepare_tick already ran for the live clients, so nothing is re-quantised). Every 3rd tick
## record_tick() encodes all live entities as A-tier records against the previous written frame (a lossless
## baseline) in chunks of CHUNK_ENTITIES, so a frame is any number of SNAPSHOT packets; a keyframe (no baseline,
## every record FULL, plus ENTITY_META for the whole roster) opens the file and repeats every 10 s. Events go
## through EventRouter with an unfiltered audience. Output is one streaming gzip; memory is the flush window only.
## open_file() writes `<path>.part` and renames on finish(); open_memory() keeps the stream for tests.

var frames_written: int = 0
var keyframes: int = 0
var raw_bytes: int = 0                      # uncompressed stream bytes so far
var bytes_out: int = 0                      # gzip bytes produced so far
var deferred: int = 0                       # records the packet cap deferred (must stay 0)
var last_error: int = OK
var meta_us: int = 0                        # cumulative microseconds: roster diff, snapshot encode, container + gzip
var encode_us: int = 0
var io_us: int = 0
var _store: BaselineStore = BaselineStore.new(ReplayFormat.REPLAY_TEAM)
var _sent: Roster = Roster.new()
var _router: EventRouter = EventRouter.new()
var _aud: EventAudience = EventAudience.new()
var _auds: Array[EventAudience] = []
var _gz: StreamPeerGZIP = StreamPeerGZIP.new()
var _pending: PackedByteArray = PackedByteArray()
var _out: PackedByteArray = PackedByteArray()
var _file: FileAccess = null
var _path: String = ""
var _last_snap: int = -1
var _last_key: int = -1
var _index_tick: PackedInt32Array = PackedInt32Array()
var _index_off: PackedInt32Array = PackedInt32Array()
var _stamp: PackedInt32Array = PackedInt32Array()
var _sent_gen: PackedInt32Array = PackedInt32Array()   # generation last sent per slot, -1 = not in the reader's roster
var _live: PackedInt32Array = PackedInt32Array()
var _packets: Array[PackedByteArray] = []
var _scratch: Array[PackedByteArray] = []
var _slots_a: PackedInt32Array = PackedInt32Array()
var _reasons: PackedInt32Array = PackedInt32Array()
var _none: PackedInt32Array = PackedInt32Array()
var _open: bool = false


func _init() -> void:
	var _r: int = _stamp.resize(Roster.CAPACITY)
	_stamp.fill(-1)
	var _g: int = _sent_gen.resize(Roster.CAPACITY)
	_sent_gen.fill(-1)
	_aud.unfiltered = true
	_auds.append(_aud)


## Streams to `<path>.part`; finish() renames it to `path`. Returns an Error.
func open_file(path: String, header: ReplayHeader) -> int:
	_file = FileAccess.open(path + ".part", FileAccess.WRITE)
	if _file == null:
		last_error = FileAccess.get_open_error()
		return last_error
	_path = path
	return _start(header)


func open_memory(header: ReplayHeader) -> int:
	_path = ""
	return _start(header)


func _start(header: ReplayHeader) -> int:
	var _e: Error = _gz.start_compression(false, 65535)
	_open = true
	_put(header.to_bytes())
	return OK


## Call once per sim tick after SnapshotCodec.prepare_tick(frame) for `tick`. `slots` = every live roster index
## (Interest.all_ids), `roster` the authoritative roster (def / owner / team / generation per slot), `events` =
## SimWorld.drain_events() for the tick (may be empty). Writes an EVENTS frame when events routed, and a snapshot
## frame on every SNAPSHOT_EVERY-th tick.
func record_tick(codec: SnapshotCodec, tick: int, slots: PackedInt32Array, roster: Roster, events: Array[SimEvent]) -> void:
	if not _open or tick <= 0:
		return
	if not events.is_empty():
		_aud.roster = roster
		_router.route(tick, events, _auds)
		if not _aud.outbox.is_empty():
			_frame(ReplayFormat.FrameType.EVENTS, tick, _container(_aud.outbox))
		_aud.clear_out()
	if _last_snap < 0 or tick - _last_snap >= ReplayFormat.SNAPSHOT_EVERY:
		_snapshot(codec, tick, slots, roster)


func _snapshot(codec: SnapshotCodec, tick: int, slots: PackedInt32Array, roster: Roster) -> void:
	var key: bool = _last_key < 0 or tick - _last_key >= ReplayFormat.KEYFRAME_TICKS
	if key:
		_store.reset()
		_sent.clear()
		_sent_gen.fill(-1)
	else:
		_store.ack(_last_snap)
	_live.clear()
	for s: int in slots:
		if roster.has(s):
			var _p: bool = _live.push_back(s)
			_stamp[s] = tick
	_packets.clear()
	var t0: int = Time.get_ticks_usec()
	_meta(roster, tick)
	var t1: int = Time.get_ticks_usec()
	var has_snap: bool = _encode(codec, tick)
	var t2: int = Time.get_ticks_usec()
	meta_us += t1 - t0
	encode_us += t2 - t1
	if not has_snap and _packets.is_empty():
		return
	if has_snap:
		_last_snap = tick
	if key and has_snap:
		_last_key = tick
		keyframes += 1
		var _a: bool = _index_tick.push_back(tick)
		var _b: bool = _index_off.push_back(raw_bytes)
	_frame(ReplayFormat.FrameType.KEYFRAME if key and has_snap else ReplayFormat.FrameType.DELTA, tick, _container(_packets))
	io_us += Time.get_ticks_usec() - t2


## ENTITY_META for new or recycled slots, ROSTER_REMOVE for slots that left; keeps `_sent` equal to the reader's roster.
func _meta(roster: Roster, tick: int) -> void:
	_slots_a.clear()
	for s: int in _live:
		var gen: int = roster.generation_of(s)
		if _sent_gen[s] != gen:
			_sent_gen[s] = gen
			var _p: bool = _slots_a.push_back(s)
			var _ok: bool = _sent.add(s, gen, roster.def_of(s), roster.owner_of(s), roster.team_of(s), roster.tag_of(s))
	var _n: int = RosterCodec.encode_meta(_sent, _slots_a, _packets) if not _slots_a.is_empty() else 0
	if _sent.count() == _live.size():
		return                              # `_sent` now holds every live slot, so nothing left
	_slots_a.clear()
	_reasons.clear()
	for s: int in Roster.CAPACITY:
		if _sent_gen[s] >= 0 and _stamp[s] != tick:
			_sent_gen[s] = -1
			var _q: bool = _slots_a.push_back(s)
			var _r: bool = _reasons.push_back(Protocol.RosterRemoveReason.DEATH)
			var _x: bool = _sent.remove(s, Protocol.RosterRemoveReason.DEATH)
	if not _slots_a.is_empty():
		var _m: int = RosterCodec.encode_remove(_slots_a, _reasons, _packets)


## SNAPSHOT packets for all live slots in chunks; false when no record was written.
func _encode(codec: SnapshotCodec, tick: int) -> bool:
	var any: bool = false
	var saved_max: int = codec.max_packets
	codec.max_packets = SnapshotCodec.MAX_PACKETS_PER_TICK
	var at: int = 0
	var sorted: PackedInt32Array = _live.duplicate()
	sorted.sort()
	while at < sorted.size():
		_scratch.clear()
		codec.append_frame = at > 0
		var _n: int = codec.encode(_store, tick, sorted.slice(at, at + ReplayFormat.CHUNK_ENTITIES), _none, _none, null, _scratch)
		deferred += codec.deferred
		for p: PackedByteArray in _scratch:
			if p.size() > SnapshotCodec.HEADER_BYTES:
				_packets.append(p)
				any = true
		at += ReplayFormat.CHUNK_ENTITIES
	codec.append_frame = false
	codec.max_packets = saved_max
	return any


## CHAT frame (04 s10.7: the only copy of chat text).
func record_chat(tick: int, msg_id: int, sender: int, scope: int, text: String) -> void:
	if not _open:
		return
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.put_u64(msg_id)
	b.put_u8(sender)
	b.put_u8(scope)
	var u: PackedByteArray = text.to_utf8_buffer().slice(0, 65535)
	b.put_u16(u.size())
	var _e: Error = b.put_data(u)
	_frame(ReplayFormat.FrameType.CHAT, tick, b.data_array)


## INPUT_SUMMARY frame (1 Hz): per possessing player slot u8, entity u32, 30 x 8 B PilotWire inputs.
func record_input_summary(tick: int, player_slots: PackedInt32Array, entities: PackedInt32Array, inputs: PackedByteArray) -> void:
	var n: int = player_slots.size()
	if not _open or n > 255 or entities.size() != n or inputs.size() != n * ReplayFormat.INPUT_SUMMARY_TICKS * PilotWire.BYTES:
		return
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.put_u8(n)
	var per: int = ReplayFormat.INPUT_SUMMARY_TICKS * PilotWire.BYTES
	for i: int in n:
		b.put_u8(player_slots[i])
		b.put_u32(entities[i])
		var _e: Error = b.put_data(inputs.slice(i * per, (i + 1) * per))
	_frame(ReplayFormat.FrameType.INPUT_SUMMARY, tick, b.data_array)


## Writes INDEX and FOOTER, finishes the gzip stream and (file mode) renames `.part`. Returns the whole file in
## memory mode, else an empty array. `result_hash` is 32 bytes (zero-padded).
func finish(result_hash: PackedByteArray, ended_tick: int) -> PackedByteArray:
	if not _open:
		return PackedByteArray()
	_open = false
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	var index_offset: int = raw_bytes
	b.put_u32(_index_tick.size())
	for i: int in _index_tick.size():
		b.put_u32(_index_tick[i])
		b.put_u32(_index_off[i])
	var h: PackedByteArray = result_hash.slice(0, ReplayFormat.HASH_BYTES)
	var _r: int = h.resize(ReplayFormat.HASH_BYTES)
	b.put_u32(index_offset)
	var _e: Error = b.put_data(h)
	b.put_u32(ended_tick)
	_e = b.put_data(ReplayFormat.END_MAGIC)
	_put(b.data_array)
	_flush()
	_e = _gz.finish()
	_drain()
	if _file != null:
		_file.close()
		_file = null
		var dir: DirAccess = DirAccess.open(_path.get_base_dir())
		if dir == null or dir.rename(_path + ".part", _path) != OK:
			last_error = ERR_FILE_CANT_WRITE
		return PackedByteArray()
	return _out


func _frame(type: int, tick: int, payload: PackedByteArray) -> void:
	var head: PackedByteArray = PackedByteArray()
	var _r: int = head.resize(ReplayFormat.FRAME_HEADER_BYTES)
	head[0] = type
	head.encode_u32(1, tick)
	head.encode_u32(5, payload.size())
	_put(head)
	_put(payload)
	frames_written += 1


## Packet container: u16 count, then u16 length + bytes per packet.
func _container(packets: Array[PackedByteArray]) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	var _r: int = out.resize(2)
	out.encode_u16(0, packets.size())
	for p: PackedByteArray in packets:
		var at: int = out.size()
		var _q: int = out.resize(at + 2)
		out.encode_u16(at, p.size())
		out.append_array(p)
	return out


func _put(bytes: PackedByteArray) -> void:
	_pending.append_array(bytes)
	raw_bytes += bytes.size()
	if _pending.size() >= ReplayFormat.FLUSH_BYTES:
		_flush()


func _flush() -> void:
	var at: int = 0
	while at < _pending.size():
		var r: Array = _gz.put_partial_data(_pending.slice(at, at + 65536))
		var sent: int = r[1]
		at += sent
		_drain()
	_pending.clear()


func _drain() -> void:
	var d: PackedByteArray = ReplayFormat.drain(_gz)
	if d.is_empty():
		return
	bytes_out += d.size()
	if _file != null:
		var _ok: bool = _file.store_buffer(d)
	else:
		_out.append_array(d)
