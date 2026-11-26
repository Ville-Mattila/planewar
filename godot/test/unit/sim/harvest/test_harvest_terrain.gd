extends GdUnitTestSuite
## BUG-3 on cradle's real terrain (sim/build B10, sim/harvest H-reach): the start kit of slot 0 stands on the ground, so
## its Harvester, which `GroundMotion` keeps on the ground, reaches the Refinery (`Harvest._refinery_near`, 3-D
## `radius + salvage_deliver_m`), mines a home field and delivers. The unit is moved by teleport here (no autopilot: the
## sim's reach rules only); the driven cycle is `test/sim/ai/test_bug3_cradle_cycle.gd`. A save/restore of the
## world on terrain is byte-equal.

const R: float = Sphere.PLANET_RADIUS
const HZ: int = 30
const SLOT0: Vector3 = Vector3(0.923879533, 0.382683432, 0.0)
const FIELD_A: Vector3 = Vector3(0.838630392, 0.544700895, 0.0)   # home_field_a_s0 of cradle's features.json

var _w: SimWorld


func before_test() -> void:
	_w = SimWorld.new(WorldTestKit.content())
	var map: MapDef = MapDef.new()
	map.id = &"cradle"
	var res: Result = _w.load_map(map, 7, WorldTestKit.rules())
	assert(res.ok, res.message)
	_w.add_player(0, 0, &"", PlayerTable.KIND_HUMAN)
	_w.add_player(2, 1, &"", PlayerTable.KIND_HUMAN)
	assert(_w.spawn_start_kit(0, SLOT0, FIELD_A))


func _harvester() -> int:
	var d: int = WorldTestKit.def_id(&"harvester")
	for s: int in _w.store().ground:
		if _w.store().def_id[s] == d and _w.store().owner[s] == 0:
			return s
	return -1


# Puts ground unit `s` at rest on the ground `metres` from `dir` toward `toward`.
func _put(s: int, dir: Vector3, toward: Vector3, metres: float) -> void:
	var n: Vector3 = dir.normalized()
	var t: Vector3 = (toward - n * toward.dot(n)).normalized()
	var a: float = metres / R
	var d: Vector3 = (n * cos(a) + t * sin(a)).normalized()
	var st: EntityStore = _w.store()
	st.pos[s] = d * (R + _w.terrain().height_at(d) + _w.store().radius[s])
	st.vel[s] = Vector3.ZERO


func test_start_kit_stands_on_the_ground() -> void:
	var st: EntityStore = _w.store()
	assert_int(st.structures.size()).is_greater_equal(4)
	for s: int in st.structures:
		if st.owner[s] != 0:
			continue
		var h: float = _w.terrain().height_at(st.pos[s])
		assert_float(h).is_less(-300.0)   # cradle slot 0 is far below the datum
		assert_float(st.pos[s].length()).override_failure_message("def %d at %.1f m, ground %.1f m" % [st.def_id[s], st.pos[s].length() - R, h]) \
				.is_equal_approx(R + h, 0.01)
	var hv: int = _harvester()
	assert_int(hv).is_greater_equal(0)
	assert_float(st.pos[hv].length() - R - _w.terrain().height_at(st.pos[hv])).is_less(st.radius[hv] + 0.01)


func test_a_loaded_harvester_beside_the_refinery_docks_and_delivers() -> void:
	var st: EntityStore = _w.store()
	var ref: int = EconomyTestKit.find(_w, &"refinery")
	var hv: int = _harvester()
	_put(hv, st.pos[ref], SLOT0, st.radius[ref] + 10.0)
	st.cargo[hv] = 100.0
	st.cargo_kind[hv] = 1
	var before: int = _w.economy().build.delivered_ore[0]
	_w.step()
	assert_int(Harvest.state_of(st.link[hv])).override_failure_message("%.1f m from the Refinery" % st.pos[hv].distance_to(st.pos[ref])) \
			.is_not_equal(Harvest.State.TRAVEL)
	var _e: Array[SimEvent] = EconomyTestKit.run(_w, 30 * HZ)
	assert_float(st.cargo[hv]).is_equal(0.0)
	assert_int(_w.economy().build.delivered_ore[0] - before).is_greater_equal(100)   # + the Core trickle


func test_mine_then_deliver_cycle_on_cradle() -> void:
	var st: EntityStore = _w.store()
	var ref: int = EconomyTestKit.find(_w, &"refinery")
	var hv: int = _harvester()
	var hd: GroundUnitDef = null
	for g: GroundUnitDef in WorldTestKit.content().ground_units:
		hd = g if g.id == &"harvester" else hd
	_put(hv, FIELD_A, SLOT0, 0.0)
	var mined: bool = false
	for _k: int in 120 * HZ:
		_w.step()
		if st.cargo[hv] >= float(hd.cargo_ore):
			mined = true
			break
	assert_bool(mined).override_failure_message("cargo %.1f" % st.cargo[hv]).is_true()
	var before: int = _w.economy().build.delivered_ore[0]
	_put(hv, st.pos[ref], FIELD_A, st.radius[ref] + 10.0)
	var _e: Array[SimEvent] = EconomyTestKit.run(_w, 60 * HZ)
	assert_float(st.cargo[hv]).is_equal(0.0)
	assert_int(_w.economy().build.delivered_ore[0] - before).is_greater_equal(hd.cargo_ore)   # + the Core trickle


func test_save_restore_on_terrain_is_byte_equal() -> void:
	var _e: Array[SimEvent] = EconomyTestKit.run(_w, 10)
	var a: PackedByteArray = _w.serialize()
	var r: SimWorld = SimWorld.deserialize(a, WorldTestKit.content(), null)
	assert_object(r).is_not_null()
	assert_bool(r.serialize() == a).is_true()
	var _e2: Array[SimEvent] = EconomyTestKit.run(_w, 30)
	var _e3: Array[SimEvent] = EconomyTestKit.run(r, 30)
	assert_bool(r.serialize() == _w.serialize()).is_true()
