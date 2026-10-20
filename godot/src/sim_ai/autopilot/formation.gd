class_name Formation extends RefCounted
## Formation slots and the velocity command that keeps them (05 s5.6), static only.
## Class slots are offsets in the escortee's tangent frame (forward = its velocity heading, right = forward x up);
## SL-2 wing slots are offsets in the leader's body frame. `v_cmd = v_leader + k_form * (slot_world - p)`, capped at
## the escort's cruise + 10 %. A slot above the soft ceiling is pulled down to it (wingmen never follow above it).


## World position of slot `idx` of the class table (`wing` false) or the SL-2 table, for a leader at `lp` moving at
## `lv` with body basis `lb` (SimView convention: Basis(right, up, -forward)).
static func slot_world(lp: Vector3, lv: Vector3, lb: Basis, idx: int, wing: bool, prm: FormationParams) -> Vector3:
	var up: Vector3 = lp.normalized()
	var fwd: Vector3
	var right: Vector3
	var vert: Vector3 = up
	var off: Vector3
	if wing:
		off = prm.wing_slots[idx]
		fwd = -lb.z
		right = lb.x
		vert = lb.y
	else:
		off = prm.class_slots[idx]
		fwd = lv - up * lv.dot(up)
		if fwd.length() < prm.min_heading_speed:
			fwd = -lb.z - up * (-lb.z).dot(up)
		fwd = fwd.normalized()
		right = fwd.cross(up)
	var w: Vector3 = lp + right * off.x + fwd * off.y + vert * off.z
	var limit: float = Sphere.PLANET_RADIUS + prm.ceiling_m
	if w.length() > limit:
		w = w.normalized() * limit
	return w


## Guidance velocity of an escort at `p` for the slot position `slot_pos` behind a leader moving at `lv`.
static func v_cmd(p: Vector3, slot_pos: Vector3, lv: Vector3, cruise: float, prm: FormationParams) -> Vector3:
	var v: Vector3 = lv + (slot_pos - p) * prm.k_form
	var cap: float = cruise * prm.speed_cap_mult
	return v.limit_length(cap)


## How many of `count` escorts may be out of formation at once: `max_break_frac` of them, at least one.
static func max_breakers(count: int, prm: FormationParams) -> int:
	return maxi(1, floori(float(count) * prm.max_break_frac))


## The escort in slot `slot` of a group of `count` may break: the lower slots stay.
static func may_break(slot: int, count: int, prm: FormationParams) -> bool:
	return slot >= count - max_breakers(count, prm)


## The lowest slot index below `limit` whose bit is clear in `used`; `AiState.NO_SLOT` when all are taken.
static func free_slot(used: int, limit: int) -> int:
	for k: int in limit:
		if (used >> k) & 1 == 0:
			return k
	return AiState.NO_SLOT
