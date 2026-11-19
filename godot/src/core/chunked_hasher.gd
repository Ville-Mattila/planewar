class_name ChunkedHasher extends RefCounted
## Incremental SHA-256 for the single-threaded web build (03 s11.1): `HashingContext.update` in 256 KiB pieces,
## advanced by `step()` once per frame so no frame spends more than the budget (never > 33 ms). No Nodes, no await.

const CHUNK_BYTES: int = 262144  ## 256 KiB
const DEFAULT_BUDGET_USEC: int = 8000  ## per-step time budget; at least one chunk is always hashed

var _data: PackedByteArray = PackedByteArray()
var _ctx: HashingContext = null
var _offset: int = 0
var _digest: PackedByteArray = PackedByteArray()
var _done: bool = false


static func chunk_count(size: int) -> int:
	return ceili(float(size) / float(CHUNK_BYTES))


## Starts (or restarts) hashing `data`. The array is shared copy-on-write, not copied.
func begin(data: PackedByteArray) -> void:
	_data = data
	_offset = 0
	_digest = PackedByteArray()
	_done = false
	_ctx = HashingContext.new()
	var _s: int = _ctx.start(HashingContext.HASH_SHA256)


## Hashes at least one chunk, then more while the elapsed time is under `budget_usec`. Returns true once done.
func step(budget_usec: int = DEFAULT_BUDGET_USEC) -> bool:
	if _done:
		return true
	if _ctx == null:
		return false
	var t0: int = Time.get_ticks_usec()
	while _offset < _data.size():
		var n: int = mini(CHUNK_BYTES, _data.size() - _offset)
		var _u: int = _ctx.update(_data.slice(_offset, _offset + n))
		_offset += n
		if Time.get_ticks_usec() - t0 >= budget_usec:
			break
	if _offset >= _data.size():
		_digest = _ctx.finish()
		_done = true
	return _done


func is_done() -> bool:
	return _done


## 0.0 .. 1.0; 1.0 once done (also for empty input).
func progress() -> float:
	if _done:
		return 1.0
	if _data.is_empty():
		return 0.0
	return float(_offset) / float(_data.size())


## The 32-byte digest; empty until `is_done()`.
func digest() -> PackedByteArray:
	return _digest
