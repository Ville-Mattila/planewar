extends GdUnitTestSuite
## TA-37 Vision (03 s3.7): range, horizon occlusion incl. the A-10 below-datum vectors, Sensor Mast reveal, wrecks,
## own / neutral bits, bit clearing, and exactness of the pruned pass against a brute force over random scenes
## (cube corners and edges, crater floors, every team group). Stagger, lists and determinism: test_vision_lists.gd.

const R: float = Sphere.PLANET_RADIUS


func test_sees_in_range_not_beyond() -> void:
	var w: SimWorld = VisionTestKit.world()
	var dart: int = VisionTestKit.put(w, &"dart", 0, VisionTestKit.at(500.0))
	var near: int = VisionTestKit.put(w, &"harvester", 1, VisionTestKit.at(1.0, 800.0))     # ~943 m < 1,400
	var far: int = VisionTestKit.put(w, &"harvester", 1, VisionTestKit.at(1.0, 1500.0))     # ~1,581 m > 1,400
	VisionTestKit.sense(w)
	assert_bool(VisionTestKit.visible(w, 0, near)).is_true()
	assert_bool(VisionTestKit.visible(w, 0, far)).is_false()
	assert_bool(VisionTestKit.visible(w, 1, dart)).is_false()   # harvester sensor 600 m
	assert_bool(w.view().visible_to(0, near)).is_true()
	assert_bool(w.view().visible_to(0, far)).is_false()


func test_horizon_occludes_in_range() -> void:
	var w: SimWorld = VisionTestKit.world()
	var _own: int = VisionTestKit.put(w, &"harvester", 0, VisionTestKit.at(1.0))
	var close: int = VisionTestKit.put(w, &"harvester", 1, VisionTestKit.at(1.0, 150.0))    # sag 0.47 m < 1 m
	var hidden: int = VisionTestKit.put(w, &"harvester", 1, VisionTestKit.at(1.0, 500.0))   # in range, sag 5.2 m
	VisionTestKit.sense(w)
	assert_bool(VisionTestKit.visible(w, 0, close)).is_true()
	assert_bool(VisionTestKit.visible(w, 0, hidden)).is_false()


## A-10 vector 2 through Vision: a floor unit at R - 200 and a scout 500 m above it, 1,500 m east along the
## tangent (1,581 m apart, scout sensor 2,000 m) see each other; the endpoint below the datum never occludes.
func test_below_datum_unit_sees_and_is_seen() -> void:
	var w: SimWorld = VisionTestKit.world()
	var a: Vector3 = Vector3(R - 200.0, 0.0, 0.0)
	var b: Vector3 = a + Vector3(500.0, 1500.0, 0.0)
	assert_bool(Sphere.is_occluded_by_datum(a, b)).is_false()
	var low: int = VisionTestKit.put(w, &"scout", 1, a)
	var high: int = VisionTestKit.put(w, &"scout", 0, b)
	VisionTestKit.sense(w)
	assert_bool(VisionTestKit.visible(w, 0, low)).is_true()
	assert_bool(VisionTestKit.visible(w, 1, high)).is_true()


## A-10 vector 1 through Vision: two floor units at R - 200, 1,900 m apart (in scout range) are hidden by the
## datum between them, both ways.
func test_two_below_datum_units_occluded() -> void:
	var w: SimWorld = VisionTestKit.world()
	var fr: float = R - 200.0
	var p: Vector3 = Sphere.from_lat_lon(0.0, 0.0, fr)
	var q: Vector3 = Sphere.from_lat_lon(0.0, 2.0 * asin(950.0 / fr), fr)
	assert_float(p.distance_to(q)).is_equal_approx(1900.0, 0.01)
	assert_bool(Sphere.is_occluded_by_datum(p, q)).is_true()
	var u0: int = VisionTestKit.put(w, &"scout", 0, p)
	var u1: int = VisionTestKit.put(w, &"scout", 1, q)
	VisionTestKit.sense(w)
	assert_bool(VisionTestKit.visible(w, 0, u1)).is_false()
	assert_bool(VisionTestKit.visible(w, 1, u0)).is_false()


## 01 s6.2: a Sensor Mast reveals everything within deck_reveal_radius (1,200 m) regardless of occlusion; its
## sensor_radius (3,500 m) still needs a clear line. A Solar Array in the same place reveals nothing occluded.
func test_sensor_mast_reveals_within_1200_regardless_of_occlusion() -> void:
	var w: SimWorld = VisionTestKit.world()
	var mast: int = VisionTestKit.put(w, &"sensor_mast", 0, VisionTestKit.at(1.0))
	var r_mast: float = w.vision.reveal_r[0 * Vision.DEF_N + WorldTestKit.def_id(&"sensor_mast")]   # owner slot 0
	assert_float(r_mast).is_equal(1200.0)
	var in_reveal: int = VisionTestKit.put(w, &"harvester", 1, VisionTestKit.at(1.0, 1100.0))
	var beyond: int = VisionTestKit.put(w, &"harvester", 1, VisionTestKit.at(1.0, 1300.0))
	var crater: int = VisionTestKit.put(w, &"harvester", 1, VisionTestKit.at(-300.0, -1000.0))
	var high: int = VisionTestKit.put(w, &"dart", 1, VisionTestKit.at(800.0, -3000.0))   # horizons 110 + 3,200 m
	assert_bool(Sphere.is_occluded_by_datum(w.store().pos[EntityId.slot(mast)], w.store().pos[EntityId.slot(in_reveal)])).is_true()
	VisionTestKit.sense(w)
	assert_bool(VisionTestKit.visible(w, 0, in_reveal)).is_true()
	assert_bool(VisionTestKit.visible(w, 0, crater)).is_true()
	assert_bool(VisionTestKit.visible(w, 0, beyond)).is_false()
	assert_bool(VisionTestKit.visible(w, 0, high)).is_true()


func test_non_mast_structure_does_not_reveal() -> void:
	var w: SimWorld = VisionTestKit.world()
	var _solar: int = VisionTestKit.put(w, &"solar_array", 0, VisionTestKit.at(1.0))       # sensor 400, no reveal
	var occluded: int = VisionTestKit.put(w, &"harvester", 1, VisionTestKit.at(1.0, 300.0))   # sag 1.9 m > 1 m
	VisionTestKit.sense(w)
	assert_bool(VisionTestKit.visible(w, 0, occluded)).is_false()
	var _mast: int = VisionTestKit.put(w, &"sensor_mast", 0, VisionTestKit.at(1.0, -10.0))
	VisionTestKit.sense(w)
	assert_bool(VisionTestKit.visible(w, 0, occluded)).is_true()


func test_wrecks_do_not_sense_own_and_neutral_bits() -> void:
	var w: SimWorld = VisionTestKit.world()
	var wreck: int = VisionTestKit.put(w, &"dart", 0, VisionTestKit.at(500.0), EntityStore.K_WRECK)
	var enemy: int = VisionTestKit.put(w, &"harvester", 1, VisionTestKit.at(1.0, 800.0))
	var relay: int = VisionTestKit.put(w, &"relay_station", -1, VisionTestKit.at(1.0, -400.0))
	VisionTestKit.sense(w)
	assert_bool(VisionTestKit.visible(w, 0, enemy)).is_false()
	assert_bool(VisionTestKit.visible(w, 0, wreck)).is_true()          # own team
	assert_bool(VisionTestKit.visible(w, 0, relay)).is_false()
	var _dart: int = VisionTestKit.put(w, &"dart", 0, VisionTestKit.at(500.0, -100.0))
	VisionTestKit.sense(w)
	assert_bool(VisionTestKit.visible(w, 0, enemy)).is_true()
	assert_bool(VisionTestKit.visible(w, 0, relay)).is_true()          # neutral, seen like any other
	assert_int(w.store().visible_mask[EntityId.slot(relay)] & 0xFE).is_equal(0)


## V9: the index caches structures until the structures list or a team byte changes; a captured (re-teamed) Relay
## Station senses and reveals for its new team on the next pass, and loses its old group.
func test_captured_structure_rebuckets() -> void:
	var w: SimWorld = VisionTestKit.world()
	var relay: int = VisionTestKit.put(w, &"relay_station", -1, VisionTestKit.at(1.0))
	var enemy: int = VisionTestKit.put(w, &"harvester", 1, VisionTestKit.at(1.0, 1000.0))   # occluded, inside reveal
	VisionTestKit.sense(w)
	assert_bool(VisionTestKit.visible(w, 0, enemy)).is_false()
	assert_bool(VisionTestKit.visible(w, 0, relay)).is_false()
	w.store().team[EntityId.slot(relay)] = 0
	w.store().owner[EntityId.slot(relay)] = 0
	VisionTestKit.sense(w)
	assert_bool(VisionTestKit.visible(w, 0, enemy)).is_true()
	assert_bool(VisionTestKit.visible(w, 0, relay)).is_true()
	var cell: int = Sphere.cell_of(w.store().pos[EntityId.slot(relay)], Sphere.GRID_INTEREST)
	assert_bool(w.vision.ids_in_cell(0, cell).has(relay)).is_true()


func test_bit_clears_when_target_leaves_range() -> void:
	var w: SimWorld = VisionTestKit.world()
	var _dart: int = VisionTestKit.put(w, &"dart", 0, VisionTestKit.at(500.0))
	var enemy: int = VisionTestKit.put(w, &"harvester", 1, VisionTestKit.at(1.0, 800.0))
	VisionTestKit.sense(w)
	assert_bool(VisionTestKit.visible(w, 0, enemy)).is_true()
	var cell: int = Sphere.cell_of(w.store().pos[EntityId.slot(enemy)], Sphere.GRID_INTEREST)
	assert_bool(w.vision.ids_in_cell(0, cell).has(enemy)).is_true()
	w.store().pos[EntityId.slot(enemy)] = VisionTestKit.at(1.0, 1700.0)
	VisionTestKit.sense(w)
	assert_bool(VisionTestKit.visible(w, 0, enemy)).is_false()
	for c: int in InterestGrid.CELLS:
		assert_bool(w.vision.ids_in_cell(0, c).has(enemy)).is_false()


func test_pair_test_matches_sphere() -> void:
	var rng: Rng = Rng.new(37)
	for _k: int in 2000:
		var a: Vector3 = VisionTestKit.random_dir(rng) * (R + rng.range_f(Sphere.RELIEF_MIN, Sphere.CEILING_HARD))
		var b: Vector3 = (a.normalized() + VisionTestKit.random_dir(rng) * rng.range_f(0.0, 0.6)).normalized() \
			* (R + rng.range_f(Sphere.RELIEF_MIN, Sphere.CEILING_HARD))
		var s: float = rng.range_f(0.0, 4000.0)
		var expect: bool = a.distance_to(b) <= s and not Sphere.is_occluded_by_datum(a, b)
		if absf(a.distance_to(b) - s) > 0.01:
			assert_bool(Vision.sees(a, b, s, 0.0)).is_equal(expect)
		assert_bool(Vision.sees(a, b, 0.0, s)).is_equal(a.distance_squared_to(b) <= s * s)


## The pruned pass equals the brute force of 03 s3.7 for every team on random scenes around a cube corner, a cube
## edge and two face points: ships -300..1,800 m, ground and structures -400..300 m, 10 % wrecks, neutrals.
func test_random_scenes_equal_brute_force() -> void:
	for seed_value: int in [3, 11, 29]:
		var w: SimWorld = VisionTestKit.world()
		VisionTestKit.scatter(w, Rng.new(seed_value), 260)
		VisionTestKit.sense(w)
		for t: int in 4:
			var want: PackedByteArray = VisionTestKit.brute(w, t)
			var bad: int = 0
			for list: PackedInt32Array in [w.store().structures, w.store().ships, w.store().ground, w.store().wrecks]:
				for s: int in list:
					var got: int = (w.store().visible_mask[s] >> t) & 1
					if got != want[s]:
						bad += 1
			assert_int(bad).override_failure_message("seed %d team %d: %d mismatches" % [seed_value, t, bad]).is_equal(0)


func test_interest_cell_of_hash_equals_sphere() -> void:
	var rng: Rng = Rng.new(5)
	for k: int in 5000:
		var d: Vector3 = VisionTestKit.random_dir(rng)
		if k % 3 == 0:
			d = (Vector3(signf(d.x), signf(d.y), signf(d.z)) + d * 0.02).normalized()   # near cube corners
		var p: Vector3 = d * (R + rng.range_f(Sphere.RELIEF_MIN, Sphere.CEILING_HARD))
		assert_int(InterestGrid.interest_of_hash(Spatial.cell_of(p))).is_equal(Sphere.cell_of(p, Sphere.GRID_INTEREST))


func test_bind_reads_resolved_sensor_and_reveal_radii() -> void:
	var w: SimWorld = VisionTestKit.world()
	var v: Vision = w.vision
	for owner: int in [0, 1, WorldDefs.NEUTRAL]:
		var row: int = owner * Vision.DEF_N
		assert_float(v.sensor_r[row + WorldTestKit.def_id(&"dart")]).is_equal(1400.0)
		assert_float(v.sensor_r[row + WorldTestKit.def_id(&"harvester")]).is_equal(600.0)
		assert_float(v.sensor_r[row + WorldTestKit.def_id(&"sensor_mast")]).is_equal(3500.0)
		assert_float(v.reveal_r[row + WorldTestKit.def_id(&"sensor_mast")]).is_equal(1200.0)
		assert_float(v.reveal_r[row + WorldTestKit.def_id(&"core")]).is_equal(0.0)
	assert_float(v.grid.reach_m).is_greater_equal(3500.0)
	assert_int(v.rung_2_hz).is_equal(WorldTestKit.content().rules.rung_2_vision_hz)
	assert_int(v.hz).is_equal(Vision.VISION_HZ)
	assert_int(v.period(PackedInt32Array([1]))).is_equal(MathX.floori_div(WorldTestKit.content().rules.tick_hz, Vision.VISION_HZ))
