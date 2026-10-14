class_name EntityDemoWorld
extends RefCounted
## World driver of the TA-26 entity demo: a SimWorld with `n` ships, ground units and structures around the eight
## bases of the s_world1_r6000 moon, ships orbiting their base under a stub act hook. Entities are written straight
## into the store (demo only). The demo loads this script by path at runtime, so the scene itself never compiles
## the sim (`validate_scenes` runs without autoloads). Not shipped; self-contained (no test code).

const MAP: StringName = &"s_world1_r6000"
const SEED: int = 26
const TEAMS: int = 8
const ORBIT_M: float = 1200.0
const DEFS_DIR: String = "res://content/defs/"
const SHIP_IDS: Array[StringName] = [&"dart", &"dart", &"lancer", &"bomber", &"scout", &"hauler"]
const GROUND_IDS: Array[StringName] = [&"harvester", &"siege_crawler"]
const STRUCTURE_IDS: Array[StringName] = [&"solar_array", &"refinery", &"reactor", &"relay_pylon", &"sensor_mast"]

var world: SimWorld
var ships: PackedInt32Array = PackedInt32Array()
var _content: ContentSet
var _rng: Rng = Rng.new(SEED)
var _bases: PackedVector3Array = PackedVector3Array()


func build(n_ships: int, n_ground: int, n_structures: int) -> void:
	var texts: Dictionary = {}
	for f: String in DirAccess.get_files_at(DEFS_DIR):
		if f.ends_with(".json"):
			texts[f] = FileAccess.get_file_as_string(DEFS_DIR + f)
	_content = ContentLoader.build(texts, {})
	var r: MatchRules = MatchRules.from_defs(null, _content.match_rules, _content.rules, &"standard")
	r.debug_commands = false
	world = SimWorld.new(_content)
	var map: MapDef = MapDef.new()
	map.id = MAP
	var res: Result = world.load_map(map, SEED, r)
	assert(res.ok, res.message)
	for t: int in TEAMS:
		world.add_player(t, t, &"", PlayerTable.KIND_BOT)
		var _b: bool = _bases.push_back(Sphere.from_lat_lon(0.0, deg_to_rad(Sphere.SLOT_LON0_DEG + Sphere.SLOT_SPACING_DEG * t), 1.0))
	for k: int in n_ships:
		var s: int = _put(SHIP_IDS[k % SHIP_IDS.size()], k % TEAMS, _rng.range_f(80.0, 900.0), _rng.range_f(0.0, ORBIT_M))
		var _a: bool = ships.push_back(s)
		var p: Vector3 = world.store().pos[s]
		world.store().vel[s] = Sphere.tangent_frame(p).x.rotated(p.normalized(), _rng.range_f(0.0, TAU)) * 120.0
	for k: int in n_ground:
		var _g: int = _put(GROUND_IDS[k % GROUND_IDS.size()], k % TEAMS, 0.0, _rng.range_f(100.0, ORBIT_M))
	for k: int in n_structures:
		var _s: int = _put(STRUCTURE_IDS[k % STRUCTURE_IDS.size()], k % TEAMS, 0.0, _rng.range_f(0.0, ORBIT_M * 0.8))
	var hook: OrbitHook = OrbitHook.new()
	hook.ships = ships
	hook.bases = _bases
	world.set_ai_hook(hook)
	var st: EntityStore = world.store()
	for live: PackedInt32Array in [st.ships, st.ground, st.structures]:
		for s: int in live:
			st.visible_mask[s] = 0xFF   # spectator: every team visible


func step() -> void:
	world.step()


func view() -> SimView:
	return world.view()


func terrain() -> Terrain:
	return world.terrain()


func content() -> ContentSet:
	return _content


func hero_id() -> int:
	return world.store().id_of(ships[0])


## Position of the first structure (the camera's base target).
func base_pos() -> Vector3:
	var st: EntityStore = world.store()
	return st.pos[st.structures[0]]


func _def_id(def: StringName) -> int:
	var d: int = _content.entity_index.get(def, -1)
	return d


func _put(def: StringName, team: int, alt: float, dist: float) -> int:
	var d: int = _def_id(def)
	var st: EntityStore = world.store()
	var kind: int = EntityStore.K_STRUCTURE
	if DefRanges.kind_of(d) == DefRanges.K_SHIP:
		kind = EntityStore.K_SHIP
	elif DefRanges.kind_of(d) == DefRanges.K_GROUND:
		kind = EntityStore.K_GROUND
	var s: int = EntityId.slot(st.alloc(kind, 0))
	var base: Vector3 = _bases[team]
	var f: Basis = Sphere.tangent_frame(base * Sphere.PLANET_RADIUS)
	var off: Vector3 = (f.x * cos(_rng.range_f(0.0, TAU)) + f.y * sin(_rng.range_f(0.0, TAU))).normalized()
	var dir: Vector3 = (base + off * (dist / Sphere.PLANET_RADIUS)).normalized()
	st.pos[s] = dir * (Sphere.PLANET_RADIUS + world.terrain().height_at(dir) + alt + 2.0)
	st.def_id[s] = d
	st.owner[s] = team
	st.team[s] = team
	st.fwd[s] = Sphere.tangent_frame(st.pos[s]).y
	st.up[s] = dir
	st.radius[s] = 14.0 if kind == EntityStore.K_STRUCTURE else 6.0
	st.hp[s] = 100.0
	if kind == EntityStore.K_SHIP:
		var sd: ShipDef = _content.ships[d]
		st.fuel[s] = sd.fuel_s * 100.0
		st.radius[s] = sd.bounding_radius
		st.flip_time[s] = -sd.flip_cooldown_s
		st.boost_time[s] = -sd.boost_cooldown_s
	return s


## Stub act step: steer toward a point ORBIT_M ahead on the circle around the base, hold ~450 m above the datum.
class OrbitHook extends SimAiHook:
	var ships: PackedInt32Array
	var bases: PackedVector3Array
	var _in: PilotInput = PilotInput.new()

	func on_tick(_t: int, view: SimView, sink: CommandSinkBase) -> void:
		for s: int in ships:
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
			_in.buttons = 0
			var _r: int = sink.drive(id, _in)
