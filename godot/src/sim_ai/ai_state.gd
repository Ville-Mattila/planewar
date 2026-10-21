class_name AiState extends RefCounted
## AI state proper, structure of arrays indexed by entity slot (05 s4.3; the entity store holds only `ai_tag`, R0 C2-07).
## Beyond the 05 s4.3 fields it carries the driver's per-slot scheduling data (`cls`, `eid`, `stagger`, `last_wake`,
## `wake_pending`), the landing fields of AI-09, the overlay state of AI-08 (`overlay`, `ov_flags`; the overlays use
## `integ`), the escort fields of AI-11 and the brain fields of AI-13 (FORMAT 5: `sub`, `passes`, `prev_mode`, `wp`,
## `bflags`, `seen_tick`, `mark_tick`, `burst_tick`, `order_tick`, `hp_mark`, `clear_m`, `home`, `goal`, `aim_err`) and
## the Lancer's rocket lock of AI-14 (FORMAT 6: `lock_tick`).
## `serialize` writes only registered slots (`cls != NO_CLASS`), ascending, so bytes are a function of state.

const NO_CLASS: int = 255
const FORMAT: int = 6
const WAKE_NEVER: int = -1000000
const LAND_BUSY: int = 1                ## land_flags: the pad is occupied, queued or claimed by another ship
const LAND_THREAT: int = 2              ## land_flags: an enemy projectile is inbound to the pad
const LAND_FOREIGN: int = 4             ## land_flags: the pad is no longer this ship's team's
const RECORD_MIN: int = 237             ## slot u32, 17 u8, 15 i32, 27 f32 (9 Vector3), 11 f32, path count i32
const ROSTER_WIDTH: int = 8             ## form_roster entries per escortee (class slots are at most this many)
const NO_SLOT: int = 255                ## form_slot: no formation slot assigned
## `ov_flags` bits (AI-08): PULL_UP running, system RETURN already requested, POSSESSED at the last check.
const OV_PULL_UP: int = 1
const OV_RTB_SENT: int = 2
const OV_POSSESSED: int = 4

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
var overlay: PackedByteArray = PackedByteArray()          ## ControlMachine.Overlay SAFETY / RECOVER_CEILING run here, or NONE
var ov_flags: PackedByteArray = PackedByteArray()         ## OV_* bits
var land_phase: PackedByteArray = PackedByteArray()       ## LandingController.Phase of the current landing
var land_attempts: PackedByteArray = PackedByteArray()    ## go-arounds on the current pad
var land_abort: PackedByteArray = PackedByteArray()       ## LandingController.Abort of the last abort
var land_flags: PackedByteArray = PackedByteArray()       ## LAND_BUSY | LAND_THREAT | LAND_FOREIGN, refreshed at think
var land_bearing: PackedVector3Array = PackedVector3Array()   ## LandingState.bearing
var land_mark: PackedVector3Array = PackedVector3Array()      ## LandingState.mark
var land_ga_dir: PackedVector3Array = PackedVector3Array()    ## LandingState.ga_dir
var form_slot: PackedByteArray = PackedByteArray()        ## AI-11: escort class slot k (in the roster), k + ROSTER_WIDTH (overflow, doubles up, not in the roster), NO_SLOT
var form_state: PackedByteArray = PackedByteArray()       ## AI-11: EscortPilot.FORM / ENGAGE
var sep_age: PackedByteArray = PackedByteArray()          ## AI-11: Separation.AGE_FRESH | AGE_CLOSING flags of the last think (Separation.term)
var sep_push: PackedVector3Array = PackedVector3Array()   ## AI-11: the cached Separation.push term
var form_roster: PackedInt32Array = PackedInt32Array()    ## AI-11: by escortee slot * ROSTER_WIDTH + class slot: EntityId of the escort holding it (derived, not in the S4 bytes; checked on use)
var form_order: PackedInt32Array = PackedInt32Array()      ## AI-11: issue_tick of the ESCORT order the escort state belongs to
var integ: PackedVector2Array = PackedVector2Array()      ## FlightController.track_velocity integrators
var sub: PackedByteArray = PackedByteArray()              ## AI-13: sub-machine step (AttackRun step | band << 4)
var passes: PackedByteArray = PackedByteArray()           ## AI-13: AttackRun passes flown on the current order
var prev_mode: PackedByteArray = PackedByteArray()        ## AI-13: mode to resume after PULL_UP / EXTEND / EVADE
var wp: PackedByteArray = PackedByteArray()               ## AI-13: patrol waypoint index; in a bomb release the bombs left at its end
var bflags: PackedByteArray = PackedByteArray()           ## AI-13: brain flag bits (the class brain's B_* constants)
var seen_tick: PackedInt32Array = PackedInt32Array()      ## AI-13: last tick the target was visible to the team
var mark_tick: PackedInt32Array = PackedInt32Array()      ## AI-13: tick of `hp_mark`
var burst_tick: PackedInt32Array = PackedInt32Array()     ## AI-13: start tick of the current gun burst cycle (0 = none)
var order_tick: PackedInt32Array = PackedInt32Array()     ## AI-13: issue_tick of the head order the brain state belongs to (-1 = AUTO)
var lock_tick: PackedInt32Array = PackedInt32Array()      ## AI-14: first tick of the current rocket lock attempt (target in cone and range), 0 = none
var hp_mark: PackedFloat32Array = PackedFloat32Array()    ## AI-13: hp01 at `mark_tick` (EVADE trigger window)
var clear_m: PackedFloat32Array = PackedFloat32Array()    ## AI-13: visible clearance of the last think (min AGL, worst drop-free clearance)
var home: PackedVector3Array = PackedVector3Array()       ## AI-13: patrol centre (home pad or the first think's position)
var goal: PackedVector3Array = PackedVector3Array()       ## AI-13: last known aim point of the order (ATTACK target, MOVE point)
var aim_err: PackedVector2Array = PackedVector2Array()    ## AI-13: per-burst aim error (yaw, pitch rad), drawn from the AI RNG
var rtb_floor: PackedFloat32Array = PackedFloat32Array()  ## AI-13: cached RTB fuel floor (LandingPilot.fuel_floor), 0 = unset
var target_count: PackedByteArray = PackedByteArray()     ## AI-13: by slot, registered entities whose `target` is that slot (derived, not in the S4 bytes; saturates 255)
var ground_h: PackedFloat32Array = PackedFloat32Array()   ## terrain height under the ship at the last think (m)
var lift: PackedFloat32Array = PackedFloat32Array()       ## TerrainProbe lift of the last think (m/s)
var pad_claim: PackedInt32Array = PackedInt32Array()      ## by pad slot: EntityId of the ship landing on it, or 0
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
		eid.resize(slots), stagger.resize(slots), last_wake.resize(slots), wake_pending.resize(slots), overlay.resize(slots),
		ov_flags.resize(slots), form_slot.resize(slots), form_state.resize(slots), form_order.resize(slots), sep_age.resize(slots), sep_push.resize(slots),
		land_phase.resize(slots), land_attempts.resize(slots), land_abort.resize(slots), land_flags.resize(slots),
		land_bearing.resize(slots), land_mark.resize(slots), land_ga_dir.resize(slots), integ.resize(slots),
		ground_h.resize(slots), lift.resize(slots), pad_claim.resize(slots), form_roster.resize(slots * ROSTER_WIDTH),
		sub.resize(slots), passes.resize(slots), prev_mode.resize(slots), wp.resize(slots), bflags.resize(slots),
		seen_tick.resize(slots), mark_tick.resize(slots), burst_tick.resize(slots), order_tick.resize(slots),
		hp_mark.resize(slots), clear_m.resize(slots), home.resize(slots), goal.resize(slots), aim_err.resize(slots),
		target_count.resize(slots), rtb_floor.resize(slots), lock_tick.resize(slots)]
	capacity = slots
	for s: int in range(old, slots):
		clear_slot(s)


## Resets slot `s` to the unregistered, all-zero state (its target's `target_count` drops by one).
func clear_slot(s: int) -> void:
	set_target(s, 0)
	mode[s] = 0
	mode_since[s] = 0
	overlay_since[s] = 0
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
	overlay[s] = 0
	ov_flags[s] = 0
	form_slot[s] = NO_SLOT
	form_state[s] = 0
	form_order[s] = 0
	sep_age[s] = 0
	sep_push[s] = Vector3.ZERO
	for k: int in ROSTER_WIDTH:
		form_roster[s * ROSTER_WIDTH + k] = 0
	land_phase[s] = 0
	land_attempts[s] = 0
	land_abort[s] = 0
	land_flags[s] = 0
	land_bearing[s] = Vector3.ZERO
	land_mark[s] = Vector3.ZERO
	land_ga_dir[s] = Vector3.ZERO
	integ[s] = Vector2.ZERO
	ground_h[s] = 0.0
	lift[s] = 0.0
	pad_claim[s] = 0
	_clear_brain(s)
	var _e: bool = path.erase(s)


func _clear_brain(s: int) -> void:
	sub[s] = 0
	passes[s] = 0
	prev_mode[s] = 0
	wp[s] = 0
	bflags[s] = 0
	seen_tick[s] = 0
	mark_tick[s] = 0
	burst_tick[s] = 0
	order_tick[s] = -1
	lock_tick[s] = 0
	hp_mark[s] = 0.0
	clear_m[s] = 0.0
	home[s] = Vector3.ZERO
	goal[s] = Vector3.ZERO
	aim_err[s] = Vector2.ZERO
	rtb_floor[s] = 0.0


## AI-13: the one writer of `target`: keeps `target_count` (the focus-fire count of 05 s6.2) equal to the number of
## registered slots targeting each slot, in a continuous run and after `deserialize` alike (S4).
func set_target(s: int, t: int) -> void:
	var old: int = target[s]
	if old == t:
		return
	var o: int = EntityId.slot(old)
	if old != 0 and o < capacity:
		target_count[o] = maxi(target_count[o] - 1, 0)
	var n: int = EntityId.slot(t)
	if t != 0 and n < capacity:
		target_count[n] = mini(target_count[n] + 1, 255)
	target[s] = t


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
	var claims: int = 0
	for s: int in capacity:
		claims += 1 if pad_claim[s] != 0 else 0
	b.put_u32(claims)
	for s: int in capacity:
		if pad_claim[s] != 0:
			b.put_u32(s)
			b.put_32(pad_claim[s])
	return b.data_array


func _write_slot(b: StreamPeerBuffer, s: int) -> void:
	b.put_u32(s)
	b.put_u8(cls[s])
	b.put_u8(wake_pending[s])
	b.put_u8(fire_mask[s])
	b.put_u8(overlay[s])
	b.put_u8(ov_flags[s])
	b.put_u8(form_slot[s])
	b.put_u8(form_state[s])
	b.put_u8(sep_age[s])
	for v: int in [land_phase[s], land_attempts[s], land_abort[s], land_flags[s], sub[s], passes[s], prev_mode[s], wp[s], bflags[s]]:
		b.put_u8(v)
	for v: int in [mode[s], mode_since[s], overlay_since[s], target[s], aux_id[s], path_ticket[s], eid[s], stagger[s],
			last_wake[s], form_order[s], seen_tick[s], mark_tick[s], burst_tick[s], order_tick[s], lock_tick[s]]:
		b.put_32(v)
	for p: Vector3 in [guidance_vel[s], guidance_point[s], aim_lead[s], land_bearing[s], land_mark[s], land_ga_dir[s], sep_push[s],
			home[s], goal[s]]:
		b.put_float(p.x)
		b.put_float(p.y)
		b.put_float(p.z)
	b.put_float(tti[s])
	b.put_float(timer[s])
	b.put_float(integ[s].x)
	b.put_float(integ[s].y)
	b.put_float(ground_h[s])
	b.put_float(lift[s])
	b.put_float(hp_mark[s])
	b.put_float(clear_m[s])
	b.put_float(aim_err[s].x)
	b.put_float(aim_err[s].y)
	b.put_float(rtb_floor[s])
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
			return _fail()
	if b.get_available_bytes() < 4:
		return _fail()
	var claims: int = b.get_u32()
	if claims * 8 != b.get_available_bytes():
		return _fail()
	for i: int in claims:
		var s: int = b.get_u32()
		if s >= capacity:
			return _fail()
		pad_claim[s] = b.get_32()
	_rebuild_roster()
	_rebuild_targets()
	return true


func _rebuild_targets() -> void:
	target_count.fill(0)
	for s: int in capacity:
		if cls[s] != NO_CLASS and target[s] != 0:
			var n: int = EntityId.slot(target[s])
			if n < capacity:
				target_count[n] = mini(target_count[n] + 1, 255)


# The escort rosters are derived from the records: every registered escort with a slot goes back to its escortee's row.
func _rebuild_roster() -> void:
	for s: int in capacity:
		var k: int = form_slot[s]
		if cls[s] != NO_CLASS and k < ROSTER_WIDTH and aux_id[s] != 0:
			var row: int = EntityId.slot(aux_id[s])
			if row < capacity:
				form_roster[row * ROSTER_WIDTH + k] = eid[s]


func _fail() -> bool:
	for s: int in capacity:
		clear_slot(s)
	target_count.fill(0)
	return false


func _read_slot(b: StreamPeerBuffer) -> bool:
	if b.get_available_bytes() < RECORD_MIN:
		return false
	var s: int = b.get_u32()
	if s >= capacity:
		return false
	cls[s] = b.get_u8()
	wake_pending[s] = b.get_u8()
	fire_mask[s] = b.get_u8()
	overlay[s] = b.get_u8()
	ov_flags[s] = b.get_u8()
	form_slot[s] = b.get_u8()
	form_state[s] = b.get_u8()
	sep_age[s] = b.get_u8()
	land_phase[s] = b.get_u8()
	land_attempts[s] = b.get_u8()
	land_abort[s] = b.get_u8()
	land_flags[s] = b.get_u8()
	sub[s] = b.get_u8()
	passes[s] = b.get_u8()
	prev_mode[s] = b.get_u8()
	wp[s] = b.get_u8()
	bflags[s] = b.get_u8()
	mode[s] = b.get_32()
	mode_since[s] = b.get_32()
	overlay_since[s] = b.get_32()
	target[s] = b.get_32()
	aux_id[s] = b.get_32()
	path_ticket[s] = b.get_32()
	eid[s] = b.get_32()
	stagger[s] = b.get_32()
	last_wake[s] = b.get_32()
	form_order[s] = b.get_32()
	seen_tick[s] = b.get_32()
	mark_tick[s] = b.get_32()
	burst_tick[s] = b.get_32()
	order_tick[s] = b.get_32()
	lock_tick[s] = b.get_32()
	guidance_vel[s] = _get_v3(b)
	guidance_point[s] = _get_v3(b)
	aim_lead[s] = _get_v3(b)
	land_bearing[s] = _get_v3(b)
	land_mark[s] = _get_v3(b)
	land_ga_dir[s] = _get_v3(b)
	sep_push[s] = _get_v3(b)
	home[s] = _get_v3(b)
	goal[s] = _get_v3(b)
	tti[s] = b.get_float()
	timer[s] = b.get_float()
	var ix: float = b.get_float()
	integ[s] = Vector2(ix, b.get_float())
	ground_h[s] = b.get_float()
	lift[s] = b.get_float()
	hp_mark[s] = b.get_float()
	clear_m[s] = b.get_float()
	var ex: float = b.get_float()
	aim_err[s] = Vector2(ex, b.get_float())
	rtb_floor[s] = b.get_float()
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
