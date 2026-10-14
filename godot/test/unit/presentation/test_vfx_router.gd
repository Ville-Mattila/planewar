extends GdUnitTestSuite
## TA-26: VfxRouter routing per SimEvent kind (03 s10.1, 07 s6), the pooled effects it spawns, and the pre-warm.

var _pool: VfxPool
var _decals: DecalPool
var _router: VfxRouter
var _view: StubSimView


func before_test() -> void:
	_pool = auto_free(VfxPool.new())
	add_child(_pool)
	_pool.setup()
	_decals = auto_free(DecalPool.new())
	add_child(_decals)
	_decals.setup_decals()
	_router = VfxRouter.new(_pool, _decals)
	_view = StubSimView.new()


func _ev(kind: int, pos: Vector3 = Vector3(0.0, 0.0, Sphere.PLANET_RADIUS)) -> SimEvent:
	var e: SimEvent = SimEvent.new()
	e.kind = kind as SimEvent.Kind
	e.pos = pos
	return e


func test_route_table_per_kind() -> void:
	var expected: Dictionary = {
		SimEvent.Kind.HIT: &"vfx_hit_spark",
		SimEvent.Kind.BOMB_IMPACT: &"vfx_bomb_impact_s",
		SimEvent.Kind.DEATH: &"vfx_explosion_ship",
		SimEvent.Kind.STRUCTURE_LOST: &"vfx_explosion_structure",
		SimEvent.Kind.LAUNCHED: &"vfx_dust_plume",
		SimEvent.Kind.LANDING: &"vfx_dust_plume",
		SimEvent.Kind.DOCKED: &"vfx_dock_beam",
		SimEvent.Kind.SERVICED: &"vfx_pad_lights",
		SimEvent.Kind.BUILD_DONE: &"vfx_spawn_in",
		SimEvent.Kind.SHIELD_COLLAPSE: &"vfx_shield_hit",
		SimEvent.Kind.POSSESSED: &"vfx_possess_pulse",
	}
	for k: int in SimEvent.Kind.values():
		var want: StringName = expected.get(k, &"")
		assert_str(String(VfxRouter.route(k))).is_equal(String(want))


func test_every_routed_id_is_in_the_catalog() -> void:
	for k: int in SimEvent.Kind.values():
		var id: StringName = VfxRouter.route(k)
		if id != &"":
			assert_bool(VfxCatalog.has(id)).is_true()


func test_handle_spawns_the_routed_effect() -> void:
	for k: int in [SimEvent.Kind.DEATH, SimEvent.Kind.DOCKED, SimEvent.Kind.LAUNCHED, SimEvent.Kind.BUILD_DONE]:
		var before: int = _pool.spawned_total
		assert_int(_router.handle(_ev(k), _view)).is_equal(1)
		assert_int(_pool.spawned_total).is_equal(before + 1)
		assert_str(String(_pool.last_id)).is_equal(String(VfxRouter.route(k)))


func test_unrouted_kinds_spawn_nothing() -> void:
	assert_int(_router.handle(_ev(SimEvent.Kind.ORDER_DONE), _view)).is_equal(0)
	assert_int(_router.handle(_ev(SimEvent.Kind.MATCH_END), _view)).is_equal(0)
	assert_int(_pool.spawned_total).is_equal(0)


func test_bomb_impact_leaves_a_scorch_decal() -> void:
	assert_int(_router.handle(_ev(SimEvent.Kind.BOMB_IMPACT), _view)).is_equal(1)
	assert_int(_decals.live_count()).is_equal(1)
	assert_int(_decals.multimesh.visible_instance_count).is_equal(1)


func test_hit_adds_smoke_below_the_hp_thresholds() -> void:
	var dart: int = WorldTestKit.def_id(&"dart")
	var healthy: int = _view.put(0, Vector3(1.0, 0.0, Sphere.PLANET_RADIUS), dart, 0, 6.0, 0.9)
	var hurt: int = _view.put(1, Vector3(1.0, 0.0, Sphere.PLANET_RADIUS), dart, 0, 6.0, 0.4)
	var e1: SimEvent = _ev(SimEvent.Kind.HIT)
	e1.a = healthy
	assert_int(_router.handle(e1, _view)).is_equal(1)
	var e2: SimEvent = _ev(SimEvent.Kind.HIT)
	e2.a = hurt
	assert_int(_router.handle(e2, _view)).is_equal(2)
	assert_int(int(_pool.counts.get(VfxRouter.SMOKE_ID, 0))).is_equal(1)
	assert_int(VfxRouter.smoke_step(0.8, VfxRouter.SMOKE_HP01)).is_equal(0)
	assert_int(VfxRouter.smoke_step(0.7, VfxRouter.SMOKE_HP01)).is_equal(1)
	assert_int(VfxRouter.smoke_step(0.4, VfxRouter.SMOKE_HP01)).is_equal(2)
	assert_int(VfxRouter.smoke_step(0.1, VfxRouter.SMOKE_HP01)).is_equal(3)


func test_drain_handles_a_list() -> void:
	var evs: Array[SimEvent] = [_ev(SimEvent.Kind.DEATH), _ev(SimEvent.Kind.ORDER_DONE), _ev(SimEvent.Kind.LANDING)]
	assert_int(_router.drain(evs, _view)).is_equal(2)


func test_pool_recycles_oldest_when_full() -> void:
	var small: VfxPool = auto_free(VfxPool.new())
	add_child(small)
	small.setup(3)
	for i: int in 5:
		assert_bool(small.spawn(&"vfx_hit_spark", Vector3(float(i), 0.0, Sphere.PLANET_RADIUS))).is_true()
	assert_int(small.active_count()).is_equal(3)
	assert_bool(small.spawn(&"vfx_nonexistent", Vector3.ZERO)).is_false()
	small.update(10.0)
	assert_int(small.active_count()).is_equal(0)


func test_prewarm_spawns_each_effect() -> void:
	var pool: VfxPool = auto_free(VfxPool.new())
	add_child(pool)
	pool.setup(VfxCatalog.ids().size())
	var ids: PackedStringArray = VfxPrewarm.load_list()
	assert_int(ids.size()).is_equal(VfxCatalog.ids().size())
	assert_int(VfxPrewarm.run(pool, ids, Vector3(0.0, 0.0, Sphere.PLANET_RADIUS))).is_equal(ids.size())
	for id: String in ids:
		assert_int(int(pool.counts.get(StringName(id), 0))).is_equal(1)
	assert_int(pool.active_count()).is_equal(ids.size())
	VfxPrewarm.finish(pool)
	assert_int(pool.active_count()).is_equal(0)


func test_prewarm_list_file_filters_unknown_ids() -> void:
	var path: String = "user://vfx_prewarm_test.json"
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string('{"effects": ["vfx_hit_spark", "vfx_nope"]}')
	f.close()
	var ids: PackedStringArray = VfxPrewarm.load_list(path)
	assert_array(ids).contains_exactly(["vfx_hit_spark"])
	assert_int(VfxPrewarm.load_list("user://missing_prewarm.json").size()).is_equal(VfxCatalog.ids().size())


func test_catalog_materials_load() -> void:
	for id: String in VfxCatalog.ids():
		assert_object(_pool.material_for(StringName(id))).is_not_null()
		assert_float(VfxCatalog.life_s(StringName(id))).is_greater(0.0)
