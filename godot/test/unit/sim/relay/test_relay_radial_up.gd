extends GdUnitTestSuite
## GD-52 (R0 B.33 A-157; sim/relay/MODULE.md MapRelays, sim/build B10): every structure has `up` = `pos.normalized()`,
## whoever spawns it. Map-spawned Relay Stations, `Build.place` and `spawn_start_kit` on sloped ground; a Hauler lands tail-down
## and captures on a 10 degree relay site; `Economy.solar_factor` on a 15 degree slope equals the level-ground value.

const FIX: String = "res://test/unit/sim/relay/fixtures/"
const K: GDScript = preload("res://test/unit/sim/relay/relay_test_kit.gd")
const SLOT0: Vector3 = Vector3(0.923879533, 0.382683432, 0.0)
const FIELD_A: Vector3 = Vector3(0.838630392, 0.544700895, 0.0)


## Height rises `tan(slope_deg)` metres per metre of arc toward +z, the sun side (the fixture sites lie on the equator, dir x = 1).
class RampTerrain extends Terrain:
	var rise: float = 0.0

	func _init() -> void:   # a non-zero resolution makes normal_at sample height_at (the flat stub returns the radial normal)
		face_resolution = 1025
		_nm1 = 1024.0
		_texel_rad = PI * 0.5 / _nm1

	func slope_deg_at_dir(_dir: Vector3) -> float:   # the baked slope band: the constant slope of the ramp
		return rad_to_deg(atan(rise))

	func height_at(dir: Vector3) -> float:
		return rise * Sphere.PLANET_RADIUS * asin(clampf(dir.normalized().z, -1.0, 1.0))


static func ramp(deg: float) -> RampTerrain:
	var t: RampTerrain = RampTerrain.new()
	t.rise = tan(deg_to_rad(deg))
	return t


func _spawn(w: SimWorld, t: Terrain, dir: String) -> int:
	return MapRelays.spawn(FIX + dir, w._defs, t, w.store(), w._applier, w.tick())


func test_ramp_fixture_slopes_ten_degrees_at_the_relay_site() -> void:
	var t: RampTerrain = ramp(10.0)
	var n: Vector3 = t.normal_at(Vector3(1.0, 0.0, 0.0))
	assert_float(rad_to_deg(n.angle_to(Vector3(1.0, 0.0, 0.0)))).is_equal_approx(10.0, 0.05)


func test_map_relays_up_is_radial_on_a_sloped_site() -> void:
	var w: SimWorld = K.world()
	assert_int(_spawn(w, ramp(10.0), "two_blocks")).is_equal(3)
	var st: EntityStore = w.store()
	var def: int = WorldTestKit.def_id(&"relay_station")
	var seen: int = 0
	for s: int in st.structures:
		if st.def_id[s] != def:
			continue
		seen += 1
		assert_float(st.up[s].distance_to(st.pos[s].normalized())).is_less(1e-6)
		assert_float(st.fwd[s].dot(st.up[s])).is_less(1e-6)
		assert_float(st.fwd[s].length()).is_equal_approx(1.0, 1e-6)
	assert_int(seen).is_equal(3)


## Cannot fail on this ramp: the facing (0,1,0) is already tangent at dir (1,0,0) and the ramp tilts toward z, so projection is a no-op.
func test_map_relays_fwd_is_the_facing_projected_on_the_tangent_plane() -> void:
	var w: SimWorld = K.world()
	var _n: int = _spawn(w, ramp(10.0), "one_relay")
	var s: int = w.store().structures[0]
	assert_float(w.store().fwd[s].distance_to(Vector3(0.0, 1.0, 0.0))).is_less(1e-6)   # facing (0,1,0) is already tangent at dir (1,0,0)


func test_map_relays_stands_on_the_surface_point() -> void:
	var w: SimWorld = K.world()
	var t: RampTerrain = ramp(10.0)
	var _n: int = _spawn(w, t, "one_relay")
	var s: int = w.store().structures[0]
	assert_vector(w.store().pos[s]).is_equal(t.surface_point(Vector3(1.0, 0.0, 0.0)))


func test_build_place_up_is_radial_on_a_15_degree_slope() -> void:
	var content: ContentSet = WorldTestKit.content()
	var defs: WorldDefs = WorldDefs.new(content)
	var st: EntityStore = EntityStore.new()
	var pl: PlayerTable = PlayerTable.new()
	pl.active[0] = 1
	pl.team[0] = 0
	pl.team_ore[0] = 100000
	var b: Build = Build.new(defs, st, pl, ramp(15.0), WorldTestKit.rules())
	var cell: int = Sphere.cell_of(Vector3(1.0, 0.0, 0.0), Sphere.GRID_BUILD)
	var s: int = EntityId.slot(b.stamp(0, content.entity_index[&"core"], cell, 0, true))
	var p: int = EntityId.slot(b.place(0, content.entity_index[&"solar_array"], Sphere.cell_of(Vector3(1.0, 0.0, 0.02).normalized(), Sphere.GRID_BUILD), 0))
	assert_int(p).is_greater(0)
	for k: int in [s, p]:
		assert_float(st.up[k].distance_to(st.pos[k].normalized())).is_less(1e-6)


func test_start_kit_up_is_radial_on_cradle() -> void:
	var w: SimWorld = SimWorld.new(WorldTestKit.content())
	var map: MapDef = MapDef.new()
	map.id = &"cradle"
	var res: Result = w.load_map(map, 7, WorldTestKit.rules())
	assert(res.ok, res.message)
	w.add_player(0, 0, &"", PlayerTable.KIND_HUMAN)
	assert_bool(w.spawn_start_kit(0, SLOT0, FIELD_A)).is_true()
	var st: EntityStore = w.store()
	assert_int(st.structures.size()).is_greater_equal(4)
	for s: int in st.structures:
		assert_float(st.up[s].distance_to(st.pos[s].normalized())).is_less(1e-6)


## The world is flat (K.world); only the relay spawn sees the ramp, so the stored `up` is the only thing the slope can change.
func test_a_hauler_lands_tail_down_and_captures_on_a_10_degree_relay_site() -> void:
	var w: SimWorld = K.world()
	var _n: int = _spawn(w, ramp(10.0), "one_relay")
	var _ev: Array[SimEvent] = w.drain_events()
	var relay: int = w.store().id_of(w.store().structures[0])
	var sd: ShipDef = DockingTestKit.ship_def(&"hauler")
	var up: Vector3 = w.store().pos[EntityId.slot(relay)].normalized()   # radial, read from pos, not from the stored up under test
	var h: int = DockingTestKit.ship_over(w, &"hauler", 0, 0, relay, sd.bounding_radius, 0.0, -up * 2.0)   # on the pad centre
	var _d: Array[SimEvent] = w.drain_events()
	w.step()
	var hs: int = EntityId.slot(h)
	assert_int(w.store().link[hs]).is_equal(relay)
	assert_bool((w.store().flags[hs] & EntityStore.F_DOCKED) != 0).is_true()
	assert_float(w.store().fwd[hs].dot(up)).is_greater(0.99)   # tail-down: thrust axis within 0.99 of radial (a 10 degree normal gives 0.985)
	for _i: int in K.seconds(K.rule("capture_s")) + 5:
		w.step()
	assert_int(K.team_of(w, relay)).is_equal(0)


func test_solar_factor_on_a_15_degree_slope_equals_level_ground_at_its_latitude() -> void:
	var content: ContentSet = WorldTestKit.content()
	var st: EntityStore = EntityStore.new()
	var pl: PlayerTable = PlayerTable.new()
	pl.active[0] = 1
	pl.team[0] = 0
	var t: RampTerrain = ramp(15.0)
	var defs: WorldDefs = WorldDefs.new(content)
	var band: float = defs.economy.solar_band_deg
	var mult: float = defs.economy.solar_plateau_mult
	var b: Build = Build.new(defs, st, pl, t, WorldTestKit.rules())
	var sun: Vector3 = Vector3(0.0, 0.0, 1.0)
	var moved: int = 0
	for lat: float in [-1.0, -0.2, 0.0, 0.2, 1.0, 20.0]:
		var dir: Vector3 = Vector3(cos(deg_to_rad(lat)), 0.0, sin(deg_to_rad(lat)))
		var cell: int = Sphere.cell_of(dir, Sphere.GRID_BUILD)
		var s: int = EntityId.slot(b.stamp(0, content.entity_index[&"solar_array"], cell, 0, true))
		var c: Vector3 = st.pos[s].normalized()   # the footprint centre: the structure's own latitude
		var level: float = Economy.solar_factor(c, sun, false, band, mult)
		assert_float(Economy.solar_factor(st.up[s], sun, false, band, mult)).is_equal(level)
		if absf(Economy.solar_factor(t.normal_at(c), sun, false, band, mult) - level) > 0.01:
			moved += 1
	assert_int(moved).is_greater(0)   # the fixture discriminates: the terrain normal would have moved the step
