class_name BarrelSlew extends RefCounted
## Tick-order step 5 for the barrel of a ground-mounted weapon (GD-50; 06 s3.2 "`pitch` = barrel"). A ground unit whose
## def has a barrel (`ground_units.json` `barrel_slew_dps` > 0 or a non-zero `barrel_min_deg` / `barrel_max_deg`) carries
## an elevation in radians above the local horizontal: each tick `e = clamp(e + clamp(pitch, -1, 1) x barrel_slew_dps x dt,
## barrel_min_deg, barrel_max_deg)` (+pitch raises the muzzle, the tower sign). The input slot is the only source, so a
## possessed player (PILOT_INPUT) and an autopilot (`CommandSinkBase.drive`) slew it alike; pitch 0 holds it. A unit starts
## at rest, `clamp(0, min, max)`. Step 9 fires along `frame()`: the unit's heading tilted up by the elevation about the
## heading's right, in the radial frame at the unit's position (the frame `SiegeAim.loft` solves in), spread around it.
## State (S4): `elevation` and `bound` per main-range slot; a slot whose `bound` is not its live EntityId is at rest, so a
## reused slot never inherits a dead unit's barrel and no death hook is needed. No allocation per tick or per unit.

const _STATE: PackedStringArray = ["elevation", "bound"]

var elevation: PackedFloat64Array = PackedFloat64Array()   ## per main-range slot: radians above the local horizontal
var bound: PackedInt32Array = PackedInt32Array()           ## per slot: the EntityId `elevation` belongs to, 0 = none
var frame_up: Vector3 = Vector3.ZERO                       ## `frame`'s second result: the barrel's up (spread axis)

var _store: EntityStore
var _inputs: InputSlots
var _rate: PackedFloat64Array = PackedFloat64Array()   # by def_id: barrel_slew_dps in rad/s
var _lo: PackedFloat64Array = PackedFloat64Array()     # by def_id: barrel_min_deg in rad
var _hi: PackedFloat64Array = PackedFloat64Array()     # by def_id: barrel_max_deg in rad
var _has: PackedByteArray = PackedByteArray()          # by def_id: 1 = the def has a barrel


func _init(store: EntityStore, inputs: InputSlots, defs: WorldDefs) -> void:
	_store = store
	_inputs = inputs
	var n: int = InputSlots.ENTITY_SLOTS
	var gs: Array[GroundUnitDef] = defs.content.ground_units
	var m: int = DefRanges.GROUND_BASE + gs.size()
	var e: int = elevation.resize(n) | bound.resize(n) | _rate.resize(m) | _lo.resize(m) | _hi.resize(m) | _has.resize(m)
	assert(e == OK)
	elevation.fill(0.0)
	bound.fill(0)
	_rate.fill(0.0)
	_lo.fill(0.0)
	_hi.fill(0.0)
	_has.fill(0)
	for k: int in gs.size():
		var g: GroundUnitDef = gs[k]
		var lo: float = deg_to_rad(g.barrel_min_deg)
		var hi: float = deg_to_rad(g.barrel_max_deg)
		var d: int = DefRanges.GROUND_BASE + k
		_rate[d] = maxf(deg_to_rad(g.barrel_slew_dps), 0.0)
		_lo[d] = minf(lo, hi)
		_hi[d] = maxf(lo, hi)
		_has[d] = 1 if _rate[d] > 0.0 or lo != 0.0 or hi != 0.0 else 0


## True when ground def `def_id` has a barrel (else its weapon fires along the heading, as before GD-50).
func has_barrel(def_id: int) -> bool:
	return def_id >= 0 and def_id < _has.size() and _has[def_id] != 0


## The rest elevation of `def_id`: `clamp(0, barrel_min, barrel_max)` in radians; 0 without a barrel.
func rest(def_id: int) -> float:
	return clampf(0.0, _lo[def_id], _hi[def_id]) if has_barrel(def_id) else 0.0


## Slews every live ground unit with a barrel by its input slot's `pitch` over `dt` (step 5, ascending slot order).
func step(dt: float) -> void:
	var did: PackedInt32Array = _store.def_id
	var gen: PackedInt32Array = _store.generation
	var ip: PackedFloat64Array = _inputs.e_pitch
	for s: int in _store.ground:
		var d: int = did[s]
		if not has_barrel(d):
			continue
		var id: int = EntityId.make(s, gen[s])
		var p: float = ip[s]
		if bound[s] == id and p == 0.0:
			continue
		var e: float = elevation[s] if bound[s] == id else rest(d)
		elevation[s] = clampf(e + clampf(p, -1.0, 1.0) * _rate[d] * dt, _lo[d], _hi[d])
		bound[s] = id


## The barrel elevation (radians) of the live unit in slot `s`: its slewed value, the def's rest before its first step-5
## slew, 0 for a unit or def without a barrel.
func elevation_of(s: int) -> float:
	var d: int = _store.def_id[s]
	if not has_barrel(d):
		return 0.0
	return elevation[s] if bound[s] == _store.id_of(s) else rest(d)


## The muzzle direction of slot `s` at `p` heading `fwd` (unit, tangent at `p`): `muzzle_dir(p, fwd, elevation_of(s))`;
## `frame_up` = `muzzle_up(...)`. A unit without a barrel returns `fwd` and sets `frame_up` = `up` (the pre-GD-50 frame).
func frame(s: int, p: Vector3, fwd: Vector3, up: Vector3) -> Vector3:
	if not has_barrel(_store.def_id[s]):
		frame_up = up
		return fwd
	var e: float = elevation_of(s)
	frame_up = muzzle_up(p, fwd, e)
	return muzzle_dir(p, fwd, e)


## `h cos(e) + n sin(e)`: n = the radial at `p`, h = `fwd` made tangent at `p` and unit.
static func muzzle_dir(p: Vector3, fwd: Vector3, e: float) -> Vector3:
	var n: Vector3 = p.normalized()
	var h: Vector3 = (fwd - n * fwd.dot(n)).normalized()
	return h * cos(e) + n * sin(e)


## `n cos(e) - h sin(e)`: the barrel's up, perpendicular to `muzzle_dir` in the vertical plane of the heading.
static func muzzle_up(p: Vector3, fwd: Vector3, e: float) -> Vector3:
	var n: Vector3 = p.normalized()
	var h: Vector3 = (fwd - n * fwd.dot(n)).normalized()
	return n * cos(e) - h * sin(e)


func write_state(buf: StreamPeerBuffer) -> void:
	StateIO.put_props(buf, self, _STATE)


## False on missing bytes, a wrong array size or a non-finite elevation.
func read_state(buf: StreamPeerBuffer) -> bool:
	if not StateIO.get_props(buf, self, _STATE) or not StateIO.sizes_ok(self, _STATE, InputSlots.ENTITY_SLOTS):
		return false
	for s: int in elevation.size():
		if not is_finite(elevation[s]):
			return false
	return true
