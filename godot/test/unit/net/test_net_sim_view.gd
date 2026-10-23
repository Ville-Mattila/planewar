extends GdUnitTestSuite
## NET-17 NetSimView / NetPose (04 s5.6, s3.7; R0 C2-12, B.11 A-56, B.19 A-103): sample(render_tick) interpolates
## between the frames around the render tick, dead-reckons past the newest frame for at most 3 ticks (gravity term for
## gravity defs and DYING entries), then freezes and sets `stale`; a known blip shows its stored bucket and is never
## extrapolated (KnownBlipFixture, the NET-56 fixture); float dr(t) agrees with shown_levels at integer ticks; the
## TEST-02 factory exempts exactly the clauses that fail, and the replicable part of each is asserted here; the
## EntityStore / Spatial mirrors and the NetDefs tables are pinned to the sim.

const G: float = 6.0
const DT: float = 1.0 / 30.0
const I: int = 7
const DEF: int = 2

var _roster: Roster
var _dec: SnapshotDecoder
var _view: NetSimView


func before_test() -> void:
	_roster = Roster.new()
	var _a: bool = _roster.add(I, 3, DEF, 1, 1)
	_dec = SnapshotDecoder.new(G, 30, 0, _roster)
	_view = NetSimView.new(_roster, _dec)
	var defs: NetDefs = NetDefs.new()
	defs.gravity = G
	_view.bind(defs, null)


func _id() -> int:
	return EntityId.make(I, 3)


func _p0() -> Vector3:
	return Sphere.from_lat_lon(0.4, 1.1, Sphere.PLANET_RADIUS + 800.0)


## A frame at `t` holding entity I as a FULL record at `p` with velocity `v` (ENU of p's cell) and orientation `q`.
func _full(t: int, base: int, p: Vector3, v: Vector3, q: Quaternion, flag_b: int = 0) -> BaselineFrame:
	var f: BaselineFrame = _dec.store.begin(t, base)
	var pq: int = Codec.quantize_pos(p)
	f.set_full(I, t, pq, Codec.quantize_quat(q), Codec.quantize_vel(v, Codec.pos_cell(pq)), 255, flag_b, -1)
	_dec.store.newest_tick = maxi(_dec.store.newest_tick, t)
	return f


func _copy(t: int, base: int) -> void:
	var _f: BaselineFrame = _dec.store.begin(t, base)
	_dec.store.newest_tick = maxi(_dec.store.newest_tick, t)


func _world(t: int) -> Vector3:
	var f: BaselineFrame = _dec.store.frame_at(t)
	return Codec.dequantize_pos(f.pos[I])


func test_interpolates_position_and_orientation_between_frames() -> void:
	var q0: Quaternion = Quaternion(Vector3.UP, 0.2)
	var q1: Quaternion = Quaternion(Vector3.UP, 0.4)
	var _a: BaselineFrame = _full(10, 0, _p0(), Vector3.ZERO, q0)
	var _b: BaselineFrame = _full(11, 10, _p0() + _p0().normalized().cross(Vector3.UP).normalized() * 4.0, Vector3.ZERO, q1)
	_view.sample(10.25)
	assert_bool(_view.stale).is_false()
	assert_float(_view.pos(_id()).distance_to(_world(10).lerp(_world(11), 0.25))).is_less(1e-3)
	var want: Quaternion = Codec.dequantize_quat(Codec.quantize_quat(q0)).slerp(Codec.dequantize_quat(Codec.quantize_quat(q1)), 0.25)
	assert_float(absf(_view.basis(_id()).get_rotation_quaternion().dot(want))).is_greater(1.0 - 1e-6)
	assert_int(_view.pose.tick_a).is_equal(10)
	assert_int(_view.pose.tick_b).is_equal(11)
	assert_bool(_view.unknown(_id())).is_true()                               # another team's entity


func test_a_lost_frame_interpolates_across_the_gap() -> void:
	var _a: BaselineFrame = _full(10, 0, _p0(), Vector3.ZERO, Quaternion.IDENTITY)
	var _b: BaselineFrame = _full(13, 10, _p0() + Vector3(0, 0, 9), Vector3.ZERO, Quaternion.IDENTITY)
	_view.sample(11.5)
	assert_int(_view.pose.tick_a).is_equal(10)
	assert_int(_view.pose.tick_b).is_equal(13)
	assert_float(_view.pos(_id()).distance_to(_world(10).lerp(_world(13), 0.5))).is_less(1e-3)


func test_extrapolation_stops_at_3_ticks_then_freezes_stale() -> void:
	var v: Vector3 = Vector3(60.0, -20.0, 4.0)                           # ENU m/s
	var _a: BaselineFrame = _full(20, 0, _p0(), v, Quaternion.IDENTITY)
	var p20: Vector3 = _world(20)
	var vw: Vector3 = NetPose.fine_to_world(DeadReckon.fine_from_bits(Codec.quantize_vel(v, Codec.pos_cell(Codec.quantize_pos(_p0())))),
			Codec.pos_cell(Codec.quantize_pos(_p0())))
	for ticks: float in [0.0, 1.5, 2.0, 3.0]:
		_view.sample(20.0 + ticks)
		assert_float(_view.pos(_id()).distance_to(p20 + vw * (ticks * DT))).is_less(1e-3)
		assert_bool(_view.stale).is_false()
	var at3: Vector3 = p20 + vw * (3.0 * DT)
	for r: float in [23.01, 24.0, 40.0]:
		_view.sample(r)
		assert_bool(_view.stale).is_true()
		assert_float(_view.pos(_id()).distance_to(at3)).is_less(1e-3)
		assert_vector(_view.vel(_id())).is_equal_approx(vw, Vector3.ONE * 1e-4)


func test_extrapolation_is_gravity_aware_for_dying_and_gravity_defs() -> void:
	var v: Vector3 = Vector3(10.0, 0.0, 30.0)
	for mode: int in 2:
		before_test()
		var flag_b: int = Codec.FLAG_DYING if mode == 0 else 0
		if mode == 1:
			_view.defs.gravity_def[DEF] = 1
			_view.bind(_view.defs, null)
		var _a: BaselineFrame = _full(20, 0, _p0(), v, Quaternion.IDENTITY, flag_b)
		var cell: int = Codec.pos_cell(Codec.quantize_pos(_p0()))
		var vw: Vector3 = NetPose.fine_to_world(DeadReckon.fine_from_bits(Codec.quantize_vel(v, cell)), cell)
		var p20: Vector3 = _world(20)
		_view.sample(23.0)
		var t: float = 3.0 * DT
		var want: Vector3 = p20 + vw * t - p20.normalized() * (0.5 * G * t * t)
		assert_float(_view.pos(_id()).distance_to(want)).override_failure_message("mode %d" % mode).is_less(1e-3)
		assert_float(_view.pos(_id()).distance_to(p20 + vw * t)).is_greater(0.01)


func test_float_dr_matches_shown_levels_at_integer_ticks() -> void:
	var v: Vector3 = Vector3(110.0, -30.0, -24.0)
	for mode: int in 2:
		before_test()
		var f: BaselineFrame = _full(10, 0, _p0(), v, Quaternion.IDENTITY, Codec.FLAG_DYING if mode == 1 else 0)
		var prev: int = 10
		for t: int in [12, 15, 20, 30]:
			_copy(t, prev)
			prev = t
			f = _dec.store.frame_at(t)
			_view.sample(float(t))
			var lv: Vector3i = f.shown_levels(I, t, false, G, DT)
			var want: Vector3 = Codec.dequantize_pos(Codec.pack_pos(Codec.pos_cell(f.pos[I]), lv.x, lv.y, lv.z))
			assert_float(_view.pos(_id()).distance_to(want)).is_less(Codec.POS_U_QUANTUM)


## R0 B.19 A-103 / NET-56 with the shared fixture of test_dying_blip_rests_300_ticks_at_blip_pos: a DYING known blip
## shows its bucket at every render tick, interpolated, at a frame, and past the newest frame (never extrapolated).
func test_dying_known_blip_rests_at_its_bucket_and_is_never_extrapolated() -> void:
	for grav: bool in [false, true]:
		_roster = Roster.new()
		var _a: bool = _roster.add(KnownBlipFixture.SLOT, 1, DEF, 1, 1)
		_dec = SnapshotDecoder.new(G, 30, 0, _roster)
		_view = NetSimView.new(_roster, _dec)
		var defs: NetDefs = NetDefs.new()
		defs.gravity = G
		defs.gravity_def[DEF] = 1 if grav else 0
		_view.bind(defs, null)
		var f10: BaselineFrame = _dec.store.begin(KnownBlipFixture.FULL_TICK, 0)
		KnownBlipFixture.apply(f10)
		var prev: int = KnownBlipFixture.FULL_TICK
		var id: int = EntityId.make(KnownBlipFixture.SLOT, 1)
		var bucket: Vector3 = Codec.dequantize_pos(f10.pos[KnownBlipFixture.SLOT])
		for dt_ticks: int in KnownBlipFixture.RESTS:
			var t: int = KnownBlipFixture.BLIP_TICK + dt_ticks
			_copy(t, prev)
			prev = t
			assert_that(_dec.store.frame_at(t).shown_levels(KnownBlipFixture.SLOT, t, grav, G, DT)).is_equal(KnownBlipFixture.bucket(f10))
			for r: float in [float(t) - 0.5, float(t), float(t) + 2.0, float(t) + 30.0]:
				_view.sample(r)
				assert_float(_view.pos(id).distance_to(bucket)).override_failure_message("t %d r %f" % [t, r]).is_less(1e-4)
				assert_vector(_view.vel(id)).is_equal(Vector3.ZERO)
				assert_bool(_view.basis(id) == Basis.IDENTITY).is_true()     # C tier: basis not received
				assert_bool(_view.unknown(id)).is_true()


func test_mirror_constants_equal_the_sim() -> void:
	assert_int(NetSimView.K_STRUCTURE).is_equal(EntityStore.K_STRUCTURE)
	assert_int(NetSimView.K_SHIP).is_equal(EntityStore.K_SHIP)
	assert_int(NetSimView.K_GROUND).is_equal(EntityStore.K_GROUND)
	assert_int(NetSimView.K_WRECK).is_equal(EntityStore.K_WRECK)
	assert_int(NetSimView.F_ALIVE).is_equal(EntityStore.F_ALIVE)
	assert_int(NetSimView.F_DOCKED).is_equal(EntityStore.F_DOCKED)
	assert_int(NetSimView.F_POSSESSABLE).is_equal(EntityStore.F_POSSESSABLE)
	assert_int(NetSimView.MASK_PROJECTILE).is_equal(Spatial.MASK_PROJECTILE)
	assert_int(1 << NetSimView.K_SHIP).is_equal(Spatial.MASK_SHIP)
	assert_int(1 << NetSimView.K_STRUCTURE).is_equal(Spatial.MASK_STRUCTURE)
	assert_int(1 << NetSimView.K_WRECK).is_equal(Spatial.MASK_WRECK)
	assert_int(NetSimView.NONE).is_equal(EntityStore.NONE_U8)
	assert_int(NetSimView.TEAMS).is_equal(PlayerTable.TEAMS)
	assert_int(NetSimView.SERVICE_DOCKED).is_equal(1)                       # R0 B.3 service state DOCKED
	for p: int in 3:
		assert_int(PilotBlock.boost_byte(p, 0.7) & NetSimView.BOOST_MASK).is_equal(p)


func test_net_defs_equal_world_defs() -> void:
	var content: ContentSet = WorldTestKit.content()
	var nd: NetDefs = NetDefs.new(content)
	var wd: WorldDefs = WorldDefs.new(content)
	assert_float(nd.gravity).is_equal(content.rules.gravity)
	assert_int(nd.tick_hz).is_equal(content.rules.tick_hz)
	var n: int = 0
	for d: int in DefRanges.PROJECTILE_BASE:
		if nd.kind[d] < 0:
			continue
		n += 1
		assert_float(nd.radius[d]).is_equal_approx(wd.radius_of(d), 1e-5)
		assert_bool(nd.possessable[d] != 0).is_equal(wd.possessable(d))
		assert_float(nd.hp[d]).is_equal(wd.hp_max(0, d))
		assert_bool(nd.pad[d] != 0).is_equal(d < wd.pad_radius_by_def.size() and wd.pad_radius_by_def[d] > 0.0)
	assert_int(n).is_equal(content.ships.size() + content.ground_units.size() + content.structures.size())
	for k: int in content.projectiles.size():
		assert_bool(nd.gravity_def[DefRanges.PROJECTILE_BASE + k] != 0).is_equal(content.projectiles[k].gravity)


func test_factory_exempts_exactly_the_failing_clauses() -> void:
	var scene: SimViewScene = SimViewScene.build()
	var f: NetSimViewFactory = NetSimViewFactory.new()
	var c: SimViewContract = SimViewContract.new()
	c.run(f.make(scene), scene)
	var failed: Array = Array(c.failed)
	var ex: Array = Array(f.exempt())
	failed.sort()
	ex.sort()
	assert_array(failed).is_equal(ex)


## The replicable part of each exempt clause, on the same scene and view as TEST-02.
func test_replicable_part_of_exempt_clauses() -> void:
	var s: SimViewScene = SimViewScene.build()
	var v: NetSimView = NetSimViewFactory.new().make(s) as NetSimView
	var st: EntityStore = s.world.store()
	for id: int in [s.a, s.b, s.c, s.core, s.pad, s.yard, s.tower]:
		assert_bool(v.alive(id)).is_true()
		assert_int(v.def_kind(id)).is_equal(st.kind[EntityId.slot(id)])
		assert_float(v.radius(id)).is_equal_approx(st.radius[EntityId.slot(id)], 1e-5)
	for id: int in [s.dead, 0, s.wreck, s.rocket]:
		assert_bool(v.alive(id)).is_false()
	assert_bool(s.world.view().visible_to(0, s.wreck)).is_false()            # why the wreck is not received
	assert_int(v.control_state(s.a)).is_equal(SimViewScene.CONTROL & Codec.FLAG_CONTROL_MASK)
	assert_float(v.flip_cooldown01(s.a)).is_equal_approx(SimViewScene.FLIP_CD01, 0.5 / 255.0)
	assert_float(v.shield01(s.core)).is_equal(-1.0)
	assert_float(v.wreck_ore(s.wreck)).is_equal(-1.0)
	var out: PackedInt32Array = PackedInt32Array([-7, -7])
	assert_int(v.visible_enemy_ships(0, out)).is_equal(1)
	assert_int(out[0]).is_equal(s.b)
	assert_int(v.visible_enemy_ships(1, out)).is_equal(0)
	var eco: EconomyDef = s.content.economy
	assert_float(v.stockpile(0).x).is_equal(float(eco.start_ore * 2))
	assert_float(v.stockpile(0).y).is_equal(float(eco.start_ice * 2))
	assert_vector(v.stockpile(0)).is_equal_approx(s.world.view().stockpile(0), Vector3.ONE * 1e-4)
	assert_int(v.unit_count(0)).is_equal(2)
	assert_int(v.team_flags(0) & TeamStateView.CORE_SHIELD_UP).is_equal(TeamStateView.CORE_SHIELD_UP)   # GD-38 via 0x85
	assert_int(v.team_flags(0)).is_equal(s.world.view().team_state(0).flags)
	assert_int(v.team_flags(1)).is_equal(0)
	# unknown: per field (NetUnknown); unknown(id) = any field, true for every entity while some accessor has no wire
	assert_bool(v.unknown(s.a)).is_true()
	for f: StringName in [&"fuel01", &"ammo", &"boost_state", &"basis", &"vel", &"ai_tag", &"radius", &"hp01", &"possessor"]:
		assert_bool(v.field_unknown(s.a, f)).override_failure_message("a %s" % f).is_false()   # own possessed unit
	for f: StringName in [&"overlay", &"cargo", &"cargo_kind", &"link", &"order_issuer", &"supply01", &"shield01", &"wreck_ore"]:
		assert_bool(v.field_unknown(s.a, f)).override_failure_message("a %s" % f).is_true()    # exempt as not received
	for f: StringName in [&"fuel01", &"flip_cooldown01", &"incoming_rockets", &"ai_tag"]:
		assert_bool(v.field_unknown(s.b, f)).override_failure_message("b %s" % f).is_true()    # other team, not possessed
	assert_bool(v.field_unknown(s.b, &"pos")).is_false()
	assert_bool(v.field_unknown(s.dead, &"pos")).is_true()
	assert_int(v.def_kind(s.dead)).is_equal(-1)
	assert_float(v.radius(s.dead)).is_equal(0.0)
	# ids_in_cell: the local cell list minus what team 0 does not receive (the rocket, CQ-1)
	s.world.spatial.rebuild()                                                 # the factory snapped positions after the scene's hash
	var cell: int = Spatial.cell_of(v.pos(s.a))
	var want: Array = []
	for id: int in s.world.view().ids_in_cell(cell):
		if v.alive(id):
			want.append(id)
	var got: Array = Array(v.ids_in_cell(cell))
	want.sort()
	got.sort()
	assert_array(got).is_equal(want)
	assert_bool(got.has(s.a) and not got.has(s.b) and not got.has(s.rocket)).is_true()
	assert_bool(v.ids_in_cell(Spatial.cell_of(v.pos(s.b))).has(s.b)).is_true()
	var ids: PackedInt32Array = PackedInt32Array([s.a, s.dead, s.rocket, s.b, s.wreck, 0, s.c])
	var p: PackedVector3Array = PackedVector3Array()
	var r: PackedVector4Array = PackedVector4Array()
	var _x: int = p.resize(ids.size())
	var _y: int = r.resize(ids.size())
	assert_int(v.read_poses(ids, p, r)).is_equal(3)                           # a, b, c: what team 0 receives
	for k: int in ids.size():
		var q: Quaternion = v.basis(ids[k]).get_rotation_quaternion()
		assert_vector(p[k]).is_equal(v.pos(ids[k]))
		assert_float(Vector4(q.x, q.y, q.z, q.w).distance_to(r[k])).is_less(1e-6)


## The wreck path the TEST-02 scene cannot reach (its wreck is invisible to team 0): the same scene with the wreck made
## visible to team 0, so the client receives it.
func test_a_received_wreck() -> void:
	var s: SimViewScene = SimViewScene.build()
	var st: EntityStore = s.world.store()
	var sw: int = EntityId.slot(s.wreck)
	st.visible_mask[sw] |= 1
	var v: NetSimView = NetSimViewFactory.new().make(s) as NetSimView
	assert_bool(v.alive(s.wreck)).is_true()
	assert_int(v.def_kind(s.wreck)).is_equal(EntityStore.K_WRECK)
	assert_int(v.def_kind(s.wreck)).is_equal(s.world.view().def_kind(s.wreck))
	assert_array(Array(v.wrecks())).is_equal([s.wreck])
	assert_bool(Array(v.ships()).has(s.wreck)).is_false()
	assert_int(v.def_id(s.wreck)).is_equal(st.def_id[sw])                     # the hull's def (a Dart), kind by slot
	assert_int(v.flags(s.wreck)).is_equal(NetSimView.F_ALIVE)                 # a Dart def is possessable, its wreck is not
	assert_int(st.flags[sw] & EntityStore.F_POSSESSABLE).is_equal(0)
	assert_vector(v.pos(s.wreck)).is_equal(st.pos[sw])
	assert_int(v.owner(s.wreck)).is_equal(-1)
	assert_int(v.team(s.wreck)).is_equal(-1)
	assert_bool(v.visible_to(0, s.wreck)).is_true()
	# R0 B.22 A-114: a split wreck's radius is hull / n in the sim; n is not on the wire: the def radius + unknown
	assert_float(v.radius(s.wreck)).is_equal(s.ship_def().bounding_radius)
	assert_bool(v.field_unknown(s.wreck, &"radius")).is_true()
	assert_float(st.radius[sw]).is_equal(5.0)
	var ids: PackedInt32Array = PackedInt32Array([s.a, s.wreck, s.dead, s.b])
	var p: PackedVector3Array = PackedVector3Array()
	var r: PackedVector4Array = PackedVector4Array()
	var _x: int = p.resize(ids.size())
	var _y: int = r.resize(ids.size())
	assert_int(v.read_poses(ids, p, r)).is_equal(3)
	assert_vector(p[1]).is_equal(st.pos[sw])
	var q: Quaternion = v.basis(s.wreck).get_rotation_quaternion()
	assert_float(Vector4(q.x, q.y, q.z, q.w).distance_to(r[1])).is_less(1e-6)
	assert_bool(v.basis(s.wreck).is_equal_approx(s.world.view().basis(s.wreck))).is_true()


func test_net_defs_kind_of_wreck_slots() -> void:
	var nd: NetDefs = NetDefs.new(WorldTestKit.content())
	var dart: int = WorldTestKit.def_id(&"dart")
	assert_int(nd.kind_of(dart, 5)).is_equal(NetSimView.K_SHIP)
	assert_int(nd.kind_of(dart, EntityId.WRECK_SLOT_MIN)).is_equal(NetSimView.K_WRECK)
	assert_int(nd.kind_of(dart, EntityId.WRECK_SLOT_END - 1)).is_equal(NetSimView.K_WRECK)
	assert_int(nd.kind_of(dart, EntityId.WRECK_SLOT_MIN - 1)).is_equal(NetSimView.K_SHIP)
	assert_int(nd.kind_of(-1, 3)).is_equal(-1)


func test_snap_world_reaches_a_fixed_point() -> void:
	var s: SimViewScene = SimViewScene.build()
	var rig: NetViewRig = NetViewRig.new(s.world, s.content)
	assert_bool(rig.snap_world()).is_true()
	var st: EntityStore = s.world.store()
	var pos: PackedVector3Array = st.pos.duplicate()
	var fwd: PackedVector3Array = st.fwd.duplicate()
	var up: PackedVector3Array = st.up.duplicate()
	assert_bool(rig.snap_world()).is_true()
	assert_bool(st.pos == pos and st.fwd == fwd and st.up == up).is_true()   # a second snap moves nothing
