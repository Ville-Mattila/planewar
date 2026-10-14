class_name AiState extends RefCounted
## AI state proper, structure of arrays indexed by entity slot (05 s4.3; the entity store holds only `ai_tag`, R0 C2-07).
## Beyond the 05 s4.3 fields it carries the driver's per-slot scheduling data (`cls`, `eid`, `stagger`, `last_wake`,
## `wake_pending`). `serialize` writes only registered slots (`cls != NO_CLASS`), ascending, so bytes are a function of state.

const NO_CLASS: int = 255
const FORMAT: int = 1
const WAKE_NEVER: int = -1000000
const RECORD_MIN: int = 91              ## slot u32, 3 u8, 9 i32, 9 f32, 2 f32, path count i32

var mode: PackedInt32Array = PackedInt32Array()           ## brain-specific enum value
var mode_since: PackedInt32Array = PackedInt32Array()     ## tick
var overlay_since: PackedInt32Array = PackedInt32Array()
var target: PackedInt32Array = PackedInt32Array()         ## EntityId or 0
var aux_id: PackedInt32Array = PackedInt32Array()         ## pad / field / escortee / squad id
var guidance_vel: PackedVector3Array = PackedVector3Array()
var guidance_point: PackedVector3Array = PackedVector3Array()
var aim_lead: PackedVector3Array = PackedVector3Array()
var tti: PackedFloat32Array = PackedFloat32Array()        ## cached time-to-impact (s)
var timer: PackedFloat32Array = PackedFloat32Array()      ## generic per-mode timer (s)
var fire_mask: PackedByteArray = PackedByteArray()        ## bit0 guns, bit1 bombs armed, bit2 rockets
var path_ticket: PackedInt32Array = PackedInt32Array()    ## pending Pathing ticket or -1
var path: Dictionary = {}                                  ## slot -> PackedVector3Array; replaced whole, never mutated in place
var cls: PackedByteArray = PackedByteArray()              ## class batch index, NO_CLASS when not AI-driven here
var eid: PackedInt32Array = PackedInt32Array()            ## the registered full EntityId (generation check)
var stagger: PackedInt32Array = PackedInt32Array()        ## think when (tick + stagger) % P == 0
var last_wake: PackedInt32Array = PackedInt32Array()      ## tick of the last accepted wake
var wake_pending: PackedByteArray = PackedByteArray()     ## 1 = think on the next on_tick regardless of phase
var capacity: int = 0


func _init(slots: int = EntityStore.SLOT_COUNT) -> void:
	ensure_capacity(slots)


## Grows every array to `slots` entries (never shrinks); new entries are cleared.
func ensure_capacity(slots: int) -> void:
	if slots <= capacity:
		return
	var old: int = capacity
	var _r: Array[int] = [
		mode.resize(slots), mode_since.resize(slots), overlay_since.resize(slots), target.resize(slots),
		aux_id.resize(slots), guidance_vel.resize(slots), guidance_point.resize(slots), aim_lead.resize(slots),
		tti.resize(slots), timer.resize(slots), fire_mask.resize(slots), path_ticket.resize(slots), cls.resize(slots),
		eid.resize(slots), stagger.resize(slots), last_wake.resize(slots), wake_pending.resize(slots)]
	capacity = slots
	for s: int in range(old, slots):
		clear_slot(s)


## Resets slot `s` to the unregistered, all-zero state.
func clear_slot(s: int) -> void:
	mode[s] = 0
	mode_since[s] = 0
	overlay_since[s] = 0
	target[s] = 0
	aux_id[s] = 0
	guidance_vel[s] = Vector3.ZERO
	guidance_point[s] = Vector3.ZERO
	aim_lead[s] = Vector3.ZERO
	tti[s] = 0.0
	timer[s] = 0.0
	fire_mask[s] = 0
	path_ticket[s] = -1
	cls[s] = NO_CLASS
	eid[s] = 0
	stagger[s] = 0
	last_wake[s] = WAKE_NEVER
	wake_pending[s] = 0
	var _e: bool = path.erase(s)


## Sets the mode of entity `id`; `mode_since` moves only on a change.
func set_mode(id: int, m: int, tick: int) -> void:
	var s: int = EntityId.slot(id)
	if mode[s] != m:
		mode[s] = m
		mode_since[s] = tick


## Number of registered slots.
func registered_count() -> int:
	var n: int = 0
	for s: int in capacity:
		if cls[s] != NO_CLASS:
			n += 1
	return n


## S4 bytes: FORMAT u8, capacity u32, count u32, then one record per registered slot in ascending slot order.
func serialize() -> PackedByteArray:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.put_u8(FORMAT)
	b.put_u32(capacity)
	b.put_u32(registered_count())
	for s: int in capacity:
		if cls[s] != NO_CLASS:
			_write_slot(b, s)
	return b.data_array


func _write_slot(b: StreamPeerBuffer, s: int) -> void:
	b.put_u32(s)
	b.put_u8(cls[s])
	b.put_u8(wake_pending[s])
	b.put_u8(fire_mask[s])
	for v: int in [mode[s], mode_since[s], overlay_since[s], target[s], aux_id[s], path_ticket[s], eid[s], stagger[s],
			last_wake[s]]:
		b.put_32(v)
	for p: Vector3 in [guidance_vel[s], guidance_point[s], aim_lead[s]]:
		b.put_float(p.x)
		b.put_float(p.y)
		b.put_float(p.z)
	b.put_float(tti[s])
	b.put_float(timer[s])
	var pts: PackedVector3Array = path.get(s, PackedVector3Array())
	b.put_32(pts.size())
	for p: Vector3 in pts:
		b.put_float(p.x)
		b.put_float(p.y)
		b.put_float(p.z)


## Replaces all state from `serialize` bytes; false (state cleared) on a malformed or wrong-format blob.
func deserialize(bytes: PackedByteArray) -> bool:
	for s: int in capacity:
		clear_slot(s)
	if bytes.size() < 9:
		return false
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.data_array = bytes
	if b.get_u8() != FORMAT:
		return false
	ensure_capacity(b.get_u32())
	var n: int = b.get_u32()
	for i: int in n:
		if b.get_available_bytes() < 1 or not _read_slot(b):
			for s: int in capacity:
				clear_slot(s)
			return false
	return b.get_available_bytes() == 0


func _read_slot(b: StreamPeerBuffer) -> bool:
	if b.get_available_bytes() < RECORD_MIN:
		return false
	var s: int = b.get_u32()
	if s >= capacity:
		return false
	cls[s] = b.get_u8()
	wake_pending[s] = b.get_u8()
	fire_mask[s] = b.get_u8()
	mode[s] = b.get_32()
	mode_since[s] = b.get_32()
	overlay_since[s] = b.get_32()
	target[s] = b.get_32()
	aux_id[s] = b.get_32()
	path_ticket[s] = b.get_32()
	eid[s] = b.get_32()
	stagger[s] = b.get_32()
	last_wake[s] = b.get_32()
	guidance_vel[s] = _get_v3(b)
	guidance_point[s] = _get_v3(b)
	aim_lead[s] = _get_v3(b)
	tti[s] = b.get_float()
	timer[s] = b.get_float()
	var m: int = b.get_32()
	if m < 0 or m * 12 > b.get_available_bytes():
		return false
	if m > 0:
		var pts: PackedVector3Array = PackedVector3Array()
		var _e: int = pts.resize(m)
		for k: int in m:
			pts[k] = _get_v3(b)
		path[s] = pts
	return true


static func _get_v3(b: StreamPeerBuffer) -> Vector3:
	var x: float = b.get_float()
	var y: float = b.get_float()
	return Vector3(x, y, b.get_float())
