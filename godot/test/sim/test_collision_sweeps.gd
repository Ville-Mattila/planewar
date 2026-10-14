extends GdUnitTestSuite
## Scenario layer for sim/collision.gd (03 s6.1, TA-14 acceptance): swept slugs (700 m/s) and rail slugs
## (1,500 m/s) against a 6 m sphere for 1,000 random geometries each, flown tick by tick through
## Kinematics.step_projectile -> Spatial.rebuild -> Collision.step, at cube edges and corners included; near misses
## just outside the combined radius never hit; a random multi-tick battle produces byte-identical contacts twice.

const R: float = Sphere.PLANET_RADIUS
const TARGET_RADIUS: float = 6.0
const GEOMETRIES: int = 1000
const BATTLE_KINDS: Array[int] = [EntityStore.K_SHIP, EntityStore.K_SHIP, EntityStore.K_STRUCTURE, EntityStore.K_GROUND]


## Random unit vector; every third one near a cube corner, every third on a cube edge.
static func _dir(rng: Rng, k: int) -> Vector3:
	var j: Vector3 = Vector3(rng.range_f(-1.0, 1.0), rng.range_f(-1.0, 1.0), rng.range_f(-1.0, 1.0))
	var s: Vector3 = Vector3(1 if rng.next_float() < 0.5 else -1, 1 if rng.next_float() < 0.5 else -1,
		1 if rng.next_float() < 0.5 else -1)
	if k % 3 == 0:
		return (s + j * 0.02).normalized()
	if k % 3 == 1:
		s[rng.range_i(0, 2)] = rng.range_f(-1.0, 1.0)
		return (s + j * 0.01).normalized()
	return j.normalized() if j.length_squared() > 1e-6 else Vector3.UP


## Flies one projectile of `id` past a 6 m target with closest approach `miss` (m) after travelling `travel` (m).
## Returns the tick of the HIT on the target, or -1.
func _fly(kit: CollisionTestKit, def: ProjectileDef, id: String, rng: Rng, k: int, miss: float, travel: float) -> int:
	var n: Vector3 = _dir(rng, k)
	var c: Vector3 = n * (R + rng.range_f(200.0, 1500.0))
	var f: Basis = Sphere.tangent_frame(c)
	var a: float = rng.range_f(0.0, TAU)
	var w: Vector3 = (f.x * cos(a) + f.y * sin(a) + n * rng.range_f(-0.15, 0.15)).normalized()   # near-level shot
	var side: Vector3 = w.cross(n).normalized().rotated(w, rng.range_f(0.0, TAU))
	var target: int = kit.entity(EntityStore.K_SHIP, c, TARGET_RADIUS, 1)
	var i: int = kit.projectile(id, c + side * miss - w * travel, w * def.speed_mps, 0)
	var hit: int = -1
	for t: int in ceili(def.lifetime_s / kit.dt):
		kit.tick(t + 1, def)
		var h: int = kit.first(Collision.C_HIT)
		if h >= 0:
			assert_int(kit.collision.c_b[h]).is_equal(kit.store.id_of(target))
			hit = t + 1
			break
	var _a: bool = kit.proj.free_slot(i, 0)
	var _b: bool = kit.store.free_slot(target, 0)
	return hit


func _sweep_case(id: String, seed_value: int) -> void:
	var kit: CollisionTestKit = CollisionTestKit.new()
	var def: ProjectileDef = FlightTestKit.projectile(StringName(id))
	var rng: Rng = Rng.new(seed_value)
	var reach: float = def.speed_mps * def.lifetime_s
	var combined: float = TARGET_RADIUS + def.radius_m
	var hits: int = 0
	for k: int in GEOMETRIES:
		var miss: float = combined * rng.range_f(0.0, 0.995)
		var travel: float = rng.range_f(def.speed_mps * kit.dt * 0.5, reach * 0.9)
		if _fly(kit, def, id, rng, k, miss, travel) > 0:
			hits += 1
		else:
			fail("%s geometry %d missed (miss %.3f m, travel %.1f m)" % [id, k, miss, travel])
			return
	assert_int(hits).is_equal(GEOMETRIES)
	for k: int in 200:
		var miss: float = combined * rng.range_f(1.01, 3.0)
		assert_int(_fly(kit, def, id, rng, k, miss, rng.range_f(10.0, reach * 0.9))).is_equal(-1)


func test_swept_slug_hits_6m_sphere_at_700mps_for_1000_geometries() -> void:
	_sweep_case("slug_light", 700)


func test_swept_rail_slug_hits_6m_sphere_at_1500mps_for_1000_geometries() -> void:
	_sweep_case("rail_slug", 1500)


## Random battle: ships, structures (pads included), ground units and 1,500 slugs flown for 40 ticks with
## terrain reports; two independent runs give byte-identical contact streams.
func _battle(seed_value: int) -> PackedByteArray:
	var kit: CollisionTestKit = CollisionTestKit.new("res://content/maps/s_world1_r6000")
	kit.collision.shooter_grace_ticks = 10
	var rng: Rng = Rng.new(seed_value)
	var slug: ProjectileDef = FlightTestKit.projectile(&"slug_light")
	var centre: Vector3 = Vector3(0.6, 0.6, 0.53).normalized()
	var ships: PackedInt32Array = PackedInt32Array()
	for k: int in 300:
		var d: Vector3 = (centre + _dir(rng, 2) * rng.range_f(0.0, 0.03)).normalized()
		var kind: int = BATTLE_KINDS[k % 4]
		var alt: float = kit.terrain.height_at(d) + (rng.range_f(6.0, 400.0) if kind == EntityStore.K_SHIP else 0.0)
		var def_id: int = CollisionTestKit.PAD_DEF if k % 8 == 2 else CollisionTestKit.PLAIN_DEF
		var s: int = kit.entity(kind, d * (R + alt), rng.range_f(4.0, 20.0), k % 2, def_id)
		kit.store.vel[s] = _dir(rng, 2) * rng.range_f(0.0, 30.0)
		if kind == EntityStore.K_SHIP:
			var _a: bool = ships.push_back(s)
	for k: int in 1500:
		var s: int = ships[k % ships.size()]
		var _i: int = kit.projectile("slug_light", kit.store.pos[s], _dir(rng, 2) * slug.speed_mps, k % 2,
			kit.store.id_of(s))
	var out: PackedByteArray = PackedByteArray()
	for t: int in 40:
		for s: int in ships:
			if rng.next_float() < 0.2:
				kit.collision.report_terrain(s, t + 1, rng.range_f(0.0, 30.0))
		kit.tick(t + 1, slug)
		var c: Collision = kit.collision
		var n: int = c.contact_count
		out.append_array(c.c_kind.slice(0, n))
		out.append_array(c.c_class.slice(0, n))
		out.append_array(c.c_a.slice(0, n).to_byte_array())
		out.append_array(c.c_b.slice(0, n).to_byte_array())
		out.append_array(c.c_value.slice(0, n).to_byte_array())
		out.append_array(c.c_point.slice(0, n).to_byte_array())
	return out


func test_collision_is_deterministic() -> void:
	var a: PackedByteArray = _battle(31)
	var b: PackedByteArray = _battle(31)
	assert_int(a.size()).is_greater(1000)
	assert_bool(a == b).is_true()
