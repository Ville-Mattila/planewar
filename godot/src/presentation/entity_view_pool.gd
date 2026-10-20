class_name EntityViewPool
extends Node3D
## Pooled entity views with tier caps and the far-pool hand-off (03 s10.1, R0 C1-07 / C1-17).
##
## `sync(view, render_time)` draws every entity the viewer team sees: the nearest `view_cap` within their `_Far`
## switch distance get a pooled mesh node (nearest first, hysteresis-free: re-ranked per tick), the rest draw as
## `_Far` meshes through `FarPools`, and anything past the icon band as an `IconPool` glyph (~8 draws in total).
## SimView is read once per sim tick (ids, then `SimView.read_poses` bulk calls, R0 B.11 A-56, half on the tick frame and half on the next, TA-55); between ticks the pool interpolates the last two ticks
## with `render_time` (offline: LocalSimView; online: the same call over NetSimView, R0 C1-01). The possessed
## unit is driven by `set_local_override` every `_process` frame instead (R0 C1-07).
##
## Set `cam_pos`, `px_per_m` (viewport height / (2 tan(fov / 2))) and `viewer_team` before `sync`.

const MODE_VIEW: int = 0
const MODE_FAR: int = 1
const MODE_ICON: int = 2
## A bound view re-reads team and damage state every this many ticks (staggered by slot).
const STATE_REFRESH_TICKS: int = 4
## Fewer entities than this read in one frame.
const STAGGER_MIN: int = 64
const DEFAULT_TICK_HZ: float = 30.0
const DEFAULT_PX_PER_M: float = 704.0   ## 1080 p, 75 degree vertical fov
const FAR_CAPACITY: int = 1280          ## 03 s7.10 icon / far capacity, Standard profile
const WRECK_TINT: float = 0.35

var cam_pos: Vector3 = Vector3.ZERO
var px_per_m: float = DEFAULT_PX_PER_M
var viewer_team: int = 0
var tick_hz: float = DEFAULT_TICK_HZ
var far: FarPools = null
var icons: IconPool = null
var last_views: int = 0
var last_far: int = 0
var last_icons: int = 0

var _cfg: EntityViewConfig = null
var _classes: EntityClassTable = null
var _materials: UnitMaterialCache = null
var _views: Array[EntityView] = []
var _free: PackedInt32Array = PackedInt32Array()
var _ids: PackedInt32Array = PackedInt32Array()
var _pose_pos: PackedVector3Array = PackedVector3Array()   ## SimView.read_poses scratch, sized with _d2 (no per-frame allocation)
var _pose_rot: PackedVector4Array = PackedVector4Array()
var _pose_hi: PackedVector3Array = PackedVector3Array()   ## second-half scratch (TA-55)
var _rot_hi: PackedVector4Array = PackedVector4Array()
var _ids_lo: PackedInt32Array = PackedInt32Array()
var _ids_hi: PackedInt32Array = PackedInt32Array()
var _tail_pending: bool = false
var _split: int = 0   ## entries at index >= _split have not had this tick's pose committed yet
var _last_tick: int = -1
var _frame: int = 0
var _ov_id: int = EntityId.NULL_ID
var _ov_pos: Vector3 = Vector3.ZERO
var _ov_basis: Basis = Basis.IDENTITY
var _team_color: PackedColorArray = PackedColorArray()
var _wreck_color: PackedColorArray = PackedColorArray()
# Per-slot cache (index = EntityId.slot): valid while _s_id[slot] equals the live id.
var _s_id: PackedInt32Array = PackedInt32Array()
var _s_view: PackedInt32Array = PackedInt32Array()
var _s_group: PackedInt32Array = PackedInt32Array()
var _s_team: PackedInt32Array = PackedInt32Array()
var _s_state: PackedInt32Array = PackedInt32Array()
var _s_radius: PackedFloat32Array = PackedFloat32Array()
var _s_prev: PackedVector3Array = PackedVector3Array()
var _s_cur: PackedVector3Array = PackedVector3Array()
var _s_pq: Array[Quaternion] = []
var _s_cq: Array[Quaternion] = []
var _s_wreck: PackedByteArray = PackedByteArray()
var _d2: PackedFloat32Array = PackedFloat32Array()
var _mode: PackedByteArray = PackedByteArray()
var _rank: PackedFloat32Array = PackedFloat32Array()


## Pre-instantiates `cfg.view_cap` hidden views and the far and icon pools.
func setup(cfg: EntityViewConfig, classes: EntityClassTable, materials: UnitMaterialCache, far_capacity: int = FAR_CAPACITY) -> void:
	_cfg = cfg
	_classes = classes
	_materials = materials
	for t: int in UnitMaterialCache.TEAM_COUNT:
		var _a: bool = _team_color.push_back(UnitMaterialCache.team_color(t))
		var c: Color = UnitMaterialCache.team_color(t)
		var _b: bool = _wreck_color.push_back(Color(c.r * WRECK_TINT, c.g * WRECK_TINT, c.b * WRECK_TINT))
	var slots: int = EntityId.WRECK_SLOT_END
	var _r1: int = _s_id.resize(slots)
	var _r2: int = _s_view.resize(slots)
	_s_view.fill(-1)
	var _r3: int = _s_group.resize(slots)
	var _r4: int = _s_team.resize(slots)
	var _r5: int = _s_state.resize(slots)
	var _r6: int = _s_radius.resize(slots)
	var _r7: int = _s_prev.resize(slots)
	var _r8: int = _s_cur.resize(slots)
	var _r9: int = _s_wreck.resize(slots)
	var _r10: int = _s_pq.resize(slots)
	var _r11: int = _s_cq.resize(slots)
	for i: int in cfg.view_cap:
		var v: EntityView = EntityView.new()
		v.visible = false
		v.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(v)
		_views.append(v)
		var _f: bool = _free.push_back(cfg.view_cap - 1 - i)
	far = FarPools.new()
	far.name = "FarPools"
	add_child(far)
	far.setup(classes, far_capacity)
	icons = IconPool.new()
	icons.name = "Icons"
	add_child(icons)
	icons.setup_icons(far_capacity)


## R0 C1-07: the possessed unit's pose this frame (from Prediction.render_state). Wins over the sim sample.
func set_local_override(id: int, p: Vector3, b: Basis) -> void:
	_ov_id = id
	_ov_pos = p
	_ov_basis = b
	var s: int = EntityId.slot(id)
	if s >= 0 and s < _s_view.size() and _s_id[s] == id and _s_view[s] >= 0:
		_place(_views[_s_view[s]], p, b, _s_radius[s])


func clear_local_override() -> void:
	_ov_id = EntityId.NULL_ID


## Forces the next sync to re-read the SimView (viewer team change, world swap).
func invalidate() -> void:
	_last_tick = -1
	_tail_pending = false


func view_capacity() -> int:
	return _views.size()


func bound_count() -> int:
	return _views.size() - _free.size()


## The pooled view currently bound to `id`, or null (far and icon entities have none).
func view_for(id: int) -> EntityView:
	var s: int = EntityId.slot(id)
	if s < 0 or s >= _s_view.size() or _s_id[s] != id or _s_view[s] < 0:
		return null
	return _views[_s_view[s]]


func draw_calls() -> int:
	return bound_count() + far.draw_calls() + icons.draw_calls()


func sync(view: SimView, render_time: float) -> void:
	_frame += 1
	var tick: int = view.tick()
	if tick != _last_tick:
		_read_tick(view, tick)
	elif _tail_pending:
		_read_tail(view)
	var alpha: float = clampf(render_time * tick_hz - float(tick - 1), 0.0, 1.0)
	var threshold: float = _classify(alpha)
	_draw(alpha, threshold)
	_sweep(render_time)


## Sets `_mode` / `_d2` per entity and returns the squared distance of the `view_cap`-th nearest view candidate.
func _classify(alpha: float) -> float:
	var n: int = _ids.size()
	var icon_m2: float = _cfg.icon_band_start_m * _cfg.icon_band_start_m
	var far_k: float = 2.0 * px_per_m / _cfg.far_px
	var elig: int = 0
	for i: int in n:
		var id: int = _ids[i]
		var s: int = EntityId.slot(id)
		var d2: float = 0.0
		var mode: int = MODE_VIEW
		if id != _ov_id:
			d2 = cam_pos.distance_squared_to(_s_prev[s].lerp(_s_cur[s], alpha if i < _split else 1.0))
			var fd: float = _s_radius[s] * far_k
			if d2 >= fd * fd:
				mode = MODE_ICON if d2 >= icon_m2 else MODE_FAR
		_d2[i] = d2
		_mode[i] = mode
		if mode == MODE_VIEW:
			elig += 1
	if elig <= _cfg.view_cap:
		return INF
	var _r12: int = _rank.resize(elig)
	var k: int = 0
	for i: int in n:
		if _mode[i] == MODE_VIEW:
			_rank[k] = _d2[i]
			k += 1
	_rank.sort()
	return _rank[_cfg.view_cap - 1]


func _draw(alpha: float, threshold: float) -> void:
	far.begin()
	icons.begin()
	var nv: int = 0
	for i: int in _ids.size():
		var id: int = _ids[i]
		var s: int = EntityId.slot(id)
		var mode: int = _mode[i]
		var r: float = _s_radius[s]
		var a: float = alpha if i < _split else 1.0
		if mode == MODE_VIEW:
			var v: EntityView = _bind(s, id) if _d2[i] <= threshold else null
			if v != null:
				v.seen_tick = _frame
				v.linger_until = -1.0
				nv += 1
				if id == _ov_id:
					_place(v, _ov_pos, _ov_basis, r)
				else:
					_place(v, _s_prev[s].lerp(_s_cur[s], a), Basis(_s_pq[s].slerp(_s_cq[s], a)), r)
				continue
			mode = MODE_FAR
		_unbind(s)
		var p: Vector3 = _s_prev[s].lerp(_s_cur[s], a)
		var col: Color = _wreck_color[_s_team[s]] if _s_wreck[s] != 0 else _team_color[_s_team[s]]
		if mode == MODE_ICON:
			var _i: bool = icons.add(p, IconPool.icon_size(r, cam_pos.distance_to(p), px_per_m), col, _classes.group_kind(_s_group[s]))
		else:
			var _f: bool = far.push(_s_group[s], Transform3D(Basis(_s_cq[s]).scaled(Vector3(r, r, r)), p), col)
	far.commit()
	icons.commit()
	last_views = nv
	last_far = far.instance_total()
	last_icons = icons.count


## Reads ids and the first half of the new tick's poses into the per-slot cache (shifts cur -> prev); the second half
## follows in the next `sync` frame (`_read_tail`, TA-55). Entities not yet committed draw at alpha 1.0 of their old pair,
## which is exactly where the new pair starts, so nothing pops. A tick that arrives while a tail is still pending
## (frame rate below the tick rate) reads everything at once.
func _read_tick(view: SimView, tick: int) -> void:
	_last_tick = tick
	_ids = view.visible_ids(viewer_team)
	var n: int = _ids.size()
	if _d2.size() < n:
		var _r13: int = _d2.resize(n + (n >> 1) + 16)
		var _r14: int = _mode.resize(_d2.size())
	var split: int = n if (_tail_pending or n < STAGGER_MIN) else n >> 1
	_tail_pending = split < n
	_split = split
	var _r17: int = _ids_lo.resize(split)
	var _r18: int = _ids_hi.resize(n - split)
	for i: int in split:
		_ids_lo[i] = _ids[i]
	for i: int in n - split:
		_ids_hi[i] = _ids[split + i]
	_grow_pose(split, n - split)
	var _alive: int = view.read_poses(_ids_lo, _pose_pos, _pose_rot)
	_commit(view, _ids_lo, _pose_pos, _pose_rot, tick)
	if _tail_pending:
		_prime_fresh(view)


func _read_tail(view: SimView) -> void:
	_tail_pending = false
	_split = _ids.size()
	var _alive: int = view.read_poses(_ids_hi, _pose_hi, _rot_hi)
	_commit(view, _ids_hi, _pose_hi, _rot_hi, _last_tick)


func _grow_pose(lo: int, hi: int) -> void:
	if _pose_pos.size() < lo:
		var _a1: int = _pose_pos.resize(lo + (lo >> 1) + 16)
		var _a2: int = _pose_rot.resize(_pose_pos.size())
	if _pose_hi.size() < hi:
		var _a3: int = _pose_hi.resize(hi + (hi >> 1) + 16)
		var _a4: int = _rot_hi.resize(_pose_hi.size())


## New ids in the pending half: adopt now with a single settled pose.
func _prime_fresh(view: SimView) -> void:
	for i: int in _ids_hi.size():
		var id: int = _ids_hi[i]
		var s: int = EntityId.slot(id)
		if _s_id[s] == id:
			continue
		_adopt(view, id, s)
		var p: Vector3 = view.pos(id)
		var q: Quaternion = Quaternion(view.basis(id))
		_s_prev[s] = p
		_s_cur[s] = p
		_s_pq[s] = q
		_s_cq[s] = q


func _commit(view: SimView, ids: PackedInt32Array, pos: PackedVector3Array, rot: PackedVector4Array, tick: int) -> void:
	for i: int in ids.size():
		var id: int = ids[i]
		var s: int = EntityId.slot(id)
		var fresh: bool = _s_id[s] != id
		if fresh:
			_adopt(view, id, s)
		elif (s + tick) % STATE_REFRESH_TICKS == 0:
			_refresh_state(view, id, s)
		var p: Vector3 = pos[i]
		var rv: Vector4 = rot[i]
		var q: Quaternion = Quaternion(rv.x, rv.y, rv.z, rv.w)
		_s_prev[s] = p if fresh else _s_cur[s]
		_s_cur[s] = p
		_s_pq[s] = q if fresh else _s_cq[s]
		_s_cq[s] = q


## A slot taken by a new id: drop the old binding (its view lingers), read the static facts.
func _adopt(view: SimView, id: int, s: int) -> void:
	_s_view[s] = -1   # an old view still bound here lingers on its own (see _sweep)
	_s_id[s] = id
	_s_group[s] = maxi(_classes.group_of(view.def_id(id)), 0)
	_s_radius[s] = maxf(view.radius(id), 1.0)
	_s_wreck[s] = 1 if EntityId.is_wreck(id) else 0
	_s_team[s] = clampi(view.team(id), 0, UnitMaterialCache.TEAM_COUNT - 1)
	_s_state[s] = -1
	_refresh_state(view, id, s)


func _refresh_state(view: SimView, id: int, s: int) -> void:
	var t: int = clampi(view.team(id), 0, UnitMaterialCache.TEAM_COUNT - 1)
	var st: int = UnitMaterialCache.state_for(1.0 - view.hp01(id), _s_wreck[s] != 0)
	if t == _s_team[s] and st == _s_state[s]:
		return
	_s_team[s] = t
	_s_state[s] = st
	if _s_view[s] >= 0:
		_views[_s_view[s]].material_override = _materials.get_material(t, st)


func _bind(s: int, id: int) -> EntityView:
	if _s_view[s] >= 0:
		return _views[_s_view[s]]
	var vi: int = -1
	if not _free.is_empty():
		vi = _free[_free.size() - 1]
		var _e: int = _free.resize(_free.size() - 1)
	else:
		vi = _steal_lingering()
	if vi < 0:
		return null
	var v: EntityView = _views[vi]
	v.id = id
	v.group = _s_group[s]
	v.mesh = PlaceholderMeshes.mesh_for(_classes.group_kind(v.group))
	v.material_override = _materials.get_material(_s_team[s], _s_state[s])
	v.visible = true
	_s_view[s] = vi
	return v


func _steal_lingering() -> int:
	for vi: int in _views.size():
		var v: EntityView = _views[vi]
		if v.id != EntityId.NULL_ID and v.linger_until >= 0.0:
			_release(vi)
			var _e: int = _free.resize(_free.size() - 1)
			return vi
	return -1


## An entity that stays visible but is no longer a view candidate: free its view at once.
func _unbind(s: int) -> void:
	var vi: int = _s_view[s]
	if vi < 0:
		return
	_s_view[s] = -1
	_views[vi].id = EntityId.NULL_ID
	_views[vi].visible = false
	var _f: bool = _free.push_back(vi)


## Views whose entity left the visible list: linger for the death effect, then return to the pool.
func _sweep(render_time: float) -> void:
	for vi: int in _views.size():
		var v: EntityView = _views[vi]
		if v.id == EntityId.NULL_ID or v.seen_tick == _frame:
			continue
		if v.linger_until < 0.0:
			v.linger_until = render_time + _cfg.linger_s
		elif render_time >= v.linger_until:
			_release(vi)


func _release(vi: int) -> void:
	var v: EntityView = _views[vi]
	var s: int = EntityId.slot(v.id)
	if s >= 0 and s < _s_view.size() and _s_view[s] == vi:
		_s_view[s] = -1
	v.id = EntityId.NULL_ID
	v.visible = false
	v.linger_until = -1.0
	var _f: bool = _free.push_back(vi)


func _place(v: EntityView, p: Vector3, b: Basis, r: float) -> void:
	v.transform = Transform3D(b.scaled(Vector3(r, r, r)), p)
