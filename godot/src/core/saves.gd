class_name Saves extends RefCounted
## Failure-tolerant user:// access (03 s11.4). On web, user:// is IndexedDB, which can be unavailable (private
## mode, blocked storage): every wrapper returns a Result and never crashes, so the game boots to the menu without
## persistence. Only user:// paths are accepted; callers elsewhere never open files for saving directly.

const ERR_BAD_PATH: int = 1001  ## path is not under user:// (or tries to climb out of it)
const ERR_UNAVAILABLE: int = 1002  ## storage is unavailable (web private mode) or simulate_unavailable is set
const USER_PREFIX: String = "user://"
const PROBE_NAME: String = "user://.pw_storage_probe"

## Test seam: behave as if user:// storage were disabled (web IndexedDB blocked).
static var simulate_unavailable: bool = false


static func is_user_path(path: String) -> bool:
	return path.begins_with(USER_PREFIX) and not path.contains("..")


static func storage_available() -> bool:
	if simulate_unavailable:
		return false
	var f: FileAccess = FileAccess.open(PROBE_NAME, FileAccess.WRITE)
	if f == null:
		return false
	f.close()
	var _e: int = DirAccess.remove_absolute(PROBE_NAME)
	return true


static func try_exists(path: String) -> bool:
	if simulate_unavailable or not is_user_path(path):
		return false
	return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)


static func try_write_bytes(path: String, data: PackedByteArray) -> Result:
	var bad: Result = _gate(path)
	if bad != null:
		return bad
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return _open_failure(path)
	var _ok: bool = f.store_buffer(data)
	var err: int = f.get_error()
	f.close()
	if err != OK:
		return Result.failure(err, "write failed: " + path)
	return Result.success()


static func try_read_bytes(path: String) -> Result:
	var bad: Result = _gate(path)
	if bad != null:
		return bad
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return _open_failure(path)
	var data: PackedByteArray = f.get_buffer(f.get_length())
	f.close()
	return Result.success(data)


static func try_write_text(path: String, text: String) -> Result:
	return try_write_bytes(path, text.to_utf8_buffer())


static func try_read_text(path: String) -> Result:
	var r: Result = try_read_bytes(path)
	if not r.ok:
		return r
	var bytes: PackedByteArray = r.value
	return Result.success(bytes.get_string_from_utf8())


static func try_remove(path: String) -> Result:
	var bad: Result = _gate(path)
	if bad != null:
		return bad
	var err: int = DirAccess.remove_absolute(path)
	if err != OK:
		return Result.failure(err, "remove failed: " + path)
	return Result.success()


static func try_make_dir(path: String) -> Result:
	var bad: Result = _gate(path)
	if bad != null:
		return bad
	var err: int = DirAccess.make_dir_recursive_absolute(path)
	if err != OK:
		return Result.failure(err, "mkdir failed: " + path)
	return Result.success()


static func _gate(path: String) -> Result:
	if simulate_unavailable:
		return Result.failure(ERR_UNAVAILABLE, "user:// storage unavailable")
	if not is_user_path(path):
		return Result.failure(ERR_BAD_PATH, "not a user:// path: " + path)
	return null


static func _open_failure(path: String) -> Result:
	var err: int = FileAccess.get_open_error()
	return Result.failure(err if err != OK else FAILED, "open failed: " + path)
