class_name NetPose extends RefCounted
## The sampled mirror behind NetSimView (04 s5.6): poses of every roster entry at a fractional `render_tick`, read
## from the decoder's BaselineStore frames. `sample(r)` picks the frame pair (tick_a <= r <= tick_b, the newest frames
## at or around r) in O(1) and bumps `generation`; an entry's pose is computed on first read per generation (lazy, so
## ClientSession.tick pays for the frames, the reader for the entities it reads) and cached in packed arrays.
## Per frame an entry shows BaselineFrame.shown_levels' rule evaluated at a float tick: a known blip (last record a
## C-BLIP) is its stored bucket, never dead-reckoned and never extrapolated, no gravity even when DYING (NET-56/57,
## R0 B.19 A-103); every other entry dead-reckons from its record with `base_grav`'s branch (gravity term for
## gravity defs and DYING entries, 04 s3.4). Between tick_a and tick_b: lerp of position and velocity, slerp of
## orientation (full quat_s3 from A, coarse from B: the slerp target simply becomes more precise); an entry that is a
## known blip in either frame is not interpolated (blips jump, the Commander view eases them). Past the newest frame:
## dead reckoning from it for at most EXTRAP_MAX_TICKS (100 ms), then frozen with `stale` set. World conversions of a
## record (dequantise, ENU velocity, quaternion) are cached per entry, keyed by the record's fields, so a record is
## converted once however many frames and samples show it. No allocation per entity.

const EXTRAP_MAX_TICKS: int = 3
const ALPHA_EPS: float = 1e-4                ## a render tick this close to a frame tick shows that frame
const _SLOTS: int = 2                       # record cache slots per entry (keyed by etick parity)

var render_tick: float = 0.0
var tick_a: int = 0
var tick_b: int = 0
var alpha: float = 0.0
var newest: int = 0
var eval_tick: float = 0.0                  ## the tick poses are evaluated at past the newest frame (<= newest + 3)
var extrapolating: bool = false
var stale: bool = false                     ## render_tick ran more than EXTRAP_MAX_TICKS past the newest frame
var generation: int = 0
var computed: int = 0                       ## entries computed since the last sample (work counter)
var converted: int = 0                      ## record conversions since the last sample (cache misses)
var store: BaselineStore
var roster: Roster
var gravity_def: PackedByteArray = PackedByteArray()
var gravity: float = 0.0
var dt: float = 1.0 / 30.0
var _stamp: PackedInt32Array = PackedInt32Array()
var _p: PackedVector3Array = PackedVector3Array()
var _v: PackedVector3Array = PackedVector3Array()
var _q: PackedVector4Array = PackedVector4Array()
var _has_q: PackedByteArray = PackedByteArray()
var _blip: PackedByteArray = PackedByteArray()
# record cache, CAPACITY * _SLOTS rows
var _k_tick: PackedInt32Array = PackedInt32Array()
var _k_pos: PackedInt64Array = PackedInt64Array()
var _k_vel: PackedInt64Array = PackedInt64Array()
var _k_ori: PackedInt64Array = PackedInt64Array()
var _k_oric: PackedInt32Array = PackedInt32Array()
var _c_p: PackedVector3Array = PackedVector3Array()
var _c_v: PackedVector3Array = PackedVector3Array()
var _c_q: PackedVector4Array = PackedVector4Array()
var _c_has_q: PackedByteArray = PackedByteArray()
var _fa: BaselineFrame = null              # frames of the last sample (reads are valid until the next sample)
var _fb: BaselineFrame = null
var _fn: BaselineFrame = null
# scratch of one state evaluation
var _sp: Vector3 = Vector3.ZERO
var _sv: Vector3 = Vector3.ZERO
var _sq: Vector4 = Vector4(0.0, 0.0, 0.0, 1.0)
var _shq: bool = false
var _sblip: bool = false


func _init(baseline: BaselineStore, roster_ref: Roster) -> void:
	store = baseline
	roster = roster_ref
	var n: int = BaselineFrame.CAPACITY
	var _a: int = _stamp.resize(n)
	_stamp.fill(-1)
	var _b: int = _p.resize(n)
	var _c: int = _v.resize(n)
	var _d: int = _q.resize(n)
	var _e: int = _has_q.resize(n)
	var _f: int = _blip.resize(n)
	var _h: int = _k_tick.resize(n * _SLOTS)
	_k_tick.fill(-1)
	var _i: int = _k_pos.resize(n * _SLOTS)
	var _j: int = _k_vel.resize(n * _SLOTS)
	var _k: int = _k_ori.resize(n * _SLOTS)
	var _l: int = _k_oric.resize(n * _SLOTS)
	var _m: int = _c_p.resize(n * _SLOTS)
	var _o: int = _c_v.resize(n * _SLOTS)
	var _r: int = _c_q.resize(n * _SLOTS)
	var _s: int = _c_has_q.resize(n * _SLOTS)


## Selects the frames for `r`; poses are computed lazily on the next read of each entry.
func sample(r: float) -> void:
	render_tick = r
	generation += 1
	computed = 0
	converted = 0
	newest = store.newest_tick
	stale = newest > 0 and r > float(newest + EXTRAP_MAX_TICKS)
	extrapolating = newest > 0 and r > float(newest)
	eval_tick = minf(r, float(newest + EXTRAP_MAX_TICKS))
	if newest <= 0 or r >= float(newest):
		tick_a = newest
		tick_b = newest
		alpha = 0.0
		_bind_frames()
		return
	tick_b = newest
	for t: int in range(maxi(maxi(ceili(r), 1), newest - BaselineStore.DEPTH + 1), newest + 1):   # only the ring can hold frames
		if store.frame_at(t) != null:
			tick_b = t
			break
	tick_a = tick_b
	for t: int in range(floori(r), maxi(newest - BaselineStore.DEPTH, 0), -1):
		if store.frame_at(t) != null:
			tick_a = t
			break
	alpha = clampf((r - float(tick_a)) / float(tick_b - tick_a), 0.0, 1.0) if tick_b > tick_a else 0.0
	if alpha <= ALPHA_EPS or alpha >= 1.0 - ALPHA_EPS:      # on a frame: one frame, no blend
		tick_a = tick_a if alpha <= ALPHA_EPS else tick_b
		tick_b = tick_a
		alpha = 0.0
	eval_tick = float(tick_b) if tick_a == tick_b else r
	_bind_frames()


func _bind_frames() -> void:
	_fn = store.frame_at(newest)
	_fb = store.frame_at(tick_b)
	_fa = store.frame_at(tick_a)


## The newest frame at the last sample (null before any state).
func frame() -> BaselineFrame:
	return _fn


## True when roster index `i` (0 .. CAPACITY - 1) has state in the newest frame of the last sample.
func present(i: int) -> bool:
	return _fn != null and _fn.present[i] != 0


## pos_of and rot_of into out_pos[k] / out_rot[k] with one cache check (read_poses).
func pose_into(i: int, out_pos: PackedVector3Array, out_rot: PackedVector4Array, k: int) -> void:
	_ensure(i)
	out_pos[k] = _p[i]
	out_rot[k] = _q[i]


func pos_of(i: int) -> Vector3:
	_ensure(i)
	return _p[i]


func vel_of(i: int) -> Vector3:
	_ensure(i)
	return _v[i]


## Orientation quaternion (x, y, z, w); identity when unknown (C tier).
func rot_of(i: int) -> Vector4:
	_ensure(i)
	return _q[i]


## False for a known blip and an entry with no orientation record: `basis` / `vel` are not received (04 s3.7).
func has_ori(i: int) -> bool:
	_ensure(i)
	return _has_q[i] != 0


func is_blip(i: int) -> bool:
	_ensure(i)
	return _blip[i] != 0


## Fine velocity (DeadReckon, 1/1024 m/s per ENU axis of `cell`) in world space.
static func fine_to_world(fine: int, cell: int) -> Vector3:
	var b: Basis = Codec.cell_frame(cell)
	var k: float = 1.0 / float(DeadReckon.FINE_PER_MPS)
	return b.x * (float(DeadReckon.fine_axis(fine, 0)) * k) + b.y * (float(DeadReckon.fine_axis(fine, 1)) * k) \
			+ b.z * (float(DeadReckon.fine_axis(fine, 2)) * k)


## The sign Basis.get_rotation_quaternion() picks, so read_poses equals basis() element-wise (R0 B.11 A-56).
static func canonical(q: Quaternion) -> Quaternion:
	return Basis(q).get_rotation_quaternion()


func _ensure(i: int) -> void:
	if _stamp[i] == generation:
		return
	_stamp[i] = generation
	computed += 1
	_compute(i)


func _compute(i: int) -> void:
	if _fn == null or _fn.present[i] == 0:
		_write(i, Vector3.ZERO, Vector3.ZERO, Vector4(0.0, 0.0, 0.0, 1.0), false, false)
		return
	if _fb == null or _fb.present[i] == 0:
		_state(_fn, i, float(_fn.etick[i]))        # entered after tick_b: shown at its first record, no backward dr
		_write(i, _sp, _sv, _sq, _shq, _sblip)
		return
	if tick_a == tick_b or _fa == null or _fa.present[i] == 0 or _same_record(i):
		if _fb.blip[i] != DeadReckon.BLIP_UNKNOWN:  # known blip (most of tier C): the bucket, fast path of _state
			var c: int = _record(_fb, i)
			_p[i] = _c_p[c]
			_v[i] = Vector3.ZERO
			_q[i] = Vector4(0.0, 0.0, 0.0, 1.0)
			_has_q[i] = 0
			_blip[i] = 1
			return
		_state(_fb, i, eval_tick)                  # one record covers r: its dr(r) is the blend (bucket for a blip)
		_write(i, _sp, _sv, _sq, _shq, _sblip)
		return
	_state(_fb, i, float(tick_b))
	var pb: Vector3 = _sp
	var vb: Vector3 = _sv
	var qb: Vector4 = _sq
	var hb: bool = _shq
	var bb: bool = _sblip
	_state(_fa, i, float(tick_a))
	if bb or _sblip:
		_write(i, _sp, _sv, _sq, _shq, _sblip)    # a blip on either side jumps: the frame at or before r
		return
	var q: Vector4 = _sq
	if hb and _shq and qb != _sq:
		var s: Quaternion = canonical(Quaternion(_sq.x, _sq.y, _sq.z, _sq.w).slerp(Quaternion(qb.x, qb.y, qb.z, qb.w), alpha))
		q = Vector4(s.x, s.y, s.z, s.w)
	_write(i, _sp.lerp(pb, alpha), _sv.lerp(vb, alpha), q, hb and _shq, false)


## True when frames a and b hold the same record for `i` (no record arrived in between).
func _same_record(i: int) -> bool:
	return _fa.etick[i] == _fb.etick[i] and _fa.pos[i] == _fb.pos[i] and _fa.vel[i] == _fb.vel[i] 			and _fa.ori[i] == _fb.ori[i] and _fa.ori_c[i] == _fb.ori_c[i] and _fa.blip[i] == _fb.blip[i] 			and _fa.flags[i] == _fb.flags[i]


func _write(i: int, p: Vector3, v: Vector3, q: Vector4, hq: bool, blip: bool) -> void:
	_p[i] = p
	_v[i] = v
	_q[i] = q if hq else Vector4(0.0, 0.0, 0.0, 1.0)
	_has_q[i] = 1 if hq else 0
	_blip[i] = 1 if blip else 0


## Entry `i` of frame `f` at tick `t` (>= its etick) into the scratch: bucket for a known blip, else dr(t).
func _state(f: BaselineFrame, i: int, t: float) -> void:
	var c: int = _record(f, i)
	_sblip = f.blip[i] != DeadReckon.BLIP_UNKNOWN
	if _sblip:
		_sp = _c_p[c]
		_sv = Vector3.ZERO
		_shq = false
		_sq = Vector4(0.0, 0.0, 0.0, 1.0)
		return
	_shq = _c_has_q[c] != 0
	_sq = _c_q[c]
	var d: int = roster.def_of(i)
	var grav: bool = f.base_grav(i, d >= 0 and d < gravity_def.size() and gravity_def[d] != 0)
	var ts: float = maxf(t - float(f.etick[i]), 0.0) * dt
	var p0: Vector3 = _c_p[c]
	var v0: Vector3 = _c_v[c]
	if not grav:
		_sp = p0 + v0 * ts
		_sv = v0
		return
	var n: Vector3 = p0.normalized()
	_sp = p0 + v0 * ts - n * (0.5 * gravity * ts * ts)
	_sv = v0 - n * (gravity * ts)


## Cache row of entry `i`'s record in `f`, converting it on a miss.
func _record(f: BaselineFrame, i: int) -> int:
	var et: int = f.etick[i]
	var c: int = i * _SLOTS + (et & 1)
	var pq: int = f.pos[i]
	if _k_tick[c] == et and _k_pos[c] == pq and _k_vel[c] == f.vel[i] and _k_ori[c] == f.ori[i] and _k_oric[c] == f.ori_c[i]:
		return c
	converted += 1
	_k_tick[c] = et
	_k_pos[c] = pq
	_k_vel[c] = f.vel[i]
	_k_ori[c] = f.ori[i]
	_k_oric[c] = f.ori_c[i]
	_c_p[c] = Codec.dequantize_pos(pq)
	_c_v[c] = fine_to_world(f.vel[i], Codec.pos_cell(pq))
	var hq: bool = true
	var q: Quaternion = Quaternion.IDENTITY
	if f.ori[i] != BaselineFrame.ORI_UNKNOWN:
		q = Codec.dequantize_quat(f.ori[i])
	elif f.ori_c[i] != BaselineFrame.ORI_UNKNOWN:
		q = Codec.dequantize_quat_coarse(f.ori_c[i])
	else:
		hq = false
	q = canonical(q)
	_c_q[c] = Vector4(q.x, q.y, q.z, q.w)
	_c_has_q[c] = 1 if hq else 0
	return c
