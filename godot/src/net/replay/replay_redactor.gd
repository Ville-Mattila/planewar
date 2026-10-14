class_name ReplayRedactor
## Redaction in place (04 s13.1, 10.7): a replay is rewritten with player names, user ids and chat text blanked
## WITHOUT changing any length or offset, so `header_len`, every frame length, the INDEX and the FOOTER stay valid
## and the file opens exactly as before. Names and chat text become '*' of the same byte length; user ids become
## zeros. Works on the inflated stream; redact_file() inflates, redacts and re-gzips atomically.

## Returns a redacted copy of the inflated stream `raw`, or an empty array when it is not a readable replay.
static func redact_raw(raw: PackedByteArray, names: bool = true, chat: bool = true, user_ids: bool = true) -> PackedByteArray:
	var r: ReplayReader = ReplayReader.new()
	if r.open_raw(raw) > ReplayFormat.Status.RECOVERED:
		return PackedByteArray()
	var out: PackedByteArray = raw.duplicate()
	var h: ReplayHeader = r.header
	for i: int in h.player_count():
		if user_ids:
			for k: int in ReplayFormat.ID_BYTES:
				out[h.uid_at[i] + k] = 0
		if names:
			_stars(out, h.name_at[i] + 1, out[h.name_at[i]])
	if chat:
		_redact_chat(out, r.frames_begin(), r.frames_end())
	return out


## Blanks `path` (a gzip `.pwr`) in place via a temporary file. Returns an Error.
static func redact_file(path: String, names: bool = true, chat: bool = true, user_ids: bool = true) -> int:
	var data: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if data.is_empty():
		return ERR_FILE_CANT_READ
	var ok: PackedByteArray = PackedByteArray([1])
	var raw: PackedByteArray = ReplayFormat.gunzip(data, ok)
	var red: PackedByteArray = redact_raw(raw, names, chat, user_ids)
	if red.is_empty():
		return ERR_FILE_CORRUPT
	var f: FileAccess = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	var _s: bool = f.store_buffer(ReplayFormat.gzip(red))
	f.close()
	var dir: DirAccess = DirAccess.open(path.get_base_dir())
	if dir == null:
		return ERR_FILE_CANT_OPEN
	var _rm: Error = dir.remove(path.get_file())
	return dir.rename(path + ".tmp", path)


static func _redact_chat(buf: PackedByteArray, begin: int, end: int) -> void:
	var at: int = begin
	while at + ReplayFormat.FRAME_HEADER_BYTES <= end:
		var n: int = buf.decode_u32(at + 5)
		if buf[at] == ReplayFormat.FrameType.CHAT:
			var p: int = at + ReplayFormat.FRAME_HEADER_BYTES
			_stars(buf, p + 12, buf.decode_u16(p + 10))
		at += ReplayFormat.FRAME_HEADER_BYTES + n


static func _stars(buf: PackedByteArray, from: int, count: int) -> void:
	for k: int in count:
		buf[from + k] = 0x2A
