extends GdUnitTestSuite
## BUG-4 (sim/world W10; R0 B.6, 02 s8.1 "1 Harvester already mining Field A"): `spawn_start_kit` puts the start Harvester
## inside Home Field A (the field at `toward`), just inside its edge on the Refinery side, facing the Refinery, with a MINING
## claim, so it mines from tick 0 with no autopilot. Without a field at `toward` (the flat datum) it waits empty beside the
## Refinery as before. Scenario layer: the cradle cases run a cradle SimWorld.

const R: float = Sphere.PLANET_RADIUS
const HZ: int = 30
const SLOT0: Vector3 = Vector3(0.923879533, 0.382683432, 0.0)
const FIELD_A: Vector3 = Vector3(0.838630392, 0.544700895, 0.0)   # home_field_a_s0 of cradle's features.json


func _cradle() -> SimWorld:
	var w: SimWorld = SimWorld.new(WorldTestKit.content())
	var map: MapDef = MapDef.new()
	map.id = &"cradle"
	var res: Result = w.load_map(map, 7, WorldTestKit.rules())
	assert(res.ok, res.message)
	w.add_player(0, 0, &"", PlayerTable.KIND_HUMAN)
	w.add_player(2, 1, &"", PlayerTable.KIND_HUMAN)
	assert(w.spawn_start_kit(0, SLOT0, FIELD_A))
	return w


static func _harvester(w: SimWorld) -> int:
	var d: int = WorldTestKit.def_id(&"harvester")
	for s: int in w.store().ground:
		if w.store().def_id[s] == d and w.store().owner[s] == 0:
			return s
	return -1


static func _hdef() -> GroundUnitDef:
	for g: GroundUnitDef in WorldTestKit.content().ground_units:
		if g.id == &"harvester":
			return g
	return null


static func _arc(a: Vector3, b: Vector3) -> float:
	return acos(clampf(a.normalized().dot(b.normalized()), -1.0, 1.0)) * R


func test_the_start_harvester_is_already_mining_home_field_a() -> void:
	var w: SimWorld = _cradle()
	var st: EntityStore = w.store()
	var fields: OreFields = w.economy().harvest.fields
	var f: int = fields.field_at(FIELD_A)
	assert_int(f).is_greater_equal(0)
	var h: int = _harvester(w)
	var ref: int = EconomyTestKit.find(w, &"refinery")
	assert_int(Harvest.state_of(st.link[h])).is_equal(Harvest.State.MINING)
	assert_int(Harvest.index_of(st.link[h])).is_equal(f)
	assert_bool(st.vel[h].is_zero_approx()).is_true()
	assert_float(st.cargo[h]).is_equal(0.0)
	var from_centre: float = _arc(st.pos[h], fields.dirs[f])
	assert_float(from_centre).is_equal_approx(fields.radius_m[f] - _hdef().bounding_radius, 0.5)   # just inside the edge
	assert_float(_arc(st.pos[h], st.pos[ref])).is_equal_approx(_arc(fields.dirs[f], st.pos[ref]) - from_centre, 0.5)   # Refinery side
	var n: Vector3 = st.pos[h].normalized()
	var to_ref: Vector3 = (st.pos[ref] - st.pos[h])
	to_ref = (to_ref - n * to_ref.dot(n)).normalized()
	assert_float(st.fwd[h].dot(to_ref)).is_greater(0.999)                                  # faces the Refinery


func test_the_start_harvester_mines_a_full_load_in_cargo_over_mine_rate_seconds() -> void:
	var w: SimWorld = _cradle()
	var h: int = _harvester(w)
	var hd: GroundUnitDef = _hdef()
	var full_ticks: int = ceili(float(hd.cargo_ore) / hd.mine_rate * float(HZ))
	var _e: Array[SimEvent] = EconomyTestKit.run(w, full_ticks - 1)
	assert_float(w.store().cargo[h]).is_less(float(hd.cargo_ore))
	assert_int(Harvest.state_of(w.store().link[h])).is_equal(Harvest.State.MINING)
	var _e2: Array[SimEvent] = EconomyTestKit.run(w, 1)
	assert_float(w.store().cargo[h]).is_equal_approx(float(hd.cargo_ore), 0.001)
	assert_int(Harvest.state_of(w.store().link[h])).is_equal(Harvest.State.TRAVEL)        # full: the claim ends (H4)
	assert_bool(w.store().vel[h].is_zero_approx()).is_true()                                # no autopilot: it never moved


func test_without_a_field_at_toward_the_start_harvester_waits_empty_beside_the_refinery() -> void:
	var w: SimWorld = EconomyTestKit.solo_world()   # flat datum, no Ore Fields
	var h: int = _harvester(w)
	var ref: int = EconomyTestKit.find(w, &"refinery")
	var eco: EconomyDef = WorldTestKit.content().economy
	assert_int(w.store().link[h]).is_equal(0)
	assert_float(_arc(w.store().pos[h], w.store().pos[ref])).is_equal_approx(eco.start_adjacent_dist_m, 5.0)   # the Refinery snaps to its cell
	var _e: Array[SimEvent] = EconomyTestKit.run(w, 2 * HZ)
	assert_float(w.store().cargo[h]).is_equal(0.0)


func test_save_restore_while_the_start_harvester_mines_is_byte_equal() -> void:
	var w: SimWorld = _cradle()
	var _e: Array[SimEvent] = EconomyTestKit.run(w, 5 * HZ)
	var a: PackedByteArray = w.serialize()
	var r: SimWorld = SimWorld.deserialize(a, WorldTestKit.content(), null)
	assert_object(r).is_not_null()
	assert_bool(r.serialize() == a).is_true()
	var _e2: Array[SimEvent] = EconomyTestKit.run(w, 20 * HZ)
	var _e3: Array[SimEvent] = EconomyTestKit.run(r, 20 * HZ)
	assert_bool(r.serialize() == w.serialize()).is_true()
	assert_float(r.store().cargo[_harvester(r)]).is_greater(0.0)
