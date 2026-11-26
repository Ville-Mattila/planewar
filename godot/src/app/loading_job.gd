class_name LoadingJob extends RefCounted
## Loading-screen job (06 s8, 03 s11.1): verifies the SHA-256 of every baked map output listed in `meta.json`
## through ChunkedHasher, one time-budgeted step per call (call `step()` once per frame so the single-threaded web
## build never stalls). `Terrain.load_map` still does the authoritative check; this keeps the loading screen alive.
## Map files live in res://; nothing here touches user:// (that goes through Saves.try_*).

const META_FILE: String = "meta.json"

## file name -> expected hex digest, from meta.json `outputs`.
var expected: Dictionary = {}

var _dir: String = ""
var _files: Array[String] = []
var _index: int = 0
var _hasher: ChunkedHasher = ChunkedHasher.new()
var _error: Error = OK
var _done: bool = false


## Reads meta.json and queues the outputs. Returns OK, or an error (the job is then already done).
func begin(map_dir: String) -> Error:
	_dir = map_dir
	_files.clear()
	_index = 0
	_error = OK
	_done = false
	var path: String = map_dir.path_join(META_FILE)
	if not FileAccess.file_exists(path):
		return _fail(ERR_FILE_NOT_FOUND)
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (meta is Dictionary):
		return _fail(ERR_FILE_CANT_READ)
	var m: Dictionary = meta
	var outs: Variant = m.get("outputs", {})
	if not (outs is Dictionary):
		return _fail(ERR_INVALID_DATA)
	var od: Dictionary = outs
	if od.is_empty():
		return _fail(ERR_INVALID_DATA)
	expected = od
	var names: Array = expected.keys()
	names.sort()
	for k: Variant in names:
		_files.append(str(k))
	_start_current()
	return OK


## One hashing step (at least one chunk, then up to `budget_usec`). Returns true once every file is verified or
## the job failed. Moving to the next file happens in the same call but hashing of it starts on the next call.
func step(budget_usec: int = ChunkedHasher.DEFAULT_BUDGET_USEC) -> bool:
	if _done:
		return true
	if not _hasher.step(budget_usec):
		return false
	if _hasher.digest().hex_encode() != str(expected.get(_files[_index], "")):
		var _e: Error = _fail(ERR_FILE_CORRUPT)
		return true
	_index += 1
	if _index >= _files.size():
		_done = true
		return true
	_start_current()
	return false


func is_done() -> bool:
	return _done


func error() -> Error:
	return _error


## 0.0 .. 1.0 by files completed plus the current file's share.
func progress() -> float:
	if _files.is_empty():
		return 1.0 if _done else 0.0
	if _done and _error == OK:
		return 1.0
	return (float(_index) + _hasher.progress()) / float(_files.size())


func _start_current() -> void:
	_hasher.begin(FileAccess.get_file_as_bytes(_dir.path_join(_files[_index])))


func _fail(err: Error) -> Error:
	_error = err
	_done = true
	return err
