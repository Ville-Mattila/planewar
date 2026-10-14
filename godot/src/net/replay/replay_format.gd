class_name ReplayFormat
## `.pwr` constants and byte helpers (04 s13.1, ADR-10). A file is one gzip stream of
## HEADER, FRAME*, INDEX, FOOTER. Frame payloads are a packet container (u16 count, then u16 length + the wire
## message bytes of 04 s3), so every record format is the live one: ENTITY_META (0x88), ROSTER_REMOVE (0x90),
## SNAPSHOT (0x84, the Section 3.4 codec, chunked) and EVENTS (0x87). Integers are little-endian.

const MAGIC: PackedByteArray = [0x50, 0x57, 0x52, 0x31]         # "PWR1"
const END_MAGIC: PackedByteArray = [0x50, 0x57, 0x52, 0x45]     # "PWRE"
const FRAME_HEADER_BYTES: int = 9                                # type u8, tick u32, len u32
const FOOTER_BYTES: int = 44                                     # index_offset u32, result_hash 32, ended_tick u32, "PWRE"
const HASH_BYTES: int = 32
const ID_BYTES: int = 16
const SNAPSHOT_EVERY: int = 3                                    # 10 Hz at 30 Hz sim
const KEYFRAME_TICKS: int = 300                                  # 10 s
const CHUNK_ENTITIES: int = 128                                  # candidates per encode chunk: 128 FULL records < 4 packets
const INPUT_SUMMARY_TICKS: int = 30
const INPUT_ENTRY_BYTES: int = 5 + INPUT_SUMMARY_TICKS * 8       # slot u8, entity u32, 30 x PilotInput wire
const REPLAY_TEAM: int = 15                                      # pseudo-client team: owns nothing, so no ai_tag bytes
const FILE_CAP: int = 20                                         # offline replays kept in user://replays (R0 C2-25)
const FLUSH_BYTES: int = 65536
enum FrameType { KEYFRAME = 1, DELTA = 2, EVENTS = 3, CHAT = 4, INPUT_SUMMARY = 5 }   # append-only
enum Status { OK, RECOVERED, BAD_MAGIC, UNSUPPORTED_VERSION, CORRUPT, IO_ERROR }       # RECOVERED = truncated, frames salvaged


## Reads a str8 (u8 length, UTF-8) at `at`; returns the end offset or -1; text in out[0].
static func read_str8(buf: PackedByteArray, at: int, out: PackedStringArray) -> int:
	if at < 0 or at >= buf.size():
		return -1
	var n: int = buf[at]
	if at + 1 + n > buf.size():
		return -1
	out[0] = buf.slice(at + 1, at + 1 + n).get_string_from_utf8()
	return at + 1 + n


## gzip `raw` into one stream.
static func gzip(raw: PackedByteArray) -> PackedByteArray:
	var gz: StreamPeerGZIP = StreamPeerGZIP.new()
	var _e: Error = gz.start_compression(false, 65535)
	var out: PackedByteArray = PackedByteArray()
	var at: int = 0
	while at < raw.size():
		var r: Array = gz.put_partial_data(raw.slice(at, at + 65536))
		var sent: int = r[1]
		at += sent
		out.append_array(drain(gz))
	_e = gz.finish()
	out.append_array(drain(gz))
	return out


## Inflates a gzip stream; a truncated stream yields every byte that could be decoded; `ok[0]` is 0 when the inflater reported an error.
static func gunzip(data: PackedByteArray, ok: PackedByteArray) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	ok[0] = 0
	if data.size() < 2 or data[0] != 0x1F or data[1] != 0x8B:
		return out
	var gz: StreamPeerGZIP = StreamPeerGZIP.new()
	var _e: Error = gz.start_decompression(false, 65535)
	var at: int = 0
	ok[0] = 1
	while at < data.size():
		var r: Array = gz.put_partial_data(data.slice(at, at + 65536))
		var err: int = r[0]
		var sent: int = r[1]
		if err != OK:
			ok[0] = 0
			break
		at += sent
		out.append_array(drain(gz))
	out.append_array(drain(gz))
	return out


static func drain(gz: StreamPeerGZIP) -> PackedByteArray:
	var n: int = gz.get_available_bytes()
	if n <= 0:
		return PackedByteArray()
	var r: Array = gz.get_data(n)
	var d: PackedByteArray = r[1]
	return d
