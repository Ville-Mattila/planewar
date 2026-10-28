extends GdUnitTestSuite
## NET-58 (R0 B.22 A-112): NetSimView resolves projectile ids through the roster block. On the TEST-02 scene served by
## NetViewRig (team-1 rocket aimed at team 0's `a`, in team 0's V through its target), the TEST-02 rocket clauses hold
## on the replicated view (alive, ids_in_cell, projectiles_near, read_poses); def_id / owner / team come from the
## rocket's ENTITY_META (ProjectileDef id, the shooter's owner / team), radius from the def, def_kind -1 as on
## LocalSimView; every other accessor answers a projectile id with its SimView default, as LocalSimView does.

var _s: SimViewScene
var _v: NetSimView


func before_test() -> void:
	_s = SimViewScene.build()
	_v = NetSimViewFactory.new().make(_s) as NetSimView


func test_rocket_clauses_hold_on_the_replicated_view() -> void:
	var local: SimView = _s.world.view()
	var r: int = _s.rocket
	assert_bool(_v.alive(r)).is_true()
	assert_vector(_v.pos(r)).is_equal(local.pos(r))
	assert_vector(_v.vel(r)).is_equal_approx(local.vel(r), Vector3.ONE * 1e-4)
	var cell: int = Spatial.cell_of(_v.pos(_s.a))
	var got: Array = Array(_v.ids_in_cell(cell))
	got.sort()
	var want: Array = [_s.a, r]
	want.sort()
	assert_array(got).is_equal(want)
	assert_array(Array(_v.projectiles_near(_v.pos(r), 30.0, 1 << 1))).is_equal([r])
	assert_bool(_v.projectiles_near(_v.pos(r), 30.0, 1 << 0).is_empty()).is_true()
	assert_bool(_v.projectiles_near(_v.pos(r), -1.0, 0xFF).is_empty()).is_true()
	assert_array(Array(_v.ids_near(_v.pos(r), 5.0, Spatial.MASK_PROJECTILE))).is_equal(Array(local.ids_near(local.pos(r), 5.0, Spatial.MASK_PROJECTILE)))
	assert_bool(Array(_v.ids_near(_v.pos(r), 5.0, Spatial.MASK_SHIP)).has(r)).is_false()
	var ids: PackedInt32Array = PackedInt32Array([_s.a, _s.dead, r, _s.b, _s.wreck, 0, _s.c, EntityId.make(EntityId.slot(r), 9)])
	var p: PackedVector3Array = PackedVector3Array()
	var q: PackedVector4Array = PackedVector4Array()
	var _x: int = p.resize(ids.size())
	var _y: int = q.resize(ids.size())
	assert_int(_v.read_poses(ids, p, q)).is_equal(4)        # a, rocket, b, c (the wreck is not in team 0's V)
	assert_vector(p[2]).is_equal(local.pos(r))
	assert_vector(p[7]).is_equal(Vector3.ZERO)              # a stale generation of the rocket's slot
	var rq: Quaternion = _v.basis(r).get_rotation_quaternion()
	assert_float(Vector4(rq.x, rq.y, rq.z, rq.w).distance_to(q[2])).is_less(1e-6)
	assert_bool(_v.basis(r).is_equal_approx(local.basis(r))).is_true()   # identity on both


func test_rocket_meta_and_defaults() -> void:
	var local: SimView = _s.world.view()
	var r: int = _s.rocket
	var ps: ProjectileStore = _s.world.projectiles()
	var i: int = ps.index_of(r)
	assert_int(_v.def_id(r)).is_equal(DefRanges.PROJECTILE_BASE + ps.projectile_def[i])
	assert_int(_v.def_id(r)).is_equal(int(_s.content.projectile_index[&"rocket"]))
	assert_int(_v.team(r)).is_equal(ps.team[i])
	assert_int(_v.team(r)).is_equal(1)
	assert_int(_v.owner(r)).is_equal(-1)                     # the scene's rocket has no owning player (NONE_U8)
	assert_float(_v.radius(r)).is_equal_approx(_s.content.projectiles[ps.projectile_def[i]].radius_m, 1e-6)
	assert_int(_v.def_kind(r)).is_equal(-1)                  # R0 B.25 A-133: no EntityStore.K_* for a projectile
	assert_int(_v.def_kind(r)).is_equal(local.def_kind(r))
	assert_int(_v.flags(r)).is_equal(local.flags(r))
	assert_float(_v.hp01(r)).is_equal(local.hp01(r))
	assert_int(_v.possessor(r)).is_equal(local.possessor(r))
	assert_int(_v.control_state(r)).is_equal(local.control_state(r))
	assert_bool(_v.visible_to(0, r)).is_equal(local.visible_to(0, r))
	assert_bool(_v.visible_to(1, r)).is_equal(local.visible_to(1, r))
	assert_bool(Array(_v.visible_ids(0)).has(r)).is_false()
	assert_bool(Array(_v.ships()).has(r) or Array(_v.structures()).has(r) or Array(_v.wrecks()).has(r)).is_false()
	assert_int(_v.index_of(r)).is_equal(-1)                  # unit / structure / wreck index only
	assert_int(_v.entry_of(r)).is_equal(Roster.index_of_slot(EntityId.slot(r)))
	assert_int(_v.id_at(_v.entry_of(r))).is_equal(r)
	assert_bool(_v.alive(EntityId.make(EntityId.slot(r), EntityId.gen(r) + 1))).is_false()
	assert_bool(_v.alive(EntityId.make(EntityId.PROJECTILE_SLOT_END, 1))).is_false()
	assert_bool(_v.alive(EntityId.make(2000, 1))).is_false()                 # a slot in the gap is no index
	assert_int(_v.def_id(EntityId.make(2000, 1))).is_equal(-1)


## ROSTER_REMOVE of the rocket's slot (DEATH) takes it out of every accessor and list at once (no ghost).
func test_removed_rocket_is_gone_from_the_view() -> void:
	var r: int = _s.rocket
	var s: int = Roster.index_of_slot(EntityId.slot(r))
	var out: Array[PackedByteArray] = []
	var _n: int = RosterCodec.encode_remove(PackedInt32Array([s]), PackedInt32Array([Protocol.RosterRemoveReason.DEATH]), out)
	assert_int(out[0].decode_u16(2)).is_equal(EntityId.slot(r))
	assert_int(RosterCodec.decode_remove(out[0], _v.roster, PackedInt32Array())).is_equal(1)
	assert_bool(_v.alive(r)).is_false()
	assert_vector(_v.pos(r)).is_equal(Vector3.ZERO)
	assert_bool(_v.projectiles_near(Vector3.ZERO, 1e9, 0xFF).is_empty()).is_true()
	assert_bool(Array(_v.ids_in_cell(Spatial.cell_of(_v.pos(_s.a)))).has(r)).is_false()
