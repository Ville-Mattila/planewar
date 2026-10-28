class_name LandingLog extends RefCounted
## The per-ship half of 03 s3.2's `scoring` side table (GD-15): every ship's last `LandingGrade.Grade` and q, stamped
## with the EntityId it was given to, so a re-used slot reads "no landing" (-1) until its own first landing. Written
## by `Docking` at each graded touchdown; read by `SimView.landing_grade_last` and by the repair bonus. Per entity slot
## of the main range; part of S4 (economy section, format 13). GD-27 adds the per-player score half here.

const NONE: int = 255                  ## g_grade value of a slot with no landing

var g_id: PackedInt32Array = PackedInt32Array()      ## per entity slot: EntityId the record belongs to, 0 none
var g_grade: PackedByteArray = PackedByteArray()     ## per entity slot: LandingGrade.Grade, NONE when empty
var g_q: PackedFloat32Array = PackedFloat32Array()   ## per entity slot: q of that landing

const _STATE: PackedStringArray = ["g_id", "g_grade", "g_q"]


func _init() -> void:
	var n: int = InputSlots.ENTITY_SLOTS
	var e: int = g_id.resize(n) | g_grade.resize(n) | g_q.resize(n)
	assert(e == OK)
	g_id.fill(0)
	g_grade.fill(NONE)
	g_q.fill(0.0)


## Records `grade` and `q` for the ship `id` (an alive main-range EntityId).
func record(id: int, grade: int, q: float) -> void:
	var s: int = EntityId.slot(id)
	g_id[s] = id
	g_grade[s] = grade
	g_q[s] = q


## The last grade of `id`, -1 when it has none (never landed, dead, another entity in the slot).
func grade_of(id: int) -> int:
	var s: int = EntityId.slot(id)
	if id == 0 or s >= g_id.size() or g_id[s] != id:
		return -1
	return g_grade[s]


## q of the last landing of `id`, -1.0 when it has none.
func q_of(id: int) -> float:
	return g_q[EntityId.slot(id)] if grade_of(id) >= 0 else -1.0


func write_state(buf: StreamPeerBuffer) -> void:
	StateIO.put_props(buf, self, _STATE)


func read_state(buf: StreamPeerBuffer) -> bool:
	if not StateIO.get_props(buf, self, _STATE) or not StateIO.sizes_ok(self, _STATE, InputSlots.ENTITY_SLOTS):
		return false
	for s: int in g_grade.size():
		if g_grade[s] != NONE and g_grade[s] > LandingGrade.Grade.AUTO:
			return false
	return true
