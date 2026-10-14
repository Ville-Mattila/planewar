extends GdUnitTestSuite
## LocalSimView (TA-18; 03 s15.4): every accessor answers from the world's arrays (or the SimView default where its
## system has not landed); reused views and specs (S3).


func test_entity_accessors() -> void:
	var w: SimWorld = WorldTestKit.world()
	var id: int = WorldTestKit.spawn(w, &"dart", 1, 1, WorldTestKit.at(500.0), Vector3(0, 40, 0))
	var v: SimView = w.view()
	var s: int = EntityId.slot(id)
	var dart: ShipDef = WorldTestKit.content().ships[WorldTestKit.def_id(&"dart")]
	assert_bool(v.alive(id)).is_true()
	assert_bool(v.alive(EntityId.make(s, 99))).is_false()
	assert_vector(v.pos(id)).is_equal(w.store().pos[s])
	assert_vector(v.vel(id)).is_equal(w.store().vel[s])
	var b: Basis = v.basis(id)
	assert_vector(-b.z).is_equal(w.store().fwd[s])
	assert_vector(b.y).is_equal(w.store().up[s])
	assert_int(v.def_id(id)).is_equal(WorldTestKit.def_id(&"dart"))
	assert_int(v.owner(id)).is_equal(1)
	assert_int(v.team(id)).is_equal(1)
	assert_float(v.hp01(id)).is_equal(1.0)
	assert_float(v.fuel01(id)).is_less_equal(1.0)
	assert_float(v.fuel01(id)).is_greater(0.9)
	assert_int(v.ammo(id)).is_equal(dart.primary_ammo)
	assert_int(v.possessor(id)).is_equal(-1)
	assert_int(v.def_kind(id)).is_equal(EntityStore.K_SHIP)
	assert_float(v.radius(id)).is_equal(dart.bounding_radius)
	assert_int(v.boost_state(id)).is_equal(0)
	assert_float(v.flip_cooldown01(id)).is_equal(0.0)
	assert_int(v.dock_state(id)).is_equal(0)
	assert_int(v.service_state(id)).is_equal(0)
	assert_array(Array(v.ships())).contains([id])
	assert_array(Array(v.ids_near(v.pos(id), 50.0, Spatial.MASK_SHIP))).contains([id])
	assert_array(Array(v.ids_in_cell(Spatial.cell_of(v.pos(id))))).contains([id])
	assert_bool(v.visible_to(1, id)).is_true()
	assert_bool(v.visible_to(0, id)).is_false()                # Vision (TA-37) not landed: mask 0
	assert_array(Array(v.visible_ids(1))).contains([id])
	assert_int(v.unit_count(1)).is_equal(1)
	assert_float(v.terrain_height(Vector3.RIGHT)).is_equal(0.0)   # flat datum
	assert_int(v.landing_grade_last(id)).is_equal(-1)
	assert_object(v.order_head(id)).is_null()
	assert_object(v.pending_order(id)).is_null()


func test_team_and_player_views() -> void:
	var w: SimWorld = WorldTestKit.world()
	var core: int = WorldTestKit.spawn(w, &"core", 0, 0, WorldTestKit.at(0.0, 300.0))
	var v: SimView = w.view()
	var eco: EconomyDef = WorldTestKit.content().economy
	var ts: TeamStateView = v.team_state(0)
	assert_int(ts.ore).is_equal(eco.start_ore * 2)          # C2-14: per player, summed into the pool (players 0 and 2)
	assert_int(ts.ice).is_equal(eco.start_ice * 2)
	assert_array(Array(ts.members)).is_equal([0, 2])
	var core_def: StructureDef = WorldTestKit.content().structures[WorldTestKit.def_id(&"core") - DefRanges.STRUCTURE_BASE]
	assert_int(ts.ore_cap).is_equal(core_def.storage_ore)
	assert_vector(v.stockpile(0)).is_equal(Vector3(float(eco.start_ore * 2), float(eco.start_ice * 2), 1.0))
	assert_object(v.team_state(0)).is_same(ts)
	var ps: PlayerStateView = v.player_state(1)
	assert_int(ps.team).is_equal(1)
	assert_str(String(ps.doctrine)).is_equal("vanguard")
	assert_bool(ps.connected).is_true()
	assert_int(v.player_state(2).kind).is_equal(PlayerTable.KIND_BOT)
	assert_int(v.player_state(0).structure_count).is_equal(1)
	assert_object(v.player_state(9)).is_null()
	assert_bool(v.tech_available(0, WorldTestKit.def_id(&"solar_array"))).is_true()   # requires core
	assert_bool(v.tech_available(0, WorldTestKit.def_id(&"outpost"))).is_false()      # requires shipyard
	assert_bool(v.tech_available(1, WorldTestKit.def_id(&"solar_array"))).is_false()
	assert_array(Array(v.structures())).contains([core])


func test_pads_and_projectiles() -> void:
	var w: SimWorld = WorldTestKit.world()
	var pad: int = WorldTestKit.spawn(w, &"pad", 0, 0, WorldTestKit.at(0.0, 200.0))
	var far_pad: int = WorldTestKit.spawn(w, &"pad", 0, 0, WorldTestKit.at(0.0, 2000.0))
	var ship: int = WorldTestKit.spawn(w, &"dart", 0, 0, WorldTestKit.at(300.0, 150.0))
	var v: SimView = w.view()
	assert_int(v.nearest_friendly_pad(ship)).is_equal(pad)
	assert_int(far_pad).is_not_equal(0)
	assert_int(v.pad_occupant(pad)).is_equal(0)
	var s: int = EntityId.slot(ship)
	w.store().flags[s] |= EntityStore.F_DOCKED
	w.store().link[s] = pad
	assert_int(v.pad_occupant(pad)).is_equal(ship)
	assert_int(v.dock_state(ship)).is_equal(2)
	assert_int(v.service_state(ship)).is_equal(1)
	var rk: int = WorldTestKit.projectile(w, &"rocket", WorldTestKit.at(300.0, 0.0), Vector3(0, 10, 0), 1, 5.0)
	var ps: ProjectileStore = w.projectiles()
	ps.kind[ps.index_of(rk)] = ProjectileStore.ROCKET
	ps.target[ps.index_of(rk)] = ship
	assert_int(v.incoming_rockets(ship)).is_equal(1)
	w.step()
	assert_array(Array(v.projectiles_near(v.pos(rk), 30.0, 1 << 1))).contains([rk])
	assert_int(v.projectiles_near(v.pos(rk), 30.0, 1 << 0).size()).is_equal(0)
	assert_bool(v.alive(rk)).is_true()
	assert_vector(v.pos(rk)).is_equal(ps.pos[ps.index_of(rk)])


func test_match_accessors() -> void:
	var w: SimWorld = WorldTestKit.world(7, WorldTestKit.rules(1.0, 2.0))
	var v: SimView = w.view()
	assert_int(v.match_phase()).is_equal(MatchRules.Phase.PLAYING)
	assert_int(v.match_arc()).is_equal(MatchArc.Arc.OPEN)
	for _i: int in 31:
		w.step()
	assert_int(v.match_phase()).is_equal(MatchRules.Phase.EXPOSURE)
	assert_int(v.match_arc()).is_equal(MatchArc.Arc.OVERTIME)
	assert_float(v.match_clock_s()).is_equal_approx(31.0 / 30.0, 1e-9)
	assert_int(v.team_state(0).flags & TeamStateView.CORE_EXPOSURE).is_not_equal(0)


func test_defaults_until_their_systems_land() -> void:
	var w: SimWorld = WorldTestKit.world()
	var id: int = WorldTestKit.spawn(w, &"shipyard", 0, 0, WorldTestKit.at(0.0, 300.0))
	var v: SimView = w.view()
	assert_int(v.production_queue(id).size()).is_equal(0)
	assert_float(v.production_progress01(id)).is_equal(0.0)
	assert_int(v.pad_queue(id).size()).is_equal(0)
	assert_vector(v.service_progress(id)).is_equal(Vector3.ZERO)
	assert_int(v.field_remaining(0)).is_equal(0)
	assert_int(v.path_grid_version(0)).is_equal(0)
	assert_vector(v.player_score(0)).is_equal(Vector2i.ZERO)
	assert_int(v.auto_replenish_target(0, 0)).is_equal(0)
	assert_float(v.supply01(id)).is_equal(0.0)
	assert_int(v.cargo_kind(id)).is_equal(0)
	assert_float(v.cargo(id)).is_equal(0.0)
	assert_int(v.link(id)).is_equal(0)
	assert_int(v.rockets(id)).is_equal(0)
	assert_int(v.bombs(id)).is_equal(0)
	assert_int(v.ai_tag(id)).is_equal(0)
	assert_int(v.flags(id) & EntityStore.F_POSSESSABLE).is_not_equal(0)
	assert_int(v.control_state(id)).is_equal(0)
	assert_vector(v.stockpile_cap(0)).is_equal(Vector2i.ZERO)
	assert_vector(v.power_balance(0)).is_equal(Vector2(0.0, 10.0))
	assert_int(v.wrecks().size()).is_equal(0)


func test_read_poses_matches_pos_and_basis() -> void:
	var w: SimWorld = WorldTestKit.world()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 51
	var pool: PackedInt32Array = PackedInt32Array()
	for k: int in 40:
		var id: int = WorldTestKit.spawn(w, &"dart", 1, 1, WorldTestKit.at(300.0 + float(k), float(k) * 20.0))
		var s: int = EntityId.slot(id)
		var up: Vector3 = Vector3(rng.randf_range(-1.0, 1.0), 1.0, rng.randf_range(-1.0, 1.0)).normalized()
		var fwd: Vector3 = up.cross(Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), 1.0)).normalized()
		w.store().up[s] = up
		w.store().fwd[s] = fwd
		var _a: bool = pool.push_back(id)
		var _b: bool = pool.push_back(EntityId.make(s, 99))   # stale generation: dead
		if k % 4 == 0:
			var _c: bool = pool.push_back(WorldTestKit.projectile(w, &"rocket", WorldTestKit.at(250.0, float(k)), Vector3(0, 5, 0), 1, 5.0))
	var _d: bool = pool.push_back(EntityId.make(1500, 1))     # never spawned
	var v: SimView = w.view()
	var ids: PackedInt32Array = PackedInt32Array()
	var _r: int = ids.resize(1000)
	var alive_expected: int = 0
	for i: int in 1000:
		ids[i] = pool[rng.randi_range(0, pool.size() - 1)]
		alive_expected += 1 if v.alive(ids[i]) else 0
	var pos: PackedVector3Array = PackedVector3Array()
	var rot: PackedVector4Array = PackedVector4Array()
	var _p: int = pos.resize(1000)
	var _q: int = rot.resize(1000)
	var n: int = v.read_poses(ids, pos, rot)
	assert_int(n).is_equal(alive_expected)
	assert_int(pos.size()).is_equal(1000)
	assert_int(rot.size()).is_equal(1000)
	assert_int(alive_expected).is_greater(0)
	assert_int(alive_expected).is_less(1000)
	for i: int in 1000:
		var q: Quaternion = v.basis(ids[i]).get_rotation_quaternion()
		assert_vector(pos[i]).is_equal(v.pos(ids[i]))
		assert_float(rot[i].x).is_equal(q.x)
		assert_float(rot[i].y).is_equal(q.y)
		assert_float(rot[i].z).is_equal(q.z)
		assert_float(rot[i].w).is_equal(q.w)


func test_read_poses_dead_id_is_zero_and_identity_and_base_default() -> void:
	var w: SimWorld = WorldTestKit.world()
	var ids: PackedInt32Array = PackedInt32Array([EntityId.make(5, 3)])
	var pos: PackedVector3Array = PackedVector3Array([Vector3.ONE])
	var rot: PackedVector4Array = PackedVector4Array([Vector4.ONE])
	assert_int(w.view().read_poses(ids, pos, rot)).is_equal(0)
	assert_vector(pos[0]).is_equal(Vector3.ZERO)
	assert_bool(rot[0] == Vector4(0.0, 0.0, 0.0, 1.0)).is_true()
	pos[0] = Vector3.ONE
	rot[0] = Vector4.ONE
	assert_int(SimView.new().read_poses(ids, pos, rot)).is_equal(0)
	assert_vector(pos[0]).is_equal(Vector3.ZERO)
	assert_bool(rot[0] == Vector4(0.0, 0.0, 0.0, 1.0)).is_true()
