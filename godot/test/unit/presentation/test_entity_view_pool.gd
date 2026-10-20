extends GdUnitTestSuite
## TA-26: EntityViewPool (03 s10.1, R0 C1-07 / C1-17): view reuse, per-tier caps, the far-pool hand-off, the
## render_state override and its judder bound, class grouping, config.

const TIERS: String = "res://content/defs/quality_tiers.json"
const NEAR_M: float = 60.0
const MID_M: float = 800.0
const BEYOND_ICON_M: float = 3000.0

var _root: Node3D


func before_test() -> void:
	_root = auto_free(Node3D.new())
	add_child(_root)


func _classes() -> EntityClassTable:
	return EntityClassTable.from_content(WorldTestKit.content())


func _tier(tier_id: String) -> EntityViewConfig:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TIERS))
	for e: Dictionary in data["quality_tiers"]:
		if str(e["id"]) == tier_id:
			return EntityViewConfig.from_dict(e)
	return null


func _pool(cfg: EntityViewConfig) -> EntityViewPool:
	var p: EntityViewPool = EntityViewPool.new()
	_root.add_child(p)
	p.setup(cfg, _classes(), UnitMaterialCache.new())
	p.cam_pos = Vector3(0.0, 0.0, Sphere.PLANET_RADIUS + 300.0)
	return p


func _cfg(cap: int) -> EntityViewConfig:
	var c: EntityViewConfig = EntityViewConfig.new()
	c.view_cap = cap
	return c


## n entities `dist` metres from the camera along +X, spread on a line, the dart def.
func _fill(v: StubSimView, n: int, dist: float, first_slot: int = 0) -> void:
	var dart: int = WorldTestKit.def_id(&"dart")
	for i: int in n:
		var _id: int = v.put(first_slot + i, Vector3(dist + float(i) * 0.1, 0.0, Sphere.PLANET_RADIUS + 300.0), dart, i % 8)


func test_caps_per_tier_match_quality_tiers() -> void:
	for pair: Array in [["low", 200], ["medium", 400], ["high", 800]]:
		var cfg: EntityViewConfig = _tier(pair[0])
		assert_int(cfg.view_cap).is_equal(pair[1])
		var pool: EntityViewPool = _pool(cfg)
		var v: StubSimView = StubSimView.new()
		_fill(v, int(pair[1]) + 100, NEAR_M)
		pool.sync(v, 0.0)
		assert_int(pool.view_capacity()).is_equal(pair[1])
		assert_int(pool.bound_count()).is_equal(pair[1])
		assert_int(pool.last_views + pool.last_far).is_equal(int(pair[1]) + 100)
		pool.queue_free()


func test_caps_profile_bounds_the_tier_cap() -> void:
	assert_int(_tier("high").bounded_by(200).view_cap).is_equal(200)
	assert_int(_tier("low").bounded_by(800).view_cap).is_equal(200)
	assert_int(_tier("medium").bounded_by(0).view_cap).is_equal(400)


func test_views_are_reused_not_allocated() -> void:
	var pool: EntityViewPool = _pool(_cfg(8))
	var kids: int = pool.get_child_count()
	var v: StubSimView = StubSimView.new()
	_fill(v, 8, NEAR_M)
	pool.sync(v, 0.0)
	var first: EntityView = pool.view_for(v.ids[0])
	assert_object(first).is_not_null()
	v.advance()
	pool.sync(v, 0.0)
	assert_object(pool.view_for(v.ids[0])).is_same(first)
	# every entity leaves; after the linger the views return and serve new ids
	var w: StubSimView = StubSimView.new()
	w.tick_no = 5
	_fill(w, 8, NEAR_M, 100)
	pool.sync(w, 100.0)
	pool.sync(w, 100.0)
	assert_int(pool.get_child_count()).is_equal(kids)
	assert_int(pool.bound_count()).is_equal(8)
	assert_object(pool.view_for(v.ids[0])).is_null()
	assert_object(pool.view_for(w.ids[0])).is_not_null()


func test_released_view_lingers_then_frees() -> void:
	var cfg: EntityViewConfig = _cfg(4)
	var pool: EntityViewPool = _pool(cfg)
	var v: StubSimView = StubSimView.new()
	_fill(v, 1, NEAR_M)
	pool.sync(v, 0.0)
	var id: int = v.ids[0]
	var view: EntityView = pool.view_for(id)
	v.ids = PackedInt32Array()
	v.advance()
	pool.sync(v, 0.5)
	assert_bool(view.visible).is_true()
	pool.sync(v, 0.5 + cfg.linger_s + 0.1)
	assert_bool(view.visible).is_false()
	assert_int(pool.bound_count()).is_equal(0)


func test_far_pool_hand_off_nearest_first() -> void:
	var pool: EntityViewPool = _pool(_cfg(4))
	var v: StubSimView = StubSimView.new()
	_fill(v, 12, NEAR_M)
	pool.sync(v, 0.0)
	assert_int(pool.last_views).is_equal(4)
	assert_int(pool.last_far).is_equal(8)
	for i: int in 4:
		assert_object(pool.view_for(v.ids[i])).is_not_null()
	assert_object(pool.view_for(v.ids[11])).is_null()
	# the far entities become the nearest: views are handed off
	v.advance()
	for i: int in 12:
		v.positions[v.ids[i]] = Vector3(NEAR_M + float(12 - i), 0.0, Sphere.PLANET_RADIUS + 300.0)
	pool.sync(v, 2.0 / 30.0)
	assert_object(pool.view_for(v.ids[11])).is_not_null()
	assert_object(pool.view_for(v.ids[0])).is_null()
	assert_int(pool.last_views).is_equal(4)
	assert_int(pool.last_far).is_equal(8)


func test_beyond_cap_entities_draw_in_at_most_eight_calls() -> void:
	var pool: EntityViewPool = _pool(_cfg(10))
	var v: StubSimView = StubSimView.new()
	var content: ContentSet = WorldTestKit.content()
	var defs: Array[int] = []
	for d: ShipDef in content.ships:
		defs.append(d.def_id)
	for d: GroundUnitDef in content.ground_units:
		defs.append(d.def_id)
	for d: StructureDef in content.structures:
		defs.append(d.def_id)
	for i: int in 400:
		var _id: int = v.put(i, Vector3(MID_M + float(i), 0.0, Sphere.PLANET_RADIUS + 300.0), defs[i % defs.size()], i % 8)
	pool.sync(v, 0.0)
	assert_int(pool.bound_count()).is_less_equal(10)
	assert_int(pool.last_far + pool.last_views).is_equal(400)
	assert_int(pool.far.draw_calls()).is_less_equal(8)
	assert_int(pool.far.pools.size()).is_less_equal(8)
	assert_int(pool.last_icons).is_equal(0)


func test_icon_band_takes_the_far_distance() -> void:
	var pool: EntityViewPool = _pool(_cfg(8))
	var v: StubSimView = StubSimView.new()
	_fill(v, 5, BEYOND_ICON_M)
	pool.sync(v, 0.0)
	assert_int(pool.last_icons).is_equal(5)
	assert_int(pool.last_far).is_equal(0)
	assert_int(pool.bound_count()).is_equal(0)
	assert_int(pool.icons.draw_calls()).is_equal(1)


func test_state_follows_damage_and_wrecks() -> void:
	var cache: UnitMaterialCache = UnitMaterialCache.new()
	var pool: EntityViewPool = EntityViewPool.new()
	_root.add_child(pool)
	pool.setup(_cfg(4), _classes(), cache)
	pool.cam_pos = Vector3(0.0, 0.0, Sphere.PLANET_RADIUS + 300.0)
	var v: StubSimView = StubSimView.new()
	var dart: int = WorldTestKit.def_id(&"dart")
	var healthy: int = v.put(0, Vector3(NEAR_M, 0.0, Sphere.PLANET_RADIUS + 300.0), dart, 2, 6.0, 1.0)
	var wreck: int = v.put(1, Vector3(NEAR_M + 10.0, 0.0, Sphere.PLANET_RADIUS + 300.0), dart, 2, 6.0, 0.2, true)
	pool.sync(v, 0.0)
	assert_object(pool.view_for(healthy).material_override).is_same(cache.get_material(2, UnitMaterialCache.State.HEALTHY))
	assert_object(pool.view_for(wreck).material_override).is_same(cache.get_material(2, UnitMaterialCache.State.WRECK))
	assert_int(cache.size()).is_equal(2)


# ---- R0 C1-07: render_state override -------------------------------------------------------------------------

func test_override_pose_wins_over_the_sim_sample() -> void:
	var pool: EntityViewPool = _pool(_cfg(4))
	var v: StubSimView = StubSimView.new()
	_fill(v, 1, NEAR_M)
	var id: int = v.ids[0]
	var p: Vector3 = Vector3(1.0, 2.0, Sphere.PLANET_RADIUS + 290.0)
	var b: Basis = Basis(Vector3.UP, 0.7)
	pool.set_local_override(id, p, b)
	pool.sync(v, 0.0)
	var view: EntityView = pool.view_for(id)
	assert_vector(view.global_transform.origin).is_equal_approx(p, Vector3.ONE * 1e-4)
	assert_vector(view.global_transform.basis.get_rotation_quaternion().get_euler()).is_equal_approx(b.get_euler(), Vector3.ONE * 1e-4)
	pool.clear_local_override()
	v.advance()
	pool.sync(v, 1.0)
	assert_vector(pool.view_for(id).global_transform.origin).is_not_equal(p)


func test_override_view_is_always_drawn_as_a_mesh_even_over_the_cap() -> void:
	var pool: EntityViewPool = _pool(_cfg(2))
	var v: StubSimView = StubSimView.new()
	_fill(v, 6, NEAR_M)
	var far_id: int = v.ids[5]
	pool.set_local_override(far_id, Vector3(5.0, 0.0, Sphere.PLANET_RADIUS), Basis.IDENTITY)
	pool.sync(v, 0.0)
	assert_object(pool.view_for(far_id)).is_not_null()
	assert_int(pool.bound_count()).is_equal(2)


## 30 Hz prediction stub, 60 fps frames, a Dart at 110 m/s (R0 C1-07): per-frame displacement of the possessed
## view has a coefficient of variation < 10 %. The control (the raw 30 Hz state) steps every other frame.
func test_possessed_dart_displacement_variance_under_ten_percent() -> void:
	var pool: EntityViewPool = _pool(_cfg(4))
	var v: StubSimView = StubSimView.new()
	_fill(v, 1, NEAR_M)
	var id: int = v.ids[0]
	var speed: float = WorldTestKit.content().ships[0].v_cruise
	var hz: float = pool.tick_hz
	var origin: Vector3 = Vector3(0.0, 0.0, Sphere.PLANET_RADIUS + 300.0)
	var frames: int = 120
	var fps: float = 60.0
	var disp: PackedFloat64Array = PackedFloat64Array()
	var raw: PackedFloat64Array = PackedFloat64Array()
	var prev: Vector3 = Vector3.ZERO
	var prev_raw: Vector3 = Vector3.ZERO
	for f: int in frames:
		var t: float = (float(f) + 1.0) / fps            # wall clock
		var tick: int = int(floor(t * hz)) + 1           # prediction input_tick
		var alpha: float = t * hz - floor(t * hz)        # Engine.get_physics_interpolation_fraction()
		var a: Vector3 = origin + Vector3.RIGHT * speed * (float(tick - 1) / hz)
		var b: Vector3 = origin + Vector3.RIGHT * speed * (float(tick) / hz)
		pool.set_local_override(id, a.lerp(b, alpha), Basis.IDENTITY)
		v.tick_no = tick
		pool.sync(v, t)
		var at: Vector3 = pool.view_for(id).global_transform.origin
		if f > 0:
			var _a: bool = disp.push_back(at.distance_to(prev))
			var _b: bool = raw.push_back(b.distance_to(prev_raw))
		prev = at
		prev_raw = b
	assert_float(_cv(disp)).is_less(0.10)
	assert_float(_mean(disp)).is_equal_approx(speed / fps, 0.01)
	assert_float(_cv(raw)).is_greater(0.5)   # the un-interpolated state would judder


func test_interpolation_between_the_last_two_ticks() -> void:
	var pool: EntityViewPool = _pool(_cfg(4))
	var v: StubSimView = StubSimView.new()
	_fill(v, 1, NEAR_M)
	var id: int = v.ids[0]
	var p0: Vector3 = v.positions[id]
	pool.sync(v, 0.0)
	v.advance()
	v.positions[id] = p0 + Vector3(30.0, 0.0, 0.0)
	var t1: float = float(v.tick()) / pool.tick_hz
	pool.sync(v, t1 - 0.5 / pool.tick_hz)    # half a tick before the latest sample
	assert_float(pool.view_for(id).global_transform.origin.x).is_equal_approx(p0.x + 15.0, 0.01)
	pool.sync(v, t1)
	assert_float(pool.view_for(id).global_transform.origin.x).is_equal_approx(p0.x + 30.0, 0.01)


# ---- classes and config --------------------------------------------------------------------------------------

func test_class_table_groups_every_def_and_stays_within_eight_pools() -> void:
	var t: EntityClassTable = _classes()
	assert_int(t.group_count()).is_between(1, 8)
	var content: ContentSet = WorldTestKit.content()
	for d: ShipDef in content.ships:
		assert_int(t.group_of(d.def_id)).is_greater_equal(0)
	for d: StructureDef in content.structures:
		assert_int(t.group_of(d.def_id)).is_greater_equal(0)
	assert_int(t.group_of(-1)).is_equal(-1)
	assert_int(t.group_of(DefRanges.END)).is_equal(-1)
	var dart: int = t.group_of(WorldTestKit.def_id(&"dart"))
	assert_str(String(t.group_name(dart))).is_equal("ShipDartFar")
	assert_int(t.group_kind(dart)).is_equal(DefRanges.K_SHIP)


func test_placeholder_meshes_fit_the_far_triangle_budget() -> void:
	for kind: int in [DefRanges.K_SHIP, DefRanges.K_GROUND, DefRanges.K_STRUCTURE]:
		assert_int(PlaceholderMeshes.triangle_count(kind)).is_between(1, PlaceholderMeshes.FAR_TRI_BUDGET)
		assert_object(PlaceholderMeshes.mesh_for(kind)).is_same(PlaceholderMeshes.mesh_for(kind))


func test_config_reads_the_tier_row() -> void:
	var c: EntityViewConfig = _tier("low")
	assert_float(c.icon_band_start_m).is_equal(1800.0)
	assert_bool(c.trails_enabled).is_false()
	assert_int(c.projectile_pool).is_equal(1024)
	assert_float(_tier("high").icon_band_start_m).is_equal(2500.0)
	assert_int(_tier("high").trail_segments).is_equal(1024)


## TA-52 (R0 B.11 A-56): the bulk read gives the same poses as the per-id pos() / basis() the pool used before.
func test_read_poses_matches_per_id_pos_and_basis() -> void:
	var w: SimWorld = WorldTestKit.world(11)
	var ids: PackedInt32Array = PackedInt32Array()
	for k: int in 6:
		var d: int = WorldTestKit.spawn(w, &"dart", 0, 0, WorldTestKit.at(300.0, 40.0 * float(k)), Vector3(0.0, 90.0, 30.0 * float(k)))
		var _a: bool = ids.push_back(d)
	for _t: int in 5:
		w.step()
	var sv: SimView = w.view()
	var pos: PackedVector3Array = PackedVector3Array()
	var rot: PackedVector4Array = PackedVector4Array()
	var _r1: int = pos.resize(ids.size())
	var _r2: int = rot.resize(ids.size())
	assert_int(sv.read_poses(ids, pos, rot)).is_equal(ids.size())
	for i: int in ids.size():
		var q: Quaternion = sv.basis(ids[i]).get_rotation_quaternion()
		assert_vector(pos[i]).is_equal(sv.pos(ids[i]))
		assert_float(absf(q.dot(Quaternion(rot[i].x, rot[i].y, rot[i].z, rot[i].w)))).is_equal_approx(1.0, 1.0e-5)


## The pool places a view from the bulk read and keeps its scratch arrays across ticks (no resize at a steady n).
func test_sync_uses_bulk_poses_with_stable_scratch() -> void:
	var pool: EntityViewPool = _pool(_cfg(50))
	var v: StubSimView = StubSimView.new()
	_fill(v, 20, NEAR_M)
	pool.sync(v, 0.0)
	var id: int = v.ids[3]
	assert_vector(pool.view_for(id).position).is_equal_approx(v.pos(id), Vector3(1.0e-3, 1.0e-3, 1.0e-3))
	var cap: int = pool._stager.pos_lo.size()
	v.advance()
	pool.sync(v, 1.0 / pool.tick_hz)
	assert_int(pool._stager.pos_lo.size()).is_equal(cap)
	assert_int(pool._stager.rot_lo.size()).is_equal(cap)


func _mean(a: PackedFloat64Array) -> float:
	var s: float = 0.0
	for x: float in a:
		s += x
	return s / float(a.size())


func _cv(a: PackedFloat64Array) -> float:
	var m: float = _mean(a)
	var s: float = 0.0
	for x: float in a:
		s += (x - m) * (x - m)
	return sqrt(s / float(a.size())) / m



const EPS: Vector3 = Vector3(1.0e-3, 1.0e-3, 1.0e-3)
const STAGGER_N: int = 200   ## head = ids[0..99], tail = ids[100..199]


## TA-55: moves every entity by `dy` along +Y.
func _shift_all(v: StubSimView, dy: float) -> void:
	for id: int in v.ids:
		v.positions[id] = (v.positions[id] as Vector3) + Vector3(0.0, dy, 0.0)


## A pool with `STAGGER_N` near views, settled on tick 1.
func _staggered_pool(v: StubSimView) -> EntityViewPool:
	var pool: EntityViewPool = _pool(_cfg(300))
	_fill(v, STAGGER_N, NEAR_M)
	pool.sync(v, 0.0)
	pool.sync(v, 0.0)
	return pool


## Render time inside tick `tick` at fraction `alpha` (alpha = rt * hz - (tick - 1)).
func _rt(pool: EntityViewPool, tick: int, alpha: float) -> float:
	return (float(tick - 1) + alpha) / pool.tick_hz


## TA-55: on the tick frame (alpha 0.3) the head half is at lerp(old, new), the tail half still at its OLD pose
## (alpha 1.0 of the old pair); one frame later the tail is at the new interpolated pose too.
func test_tick_frame_holds_the_tail_half_at_its_old_pose() -> void:
	var v: StubSimView = StubSimView.new()
	var pool: EntityViewPool = _staggered_pool(v)
	var head: int = v.ids[10]
	var tail: int = v.ids[STAGGER_N - 10]
	var head0: Vector3 = v.positions[head]
	var tail0: Vector3 = v.positions[tail]
	v.advance()
	_shift_all(v, 10.0)
	var rt: float = _rt(pool, v.tick(), 0.3)
	pool.sync(v, rt)
	assert_bool(pool._stager.pending).is_true()
	assert_vector(pool.view_for(head).position).is_equal_approx(head0 + Vector3(0.0, 3.0, 0.0), EPS)
	assert_vector(pool.view_for(tail).position).is_equal_approx(tail0, EPS)
	pool.sync(v, rt)
	assert_bool(pool._stager.pending).is_false()
	assert_vector(pool.view_for(tail).position).is_equal_approx(tail0 + Vector3(0.0, 3.0, 0.0), EPS)
	assert_vector(pool.view_for(head).position).is_equal_approx(head0 + Vector3(0.0, 3.0, 0.0), EPS)


## TA-55: a new id that lands in the pending half is adopted on the tick frame and drawn at its own pose, and stays there.
func test_new_id_in_the_pending_half_draws_at_its_pose() -> void:
	var v: StubSimView = StubSimView.new()
	var pool: EntityViewPool = _staggered_pool(v)
	v.advance()
	var p: Vector3 = Vector3(NEAR_M, 5.0, Sphere.PLANET_RADIUS + 300.0)
	var fresh: int = v.put(STAGGER_N + 40, p, WorldTestKit.def_id(&"dart"), 1)
	var rt: float = _rt(pool, v.tick(), 0.4)
	pool.sync(v, rt)
	assert_bool(pool._stager.pending).is_true()
	assert_object(pool.view_for(fresh)).is_not_null()
	assert_vector(pool.view_for(fresh).position).is_equal_approx(p, EPS)
	pool.sync(v, rt)
	assert_vector(pool.view_for(fresh).position).is_equal_approx(p, EPS)


## TA-55: ids reordered and one despawned between ticks: per-slot state keeps every remaining view on its interpolated pose.
func test_reorder_and_despawn_between_ticks_settle_correctly() -> void:
	var v: StubSimView = StubSimView.new()
	var pool: EntityViewPool = _staggered_pool(v)
	var before: Dictionary = {}
	for id: int in v.ids:
		before[id] = v.positions[id]
	var gone: int = v.ids[STAGGER_N - 5]
	var kept: PackedInt32Array = PackedInt32Array()
	for i: int in range(STAGGER_N - 1, -1, -1):
		if v.ids[i] != gone:
			var _a: bool = kept.push_back(v.ids[i])
	v.ids = kept
	var _e: bool = v.positions.erase(gone)
	v.advance()
	_shift_all(v, 10.0)
	var rt: float = _rt(pool, v.tick(), 0.5)
	pool.sync(v, rt)
	pool.sync(v, rt)
	assert_int(pool.last_views).is_equal(STAGGER_N - 1)
	for id: int in v.ids:
		assert_vector(pool.view_for(id).position).is_equal_approx((before[id] as Vector3) + Vector3(0.0, 5.0, 0.0), EPS)


## TA-55: no per-frame allocation: every scratch array keeps its size over many staggered ticks.
func test_staggered_read_keeps_scratch_capacity_steady() -> void:
	var v: StubSimView = StubSimView.new()
	var pool: EntityViewPool = _staggered_pool(v)
	var st: PoseStager = pool._stager
	var sizes: Array[int] = [st.pos_lo.size(), st.rot_lo.size(), st.pos_hi.size(), st.rot_hi.size(), st.ids_lo.size(), st.ids_hi.size(), pool._d2.size(), pool._mode.size()]
	for k: int in 40:
		v.advance()
		var rt: float = _rt(pool, v.tick(), 0.5)
		pool.sync(v, rt)
		pool.sync(v, rt)
		pool.sync(v, rt)
	assert_object(pool._stager).is_same(st)
	assert_array([st.pos_lo.size(), st.rot_lo.size(), st.pos_hi.size(), st.rot_hi.size(), st.ids_lo.size(), st.ids_hi.size(), pool._d2.size(), pool._mode.size()]).is_equal(sizes)


## TA-55: a tick that arrives before the tail ran (frame rate below the tick rate) reads everything at once and settles.
func test_tick_before_tail_reads_all_at_once() -> void:
	var v: StubSimView = StubSimView.new()
	var pool: EntityViewPool = _staggered_pool(v)
	v.advance()
	_shift_all(v, 10.0)
	pool.sync(v, _rt(pool, v.tick(), 0.0))
	assert_bool(pool._stager.pending).is_true()
	v.advance()
	_shift_all(v, 10.0)
	pool.sync(v, _rt(pool, v.tick(), 0.0))
	assert_bool(pool._stager.pending).is_false()
	pool.sync(v, _rt(pool, v.tick(), 1.0))
	for id: int in v.ids:
		assert_vector(pool.view_for(id).position).is_equal_approx(v.positions[id], EPS)
