class_name ReplayStore
## Offline replay files (R0 C2-25, ADR-10): `<dir>/<started_unix>_<mode>_<map_id>.pwr`, at most FILE_CAP (20), the
## oldest deleted first. Pure path logic over DirAccess; the web build routes calls through 06's `Saves.try_*`
## wrappers, so `dir` is whatever the caller resolved (user://replays). Names sort by their leading unix time.

static func file_name(started_unix: int, mode: String, map_id: String) -> String:
	return "%d_%s_%s.pwr" % [started_unix, _clean(mode), _clean(map_id)]


## The `.pwr` files of `dir`, oldest first (by the unix prefix, then name).
static func list(dir: String) -> PackedStringArray:
	var found: Array[String] = []
	var d: DirAccess = DirAccess.open(dir)
	if d == null:
		return PackedStringArray()
	for f: String in d.get_files():
		if f.ends_with(".pwr"):
			found.append(f)
	found.sort_custom(_older)
	return PackedStringArray(found)


## Deletes the oldest files until at most `keep` remain; returns how many were deleted.
static func prune(dir: String, keep: int = ReplayFormat.FILE_CAP) -> int:
	var names: PackedStringArray = list(dir)
	var d: DirAccess = DirAccess.open(dir)
	var removed: int = 0
	while d != null and names.size() - removed > maxi(keep, 0):
		if d.remove(names[removed]) != OK:
			break
		removed += 1
	return removed


## A path for a new replay in `dir` after making room for it (so the new file is the 20th at most).
static func make_room(dir: String) -> int:
	return prune(dir, ReplayFormat.FILE_CAP - 1)


static func _older(a: String, b: String) -> bool:
	var ta: int = int(a.get_slice("_", 0))
	var tb: int = int(b.get_slice("_", 0))
	return ta < tb if ta != tb else a < b


static func _clean(s: String) -> String:
	var out: String = ""
	for c: String in s:
		out += c if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "-" else "-"
	return out
