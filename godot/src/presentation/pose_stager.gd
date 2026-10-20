class_name PoseStager
extends RefCounted
## Splits one tick's visible ids into a head half (read on the tick frame) and a tail half (read on the next frame)
## and owns the reused `SimView.read_poses` scratch for both (TA-55, 03 s4.2, R0 B.11 A-56). Scratch arrays only grow.

## Fewer entities than this are read in one frame.
const STAGGER_MIN: int = 64

var ids_lo: PackedInt32Array = PackedInt32Array()
var ids_hi: PackedInt32Array = PackedInt32Array()
var pos_lo: PackedVector3Array = PackedVector3Array()
var rot_lo: PackedVector4Array = PackedVector4Array()
var pos_hi: PackedVector3Array = PackedVector3Array()
var rot_hi: PackedVector4Array = PackedVector4Array()
## True between the tick frame and the tail frame.
var pending: bool = false
## Entries of the full id list at index >= split have not had this tick's pose committed yet.
var split: int = 0


## Splits `ids`. A tick arriving while a tail is still pending (frame rate below the tick rate) is not staggered.
func begin(ids: PackedInt32Array) -> void:
	var n: int = ids.size()
	split = n if (pending or n < STAGGER_MIN) else n >> 1
	pending = split < n
	var _r1: int = ids_lo.resize(split)
	var _r2: int = ids_hi.resize(n - split)
	for i: int in split:
		ids_lo[i] = ids[i]
	for i: int in n - split:
		ids_hi[i] = ids[split + i]
	if pos_lo.size() < split:
		var _r3: int = pos_lo.resize(split + (split >> 1) + 16)
		var _r4: int = rot_lo.resize(pos_lo.size())
	if pos_hi.size() < n - split:
		var _r5: int = pos_hi.resize(n - split + ((n - split) >> 1) + 16)
		var _r6: int = rot_hi.resize(pos_hi.size())


func read_head(view: SimView) -> void:
	var _alive: int = view.read_poses(ids_lo, pos_lo, rot_lo)


## Reads the tail half and ends the pending state; `split` becomes the full count.
func read_tail(view: SimView) -> void:
	pending = false
	split = ids_lo.size() + ids_hi.size()
	var _alive: int = view.read_poses(ids_hi, pos_hi, rot_hi)


func reset() -> void:
	pending = false
