extends GdUnitTestSuite
## Unit tests for sim/spatial.gd (03 s3.6, R0 C1-19, TA-14): counting-sort hash vs brute force over random sets
## concentrated at cube edges and corners, ring coverage proof (ring1_m / ring2_m and no miss for r <= 139 m),
## touched-cell reset, determinism, no Dictionary in Spatial.

const R: float = Sphere.PLANET_RADIUS
const KINDS: Array[int] = [EntityStore.K_STRUCTURE, EntityStore.K_SHIP, EntityStore.K_GROUND, EntityStore.K_WRECK]


## A direction near a cube corner (mode 0), on a cube edge (1) or anywhere (2).
static func _dir(rng: Rng, mode: int) -> Vector3:
	var j: Vector3 = Vector3(rng.range_f(-1.0, 1.0), rng.range_f(-1.0, 1.0), rng.range_f(-1.0, 1.0))
	if mode == 0:
		var c: Vector3 = Vector3(1 if rng.next_float() < 0.5 else -1, 1 if rng.next_float() < 0.5 else -1,
			1 if rng.next_float() < 0.5 else -1).normalized()
		return (c + j * 0.03).normalized()
	if mode == 1:
		var axis: int = rng.range_i(0, 2)
		var v: Vector3 = Vector3(1 if rng.next_float() < 0.5 else -1, 1 if rng.next_float() < 0.5 else -1,
			1 if rng.next_float() < 0.5 else -1)
		v[axis] = rng.range_f(-1.0, 1.0)
		return (v + j * 0.01).normalized()
	return j.normalized() if j.length_squared() > 1e-6 else Vector3.UP


static func _radius(rng: Rng) -> float:
	return R + rng.range_f(Sphere.RELIEF_MIN, Sphere.CEILING_HARD)


## Random cluster world: entities of every kind plus projectiles, all within a few km of a few seeds.
func _populate(kit: CollisionTestKit, rng: Rng, entities: int, projectiles: int) -> void:
	var seeds: PackedVector3Array = PackedVector3Array()
	for m: int in 6:
		var _a: bool = seeds.push_back(_dir(rng, m % 3))
	for k: int in entities:
		var d: Vector3 = (seeds[k % 6] + _dir(rng, 2) * rng.range_f(0.0, 0.05)).normalized()
		var _s: int = kit.entity(KINDS[k % 4], d * _radius(rng), rng.range_f(2.0, 30.0), k % 3)
	for k: int in projectiles:
		var d: Vector3 = (seeds[k % 6] + _dir(rng, 2) * rng.range_f(0.0, 0.05)).normalized()
		var _i: int = kit.projectile("slug_light", d * _radius(rng), Vector3.ZERO, k % 3)


func _brute(kit: CollisionTestKit, p: Vector3, r: float, mask: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for list: PackedInt32Array in [kit.store.structures, kit.store.ships, kit.store.ground, kit.store.wrecks]:
		for s: int in list:
			if (mask & (1 << kit.store.kind[s])) != 0 and kit.store.pos[s].distance_to(p) <= r:
				var _a: bool = out.push_back(kit.store.id_of(s))
	if (mask & Spatial.MASK_PROJECTILE) != 0:
		for i: int in kit.proj.live:
			if kit.proj.pos[i].distance_to(p) <= r:
				var _b: bool = out.push_back(kit.proj.id_of(i))
	out.sort()
	return out


func test_ids_near_matches_brute_force_at_edges_and_corners() -> void:
	var kit: CollisionTestKit = CollisionTestKit.new()
	var rng: Rng = Rng.new(14)
	_populate(kit, rng, 400, 1200)
	kit.spatial.rebuild()
	var radii: PackedFloat32Array = PackedFloat32Array([5.0, 50.0, 90.0, 120.0, 139.0, 180.0, 250.0, 700.0, 3000.0])
	var masks: PackedInt32Array = PackedInt32Array([Spatial.MASK_ALL, Spatial.MASK_ENTITIES, Spatial.MASK_SHIP,
		Spatial.MASK_STRUCTURE | Spatial.MASK_WRECK, Spatial.MASK_PROJECTILE, Spatial.MASK_GROUND])
	var found: int = 0
	for q: int in 300:
		var live: PackedInt32Array = kit.store.ships if q % 2 == 0 else kit.store.structures
		var p: Vector3 = kit.store.pos[live[q % live.size()]] + _dir(rng, 2) * rng.range_f(0.0, 60.0)
		p = p.normalized() * maxf(p.length(), R + Sphere.RELIEF_MIN)          # precondition: above the terrain floor
		var r: float = radii[q % radii.size()]
		var mask: int = masks[q % masks.size()]
		var got: PackedInt32Array = kit.spatial.ids_near(p, r, mask)
		got.sort()
		assert_array(got).is_equal(_brute(kit, p, r, mask))
		found += got.size()
	assert_int(found).is_greater(1000)


func test_rebuild_buckets_every_live_item_by_cell_of() -> void:
	var kit: CollisionTestKit = CollisionTestKit.new()
	_populate(kit, Rng.new(3), 300, 900)
	kit.spatial.rebuild()
	var sp: Spatial = kit.spatial
	assert_int(sp.item_count).is_equal(kit.store.live_count() + kit.proj.live_count())
	var seen: int = 0
	for t: int in sp.touched_count:
		var c: int = sp.touched_cells[t]
		var ids: PackedInt32Array = sp.ids_in_hash_cell(c)
		assert_int(ids.size()).is_equal(sp.cell_count[c])
		for k: int in ids.size():
			var id: int = ids[k]
			var is_proj: bool = EntityId.is_projectile(id)
			assert_bool(is_proj).is_equal(k >= sp.cell_entities[c])   # entities first within a cell
			var p: Vector3 = kit.proj.pos[kit.proj.index_of(id)] if is_proj else kit.store.pos[EntityId.slot(id)]
			assert_int(Sphere.cell_of(p, Sphere.GRID_HASH)).is_equal(c)
			var hc: int = kit.proj.hash_cell[kit.proj.index_of(id)] if is_proj else kit.store.hash_cell[EntityId.slot(id)]
			assert_int(hc).is_equal(c)
		seen += ids.size()
	assert_int(seen).is_equal(sp.item_count)
	assert_int(sp.ids_in_hash_cell(-1).size()).is_equal(0)
	assert_int(sp.ids_in_hash_cell(Spatial.CELL_COUNT).size()).is_equal(0)


func test_rebuild_resets_cells_vacated_since_last_tick() -> void:
	var kit: CollisionTestKit = CollisionTestKit.new()
	var a: Vector3 = Vector3(1, 0.2, 0.1).normalized() * (R + 100.0)
	var b: Vector3 = Vector3(0.1, 1, 0.3).normalized() * (R + 100.0)
	var s: int = kit.entity(EntityStore.K_SHIP, a, 6.0, 0)
	kit.spatial.rebuild()
	var ca: int = Sphere.cell_of(a, Sphere.GRID_HASH)
	assert_int(kit.spatial.ids_in_hash_cell(ca).size()).is_equal(1)
	kit.store.pos[s] = b
	kit.spatial.rebuild()
	assert_int(kit.spatial.ids_in_hash_cell(ca).size()).is_equal(0)
	assert_int(kit.spatial.ids_in_hash_cell(Sphere.cell_of(b, Sphere.GRID_HASH))[0]).is_equal(kit.store.id_of(s))
	assert_int(kit.spatial.touched_count).is_equal(1)
	var _f: bool = kit.store.free_slot(s, 1)
	kit.spatial.rebuild()
	assert_int(kit.spatial.item_count).is_equal(0)
	assert_int(kit.spatial.ids_near(b, 50.0, Spatial.MASK_ALL).size()).is_equal(0)


## Ring coverage proof, numeric half: q within ring_k_m (3D) of p at any radius in [R + RELIEF_MIN, R + CEILING_HARD]
## is always in ring k of p's cell. Points concentrated at cube corners and edge midpoints (the narrowest strips).
func test_ring_coverage_no_miss_at_edges_and_corners() -> void:
	var kit: CollisionTestKit = CollisionTestKit.new()
	var sp: Spatial = kit.spatial
	var rng: Rng = Rng.new(99)
	for k: int in [1, 2]:
		var reach: float = sp.ring1_m if k == 1 else sp.ring2_m
		for trial: int in 4000:
			var p: Vector3 = _dir(rng, trial % 3) * _radius(rng)
			var n: int = sp.ring_cells(Sphere.cell_of(p, Sphere.GRID_HASH), k)
			var cells: PackedInt32Array = sp.ring.slice(0, n)
			var q: Vector3 = p + _dir(rng, 2) * reach * sqrt(rng.next_float())
			if q.length() < R + Sphere.RELIEF_MIN:
				continue
			var cq: int = Sphere.cell_of(q, Sphere.GRID_HASH)
			if not cells.has(cq):
				fail("ring %d misses %s -> %s (%.2f m)" % [k, p, q, p.distance_to(q)])
				return


## Ring coverage proof, analytic half: ring 1 covers asin(sin(delta) / sqrt(2)) of datum arc (104.1 m), less than
## the 139 m corner edge of 03 s2.7, so ids_near uses ring 2 above ring1_m and still never misses at r <= 139 m.
func test_ring_radii_and_cell_counts() -> void:
	var sp: Spatial = CollisionTestKit.new().spatial
	assert_float(sp.ring1_m).is_between(90.0, 104.2)
	assert_float(sp.ring2_m).is_between(180.0, 208.3)
	assert_float(sp.ring2_m).is_greater(139.0)
	assert_int(sp.ring_cells(Sphere.cell_of(Vector3(1, 0.01, 0.02), Sphere.GRID_HASH), 1)).is_equal(9)
	assert_int(sp.ring_cells(Sphere.cell_of(Vector3(1, 0.01, 0.02), Sphere.GRID_HASH), 2)).is_equal(25)
	var corner: int = Sphere.cell_of(Vector3(1, 1, 1), Sphere.GRID_HASH)
	assert_int(sp.ring_cells(corner, 1)).is_equal(8)            # cell + 7 neighbours at a cube corner
	var edge: int = Sphere.cell_of(Vector3(1, 1, 0.1), Sphere.GRID_HASH)
	assert_int(sp.ring_cells(edge, 1)).is_equal(9)
	assert_int(sp.ring_cells(edge, 2)).is_equal(25)


func test_cell_of_equals_sphere_cell_of() -> void:
	var rng: Rng = Rng.new(41)
	var ties: PackedVector3Array = PackedVector3Array([Vector3(1, 1, 0.3), Vector3(-1, 1, 1), Vector3(0.2, -1, -1),
		Vector3(1, 1, 1), Vector3(-1, -1, -1), Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, -1, 0), Vector3(1, 0, 0)])
	for p: Vector3 in ties:
		assert_int(Spatial.cell_of(p * R)).is_equal(Sphere.cell_of(p * R, Sphere.GRID_HASH))
	for k: int in 20000:
		var p: Vector3 = _dir(rng, k % 3) * _radius(rng)
		assert_int(Spatial.cell_of(p)).is_equal(Sphere.cell_of(p, Sphere.GRID_HASH))


func test_hash_is_deterministic() -> void:
	var a: CollisionTestKit = CollisionTestKit.new()
	var b: CollisionTestKit = CollisionTestKit.new()
	_populate(a, Rng.new(5), 200, 600)
	_populate(b, Rng.new(5), 200, 600)
	a.spatial.rebuild()
	b.spatial.rebuild()
	assert_array(a.spatial.cell_items.slice(0, a.spatial.item_count)).is_equal(b.spatial.cell_items.slice(0, b.spatial.item_count))
	assert_array(a.spatial.touched_cells.slice(0, a.spatial.touched_count)).is_equal(b.spatial.touched_cells.slice(0, b.spatial.touched_count))


func test_no_dictionary_in_spatial() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/sim/spatial.gd")
	for line: String in src.split("\n"):
		var code: String = line.split("#")[0]
		assert_bool(code.contains("Dictionary") or code.contains("{")).override_failure_message(line).is_false()


func _state(sp: Spatial) -> PackedByteArray:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	sp.write_state(b)
	return b.data_array


func _read(sp: Spatial, bytes: PackedByteArray) -> bool:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.data_array = bytes
	return sp.read_state(b)


## TA-65 (S4): write_state / read_state carry the index exactly as step 7 left it, including items moved, spawned
## or freed since (a rebuild would not): a fresh Spatial answers every query like the original, and its next
## rebuild resets the restored cells.
func test_state_round_trip_keeps_the_last_rebuild_not_the_current_store() -> void:
	var kit: CollisionTestKit = CollisionTestKit.new()
	_populate(kit, Rng.new(65), 120, 300)
	kit.spatial.rebuild()
	var late: Vector3 = Vector3(0.3, 1, 0.2).normalized() * (R + 300.0)
	var _p: int = kit.projectile("slug_light", late, Vector3.ZERO, 1)   # spawned after the rebuild (step 9)
	var _f: bool = kit.proj.free_slot(kit.proj.live[0], 1)            # freed after the rebuild
	var bytes: PackedByteArray = _state(kit.spatial)
	var sp: Spatial = Spatial.new(kit.store, kit.proj)
	assert_bool(_read(sp, bytes)).is_true()
	assert_bool(_state(sp) == bytes).is_true()
	assert_int(sp.item_count).is_equal(kit.spatial.item_count)
	assert_float(sp.max_entity_radius).is_equal(kit.spatial.max_entity_radius)
	assert_int(sp.ids_near(late, 50.0, Spatial.MASK_ALL).size()).is_equal(0)   # not in the saved index
	var rng: Rng = Rng.new(66)
	for _k: int in 40:
		var p: Vector3 = _dir(rng, 2) * _radius(rng)
		var r: float = rng.range_f(10.0, 900.0)
		assert_bool(sp.ids_near(p, r, Spatial.MASK_ALL) == kit.spatial.ids_near(p, r, Spatial.MASK_ALL)).is_true()
		var c: int = Spatial.cell_of(p)
		assert_bool(sp.ids_in_hash_cell(c) == kit.spatial.ids_in_hash_cell(c)).is_true()
	sp.rebuild()
	kit.spatial.rebuild()
	assert_bool(_state(sp) == _state(kit.spatial)).is_true()
	assert_int(sp.ids_near(late, 50.0, Spatial.MASK_ALL).size()).is_equal(1)


## read_state refuses wrong types, out-of-range or repeated cells, counts that do not sum to the items, and an
## entity / projectile item in the other part of its cell; the index is untouched on refusal.
func test_read_state_refuses_malformed_index() -> void:
	var kit: CollisionTestKit = CollisionTestKit.new()
	var s: int = kit.entity(EntityStore.K_SHIP, Vector3(1, 0.2, 0.1).normalized() * (R + 100.0), 6.0, 0)
	var _i: int = kit.projectile("slug_light", Vector3(1, 0.2, 0.1).normalized() * (R + 110.0), Vector3.ZERO, 1)
	kit.spatial.rebuild()
	var good: PackedByteArray = _state(kit.spatial)
	var c: int = kit.store.hash_cell[s]
	var cases: Array = [
		[PackedInt32Array([c]), PackedInt32Array([2]), PackedInt32Array([1]), PackedInt32Array([s]), 6.0],
		[PackedInt32Array([-1]), PackedInt32Array([2]), PackedInt32Array([1]), PackedInt32Array([s, 4096]), 6.0],
		[PackedInt32Array([c, c]), PackedInt32Array([1, 1]), PackedInt32Array([1, 0]), PackedInt32Array([s, 4096]), 6.0],
		[PackedInt32Array([c]), PackedInt32Array([2]), PackedInt32Array([2]), PackedInt32Array([s, 4096]), 6.0],
		[PackedInt32Array([c]), PackedInt32Array([2]), PackedInt32Array([1]), PackedInt32Array([4096, s]), 6.0],
		[PackedInt32Array([c]), PackedInt32Array([2]), PackedInt32Array([1]), PackedInt32Array([s, 4096]), -1.0],
		[PackedInt32Array([c]), PackedInt32Array([2]), PackedInt32Array([1]), PackedInt32Array([s, 4096]), 6],
	]
	for v: Array in cases:
		var b: StreamPeerBuffer = StreamPeerBuffer.new()
		for x: Variant in v:
			b.put_var(x)
		assert_bool(_read(kit.spatial, b.data_array)).is_false()
		assert_bool(_state(kit.spatial) == good).is_true()
	assert_bool(_read(kit.spatial, good.slice(0, good.size() - 4))).is_false()
	assert_bool(_read(kit.spatial, good)).is_true()
