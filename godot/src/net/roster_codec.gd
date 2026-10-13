class_name RosterCodec
## ENTITY_META (0x88) and ROSTER_REMOVE (0x90) wire codecs plus the 2-byte REQUEST_KEYFRAME (04 s2.3, s3.1, s3.6).
## ENTITY_META: id u8, count u8, entries[] x (slot u16, generation u16, def_id u16, owner u8, team u8,
## tag str8 = tlen u8 + <= 16 UTF-8 bytes). ROSTER_REMOVE: id u8, count u8, entries[] x (index u16, reason u8).
## Little-endian. Decoders validate the whole packet before touching the roster: a malformed packet is
## rejected with -1 and changes nothing; they never throw.

const META_HEADER_BYTES: int = 2
const META_FIXED_BYTES: int = 9             # 04 s5.6 "9 B" per entry with no tag: 8 fixed + the str8 length byte
const TAG_MAX_BYTES: int = 16
const REMOVE_HEADER_BYTES: int = 2
const REMOVE_ENTRY_BYTES: int = 3
const COUNT_MAX: int = 255                  # count is u8
const KEYFRAME_REQUEST_BYTES: int = 2


## Encodes the roster entries of `slots` into one or more ENTITY_META packets (split at 1,200 B and 255 entries),
## appended to `out`. Slots absent from the roster are skipped. Returns the number of packets appended.
static func encode_meta(roster: Roster, slots: PackedInt32Array, out: Array[PackedByteArray]) -> int:
	var made: int = 0
	var buf: PackedByteArray = PackedByteArray()
	var n: int = 0
	for slot: int in slots:
		if not roster.has(slot):
			continue
		var tag: PackedByteArray = roster.tag_of(slot).to_utf8_buffer().slice(0, TAG_MAX_BYTES)
		var need: int = META_FIXED_BYTES + tag.size()
		if n > 0 and (n >= COUNT_MAX or buf.size() + need > Protocol.MAX_UNRELIABLE_BYTES):
			buf[1] = n
			out.append(buf)
			made += 1
			n = 0
		if n == 0:
			buf = PackedByteArray([Protocol.ENTITY_META, 0])
		_append_meta(buf, roster, slot, tag)
		n += 1
	if n > 0:
		buf[1] = n
		out.append(buf)
		made += 1
	return made


static func _append_meta(buf: PackedByteArray, roster: Roster, slot: int, tag: PackedByteArray) -> void:
	var at: int = buf.size()
	var _r: int = buf.resize(at + META_FIXED_BYTES + tag.size())
	buf.encode_u16(at, slot)
	buf.encode_u16(at + 2, roster.generation_of(slot))
	buf.encode_u16(at + 4, roster.def_of(slot))
	buf[at + 6] = roster.owner_of(slot)
	buf[at + 7] = roster.team_of(slot)
	buf[at + 8] = tag.size()
	for i: int in tag.size():
		buf[at + 9 + i] = tag[i]


## Validates `bytes` then adds every entry to `roster`, appending the slots to `out_slots`. Returns the entry
## count, or -1 (nothing applied) for a wrong id, truncation, trailing bytes, a slot >= Roster.CAPACITY or a tag > 16 B.
static func decode_meta(bytes: PackedByteArray, roster: Roster, out_slots: PackedInt32Array) -> int:
	if bytes.size() < META_HEADER_BYTES or bytes[0] != Protocol.ENTITY_META or bytes.size() > Protocol.MAX_UNRELIABLE_BYTES:
		return -1
	var count: int = bytes[1]
	var at: int = META_HEADER_BYTES
	for _i: int in count:
		if at + META_FIXED_BYTES > bytes.size() or bytes.decode_u16(at) >= Roster.CAPACITY:
			return -1
		var tlen: int = bytes[at + 8]
		if tlen > TAG_MAX_BYTES or at + META_FIXED_BYTES + tlen > bytes.size():
			return -1
		at += META_FIXED_BYTES + tlen
	if at != bytes.size():
		return -1
	at = META_HEADER_BYTES
	for _i: int in count:
		var slot: int = bytes.decode_u16(at)
		var tlen: int = bytes[at + 8]
		var tag: String = ""
		if tlen > 0:
			tag = bytes.slice(at + 9, at + 9 + tlen).get_string_from_utf8()
		var _ok: bool = roster.add(slot, bytes.decode_u16(at + 2), bytes.decode_u16(at + 4), bytes[at + 6], bytes[at + 7], tag)
		var _a: bool = out_slots.append(slot)
		at += META_FIXED_BYTES + tlen
	return count


## Encodes parallel `slots` / `reasons` (Protocol.RosterRemoveReason) into ROSTER_REMOVE packets appended to `out`.
## Entries with an invalid reason or index are skipped: every encoded removal carries a valid reason.
static func encode_remove(slots: PackedInt32Array, reasons: PackedInt32Array, out: Array[PackedByteArray]) -> int:
	var made: int = 0
	var buf: PackedByteArray = PackedByteArray([Protocol.ROSTER_REMOVE, 0])
	var n: int = 0
	for i: int in mini(slots.size(), reasons.size()):
		if slots[i] < 0 or slots[i] >= Roster.CAPACITY or reasons[i] < 0 or reasons[i] >= Roster.REASON_COUNT:
			continue
		if n >= COUNT_MAX or buf.size() + REMOVE_ENTRY_BYTES > Protocol.max_bytes(Protocol.ROSTER_REMOVE):
			buf[1] = n
			out.append(buf)
			made += 1
			buf = PackedByteArray([Protocol.ROSTER_REMOVE, 0])
			n = 0
		var at: int = buf.size()
		var _r: int = buf.resize(at + REMOVE_ENTRY_BYTES)
		buf.encode_u16(at, slots[i])
		buf[at + 2] = reasons[i]
		n += 1
	if n > 0:
		buf[1] = n
		out.append(buf)
		made += 1
	return made


## Validates then removes every listed slot from `roster` with its wire reason. Slots not in the roster are ignored
## (a duplicate packet is harmless). Returns the entry count, or -1 (nothing applied) when malformed.
static func decode_remove(bytes: PackedByteArray, roster: Roster, out_slots: PackedInt32Array) -> int:
	if bytes.size() < REMOVE_HEADER_BYTES or bytes[0] != Protocol.ROSTER_REMOVE or bytes.size() > Protocol.max_bytes(Protocol.ROSTER_REMOVE):
		return -1
	var count: int = bytes[1]
	if bytes.size() != REMOVE_HEADER_BYTES + count * REMOVE_ENTRY_BYTES:
		return -1
	for i: int in count:
		var at: int = REMOVE_HEADER_BYTES + i * REMOVE_ENTRY_BYTES
		if bytes.decode_u16(at) >= Roster.CAPACITY or bytes[at + 2] >= Roster.REASON_COUNT:
			return -1
	for i: int in count:
		var at: int = REMOVE_HEADER_BYTES + i * REMOVE_ENTRY_BYTES
		var slot: int = bytes.decode_u16(at)
		if roster.remove(slot, bytes[at + 2]):
			var _a: bool = out_slots.append(slot)
	return count


## REQUEST_KEYFRAME (0x0B): id, reason u8 (Protocol.KeyframeRequest).
static func encode_request_keyframe(reason: int) -> PackedByteArray:
	return PackedByteArray([Protocol.REQUEST_KEYFRAME, reason & 0xFF])
