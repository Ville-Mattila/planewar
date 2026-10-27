class_name TurretSlew extends RefCounted
## Tick-order step 5 for towers (03 s4.1, R0 B.23 A-118, B.24 A-123; GD-09). A tower is an azimuth / elevation mount:
## `PilotInput.yaw` is the azimuth rate about the site normal `n = pos.normalized()` (+yaw turns the muzzle left),
## `pitch` the elevation rate about the turret's right (+pitch raises the muzzle), both fractions of the def's
## `turret_turn_dps`, the (pitch, yaw) pair clamped to unit norm (a diagonal command moves at the cap). The commanded
## rate applies in full in the tick it is commanded (no rate dynamics, no `rate_accel` for towers), so step 9 fires
## along the new muzzle (`store.fwd`). An elevation step that would reach or pass the pole is truncated there. Every
## slew tick ends with `right` re-projected onto the site tangent plane (`right = fwd x n`), so the mount never rolls and
## `right.dot(n)` is zero to float precision on every tick, however long the match. No new saved state (S4): the basis
## is `fwd` / `up`. A BUILDING structure does not slew; power does not stop a slew (an offline tower slews, cannot fire).
## `step` is the hot loop (one branch per structure, a rotation only for a commanded slew).

var _store: EntityStore
var _inputs: InputSlots
var _turn: PackedFloat32Array = PackedFloat32Array()   ## by def_id: turret_turn_dps in rad/s, 0 = not a tower


func _init(store: EntityStore, inputs: InputSlots, defs: WorldDefs) -> void:
	_store = store
	_inputs = inputs
	var cs: ContentSet = defs.content
	var e: int = _turn.resize(DefRanges.STRUCTURE_BASE + cs.structures.size())
	assert(e == OK)
	_turn.fill(0.0)
	for k: int in cs.structures.size():
		var sd: StructureDef = cs.structures[k]
		if sd.is_tower():
			_turn[DefRanges.STRUCTURE_BASE + k] = deg_to_rad(Def.num(sd.tower.get("turret_turn_dps", 0.0)))


## Slews every finished tower that has a commanded pitch or yaw by `dt`.
func step(dt: float) -> void:
	var fw: PackedVector3Array = _store.fwd
	var up: PackedVector3Array = _store.up
	var dy: PackedByteArray = _store.dirty
	var did: PackedInt32Array = _store.def_id
	var fl: PackedByteArray = _store.flags
	var ps: PackedVector3Array = _store.pos
	var ip: PackedFloat64Array = _inputs.e_pitch
	var iy: PackedFloat64Array = _inputs.e_yaw
	var changed: bool = false
	for s: int in _store.structures:
		var rate: float = _turn[did[s]] if did[s] < _turn.size() else 0.0
		if rate <= 0.0 or (fl[s] & EntityStore.F_BUILDING) != 0:
			continue
		if ip[s] == 0.0 and iy[s] == 0.0:
			continue
		var b: Basis = slew(ps[s], fw[s], up[s], ip[s], iy[s], rate * dt)
		fw[s] = -b.z
		up[s] = b.y
		dy[s] = dy[s] | EntityStore.DIRTY_POSE
		changed = true
	if changed:
		_store.fwd = fw
		_store.up = up
		_store.dirty = dy


## One slew tick of a mount at `pos` with muzzle `fwd` and up `up`: `pitch` / `yaw` are the commanded fractions of the
## turn rate, `angle` the full-rate angle of this tick (turn_rad_s x dt). Returns the new basis with columns right, up,
## -fwd (muzzle = -z), `right` tangent to the site. Pure (S8).
static func slew(pos: Vector3, fwd: Vector3, up: Vector3, pitch: float, yaw: float, angle: float) -> Basis:
	var n: Vector3 = pos.normalized()
	var p: float = pitch
	var y: float = yaw
	var m: float = sqrt(p * p + y * y)
	if m > 1.0:
		p /= m
		y /= m
	var f: Vector3 = fwd.normalized()
	var r: Vector3 = f.cross(up)
	if r.length_squared() <= 0.0:
		r = f.cross(n)
	r = r.normalized()
	var qa: Quaternion = Quaternion(n, y * angle)
	f = qa * f
	r = qa * r
	var hor: Vector3 = f - n * f.dot(n)
	var el: float = atan2(f.dot(n), hor.length())
	var de: float = clampf(p * angle, -PI * 0.5 - el, PI * 0.5 - el)
	if de != 0.0 and r.length_squared() > 0.0:
		f = Quaternion(r.normalized(), de) * f
	f = f.normalized()
	return reproject(n, f, r)


## The basis of muzzle `f` (unit) at the site normal `n` with `right` re-projected onto the tangent plane (A-123):
## `right = f x n`; within the pole guard (a horizontal part of about 0.18 deg) the previous `prev_right` minus its `n`
## component; normalised; `up = right x f`.
static func reproject(n: Vector3, f: Vector3, prev_right: Vector3) -> Basis:
	var r: Vector3 = f.cross(n)
	if is_zero_approx(r.length_squared()):
		r = prev_right - n * prev_right.dot(n)
	r = r.normalized()
	r = (r - n * r.dot(n)).normalized()   # a second pass: the cross product's rounding is amplified by the normalise near the pole
	var u: Vector3 = r.cross(f).normalized()
	return Basis(r, u, -f)
