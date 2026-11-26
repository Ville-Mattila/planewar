extends GdUnitTestSuite
## BUG-3 (sim/build B10): on a real map a structure stands on the terrain at its footprint centre (03 s7.6:
## `surface_point(anchor_dir)` sampled at the footprint centre, `up` radial = the flatten plane), not at the datum
## radius, and the 3-D checks of `can_place` (Outpost presence, sensor discs) measure from that same ground point.
## Cradle slot 0 lies ~335 m below the datum, so the datum placement failed every 300 m presence check.

const R: float = Sphere.PLANET_RADIUS
const N: int = Sphere.GRID_BUILD
const CRADLE: String = "res://content/maps/cradle"
const SLOT0: Vector3 = Vector3(0.923879533, 0.382683432, 0.0)

static var _terrain: Terrain = null

var _content: ContentSet
var _defs: WorldDefs
var _store: EntityStore
var _players: PlayerTable
var _b: Build


static func cradle() -> Terrain:
	if _terrain == null:
		_terrain = Terrain.new()
		var err: Error = _terrain.load_map(CRADLE)
		assert(err == OK, "cradle must load")
	return _terrain


func before_test() -> void:
	_content = WorldTestKit.content()
	_defs = WorldDefs.new(_content)
	_store = EntityStore.new()
	_players = PlayerTable.new()
	_players.active[0] = 1
	_players.team[0] = 0
	_players.team_ore[0] = 100000
	_players.team_ice[0] = 100000
	_b = Build.new(_defs, _store, _players, cradle(), WorldTestKit.rules())


func _def(id: StringName) -> int:
	var d: int = _content.entity_index[id]
	return d


# Direction `metres` of arc from slot 0 along bearing `deg` (0 = the tangent frame's x axis).
func _at(metres: float, deg: float) -> Vector3:
	var f: Basis = Sphere.tangent_frame(SLOT0.normalized())
	var t: Vector3 = f.x * cos(deg_to_rad(deg)) + f.y * sin(deg_to_rad(deg))
	var a: float = metres / R
	return (SLOT0.normalized() * cos(a) + t * sin(a)).normalized()


func test_cradle_slot0_is_far_below_the_datum() -> void:
	# the premise of the bug: the datum and the ground differ by more than the 300 m presence radius
	assert_float(cradle().height_at(SLOT0)).is_less(-300.0)


func test_stamp_puts_the_structure_on_the_terrain_at_its_footprint_centre() -> void:
	var sites: Array = [[&"core", 0.0, 0.0], [&"refinery", 500.0, 90.0], [&"outpost", 1000.0, 200.0], [&"relay_pylon", 300.0, 300.0]]
	for e: Array in sites:
		var id: StringName = e[0]
		var cell: int = Sphere.cell_of(_at(e[1], e[2]), N)
		var id_e: int = _b.stamp(0, _def(id), cell, 0, true)
		assert_int(id_e).is_greater(0)
		var s: int = EntityId.slot(id_e)
		var cells: PackedInt32Array = _b.footprint_cells(_def(id), cell, 0)
		var c: Vector3 = Vector3.ZERO
		for k: int in cells:
			c += Sphere.cell_center_dir(k, N)
		c = c.normalized()
		var p: Vector3 = _store.pos[s]
		assert_float(p.length()).override_failure_message("%s at %.2f m, ground %.2f m" % [id, p.length() - R, cradle().height_at(c)]) \
				.is_equal_approx(R + cradle().height_at(c), 0.01)
		assert_float(p.normalized().angle_to(c)).is_less(1e-5)
		assert_float(_store.up[s].angle_to(c)).is_less(1e-5)   # up stays radial: the flatten plane (03 s7.6)


func test_place_and_can_place_agree_on_the_site_point() -> void:
	var core: int = EntityId.slot(_b.stamp(0, _def(&"core"), Sphere.cell_of(SLOT0, N), 0, true))
	assert_float(_store.pos[core].length() - R).is_less(-300.0)
	var cell: int = Sphere.cell_of(_at(250.0, 45.0), N)
	assert_int(_b.can_place(0, _def(&"relay_pylon"), cell, 0)).is_equal(Build.Reject.OK)
	var s: int = EntityId.slot(_b.place(0, _def(&"relay_pylon"), cell, 0))
	assert_float(_store.pos[s].length()).is_equal_approx(R + cradle().height_at(_store.pos[s]), 0.01)


func test_outpost_presence_passes_on_terrain() -> void:
	var _core: int = _b.stamp(0, _def(&"core"), Sphere.cell_of(SLOT0, N), 0, true)
	var _yard: int = _b.stamp(0, _def(&"shipyard"), Sphere.cell_of(_at(100.0, 270.0), N), 0, true)   # the Outpost's prerequisite
	var hd: int = _def(&"harvester")
	var ok: int = 0
	for k: int in 12:
		var site: Vector3 = _at(1000.0, 30.0 * float(k))
		var cell: int = Sphere.cell_of(site, N)
		# a friendly, undocked Harvester resting on the ground 150 m from the site centre
		var u: int = EntityId.slot(_store.alloc(EntityStore.K_GROUND, 0))
		var ud: Vector3 = _at(1000.0, 30.0 * float(k) + 8.6)
		_store.def_id[u] = hd
		_store.team[u] = 0
		_store.owner[u] = 0
		_store.pos[u] = ud * (R + cradle().height_at(ud) + _defs.radius_of(hd))
		var r: Build.Reject = _b.can_place(0, _def(&"outpost"), cell, 0)
		assert_int(r).override_failure_message("bearing %d: %s" % [30 * k, Build.Reject.keys()[r]]).is_not_equal(Build.Reject.NO_PRESENCE)
		assert_int(r).is_not_equal(Build.Reject.NOT_VISIBLE)
		ok += 1 if r == Build.Reject.OK else 0
		var _f: bool = _store.free_slot(u, 0)
	assert_int(ok).is_greater(0)


func test_flat_datum_stamp_is_unchanged() -> void:
	var st: EntityStore = EntityStore.new()
	var b: Build = Build.new(_defs, st, _players, Terrain.new(), WorldTestKit.rules())
	var cell: int = Sphere.cell_of(SLOT0, N)
	var s: int = EntityId.slot(b.stamp(0, _def(&"core"), cell, 0, true))
	var cells: PackedInt32Array = b.footprint_cells(_def(&"core"), cell, 0)
	var c: Vector3 = Vector3.ZERO
	for k: int in cells:
		c += Sphere.cell_center_dir(k, N)
	assert_vector(st.pos[s]).is_equal(c.normalized() * R)   # bit-exact: the datum placement of before BUG-3
