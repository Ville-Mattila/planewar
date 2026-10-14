class_name PerfTickWorld extends RefCounted
## The perf_tick scenario (03 s4.4, s14.1 shape until TA-22 commits s_sim_1.json): a SimWorld with 8 players on
## 8 teams around the 8 start slots (R0 B.6 longitudes), ships orbiting their base under a stub act-step hook (row
## 3-4), ground units, structures (every 6th a pad, every 5th a tower def), wrecks, and a projectile pool topped up
## between ticks (untimed): 80 % straight slugs, 15 % bombs, 5 % guided rockets; GD-36 weapon fire on top (row 9):
## every other ship holds FIRE1 (guns of Darts / Lancers, ~100 firing), one Lancer per team holds FIRE2 (a seeker
## with no enemy in range, the human worst case), Autocannon Turrets and Flak Batteries hold FIRE1; row 3b: PerfPathLoad (up to 120 ground units re-pathing every 10 s through the sink, TA-50). Entities are written straight into the store (`SimWorld.store()` is tests' and net's), so the scenario
## does not depend on command rate limits. Deterministic: core `Rng`, fixed seed.

const SEED: int = 22
const TEAMS: int = 8
const ORBIT_M: float = 1200.0

var world: SimWorld
var ships: PackedInt32Array = PackedInt32Array()
var fire: PackedInt32Array = PackedInt32Array()     ## per ships[k]: buttons held (GD-36)
var towers: PackedInt32Array = PackedInt32Array()   ## gun and flak towers holding FIRE1
var projectiles_target: int = 0

var _rng: Rng = Rng.new(SEED)
var _bases: PackedVector3Array = PackedVector3Array()
var _defs: Dictionary = {}
var _hook: OrbitHook
var path_load: PerfPathLoad


## Counts per kind and the map (&"" = flat datum); perf_tick.gd picks the S-SIM-1 or the A/B scale.
func _init(n_ships: int, n_ground: int, n_structures: int, n_wrecks: int, n_projectiles: int, map_id: StringName) -> void:
	var c: ContentSet = WorldTestKit.content()
	var r: MatchRules = WorldTestKit.rules()
	r.profile_enabled = true
	r.debug_commands = false
	world = SimWorld.new(c)
	var map: MapDef = MapDef.new()
	map.id = map_id
	var res: Result = world.load_map(map, SEED, r)
	assert(res.ok, res.message)
	for t: int in TEAMS:
		world.add_player(t, t, [&"", &"vanguard", &"bulwark", &"foundry"][t % 4], PlayerTable.KIND_BOT)
		_bases.push_back(Sphere.from_lat_lon(0.0, deg_to_rad(Sphere.SLOT_LON0_DEG + Sphere.SLOT_SPACING_DEG * t), 1.0))
	var ship_ids: Array[StringName] = [&"dart", &"dart", &"lancer", &"bomber", &"scout", &"hauler"]
	var structure_ids: Array[StringName] = [&"solar_array", &"refinery", &"reactor", &"relay_pylon", &"sensor_mast"]
	var tower_ids: Array[StringName] = [&"autocannon_turret", &"flak_battery", &"missile_tower"]
	var seekers: int = 0
	for k: int in n_ships:
		var sid: StringName = ship_ids[k % ship_ids.size()]
		var s: int = _put(sid, k % TEAMS, _rng.range_f(80.0, 900.0), _rng.range_f(0.0, ORBIT_M))
		ships.push_back(s)
		var b: int = PilotInput.FIRE1 if k % 2 == 0 else 0
		if sid == &"lancer" and seekers < TEAMS and k % TEAMS == seekers:
			b |= PilotInput.FIRE2
			seekers += 1
		fire.push_back(b)
		var p: Vector3 = world.store().pos[s]
		world.store().vel[s] = Sphere.tangent_frame(p).x.rotated(p.normalized(), _rng.range_f(0.0, TAU)) * 120.0
	for k: int in n_ground:
		_put([&"harvester", &"siege_crawler"][k % 2], k % TEAMS, 0.0, _rng.range_f(100.0, ORBIT_M))
	for k: int in n_structures:
		var id: StringName = &"pad" if k % 6 == 0 else (tower_ids[k % 3] if k % 5 == 0 else structure_ids[k % structure_ids.size()])
		var t: int = _put(id, k % TEAMS, 0.0, _rng.range_f(0.0, ORBIT_M * 0.8))
		if id == &"autocannon_turret" or id == &"flak_battery":
			towers.push_back(t)
	for k: int in n_wrecks:
		_put(&"dart", k % TEAMS, 0.0, _rng.range_f(0.0, ORBIT_M), EntityStore.K_WRECK)
	projectiles_target = n_projectiles
	_hook = OrbitHook.new()
	_hook.ships = ships
	_hook.fire = fire
	_hook.towers = towers
	_hook.bases = _bases
	path_load = PerfPathLoad.new(n_ground, _bases)
	_hook.path_load = path_load
	world.set_ai_hook(_hook)
	top_up()


## Untimed between ticks: keeps the live projectile count at `projectiles_target`.
func top_up() -> void:
	var ps: ProjectileStore = world.projectiles()
	var missing: int = projectiles_target - ps.live_count()
	for _k: int in missing:
		var s: int = ships[_rng.range_i(0, ships.size() - 1)]
		var p: Vector3 = world.store().pos[s]
		var roll: float = _rng.next_float()
		var kind: StringName = &"slug_light" if roll < 0.8 else (&"bomb" if roll < 0.95 else &"rocket")
		var pd: ProjectileDef = WorldTestKit.content().projectiles[int(WorldTestKit.content().projectile_index[kind]) - DefRanges.PROJECTILE_BASE]
		var dir: Vector3 = Vector3(_rng.range_f(-1.0, 1.0), _rng.range_f(-1.0, 1.0), _rng.range_f(-1.0, 1.0)).normalized()
		var v: Vector3 = world.store().vel[s] + dir * maxf(pd.speed_mps, 1.0)
		var id: int = WorldTestKit.projectile(world, kind, p + dir * 8.0, v, world.store().team[s], pd.lifetime_s)
		if id == EntityId.NULL_ID:
			return
		var i: int = ps.index_of(id)
		ps.shooter[i] = world.store().id_of(s)
		if kind == &"rocket":
			ps.kind[i] = ProjectileStore.ROCKET
			ps.flags[i] |= ProjectileStore.F_GUIDED
			ps.target[i] = world.store().id_of(ships[_rng.range_i(0, ships.size() - 1)])
			ps.weapon_def[i] = int(WorldTestKit.content().weapon_index[&"rocket_lancer"]) - DefRanges.WEAPON_BASE


func _put(def: StringName, team: int, alt: float, dist: float, kind_override: int = -1) -> int:
	var d: int = WorldTestKit.def_id(def)
	var st: EntityStore = world.store()
	var kind: int = kind_override
	if kind < 0:
		match DefRanges.kind_of(d):
			DefRanges.K_SHIP:
				kind = EntityStore.K_SHIP
			DefRanges.K_GROUND:
				kind = EntityStore.K_GROUND
			_:
				kind = EntityStore.K_STRUCTURE
	var s: int = EntityId.slot(st.alloc(kind, 0))
	var base: Vector3 = _bases[team]
	var f: Basis = Sphere.tangent_frame(base * Sphere.PLANET_RADIUS)
	var off: Vector3 = (f.x * cos(_rng.range_f(0.0, TAU)) + f.y * sin(_rng.range_f(0.0, TAU))).normalized()
	var dir: Vector3 = (base + off * (dist / Sphere.PLANET_RADIUS)).normalized()
	var ground: float = world.terrain().height_at(dir)
	st.pos[s] = dir * (Sphere.PLANET_RADIUS + ground + alt + 2.0)
	st.def_id[s] = d
	st.owner[s] = team
	st.team[s] = team
	st.fwd[s] = Sphere.tangent_frame(st.pos[s]).y
	st.up[s] = dir
	st.radius[s] = 6.0 if kind == EntityStore.K_SHIP or kind == EntityStore.K_GROUND else 14.0
	st.hp[s] = 100.0
	st.ammo[s] = 1000000          # GD-36: guns and tower pools never run dry inside the run
	st.bombs[s] = 255
	st.rockets[s] = 255
	var sd: ShipDef = WorldTestKit.content().ships[d] if kind == EntityStore.K_SHIP else null
	if sd != null:
		st.fuel[s] = sd.fuel_s * 100.0
		st.radius[s] = sd.bounding_radius
		st.flip_time[s] = -sd.flip_cooldown_s
		st.boost_time[s] = -sd.boost_cooldown_s
	return s


## Stub act step (05 s10 shape, not 05's controllers): per ship, steer toward a point ORBIT_M ahead on the circle
## around its base and hold 300-600 m above the datum.
class OrbitHook extends SimAiHook:
	var ships: PackedInt32Array
	var fire: PackedInt32Array
	var towers: PackedInt32Array
	var bases: PackedVector3Array
	var path_load: PerfPathLoad
	var _in: PilotInput = PilotInput.new()

	func on_tick(t: int, view: SimView, sink: CommandSinkBase) -> void:
		path_load.tick(t, sink)
		_in.thrust = 0.0
		_in.pitch = 0.0
		_in.yaw = 0.0
		_in.roll = 0.0
		_in.buttons = PilotInput.FIRE1
		for s: int in towers:
			var _ok: bool = sink.drive(EntityId.make(s, 1), _in)
		for k: int in ships.size():
			var s: int = ships[k]
			var id: int = EntityId.make(s, 1)
			if not view.alive(id):
				continue
			var p: Vector3 = view.pos(id)
			var v: Vector3 = view.vel(id)
			var b: Basis = view.basis(id)
			var n: Vector3 = p.normalized()
			var alt: float = p.length() - Sphere.PLANET_RADIUS
			var centre: Vector3 = bases[view.team(id)]
			var radial: Vector3 = (n - centre).normalized()
			var want: Vector3 = (radial.cross(n) + (centre - n) * 0.5).normalized()
			_in.thrust = 0.7
			_in.yaw = clampf(-b.x.dot(want) * 2.0, -1.0, 1.0)
			_in.pitch = clampf((450.0 - alt) * 0.01 - v.dot(n) * 0.05, -1.0, 1.0)
			_in.roll = clampf(-b.x.dot(n) * 2.0, -1.0, 1.0)
			_in.buttons = fire[k]
			sink.drive(id, _in)
