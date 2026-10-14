class_name PerfCollision
extends SceneTree
## Spatial + Collision benchmark (RandomNumberGenerator, not Rng: no autoloads under -s) (TA-14; 03 s4.2 rows "7 Spatial rebuild" 1.2 ms and "8 Collision incl. 8b" 5.0 ms,
## 8b <= 0.5 ms inside it). godot --headless --path godot -s res://test/perf/perf_collision.gd [-- --entities=400
## --projectiles=2000 --ticks=600 --flat]. A battle on the s_world1 map: ships (60 %), structures (25 %, every 4th a pad)
## and ground units in four clusters 1-2 km wide, one at a cube corner; slugs fired from ships in random directions,
## half of them low (near the ground); ships report terrain contacts at random. Each tick moves ships and steps
## projectiles (untimed), then times Spatial.rebuild() and Collision.step(). Respawns (untimed) keep the projectile
## count constant. Prints PERF_COLL lines with p50 / p95 / max us per tick. Report only; no gate (03 s12.1).

const MAP: String = "res://content/maps/s_world1_r6000"
const WARMUP: int = 30


func _initialize() -> void:
	var entities: int = 400
	var projectiles: int = 2000
	var ticks: int = 600
	var map: String = MAP
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--entities="):
			entities = int(arg.substr(11))
		elif arg.begins_with("--projectiles="):
			projectiles = int(arg.substr(14))
		elif arg.begins_with("--ticks="):
			ticks = int(arg.substr(8))
		elif arg == "--flat":
			map = ""
	var kit: CollisionTestKit = CollisionTestKit.new(map)
	kit.collision.shooter_grace_ticks = 10
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 22
	var slug: ProjectileDef = kit.projectile_def("slug_light")
	var centres: PackedVector3Array = PackedVector3Array([Vector3(1, 1, 1).normalized(), Vector3(0.2, -1, 0.1).normalized(),
		Vector3(-0.7, 0.3, -0.6).normalized(), Vector3(0.1, 0.4, -1).normalized()])
	var ships: PackedInt32Array = PackedInt32Array()
	for k: int in entities:
		var d: Vector3 = (centres[k % 4] + _rand_dir(rng) * rng.randf_range(0.0, 0.15)).normalized()
		var m: int = k % 20
		var kind: int = EntityStore.K_SHIP if m < 12 else (EntityStore.K_STRUCTURE if m < 17 else EntityStore.K_GROUND)
		var h: float = kit.terrain.height_at(d)
		var alt: float = h + (rng.randf_range(8.0, 600.0) if kind == EntityStore.K_SHIP else 0.0)
		var def_id: int = CollisionTestKit.PAD_DEF if m == 12 else CollisionTestKit.PLAIN_DEF
		var radius: float = rng.randf_range(15.0, 25.0) if kind == EntityStore.K_STRUCTURE else rng.randf_range(4.0, 10.0)
		var s: int = kit.entity(kind, d * (Sphere.PLANET_RADIUS + alt), radius, k % 2, def_id)
		if kind == EntityStore.K_SHIP:
			kit.store.vel[s] = Sphere.tangent_frame(kit.store.pos[s]).x.rotated(d, rng.randf_range(0.0, TAU)) * 100.0
			var _a: bool = ships.push_back(s)
	for k: int in projectiles:
		_spawn(kit, rng, ships, slug, k)
	var t_hash: PackedInt32Array = PackedInt32Array()
	var t_coll: PackedInt32Array = PackedInt32Array()
	var contacts: int = 0
	var samples: int = 0
	for t: int in ticks + WARMUP:
		_move(kit, rng, ships, slug, t)
		var t0: int = Time.get_ticks_usec()
		kit.spatial.rebuild()
		var t1: int = Time.get_ticks_usec()
		kit.collision.step(t + 1)
		var t2: int = Time.get_ticks_usec()
		if t >= WARMUP:
			var _b: bool = t_hash.push_back(t1 - t0)
			var _c: bool = t_coll.push_back(t2 - t1)
			contacts += kit.collision.contact_count
			samples += kit.collision.terrain_samples
		_respawn(kit, rng, ships, slug)
	_report("spatial_rebuild", t_hash, entities, projectiles)
	_report("collision_step", t_coll, entities, projectiles)
	print("PERF_COLL contacts_per_tick=%.1f terrain_samples_per_tick=%.1f hash_items=%d touched_cells=%d" % [
		float(contacts) / float(ticks), float(samples) / float(ticks), kit.spatial.item_count, kit.spatial.touched_count])
	quit(0)


static func _rand_dir(rng: RandomNumberGenerator) -> Vector3:
	var v: Vector3 = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
	return v.normalized() if v.length_squared() > 1e-6 else Vector3.UP


func _spawn(kit: CollisionTestKit, rng: RandomNumberGenerator, ships: PackedInt32Array, slug: ProjectileDef, k: int) -> void:
	var s: int = ships[rng.randi_range(0, ships.size() - 1)]
	var p: Vector3 = kit.store.pos[s]
	var dir: Vector3 = _rand_dir(rng)
	if k % 2 == 0:
		dir = (dir - p.normalized() * (absf(dir.dot(p.normalized())) + 0.2)).normalized()   # half fly downward
	var i: int = kit.projectile("slug_light", p + dir * 12.0, dir * slug.speed_mps, kit.store.team[s], kit.store.id_of(s))
	kit.proj.ttl[i] = slug.lifetime_s


func _move(kit: CollisionTestKit, rng: RandomNumberGenerator, ships: PackedInt32Array, slug: ProjectileDef, t: int) -> void:
	for s: int in ships:
		var p: Vector3 = kit.store.pos[s] + kit.store.vel[s] * kit.dt
		kit.store.pos[s] = p.normalized() * maxf(p.length(), Sphere.PLANET_RADIUS + kit.terrain.height_at(p) + 6.0)
		if rng.randf() < 0.05:
			kit.collision.report_terrain(s, t + 1, rng.randf_range(0.0, 30.0))
	for i: int in kit.proj.live:
		var ps: ProjectileState = Kinematics.step_projectile(kit.proj.pos[i], kit.proj.vel[i], slug, kit.rules, kit.dt)
		kit.proj.prev_pos[i] = kit.proj.pos[i]
		kit.proj.pos[i] = ps.p
		kit.proj.ttl[i] -= kit.dt


## Frees projectiles that hit, grounded or expired, and spawns as many new ones.
func _respawn(kit: CollisionTestKit, rng: RandomNumberGenerator, ships: PackedInt32Array, slug: ProjectileDef) -> void:
	var dead: PackedInt32Array = PackedInt32Array()
	for k: int in kit.collision.contact_count:
		if kit.collision.c_kind[k] <= Collision.C_GROUND:
			var _a: bool = dead.push_back(kit.proj.index_of(kit.collision.c_a[k]))
	for i: int in kit.proj.live:
		if kit.proj.ttl[i] <= 0.0:
			var _b: bool = dead.push_back(i)
	var freed: int = 0
	for i: int in dead:
		if kit.proj.free_slot(i, 0):                  # a hit can also expire: free once
			freed += 1
	for k: int in freed:
		_spawn(kit, rng, ships, slug, k)


func _report(row: String, us: PackedInt32Array, entities: int, projectiles: int) -> void:
	us.sort()
	var n: int = us.size()
	print("PERF_COLL row=%s entities=%d projectiles=%d ticks=%d p50_us=%d p95_us=%d max_us=%d" % [
		row, entities, projectiles, n, us[n >> 1], us[int(float(n) * 0.95)], us[n - 1]])
